#!/usr/bin/env python3
"""Extract an image-to-video clip into Godot-ready PNG frames and an atlas."""

from __future__ import annotations

import argparse
import ctypes
import fcntl
import hashlib
import json
import math
import os
import re
import shutil
import subprocess
import sys
import uuid
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / "tools" / "art_pipeline" / "catalog" / "animations.json"
DEFAULT_OUTPUT = ROOT / ".art-pipeline" / "extracted"
DEFAULT_VIDEO_SOURCES = ROOT / ".art-pipeline" / "video-sources"
ANIMATION_PROMPTS = ROOT / "docs" / "art-prompts" / "animation"
OUTPUT_LOCK_ROOT = Path.home() / ".cache" / "lingnong-art-pipeline" / "output-locks"


class ExtractionError(RuntimeError):
    pass


def load_animation(animation_id: str) -> dict[str, Any]:
    animations = json.loads(CATALOG.read_text(encoding="utf-8"))
    for animation in animations:
        if animation["id"] == animation_id:
            return animation
    raise ExtractionError(f"unknown animation id: {animation_id}")


def run(command: list[str]) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(command, text=True, capture_output=True, check=False)
    if result.returncode:
        raise ExtractionError(
            f"command failed ({result.returncode}): {' '.join(command)}\n{result.stderr.strip()}"
        )
    return result


def require_tools() -> None:
    for tool in ("ffmpeg", "ffprobe"):
        if shutil.which(tool) is None:
            raise ExtractionError(f"required command is missing: {tool}")


def path_exists(path: Path) -> bool:
    return path.exists() or path.is_symlink()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def input_digest(paths: list[Path]) -> str:
    if not paths or any(not path.is_file() for path in paths):
        raise ExtractionError("all provenance input files must exist")
    digest = hashlib.sha256(b"lingnong-input-v1\0")
    for path in paths:
        content = path.read_bytes()
        digest.update(f"bytes:{len(content)}\n".encode())
        digest.update(content)
    return digest.hexdigest()


