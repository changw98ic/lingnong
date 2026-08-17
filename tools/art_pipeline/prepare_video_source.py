#!/usr/bin/env python3
"""Place a generated still on the exact canvas/matte required by a video prompt."""

from __future__ import annotations

import argparse
import fcntl
import hashlib
import json
import os
import shutil
import subprocess
import sys
import uuid
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / "tools" / "art_pipeline" / "catalog" / "animations.json"
DEFAULT_OUTPUT = ROOT / ".art-pipeline" / "video-sources"
OUTPUT_LOCK_ROOT = Path.home() / ".cache" / "lingnong-art-pipeline" / "output-locks"


class PreparationError(RuntimeError):
    pass


def load_animation(animation_id: str) -> dict[str, Any]:
    animations = json.loads(CATALOG.read_text(encoding="utf-8"))
    for animation in animations:
        if animation["id"] == animation_id:
            return animation
    raise PreparationError(f"unknown animation id: {animation_id}")


def run(command: list[str]) -> None:
    try:
        result = subprocess.run(
            command, text=True, capture_output=True, check=False, timeout=120
        )
    except subprocess.TimeoutExpired as exc:
        raise PreparationError(f"command timed out: {' '.join(command)}") from exc
    if result.returncode:
        raise PreparationError(
            f"command failed ({result.returncode}): {' '.join(command)}\n{result.stderr.strip()}"
        )


def probe_image(path: Path) -> tuple[int, int]:
    try:
        result = subprocess.run(
            [
                "ffprobe",
                "-v",
                "error",
                "-count_frames",
                "-select_streams",
                "v:0",
                "-show_entries",
                "stream=width,height,nb_read_frames",
                "-of",
                "json",
                str(path),
            ],
            text=True,
            capture_output=True,
            check=False,
            timeout=30,
        )
    except subprocess.TimeoutExpired as exc:
        raise PreparationError("image probe timed out") from exc
    if result.returncode:
        raise PreparationError(f"ffprobe rejected prepared image: {result.stderr.strip()}")
    streams = json.loads(result.stdout).get("streams", [])
    if not streams:
        raise PreparationError("prepared image has no readable image stream")
    if str(streams[0].get("nb_read_frames", "")) != "1":
        raise PreparationError("animated or multi-frame source images are not accepted")
    return int(streams[0]["width"]), int(streams[0]["height"])


def alpha_coverage(path: Path) -> tuple[float, float, int]:
    try:
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
                "-frames:v",
                "1",
                "-f",
                "rawvideo",
                "-pix_fmt",
                "gray",
                "-",
            ],
            capture_output=True,
            check=False,
            timeout=30,
        )
    except subprocess.TimeoutExpired as exc:
        raise PreparationError("source alpha probe timed out") from exc
    if result.returncode or not result.stdout:
        raise PreparationError("source image has no readable alpha channel")
    count = len(result.stdout)
    width, height = probe_image(path)
    if count != width * height:
        raise PreparationError("source image alpha channel has an unexpected size")
    transparent = sum(value < 16 for value in result.stdout) / count
    visible = sum(value > 32 for value in result.stdout) / count
    corner_indices = (0, width - 1, (height - 1) * width, count - 1)
    transparent_corners = sum(result.stdout[index] < 16 for index in corner_indices)
    return transparent, visible, transparent_corners


def validate_transparent_source(path: Path, anchor_check: str) -> None:
    transparent, visible, transparent_corners = alpha_coverage(path)
    fixed_canvas = anchor_check == "fixed_canvas"
    required_transparent = 0.05 if fixed_canvas else 0.10
    required_corners = 1 if fixed_canvas else 3
    if (
        transparent < required_transparent
        or visible < 0.005
        or transparent_corners < required_corners
    ):
        raise PreparationError(
            "source image failed alpha coverage checks "
            f"(transparent={transparent:.2%}, visible={visible:.2%}, "
            f"transparent_corners={transparent_corners}/4, "
            f"required_transparent={required_transparent:.0%}, "
            f"required_corners={required_corners})"
        )


def validate_prepared_matte(path: Path, matte: str) -> None:
    colors = {
        "magenta": (255, 0, 255),
        "cyan": (0, 255, 255),
        "red": (255, 0, 0),
        "black": (0, 0, 0),
    }
    try:
        result = subprocess.run(
            [
                "ffmpeg",
                "-hide_banner",
                "-loglevel",
                "error",
                "-i",
                str(path),
                "-frames:v",
                "1",
                "-f",
                "rawvideo",
                "-pix_fmt",
                "rgb24",
                "-",
            ],
            capture_output=True,
            check=False,
            timeout=30,
        )
    except subprocess.TimeoutExpired as exc:
        raise PreparationError("prepared matte probe timed out") from exc
    width, height = probe_image(path)
    expected_bytes = width * height * 3
    if result.returncode or len(result.stdout) != expected_bytes:
        raise PreparationError("prepared image has no readable RGB pixels")
    target = colors[matte]
    matte_pixels = 0
    total = len(result.stdout) // 3
    for index in range(0, len(result.stdout), 3):
        pixel = result.stdout[index : index + 3]
        if all(abs(pixel[channel] - target[channel]) <= 3 for channel in range(3)):
            matte_pixels += 1
    matte_ratio = matte_pixels / total
    subject_ratio = 1.0 - matte_ratio
    if matte_ratio < 0.02 or subject_ratio < 0.005:
        raise PreparationError(
            "prepared image failed matte coverage checks "
            f"(matte={matte_ratio:.2%}, subject={subject_ratio:.2%})"
        )