def write_json_atomic(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.part-{os.getpid()}")
    temporary.write_text(
        json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    os.replace(temporary, path)


def validate_video_provenance(
    metadata_path: Path,
    *,
    animation_id: str,
    provenance_digest: str,
    video_path: Path,
) -> dict[str, Any] | None:
    """Validate and preserve provider metadata written before extraction."""
    if not metadata_path.is_file():
        return None
    try:
        value = json.loads(metadata_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise ExtractionError(
            f"video provenance is invalid JSON: {metadata_path}"
        ) from exc
    if not isinstance(value, dict):
        raise ExtractionError(f"video provenance must be an object: {metadata_path}")
    if value.get("id") != animation_id:
        raise ExtractionError("video provenance asset id does not match")
    if value.get("input_digest") != provenance_digest:
        raise ExtractionError("video prompt or prepared first frame changed")
    if value.get("output_digest") != sha256_file(video_path):
        raise ExtractionError("video content changed after its provenance was written")
    return value


def acquire_output_lock(output: Path) -> Any:
    OUTPUT_LOCK_ROOT.mkdir(parents=True, exist_ok=True)
    key = hashlib.sha256(str(output).encode("utf-8")).hexdigest()
    lock_path = OUTPUT_LOCK_ROOT / f"{key}.lock"
    handle = lock_path.open("a+", encoding="utf-8")
    try:
        fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError as exc:
        handle.close()
        raise ExtractionError(
            f"another process is publishing this output: {output}"
        ) from exc
    handle.seek(0)
    handle.truncate()
    handle.write(f"pid={os.getpid()} output={output}\n")
    handle.flush()
    return handle


def recover_legacy_destination(destination: Path) -> None:
    """Restore an old directory if a previous one-time symlink migration stopped."""
    if path_exists(destination):
        return
    candidates = sorted(
        destination.parent.glob(f".{destination.name}.version-legacy-*"),
        key=lambda path: path.stat().st_mtime,
        reverse=True,
    )
    if not candidates:
        return
    temporary_link = destination.with_name(
        f".{destination.name}.recover-link-{os.getpid()}"
    )
    temporary_link.unlink(missing_ok=True)
    os.symlink(candidates[0].name, temporary_link, target_is_directory=True)
    os.replace(temporary_link, destination)


def atomic_exchange(first: Path, second: Path) -> None:
    """Atomically exchange two directory entries on macOS or Linux."""
    libc = ctypes.CDLL(None, use_errno=True)
    first_bytes = os.fsencode(first)
    second_bytes = os.fsencode(second)
    if sys.platform == "darwin" and hasattr(libc, "renamex_np"):
        renamex = libc.renamex_np
        renamex.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint]
        renamex.restype = ctypes.c_int
        result = renamex(first_bytes, second_bytes, 0x00000002)  # RENAME_SWAP
    elif sys.platform.startswith("linux") and hasattr(libc, "renameat2"):
        renameat2 = libc.renameat2
        renameat2.argtypes = [
            ctypes.c_int,
            ctypes.c_char_p,
            ctypes.c_int,
            ctypes.c_char_p,
            ctypes.c_uint,
        ]
        renameat2.restype = ctypes.c_int
        result = renameat2(-100, first_bytes, -100, second_bytes, 0x00000002)
    else:
        raise ExtractionError(
            "atomic migration of a legacy output directory is not supported on this platform"
        )
    if result != 0:
        error_number = ctypes.get_errno()
        raise OSError(error_number, os.strerror(error_number), str(second))


def _remove_published_path(path: Path) -> None:
    if path.is_symlink() or path.is_file():
        path.unlink()
    elif path.exists():
        shutil.rmtree(path)


def publish_version(work: Path, destination: Path, replace_existing: bool) -> list[str]:
    """Atomically switch the stable output path to a complete immutable version."""
    warnings: list[str] = []
    if not replace_existing:
        try:
            os.symlink(work.name, destination, target_is_directory=True)
        except FileExistsError as exc:
            raise ExtractionError(
                f"output appeared while publishing; preserved it: {destination}"
            ) from exc
        return warnings

    old_version: Path | None = None
    temporary_link = destination.with_name(
        f".{destination.name}.publish-link-{uuid.uuid4().hex}"
    )
    if destination.is_symlink():
        target = Path(os.readlink(destination))
        candidate = target if target.is_absolute() else destination.parent / target
        if (
            candidate.parent.resolve() == destination.parent.resolve()
            and candidate.name.startswith(f".{destination.name}.version-")
        ):
            old_version = candidate
    elif destination.exists():
        if not destination.is_dir():
            raise ExtractionError(f"output path is not a directory: {destination}")

    committed = False
    cleanup_path: Path | None = None
    try:
        os.symlink(work.name, temporary_link, target_is_directory=True)
        if destination.exists() and not destination.is_symlink():
            atomic_exchange(temporary_link, destination)
            cleanup_path = temporary_link
        else:
            os.replace(temporary_link, destination)
            cleanup_path = old_version
        committed = True
    except (OSError, ExtractionError):
        if not committed and temporary_link.is_symlink():
            temporary_link.unlink(missing_ok=True)
        raise

    if cleanup_path is not None and cleanup_path != work and path_exists(cleanup_path):
        try:
            _remove_published_path(cleanup_path)
        except OSError as exc:
            warnings.append(
                f"old version cleanup failed but the new version is live: {exc}"
            )
    return warnings


def probe_video(path: Path) -> dict[str, Any]:
    result = run(
        [
            "ffprobe",
            "-v",
            "error",
            "-select_streams",
            "v:0",
            "-show_entries",
            "stream=width,height,r_frame_rate,duration,nb_frames",
            "-of",
            "json",
            str(path),
        ]
    )
    streams = json.loads(result.stdout).get("streams", [])
    if not streams:
        raise ExtractionError(f"no video stream in: {path}")
    return streams[0]


def parse_rate(value: str) -> float:
    if "/" in value:
        numerator, denominator = value.split("/", 1)
        return float(numerator) / max(1.0, float(denominator))
    return float(value)


def validate_source_video(
    animation: dict[str, Any], source: dict[str, Any], duration_tolerance: float
) -> None:
    width = int(source.get("width", 0))
    height = int(source.get("height", 0))
    expected_width = int(animation["width"])
    expected_height = int(animation["height"])
    if (width, height) != (expected_width, expected_height):
        raise ExtractionError(
            f"source video is {width}x{height}; expected the exact production canvas "
            f"{expected_width}x{expected_height}"
        )
    source_ratio = width / float(height)
    expected_ratio = expected_width / float(expected_height)
    if abs(source_ratio - expected_ratio) / expected_ratio > 0.03:
        raise ExtractionError(
            f"source aspect ratio {source_ratio:.4f} differs from expected {expected_ratio:.4f}"
        )
    duration = float(source.get("duration", 0.0))
    expected_duration = float(animation["duration_seconds"])
    if (
        expected_duration <= 0
        or abs(duration - expected_duration) / expected_duration > duration_tolerance
    ):
        raise ExtractionError(
            f"source duration {duration:.3f}s differs from expected {expected_duration:.3f}s "
            f"beyond tolerance {duration_tolerance:.0%}"
        )
    source_fps = parse_rate(str(source.get("r_frame_rate", "0/1")))
    if source_fps + 0.01 < int(animation["source_fps"]):
        raise ExtractionError(
            f"source frame rate {source_fps:.2f} is below required source rate "
            f"{animation['source_fps']}"
        )


def extraction_filter(
    animation: dict[str, Any],
    chroma_similarity: float,
    *,
    adaptive_reference_matte: bool = False,
) -> str:
    width = int(animation["frame_width"])
    height = int(animation["frame_height"])
    target_fps = int(animation["target_fps"])
    expected_images = int(float(animation["duration_seconds"]) * target_fps)
    filters = [
        f"fps={target_fps}",
        f"trim=end_frame={expected_images}",
        f"setpts=N/({target_fps}*TB)",
    ]
    if (
        animation["matte"] in {"magenta", "cyan", "red"}
        and not adaptive_reference_matte
    ):
        key_color = {
            "magenta": "0xFF00FF",
            "cyan": "0x00FFFF",
            "red": "0xFF0000",
        }[animation["matte"]]
        filters.extend(
            [
                f"chromakey={key_color}:{chroma_similarity}:0.06",
                "format=rgba",
            ]
        )
    else:
        filters.append("format=rgba")
    filters.extend(
        [
            f"scale={width}:{height}:force_original_aspect_ratio=decrease:flags=lanczos",
            f"pad={width}:{height}:(ow-iw)/2:(oh-ih)/2:color=0x00000000",
        ]
    )
    return ",".join(filters)


def _adaptive_matte_spill_mask(pixels: Any, matte: str, numpy: Any) -> Any:
    """Return pixels that still look like the declared solid matte colour."""
    red = pixels[:, :, 0]
    green = pixels[:, :, 1]
    blue = pixels[:, :, 2]
    if matte == "magenta":
        return (
            (red > 170)
            & (blue > 170)
            & (green < 170)
            & ((numpy.minimum(red, blue) - green) > 45)
        )
    if matte == "cyan":
        return (
            (green > 170)
            & (blue > 170)
            & (red < 170)
            & ((numpy.minimum(green, blue) - red) > 45)
        )
    if matte == "red":
        return (
            (red > 170)
            & (green < 170)
            & (blue < 170)
            & ((red - numpy.maximum(green, blue)) > 45)
        )
    raise ExtractionError(f"adaptive reference matte does not support {matte}")


def apply_adaptive_reference_matte(
    frames_dir: Path,
    source_image: Path,
    animation: dict[str, Any],
) -> dict[str, Any]:
    """Remove a drifting flat background while preserving the supplied subject.

    H3 can gradually change a chroma background from magenta to pale green, white,
    or gray even when the subject remains usable. A single fixed chroma key then
    leaves the later frames opaque. This path derives a conservative subject prior
    from the prepared still, estimates each frame's border colour independently,
    and keeps only foreground components that overlap the expected subject region.
    """
    matte = str(animation["matte"])
    if matte not in {"magenta", "cyan", "red"}:
        raise ExtractionError(
            "--adaptive-reference-matte requires magenta, cyan, or red matte"
        )
    try:
        import numpy
        from PIL import Image
        from scipy import ndimage
    except ImportError as exc:
        raise ExtractionError(
            "--adaptive-reference-matte requires numpy, Pillow, and scipy"
        ) from exc

    width = int(animation["frame_width"])
    height = int(animation["frame_height"])
    matte_rgb = {
        "magenta": (255, 0, 255),
        "cyan": (0, 255, 255),
        "red": (255, 0, 0),
    }[matte]
    try:
        with Image.open(source_image) as opened:
            reference_image = opened.convert("RGB").resize(
                (width, height), Image.Resampling.LANCZOS
            )
    except (OSError, ValueError) as exc:
        raise ExtractionError(
            f"could not read adaptive matte reference: {source_image}"
        ) from exc
    reference_pixels = numpy.asarray(reference_image).astype(numpy.int32)
    matte_vector = numpy.asarray(matte_rgb, dtype=numpy.int32)
    reference_distance = numpy.sqrt(
        numpy.sum((reference_pixels - matte_vector) ** 2, axis=2)
    )
    reference_mask = reference_distance > 80
    reference_ratio = float(reference_mask.mean())
    if not 0.005 <= reference_ratio <= 0.95:
        raise ExtractionError(
            "adaptive matte reference has implausible foreground coverage "
            f"({reference_ratio:.2%})"
        )
    reference_core = ndimage.binary_erosion(reference_mask, iterations=3)
    reference_bounds = ndimage.binary_dilation(reference_mask, iterations=12)
    if not reference_core.any():
        raise ExtractionError("adaptive matte reference has no stable foreground core")

    paths = frame_files(frames_dir)
    if not paths:
        raise ExtractionError("no extracted images were produced")
    border_width = max(2, min(5, width // 8, height // 8))
    thresholds: list[float] = []
    foreground_ratios: list[float] = []
    for path in paths:
        try:
            with Image.open(path) as opened:
                pixels = numpy.asarray(opened.convert("RGB")).astype(numpy.int32)
        except (OSError, ValueError) as exc:
            raise ExtractionError(f"could not read extracted frame: {path}") from exc
        border = numpy.concatenate(
            [
                pixels[:border_width, :, :].reshape(-1, 3),
                pixels[-border_width:, :, :].reshape(-1, 3),
                pixels[:, :border_width, :].reshape(-1, 3),
                pixels[:, -border_width:, :].reshape(-1, 3),
            ]
        )
        background = numpy.median(border, axis=0)
        distance = numpy.sqrt(numpy.sum((pixels - background) ** 2, axis=2))
        border_distance = numpy.sqrt(numpy.sum((border - background) ** 2, axis=1))
        threshold = min(
            60.0,
            max(14.0, float(numpy.percentile(border_distance, 95)) + 5.0),
        )
        mask = ((distance > threshold) & reference_bounds) | reference_core
        mask &= ~_adaptive_matte_spill_mask(pixels, matte, numpy)

        labels, count = ndimage.label(mask)
        if count:
            sizes = numpy.bincount(labels.ravel())
            overlap = numpy.bincount(
                labels.ravel(),
                weights=reference_mask.ravel().astype(numpy.uint8),
                minlength=len(sizes),
            )
            keep = numpy.zeros(len(sizes), dtype=bool)
            for index in range(1, len(sizes)):
                keep[index] = sizes[index] >= 12 and overlap[index] >= 3
            mask = keep[labels]
        mask = ndimage.binary_closing(mask, iterations=1)
        alpha = numpy.clip(
            ndimage.gaussian_filter(mask.astype(numpy.float32), 0.45) * 255,
            0,
            255,
        ).astype(numpy.uint8)
        foreground_ratio = float((alpha > 32).mean())
        if foreground_ratio < 0.005:
            raise ExtractionError(
                f"adaptive matte removed the subject from {path.name}"
            )
        rgba = numpy.dstack([pixels.astype(numpy.uint8), alpha])
        temporary = path.with_name(f".{path.name}.adaptive-{os.getpid()}.png")
        try:
            Image.fromarray(rgba, "RGBA").save(temporary)
            os.replace(temporary, path)
        finally:
            temporary.unlink(missing_ok=True)
        thresholds.append(threshold)
        foreground_ratios.append(foreground_ratio)

    return {
        "strategy": "adaptive_reference",
        "reference_foreground_ratio": round(reference_ratio, 6),
        "minimum_frame_foreground_ratio": round(min(foreground_ratios), 6),
        "background_threshold_min": round(min(thresholds), 3),
        "background_threshold_max": round(max(thresholds), 3),
    }


def frame_files(frames_dir: Path) -> list[Path]:
    return sorted(frames_dir.glob("frame_*.png"))


def alpha_coverage(path: Path, width: int, height: int) -> dict[str, float | int]:
    result = subprocess.run(
        [
            "ffmpeg",
            "-hide_banner",
            "-loglevel",
            "error",
            "-i",
            str(path),
            "-vf",
            "alphaextract",
            "-f",
            "rawvideo",
            "-pix_fmt",
            "gray",
            "-",
        ],
        capture_output=True,
        check=False,
    )
    expected = width * height
    if result.returncode or len(result.stdout) != expected:
        raise ExtractionError(f"could not read the alpha channel in {path.name}")
    transparent = sum(value < 16 for value in result.stdout) / expected
    visible = sum(value > 32 for value in result.stdout) / expected
    corner_indices = (0, width - 1, (height - 1) * width, expected - 1)
    transparent_corners = sum(result.stdout[index] < 16 for index in corner_indices)
    return {
        "transparent_ratio": transparent,
        "visible_ratio": visible,
        "transparent_corners": transparent_corners,
    }


def validate_extracted_alpha(
    frames_dir: Path, width: int, height: int, anchor_check: str
) -> dict[str, Any]:
    reports = [alpha_coverage(path, width, height) for path in frame_files(frames_dir)]
    if not reports:
        raise ExtractionError("no extracted images were produced")
    isolated_anchor = anchor_check != "fixed_canvas"
    required_corners = 3 if isolated_anchor else 1
    required_transparent = 0.10 if isolated_anchor else 0.05
    for index, report in enumerate(reports, start=1):
        if (
            report["transparent_ratio"] < required_transparent
            or report["visible_ratio"] < 0.005
        ):
            raise ExtractionError(
                f"frame {index} failed alpha coverage checks "
                f"(transparent={report['transparent_ratio']:.2%}, "
                f"visible={report['visible_ratio']:.2%})"
            )
        if report["transparent_corners"] < required_corners:
            raise ExtractionError(
                f"frame {index} has only {report['transparent_corners']} transparent "
                f"corners; expected at least {required_corners}"
            )
    return {
        "verified": True,
        "minimum_transparent_ratio": round(
            min(float(report["transparent_ratio"]) for report in reports), 6
        ),
        "minimum_visible_ratio": round(
            min(float(report["visible_ratio"]) for report in reports), 6
        ),
        "minimum_transparent_corners": min(
            int(report["transparent_corners"]) for report in reports
        ),
    }


def black_matte_coverage(path: Path, width: int, height: int) -> tuple[float, float]:
    result = subprocess.run(
        [
            "ffmpeg",
            "-hide_banner",
            "-loglevel",
            "error",
            "-i",
            str(path),
            "-f",
            "rawvideo",
            "-pix_fmt",
            "rgb24",
            "-",
        ],
        capture_output=True,
        check=False,
    )
    expected = width * height * 3
    if result.returncode or len(result.stdout) != expected:
        raise ExtractionError(f"could not read RGB pixels in {path.name}")
    black = 0
    for index in range(0, expected, 3):
        if max(result.stdout[index : index + 3]) <= 8:
            black += 1
    black_ratio = black / (width * height)
    return black_ratio, 1.0 - black_ratio


def validate_black_matte_frames(
    frames_dir: Path, width: int, height: int
) -> dict[str, Any]:
    reports = [
        black_matte_coverage(path, width, height) for path in frame_files(frames_dir)
    ]
    if not reports:
        raise ExtractionError("no extracted images were produced")
    for index, (black_ratio, content_ratio) in enumerate(reports, start=1):
        if black_ratio < 0.02 or content_ratio < 0.001:
            raise ExtractionError(
                f"frame {index} failed black-matte content checks "
                f"(black={black_ratio:.2%}, content={content_ratio:.2%})"
            )
    return {
        "verified": True,
        "mode": "black_additive_content",
        "minimum_black_ratio": round(min(value[0] for value in reports), 6),
        "minimum_content_ratio": round(min(value[1] for value in reports), 6),
    }


def alpha_anchor(path: Path, mode: str) -> tuple[float, float]:
    profiles = {
        "bottom_center_root_region": (
            "crop=iw*0.30:ih*0.50:iw*0.35:ih*0.50",
            "bottom",
        ),
        "lower_right_root_region": (
            "crop=iw*0.30:ih*0.35:iw*0.65:ih*0.65",
            "bottom",
        ),
        "center_region": (
            "crop=iw*0.50:ih*0.50:iw*0.25:ih*0.25",
            "center",
        ),
        "body_center_region": (
            "crop=iw*0.20:ih*0.50:iw*0.40:ih*0.25",
            "center",
        ),
    }
    crop_filter, point_mode = profiles[mode]
    result = subprocess.run(
        [
            "ffmpeg",
            "-hide_banner",
            "-i",
            str(path),
            "-vf",
            (
                f"{crop_filter},"
                "alphaextract,cropdetect=limit=0.02:round=2:reset=0:skip=0"
            ),
            "-frames:v",
            "1",
            "-f",
            "null",
            "-",
        ],
        text=True,
        capture_output=True,
        check=False,
    )
    matches = re.findall(r"crop=(\d+):(\d+):(\d+):(\d+)", result.stderr)
    if not matches:
        raise ExtractionError(f"could not detect an alpha silhouette in {path.name}")
    width, height, x, y = map(int, matches[-1])
    if width <= 0 or height <= 0:
        raise ExtractionError(f"empty alpha silhouette in {path.name}")
    anchor_y = y + height if point_mode == "bottom" else y + height / 2.0
    return x + width / 2.0, anchor_y


def verify_anchor_drift(
    frames_dir: Path, tolerance: float, mode: str
) -> dict[str, Any]:
    anchors = [alpha_anchor(path, mode) for path in frame_files(frames_dir)]
    median_x = sorted(value[0] for value in anchors)[len(anchors) // 2]
    median_y = sorted(value[1] for value in anchors)[len(anchors) // 2]
    max_x = max(abs(value[0] - median_x) for value in anchors)
    max_y = max(abs(value[1] - median_y) for value in anchors)
    max_drift = max(max_x, max_y)
    if max_drift > tolerance:
        raise ExtractionError(
            f"detected anchor drift {max_drift:.2f}px above tolerance {tolerance:.2f}px"
        )
    return {
        "mode": mode,
        "verified": True,
        "max_x_drift_px": round(max_x, 3),
        "max_y_drift_px": round(max_y, 3),
        "tolerance_px": tolerance,
    }


def apply_seam_blend(frames_dir: Path, blend_count: int) -> None:
    originals = frame_files(frames_dir)
    if blend_count <= 0:
        raise ExtractionError("seam blending needs at least one overlap image")
    if len(originals) < blend_count * 2 + 2:
        raise ExtractionError(
            f"seam blending {blend_count} images needs at least {blend_count * 2 + 2} extracted images"
        )

    blended_dir = frames_dir.parent / "frames-seam-blend"
    if blended_dir.exists():
        shutil.rmtree(blended_dir)
    blended_dir.mkdir(parents=True)
    output_index = 1

    for source in originals[blend_count:-blend_count]:
        shutil.copyfile(source, blended_dir / f"frame_{output_index:04d}.png")
        output_index += 1

    for index in range(blend_count):
        tail = originals[-blend_count + index]
        head = originals[index]
        alpha = (index + 1) / float(blend_count + 1)
        destination = blended_dir / f"frame_{output_index:04d}.png"
        run(
            [
                "ffmpeg",
                "-hide_banner",
                "-loglevel",
                "error",
                "-y",
                "-i",
                str(tail),
                "-i",
                str(head),
                "-filter_complex",
                (
                    "[0:v]format=rgba,premultiply=inplace=1[tail];"
                    "[1:v]format=rgba,premultiply=inplace=1[head];"
                    f"[tail][head]blend=all_expr='A*(1-{alpha:.8f})+B*{alpha:.8f}'[mixed];"
                    "[mixed]unpremultiply=inplace=1,format=rgba[out]"
                ),
                "-map",
                "[out]",
                "-frames:v",
                "1",
                str(destination),
            ]
        )
        output_index += 1

    shutil.rmtree(frames_dir)
    blended_dir.rename(frames_dir)


def build_atlas(
    frames_dir: Path,
    atlas_path: Path,
    columns: int,
    padding: int,
    frame_width: int,
    frame_height: int,
    max_texture_size: int,
) -> tuple[int, int, int]:
    frames = frame_files(frames_dir)
    if not frames:
        raise ExtractionError("no extracted images were produced")
    safe_columns = (max_texture_size - padding) // (frame_width + padding)
    if safe_columns < 1:
        raise ExtractionError(
            f"frame width {frame_width} does not fit max texture size {max_texture_size}"
        )
    columns = min(columns, safe_columns, len(frames))
    rows = math.ceil(len(frames) / columns)
    atlas_height = rows * frame_height + (rows + 1) * padding
    if atlas_height > max_texture_size:
        raise ExtractionError(
            f"atlas would be {atlas_height}px high, above --max-texture-size; "
            "reduce extraction fps or frame dimensions"
        )
    atlas_path.parent.mkdir(parents=True, exist_ok=True)
    run(
        [
            "ffmpeg",
            "-hide_banner",
            "-loglevel",
            "error",
            "-y",
            "-framerate",
            "1",
            "-i",
            str(frames_dir / "frame_%04d.png"),
            "-vf",
            f"tile=layout={columns}x{rows}:padding={padding}:margin={padding}:color=0x00000000",
            "-frames:v",
            "1",
            str(atlas_path),
        ]
    )
    return len(frames), columns, rows


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--animation-id", required=True)
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument(
        "--source-image",
        type=Path,
        help="prepared still actually supplied to the image-to-video model",
    )
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--columns", type=int, default=8)
    parser.add_argument("--padding", type=int, default=4)
    parser.add_argument("--max-texture-size", type=int, default=8192)
    parser.add_argument("--seam-blend-frames", type=int, default=4)
    parser.add_argument("--chroma-similarity", type=float, default=0.12)
    parser.add_argument(
        "--adaptive-reference-matte",
        action="store_true",
        help=(
            "remove a flat background whose hue drifts between frames, using the "
            "prepared source image as a conservative subject reference"
        ),
    )
    parser.add_argument("--duration-tolerance", type=float, default=0.05)
    parser.add_argument("--anchor-tolerance-px", type=float, default=12.0)
    parser.add_argument("--overwrite", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    work_destination: Path | None = None
    output_lock: Any | None = None
    try:
        require_tools()
        if not args.input.is_file():
            raise ExtractionError(f"input video does not exist: {args.input}")
        if not 1 <= args.columns <= 8:
            raise ExtractionError("--columns must be between 1 and 8")
        if args.padding < 0:
            raise ExtractionError("--padding must be non-negative")
        if args.max_texture_size < 1024:
            raise ExtractionError("--max-texture-size must be at least 1024")
        if args.seam_blend_frames < 1:
            raise ExtractionError("--seam-blend-frames must be at least 1")
        if not 0.0 <= args.chroma_similarity <= 1.0:
            raise ExtractionError("--chroma-similarity must be between 0 and 1")
        if not 0.0 <= args.duration_tolerance <= 1.0:
            raise ExtractionError("--duration-tolerance must be between 0 and 1")
        if args.anchor_tolerance_px < 0:
            raise ExtractionError("--anchor-tolerance-px must be non-negative")

        animation = load_animation(args.animation_id)
        if args.adaptive_reference_matte and animation["matte"] not in {
            "magenta",
            "cyan",
            "red",
        }:
            raise ExtractionError(
                "--adaptive-reference-matte requires magenta, cyan, or red matte"
            )
        slug = args.animation_id.replace(".", "-").replace("_", "-")
        source_image = (
            args.source_image or (DEFAULT_VIDEO_SOURCES / f"{slug}.png")
        ).resolve()
        if not source_image.is_file():
            raise ExtractionError(
                f"prepared source image does not exist; pass --source-image: {source_image}"
            )
        prompt_path = ANIMATION_PROMPTS / f"{slug}.md"
        provenance_digest = input_digest([prompt_path, source_image])
        video_metadata_path = args.input.resolve().with_name(
            f"{args.input.name}.meta.json"
        )
        existing_video_provenance = validate_video_provenance(
            video_metadata_path,
            animation_id=str(animation["id"]),
            provenance_digest=provenance_digest,
            video_path=args.input.resolve(),
        )
        destination = args.output_dir.resolve() / slug
        destination.parent.mkdir(parents=True, exist_ok=True)
        output_lock = acquire_output_lock(destination)
        recover_legacy_destination(destination)
        if path_exists(destination) and not args.overwrite:
            raise ExtractionError(
                f"output already exists; pass --overwrite to replace it: {destination}"
            )
        source_info = probe_video(args.input)
        validate_source_video(animation, source_info, args.duration_tolerance)

        work = destination.with_name(f".{destination.name}.version-{uuid.uuid4().hex}")
        work_destination = work
        frames_dir = work / "frames"
        atlas_path = work / "atlas.png"
        metadata_path = work / "animation.json"
        frames_dir.mkdir(parents=True, exist_ok=True)

        run(
            [
                "ffmpeg",
                "-hide_banner",
                "-loglevel",
                "error",
                "-y",
                "-i",
                str(args.input),
                "-vf",
                extraction_filter(
                    animation,
                    args.chroma_similarity,
                    adaptive_reference_matte=args.adaptive_reference_matte,
                ),
                "-vsync",
                "0",
                str(frames_dir / "frame_%04d.png"),
            ]
        )
        expected_images = int(
            float(animation["duration_seconds"]) * int(animation["target_fps"])
        )
        raw_count = len(frame_files(frames_dir))
        if raw_count != expected_images:
            raise ExtractionError(
                f"extracted {raw_count} images before loop processing; expected exactly "
                f"{expected_images}"
            )
        matte_extraction = (
            apply_adaptive_reference_matte(
                frames_dir,
                source_image,
                animation,
            )
            if args.adaptive_reference_matte
            else {"strategy": "fixed_color"}
        )
        if animation["loop_mode"] == "seam_blend":
            apply_seam_blend(frames_dir, args.seam_blend_frames)

        if animation["matte"] in {"magenta", "cyan", "red"}:
            alpha_report = validate_extracted_alpha(
                frames_dir,
                int(animation["frame_width"]),
                int(animation["frame_height"]),
                str(animation["anchor_check"]),
            )
        elif animation["matte"] == "black":
            alpha_report = validate_black_matte_frames(
                frames_dir,
                int(animation["frame_width"]),
                int(animation["frame_height"]),
            )
        else:
            alpha_report = {
                "verified": False,
                "reason": "alpha validation is not applicable to preserved-scene output",
            }

        anchor_report = (
            verify_anchor_drift(
                frames_dir,
                args.anchor_tolerance_px,
                str(animation["anchor_check"]),
            )
            if animation["anchor_check"] != "fixed_canvas"
            and animation["matte"] in {"magenta", "cyan", "red"}
            else {
                "mode": "fixed_canvas_registration",
                "verified": False,
                "canvas_dimensions_verified": True,
                "assumption": (
                    "the extraction canvas is fixed, but internal effect attachment-point "
                    "drift was not measured"
                ),
            }
        )

        count, columns, rows = build_atlas(
            frames_dir,
            atlas_path,
            args.columns,
            args.padding,
            int(animation["frame_width"]),
            int(animation["frame_height"]),
            args.max_texture_size,
        )
        width = int(animation["frame_width"])
        height = int(animation["frame_height"])
        metadata = {
            "schema_version": 1,
            "animation_id": animation["id"],
            "source_asset_id": animation["source_asset_id"],
            "source_video": str(args.input.resolve()),
            "prepared_source_image": str(source_image),
            "input_digest": provenance_digest,
            "video_provenance": str(video_metadata_path),
            "source_probe": source_info,
            "frames_dir": str(destination / "frames"),
            "atlas": str(destination / "atlas.png"),
            "frame_count": count,
            "frame_width": width,
            "frame_height": height,
            "columns": columns,
            "rows": rows,
            "padding": args.padding,
            "atlas_width": columns * width + (columns + 1) * args.padding,
            "atlas_height": rows * height + (rows + 1) * args.padding,
            "playback_fps": animation["godot_fps"],
            "loop_mode": animation["loop_mode"],
            "runtime_playback": (
                "forward_then_reverse_without_duplicate_images"
                if animation["loop_mode"] == "ping_pong"
                else "forward"
            ),
            "seam_blend_frames": (
                args.seam_blend_frames if animation["loop_mode"] == "seam_blend" else 0
            ),
            "matte": animation["matte"],
            "matte_extraction": matte_extraction,
            "alpha": alpha_report,
            "anchor": anchor_report,
        }
        if existing_video_provenance is None:
            write_json_atomic(
                video_metadata_path,
                {
                    "schema_version": 1,
                    "id": animation["id"],
                    "input_digest": provenance_digest,
                    "output_digest": sha256_file(args.input.resolve()),
                    "prepared_source_image": str(source_image),
                },
            )
        metadata_path.write_text(
            json.dumps(metadata, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        publication_warnings = publish_version(work, destination, args.overwrite)
        work_destination = None
        for warning in publication_warnings:
            print(f"WARNING: {warning}", file=sys.stderr)
        print(json.dumps(metadata, ensure_ascii=False))
        return 0
    except (ExtractionError, json.JSONDecodeError, OSError) as exc:
        if work_destination is not None and work_destination.exists():
            shutil.rmtree(work_destination)
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    finally:
        if output_lock is not None:
            fcntl.flock(output_lock.fileno(), fcntl.LOCK_UN)
            output_lock.close()


if __name__ == "__main__":
    raise SystemExit(main())