def acquire_output_lock(output: Path) -> Any:
    OUTPUT_LOCK_ROOT.mkdir(parents=True, exist_ok=True)
    key = hashlib.sha256(str(output).encode("utf-8")).hexdigest()
    lock_path = OUTPUT_LOCK_ROOT / f"{key}.lock"
    handle = lock_path.open("a+", encoding="utf-8")
    try:
        fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError as exc:
        handle.close()
        raise PreparationError(f"another process is preparing this output: {output}") from exc
    handle.seek(0)
    handle.truncate()
    handle.write(f"pid={os.getpid()} output={output}\n")
    handle.flush()
    return handle


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--animation-id", required=True)
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--overwrite", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    temp: Path | None = None
    output_lock: Any | None = None
    try:
        for command in ("ffmpeg", "ffprobe"):
            if shutil.which(command) is None:
                raise PreparationError(f"required command is missing: {command}")
        if not args.input.is_file():
            raise PreparationError(f"source image does not exist: {args.input}")
        probe_image(args.input)
        animation = load_animation(args.animation_id)
        width = int(animation["width"])
        height = int(animation["height"])
        slug = args.animation_id.replace(".", "-").replace("_", "-")
        output = args.output or (DEFAULT_OUTPUT / f"{slug}.png")
        output = output.resolve()
        output.parent.mkdir(parents=True, exist_ok=True)
        output_lock = acquire_output_lock(output)
        if output.exists() and not args.overwrite:
            raise PreparationError(
                f"output already exists; pass --overwrite to replace it: {output}"
            )
        temp = output.with_name(f".{output.name}.part-{uuid.uuid4().hex}.png")

        matte = animation["matte"]
        if matte != "none":
            validate_transparent_source(args.input, str(animation["anchor_check"]))
        if matte == "none":
            filter_graph = (
                f"scale={width}:{height}:force_original_aspect_ratio=decrease:flags=lanczos,"
                f"pad={width}:{height}:(ow-iw)/2:(oh-ih)/2:color=0x000000ff,format=rgb24"
            )
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
                    filter_graph,
                    "-frames:v",
                    "1",
                    str(temp),
                ]
            )
        else:
            color = {
                "magenta": "0xFF00FF",
                "cyan": "0x00FFFF",
                "red": "0xFF0000",
                "black": "0x000000",
            }[matte]
            foreground = (
                f"[1:v]scale={width}:{height}:force_original_aspect_ratio=decrease:flags=lanczos"
                f"[fg]"
            )
            anchor_check = str(animation["anchor_check"])
            if anchor_check == "lower_right_root_region":
                overlay_position = "x=W-w:y=H-h"
            elif anchor_check in {"center_region", "body_center_region", "fixed_canvas"}:
                overlay_position = "x=(W-w)/2:y=(H-h)/2"
            else:
                overlay_position = "x=(W-w)/2:y=H-h"
            composite = f"[0:v][fg]overlay={overlay_position}:format=auto,format=rgb24[out]"
            run(
                [
                    "ffmpeg",
                    "-hide_banner",
                    "-loglevel",
                    "error",
                    "-y",
                    "-f",
                    "lavfi",
                    "-i",
                    f"color=c={color}:s={width}x{height}:d=1",
                    "-i",
                    str(args.input),
                    "-filter_complex",
                    f"{foreground};{composite}",
                    "-map",
                    "[out]",
                    "-frames:v",
                    "1",
                    str(temp),
                ]
            )
        actual_width, actual_height = probe_image(temp)
        if (actual_width, actual_height) != (width, height):
            raise PreparationError(
                f"prepared image is {actual_width}x{actual_height}, expected {width}x{height}"
            )
        if matte != "none":
            validate_prepared_matte(temp, matte)
        if args.overwrite:
            os.replace(temp, output)
        else:
            try:
                os.link(temp, output)
            except FileExistsError as exc:
                raise PreparationError(
                    f"output appeared while preparing; preserved it: {output}"
                ) from exc
            temp.unlink()
        print(
            json.dumps(
                {
                    "animation_id": args.animation_id,
                    "source": str(args.input.resolve()),
                    "output": str(output),
                    "width": width,
                    "height": height,
                    "matte": matte,
                    "anchor": animation["anchor_check"],
                },
                ensure_ascii=False,
            )
        )
        return 0
    except (PreparationError, OSError, json.JSONDecodeError) as exc:
        if temp is not None:
            temp.unlink(missing_ok=True)
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    finally:
        if output_lock is not None:
            fcntl.flock(output_lock.fileno(), fcntl.LOCK_UN)
            output_lock.close()


if __name__ == "__main__":
    raise SystemExit(main())
