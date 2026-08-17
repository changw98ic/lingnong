#!/usr/bin/env python3
"""Build, validate, queue, and report Lingnong art-production prompts.

The checked-in catalog fragments are the canonical source. Generated Markdown
files are deliberately rebuilt from scratch so stale prompts cannot survive a
catalog change.
"""

from __future__ import annotations

import argparse
import fcntl
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
CATALOG_DIR = ROOT / "tools" / "art_pipeline" / "catalog"
PROMPT_ROOT = ROOT / "docs" / "art-prompts"
STATIC_PROMPT_ROOT = PROMPT_ROOT / "static"
ANIMATION_PROMPT_ROOT = PROMPT_ROOT / "animation"
REFERENCE_ROOT = PROMPT_ROOT / "references"
RUNTIME_ROOT = ROOT / ".art-pipeline"
PIPELINE_LOCK = Path.home() / ".cache" / "lingnong-art-pipeline" / "pipeline.lock"

STYLE_REFERENCE = REFERENCE_ROOT / "style-reference.png"
COMPOSITION_REFERENCE = REFERENCE_ROOT / "composition-reference.png"

STATIC_FILES = ("environment_ui.json", "gameplay_assets.json")
ANIMATION_FILE = "animations.json"

STATIC_REQUIRED = {
    "id",
    "name_zh",
    "category",
    "purpose",
    "width",
    "height",
    "background",
    "references",
    "reference_asset_ids",
    "composition",
    "visual",
    "must_include",
    "must_avoid",
    "existing_target",
    "animation_candidate",
}
ANIMATION_REQUIRED = {
    "id",
    "source_asset_id",
    "name_zh",
    "purpose",
    "duration_seconds",
    "source_fps",
    "target_fps",
    "loop_mode",
    "width",
    "height",
    "frame_width",
    "frame_height",
    "matte",
    "anchor_check",
    "motion",
    "locked_elements",
    "must_avoid",
    "godot_fps",
}

VALID_STATIC_CATEGORIES = {
    "environment",
    "brand",
    "portrait",
    "ui",
    "resource_icon",
    "farm_icon",
    "navigation_icon",
    "action_icon",
    "crop",
    "material",
    "chest",
    "realm",
    "character",
    "prop",
    "effect_source",
}
VALID_BACKGROUNDS = {"opaque", "transparent"}
VALID_REFERENCES = {"style", "composition"}
VALID_LOOP_MODES = {"ping_pong", "continuous", "seam_blend"}
VALID_MATTES = {"magenta", "cyan", "red", "black", "none"}
VALID_ANCHOR_CHECKS = {
    "bottom_center_root_region",
    "lower_right_root_region",
    "center_region",
    "body_center_region",
    "fixed_canvas",
}

PLACEHOLDER_PATTERN = re.compile(
    r"\{\{|\}\}|\[(?:ASSET|ACTION|FRAME|MOTION|MATTE|TARGET|WIDTH|HEIGHT)[^\]]*\]",
    re.IGNORECASE,
)

STYLE_BLOCK = """High-quality rounded 2D animation art for a peaceful Chinese pastoral xianxia cultivation game. Use graceful organic silhouettes, clean stable deep-brown or muted-jade outlines, broad uncluttered color shapes, soft cel shading, restrained smooth gradients, warm jade-white highlights, and gentle blue-green shadows. The result must feel like a polished commercial mobile game animation cel: bright, calm, tactile, friendly, and full of life. It is explicitly not pixel art and not a web-dashboard illustration."""

GLOBAL_AVOID = [
    "pixel art or pixelated edges",
    "noise, grain, dithering, paper texture, or rough brush texture",
    "oversharpening, edge enhancement, jagged outlines, or aliasing",
    "photorealism, 3D rendering, plastic materials, or metallic glare",
    "dark horror lighting, heavy oil-paint texture, or muddy colors",
    "science-fiction technology, Western fantasy architecture, or modern objects",
    "embedded words, letters, numbers, labels, watermarks, or signatures",
    "busy panels, dense dashboard layout, card-game framing, or website styling",
    "cropping, duplicated objects, accidental extra parts, or broken anatomy",
]

ANIMATION_COMMON_AVOID = [
    "unrequested object morphing or permanent structural drift",
    "costume changes",
    "permanent newly invented parts",
    "frame flicker or outline boiling",
    "color drift",
    "exposure pumping",
    "unstable shadows",
    "motion blur, camera blur, or smear frames",
    "duplicated subjects or scene cuts",
]


class CatalogError(RuntimeError):
    pass


def _read_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise CatalogError(f"missing catalog file: {path}") from exc
    except json.JSONDecodeError as exc:
        raise CatalogError(f"invalid JSON in {path}: {exc}") from exc


def _write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.part-{os.getpid()}")
    temporary.write_text(
        json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    os.replace(temporary, path)


@contextmanager
def _pipeline_lock() -> Any:
    """Share one OS lock with the browser runner and all queue writers."""
    PIPELINE_LOCK.parent.mkdir(parents=True, exist_ok=True)
    inherited_fd = os.environ.get("LINGNONG_PIPELINE_LOCK_FD")
    if inherited_fd is not None:
        try:
            fd = int(inherited_fd)
            descriptor_stat = os.fstat(fd)
            lock_stat = PIPELINE_LOCK.stat()
            if (descriptor_stat.st_dev, descriptor_stat.st_ino) != (
                lock_stat.st_dev,
                lock_stat.st_ino,
            ):
                raise OSError("descriptor does not refer to the pipeline lock")
            # This is idempotent for the descriptor inherited from
            # run_with_lock.py.  For a forged but valid descriptor it obtains
            # the real lock, so the environment variable cannot bypass it.
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except (ValueError, OSError, BlockingIOError) as exc:
            raise CatalogError("invalid inherited art-pipeline lock") from exc
        yield
        return
    with PIPELINE_LOCK.open("a+", encoding="utf-8") as handle:
        try:
            fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as exc:
            raise CatalogError(
                "art pipeline is busy in another process; wait for that run to finish"
            ) from exc
        handle.seek(0)
        handle.truncate()
        handle.write(f"pid={os.getpid()}\n")
        handle.flush()
        try:
            yield
        finally:
            fcntl.flock(handle.fileno(), fcntl.LOCK_UN)


def _now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def _slug(value: str) -> str:
    return value.replace(".", "-").replace("_", "-")


def _prompt_path_for_static(asset: dict[str, Any]) -> Path:
    return STATIC_PROMPT_ROOT / asset["category"] / f"{_slug(asset['id'])}.md"


def _prompt_path_for_animation(animation: dict[str, Any]) -> Path:
    return ANIMATION_PROMPT_ROOT / f"{_slug(animation['id'])}.md"


def _static_output_path(asset: dict[str, Any]) -> Path:
    return (
        RUNTIME_ROOT
        / "outputs"
        / "static"
        / asset["category"]
        / f"{_slug(asset['id'])}.png"
    )


def _animation_output_path(animation: dict[str, Any]) -> Path:
    return RUNTIME_ROOT / "outputs" / "video" / f"{_slug(animation['id'])}.mp4"


def _prepared_video_source_path(animation: dict[str, Any]) -> Path:
    return RUNTIME_ROOT / "video-sources" / f"{_slug(animation['id'])}.png"


def _output_metadata_path(output: Path) -> Path:
    return output.with_name(f"{output.name}.meta.json")


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _input_digest(paths: list[Path]) -> str:
    if not paths or any(not path.is_file() for path in paths):
        return ""
    digest = hashlib.sha256(b"lingnong-input-v1\0")
    try:
        for path in paths:
            content = path.read_bytes()
            digest.update(f"bytes:{len(content)}\n".encode())
            digest.update(content)
    except OSError:
        return ""
    return digest.hexdigest()


def _validate_output_provenance(
    item_id: str, output: Path, metadata: Path, input_digest: str
) -> tuple[bool, str]:
    if not input_digest:
        return False, "current input digest is unresolved"
    if not metadata.is_file():
        return False, f"provenance metadata is missing: {metadata}"
    try:
        value = _read_json(metadata)
    except CatalogError as exc:
        return False, str(exc)
    if not isinstance(value, dict):
        return False, f"provenance metadata must be an object: {metadata}"
    if value.get("id") != item_id:
        return False, f"provenance asset id does not match: {metadata}"
    if value.get("input_digest") != input_digest:
        return False, f"prompt or reference inputs changed: {metadata}"
    try:
        output_digest = _sha256_file(output)
    except OSError as exc:
        return False, f"could not read completed output {output}: {exc}"
    if value.get("output_digest") != output_digest:
        return False, f"output content changed after completion: {output}"
    return True, ""


def _probe_existing_image(
    path: Path, width: int, height: int, background: str
) -> tuple[bool, str]:
    if not path.exists():
        return False, ""
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
                "stream=width,height,pix_fmt,nb_read_frames",
                "-of",
                "json",
                str(path),
            ],
            text=True,
            capture_output=True,
            check=False,
            timeout=30,
        )
    except subprocess.TimeoutExpired:
        return False, f"Existing output probe timed out and was preserved: {path}"
    if result.returncode:
        return False, f"Existing output is unreadable and was preserved: {path}"
    try:
        streams = json.loads(result.stdout).get("streams", [])
    except json.JSONDecodeError:
        return False, f"Existing output probe returned invalid data and was preserved: {path}"
    if not streams:
        return False, f"Existing output has no image stream and was preserved: {path}"
    stream = streams[0]
    if str(stream.get("nb_read_frames", "")) != "1":
        return False, f"Existing output is animated or multi-frame and was preserved: {path}"
    if (int(stream.get("width", 0)), int(stream.get("height", 0))) != (
        width,
        height,
    ):
        return False, (
            f"Existing output has wrong dimensions and was preserved: {path}"
        )
    if background == "transparent":
        try:
            alpha = subprocess.run(
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
        except subprocess.TimeoutExpired:
            return False, (
                f"Existing transparent output alpha probe timed out and was preserved: {path}"
            )
        if alpha.returncode or not alpha.stdout:
            return False, (
                f"Existing transparent output has no readable alpha channel and was preserved: {path}"
            )
        pixel_count = len(alpha.stdout)
        if pixel_count != width * height:
            return False, (
                f"Existing transparent output has an unexpected alpha size and was preserved: {path}"
            )
        transparent_ratio = sum(value < 16 for value in alpha.stdout) / pixel_count
        visible_ratio = sum(value > 32 for value in alpha.stdout) / pixel_count
        corner_indices = (0, width - 1, (height - 1) * width, pixel_count - 1)
        transparent_corners = sum(
            alpha.stdout[index] < 16 for index in corner_indices
        )
        if (
            transparent_ratio < 0.10
            or visible_ratio < 0.005
            or transparent_corners < 3
        ):
            return False, (
                "Existing transparent output failed alpha coverage checks "
                f"(transparent={transparent_ratio:.2%}, visible={visible_ratio:.2%}, "
                f"transparent_corners={transparent_corners}/4) "
                f"and was preserved: {path}"
            )
    return True, ""


def load_catalogs() -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    static_assets: list[dict[str, Any]] = []
    for filename in STATIC_FILES:
        value = _read_json(CATALOG_DIR / filename)
        if not isinstance(value, list):
            raise CatalogError(f"{filename} must contain a JSON array")
        static_assets.extend(value)
    animations = _read_json(CATALOG_DIR / ANIMATION_FILE)
    if not isinstance(animations, list):
        raise CatalogError(f"{ANIMATION_FILE} must contain a JSON array")
    return static_assets, animations


def _require_fields(item: dict[str, Any], fields: set[str], source: str) -> None:
    missing = sorted(fields - set(item))
    if missing:
        raise CatalogError(f"{source} is missing fields: {', '.join(missing)}")


def validate_catalogs(
    static_assets: list[dict[str, Any]], animations: list[dict[str, Any]]
) -> list[str]:
    errors: list[str] = []
    static_ids: set[str] = set()
    static_targets: set[str] = set()
    animation_ids: set[str] = set()
    estimated_animation_bytes = 0

    for index, asset in enumerate(static_assets):
        source = f"static[{index}]"
        if not isinstance(asset, dict):
            errors.append(f"{source} must be an object")
            continue
        try:
            _require_fields(asset, STATIC_REQUIRED, source)
        except CatalogError as exc:
            errors.append(str(exc))
            continue
        asset_id = str(asset["id"])
        if not re.fullmatch(r"[a-z0-9_]+\.[a-z0-9_]+", asset_id):
            errors.append(f"{source} has invalid id: {asset_id}")
        if asset_id in static_ids:
            errors.append(f"duplicate static id: {asset_id}")
        static_ids.add(asset_id)
        target = str(asset["existing_target"])
        if not re.fullmatch(r"res://assets/[a-z0-9_./-]+\.png", target):
            errors.append(f"{asset_id} has invalid project target: {target}")
        elif target in static_targets:
            errors.append(f"duplicate project target: {target}")
        static_targets.add(target)
        if asset["category"] not in VALID_STATIC_CATEGORIES:
            errors.append(f"{asset_id} has invalid category: {asset['category']}")
        if asset["background"] not in VALID_BACKGROUNDS:
            errors.append(f"{asset_id} has invalid background: {asset['background']}")
        if not isinstance(asset["width"], int) or int(asset["width"]) <= 0:
            errors.append(f"{asset_id} width must be a positive integer")
        if not isinstance(asset["height"], int) or int(asset["height"]) <= 0:
            errors.append(f"{asset_id} height must be a positive integer")
        refs = asset["references"]
        if not isinstance(refs, list) or not refs or not set(refs) <= VALID_REFERENCES:
            errors.append(f"{asset_id} has invalid references: {refs}")
        for field in ("must_include", "must_avoid"):
            if not isinstance(asset[field], list) or not asset[field]:
                errors.append(f"{asset_id} {field} must be a non-empty array")
        for field in ("purpose", "composition", "visual"):
            if not str(asset[field]).strip():
                errors.append(f"{asset_id} {field} must not be empty")

    static_by_id = {
        asset["id"]: asset
        for asset in static_assets
        if isinstance(asset, dict) and "id" in asset
    }
    for index, animation in enumerate(animations):
        source = f"animation[{index}]"
        if not isinstance(animation, dict):
            errors.append(f"{source} must be an object")
            continue
        try:
            _require_fields(animation, ANIMATION_REQUIRED, source)
        except CatalogError as exc:
            errors.append(str(exc))
            continue
        animation_id = str(animation["id"])
        if not re.fullmatch(r"animation\.[a-z0-9_]+", animation_id):
            errors.append(f"{source} has invalid id: {animation_id}")
        if animation_id in animation_ids:
            errors.append(f"duplicate animation id: {animation_id}")
        animation_ids.add(animation_id)
        if animation["source_asset_id"] not in static_ids:
            errors.append(
                f"{animation_id} references missing source asset: "
                f"{animation['source_asset_id']}"
            )
        if animation["loop_mode"] not in VALID_LOOP_MODES:
            errors.append(
                f"{animation_id} has invalid loop mode: {animation['loop_mode']}"
            )
        if animation["matte"] not in VALID_MATTES:
            errors.append(f"{animation_id} has invalid matte: {animation['matte']}")
        if animation["anchor_check"] not in VALID_ANCHOR_CHECKS:
            errors.append(
                f"{animation_id} has invalid anchor check: {animation['anchor_check']}"
            )
        source_asset = static_by_id.get(animation["source_asset_id"])
        if source_asset is not None:
            allowed_anchors = (
                {"fixed_canvas", "lower_right_root_region"}
                if source_asset["category"] == "effect_source"
                else {
                    "bottom_center_root_region",
                    "center_region",
                    "body_center_region",
                }
            )
            if animation["anchor_check"] not in allowed_anchors:
                errors.append(
                    f"{animation_id} anchor check {animation['anchor_check']} is not "
                    f"valid for {source_asset['category']}"
                )
            if animation["matte"] == "black" and source_asset["category"] != "effect_source":
                errors.append(
                    f"{animation_id} may use black additive matte only for effect_source assets"
                )
        for field in (
            "duration_seconds",
            "source_fps",
            "target_fps",
            "width",
            "height",
            "frame_width",
            "frame_height",
            "godot_fps",
        ):
            if not isinstance(animation[field], (int, float)) or animation[field] <= 0:
                errors.append(f"{animation_id} {field} must be positive")
        for field in ("locked_elements", "must_avoid"):
            if not isinstance(animation[field], list) or not animation[field]:
                errors.append(f"{animation_id} {field} must be a non-empty array")
        if not str(animation["motion"]).strip():
            errors.append(f"{animation_id} motion must not be empty")
        estimated_images = int(
            float(animation["duration_seconds"]) * int(animation["target_fps"])
        )
        estimated_bytes = (
            estimated_images
            * int(animation["frame_width"])
            * int(animation["frame_height"])
            * 4
        )
        estimated_animation_bytes += estimated_bytes
        if estimated_bytes > 32 * 1024 * 1024:
            errors.append(
                f"{animation_id} exceeds the 32 MiB uncompressed image budget"
            )

    candidates = {
        asset["id"]
        for asset in static_assets
        if isinstance(asset, dict) and asset.get("animation_candidate") is True
    }
    covered = {
        animation["source_asset_id"]
        for animation in animations
        if isinstance(animation, dict) and "source_asset_id" in animation
    }
    for missing in sorted(candidates - covered):
        errors.append(f"animation candidate has no video prompt: {missing}")

    static_order = {asset["id"]: index for index, asset in enumerate(static_assets)}
    for asset in static_assets:
        if not isinstance(asset, dict) or "id" not in asset:
            continue
        refs = asset.get("reference_asset_ids", [])
        if not isinstance(refs, list):
            errors.append(f"{asset['id']} reference_asset_ids must be an array")
            continue
        for reference_id in refs:
            if reference_id == asset["id"]:
                errors.append(f"{asset['id']} cannot reference itself")
            elif reference_id not in static_ids:
                errors.append(
                    f"{asset['id']} references missing static asset: {reference_id}"
                )
            elif static_order[reference_id] >= static_order[asset["id"]]:
                errors.append(
                    f"{asset['id']} reference must appear earlier in queue order: {reference_id}"
                )

    if estimated_animation_bytes > 256 * 1024 * 1024:
        errors.append("animation catalog exceeds the 256 MiB uncompressed total budget")

    return errors


def _reference_lines(
    references: list[str], reference_asset_ids: list[str]
) -> str:
    lines: list[str] = []
    if "style" in references:
        lines.append(
            "- Use the attached colored reference only for palette, rounded 2D "
            "animation rendering, materials, lighting, and character proportions."
        )
    if "composition" in references:
        lines.append(
            "- Use the attached line-art reference only for camera angle, "
            "perspective, spatial placement, and relative scale."
        )
    if reference_asset_ids:
        lines.append(
            "- Use each additional attached generated character reference only for "
            "identity, facial design, body proportions, costume, and palette."
        )
        lines.append(
            "- Redraw the complete character in the new action pose required by "
            "Composition. The silhouette, limb positions, and body posture must be "
            "clearly different from the neutral reference pose. Never return, copy, "
            "trace, or lightly retouch the attached character reference itself."
        )
    lines.append(
        "- Do not copy any baked-in interface, labels, numbers, logos, or text from a reference."
    )
    return "\n".join(lines)


def _bullets(items: list[str]) -> str:
    unique: list[str] = []
    seen: set[str] = set()
    for item in items:
        normalized = re.sub(r"\s+", " ", item.strip()).casefold()
        if normalized in seen:
            continue
        seen.add(normalized)
        unique.append(item.strip())
    return "\n".join(f"- {item}" for item in unique)


def _exclusion_categories(text: str) -> set[str]:
    """Classify broad negative-prompt concepts so each concept is stated once."""
    lowered = text.casefold()
    patterns = {
        "pixel": r"\bpixel",
        "noise": r"\bnoise\b|dither|film grain|image grain|visual grain|paper texture|rough brush|texture crawling",
        "sharpness": r"sharpen|edge enhancement|jagged|aliasing",
        "realism": r"photoreal|\brealistic\b|\b3d\b|plastic material|metallic",
        "dark": r"dark horror|oil[- ]paint|muddy color",
        "setting": r"science[- ]fiction|sci-fi|western fantasy|modern object",
        "text": r"embedded word|\btext\b|\bletter|\bnumber|\blabel|watermark|signature|\blogo\b|readable rune|readable script",
        "ui": r"busy panel|dashboard|card-game|website styl|web-dashboard|admin",
        "integrity": r"cropp|duplicated object|accidental extra|broken anatomy",
        "flicker": r"flicker|outline boiling",
        "color_drift": r"color drift|hue drift|palette drift|color shift",
        "shadow_drift": r"unstable shadow|shadow drift|moving shadow direction",
        "exposure": r"exposure pumping",
        "blur": r"motion blur|camera blur|smear frame",
        "costume": r"costume change|changing costume|clothing change|changing robe",
        "structure": r"structural drift|object morph|box morph|silhouette morph|facet morph|topology change",
        "invention": r"newly invented part|permanent new object",
        "scene_integrity": r"duplicated subject|scene cut",
    }
    return {name for name, pattern in patterns.items() if re.search(pattern, lowered)}


def _strict_exclusions(
    custom_items: list[str], common_items: list[str] | None = None
) -> str:
    """Prefer a specific asset exclusion over a duplicate generic exclusion."""
    specific_items = list(custom_items)
    seen_categories: set[str] = set()
    for item in custom_items:
        seen_categories.update(_exclusion_categories(item))
    for item in common_items or []:
        categories = _exclusion_categories(item)
        if categories and categories <= seen_categories:
            continue
        specific_items.append(item)
        seen_categories.update(categories)
    global_items = [
        item
        for item in GLOBAL_AVOID
        if not (_exclusion_categories(item) & seen_categories)
    ]
    return _bullets(global_items + specific_items)


def render_static_prompt(asset: dict[str, Any]) -> str:
    prompt = f"""Create exactly one production-ready 2D game asset for the Chinese pastoral cultivation game \"Lingnong Xiuxian\".

Asset ID: {asset['id']}
Asset category: {asset['category']}
Canvas: {asset['width']} × {asset['height']} pixels
Background: {asset['background']}

Reference usage:
{_reference_lines(asset['references'], asset['reference_asset_ids'])}

Composition:
{asset['composition']}

Object and material design:
{asset['visual']}

Mandatory content:
{_bullets(asset['must_include'])}

Art direction:
{STYLE_BLOCK}

Strict exclusions:
{_strict_exclusions(asset['must_avoid'])}

Output exactly one complete image. Keep every required object fully visible. Do not output a sprite sheet, contact sheet, frame sequence, mockup page, explanatory caption, or alternate version. Do not bake interface text into the artwork. Preserve clean separation around transparent assets and do not add a ground plane unless the composition explicitly requests one."""

    existing = asset.get("existing_target") or "new asset"
    return f"""# {asset['name_zh']} — 单张母图提示词

> Generated by `tools/art_pipeline/art_pipeline.py`. Edit the catalog entry, not this file.

| Field | Value |
|---|---|
| Asset ID | `{asset['id']}` |
| Category | `{asset['category']}` |
| Output | `{asset['width']} × {asset['height']}` `{asset['background']}` PNG |
| Project target | `{existing}` |
| Animation source | `{str(asset['animation_candidate']).lower()}` |

## Generation prompt

```text
{prompt}
```
"""


def _matte_instruction(matte: str) -> str:
    if matte == "magenta":
        return (
            "Keep a perfectly flat pure chroma-magenta (#FF00FF) background. "
            "The background must remain uniform, motionless, shadowless, and absent from the subject."
        )
    if matte == "cyan":
        return (
            "Keep a perfectly flat pure chroma-cyan (#00FFFF) background. "
            "The background must remain uniform, motionless, shadowless, and absent from the subject."
        )
    if matte == "red":
        return (
            "Keep a perfectly flat pure chroma-red (#FF0000) background. "
            "The background must remain uniform, motionless, shadowless, and absent from the subject."
        )
    if matte == "black":
        return (
            "Keep a perfectly flat pure-black background for additive compositing. "
            "Do not illuminate or texture the background."
        )
    return (
        "Preserve the supplied scene background exactly. Do not move, repaint, relight, "
        "or introduce parallax into locked scenery."
    )


def _loop_instruction(loop_mode: str) -> str:
    if loop_mode == "ping_pong":
        return (
            "Generate one gentle half-cycle beginning from the neutral pose and ending at the opposite natural extreme. "
            "Do not repeat the opening pose; post-processing will mirror the clip into a seamless ping-pong loop."
        )
    if loop_mode == "continuous":
        return (
            "Complete exactly one continuous motion cycle. The final pose, orientation, lighting, and deformation must align naturally with the opening state without reversing direction."
        )
    return (
        "Begin and end in nearly identical stable states, while keeping motion alive through the entire clip. Reserve calm matching motion at both ends so a short seam blend can close the loop."
    )


def _anchor_instructions(anchor_check: str) -> tuple[str, str]:
    instructions = {
        "fixed_canvas": (
            "Keep the full overlay canvas, effect center, and scene attachment coordinates fixed throughout the video. Internal flow and silhouettes may change only as Motion explicitly requires.",
            "Keep the full overlay canvas and scene attachment coordinates fixed across all extracted images.",
        ),
        "bottom_center_root_region": (
            "Keep the subject's lower central root, feet, or base fixed at the same pixel position throughout the video.",
            "Keep a shared fixed canvas and lower central root/base anchor across all extracted images.",
        ),
        "lower_right_root_region": (
            "Keep the subject's lower-right stem base fixed at the same pixel position throughout the video.",
            "Keep a shared fixed canvas and lower-right stem-base anchor across all extracted images.",
        ),
        "center_region": (
            "Keep the subject's geometric center fixed at the same pixel position throughout the video.",
            "Keep a shared fixed canvas and geometric-center anchor across all extracted images.",
        ),
        "body_center_region": (
            "Keep the creature's central body fixed at the same pixel position throughout the video; only the explicitly requested articulated parts may move.",
            "Keep a shared fixed canvas and central-body anchor across all extracted images.",
        ),
    }
    return instructions[anchor_check]


def render_animation_prompt(
    animation: dict[str, Any], source_asset: dict[str, Any]
) -> str:
    anchor_instruction, post_anchor = _anchor_instructions(
        animation["anchor_check"]
    )
    common_avoid = [
        item
        for item in ANIMATION_COMMON_AVOID
        if item != "costume changes" or source_asset["category"] == "character"
    ]
    prompt = f"""Animate the supplied still image for asset \"{animation['source_asset_id']}\" as one continuous {animation['duration_seconds']}-second 2D game-animation video.

Motion:
{animation['motion']}

Loop construction:
{_loop_instruction(animation['loop_mode'])}

Camera and identity lock:
- Keep the camera completely locked: no zoom, pan, tilt, shake, cut, reframing, or depth-of-field change.
- Preserve the subject identity, topology, proportions, colors, materials, viewing angle, lighting direction, and clean rounded linework of the supplied still.
- Allow articulated silhouette changes, opening parts, cloth follow-through, wing motion, and temporary effects only when Motion explicitly requests them; keep every unrelated part stable.
- {anchor_instruction}
{_bullets(animation['locked_elements'])}

Background treatment:
{_matte_instruction(animation['matte'])}

Animation style:
Slow, gentle, rounded, readable 2D animation with restrained easing, natural inertia, subtle follow-through, and stable soft cel shading. Motion must remain pleasant during long idle-game viewing. Preserve broad clean color shapes with no texture crawling.

Strict exclusions:
{_strict_exclusions(animation['must_avoid'], common_avoid)}

Output one video only. Do not output a sprite sheet, storyboard, contact sheet, frame grid, captions, labels, or multiple variants."""

    return f"""# {animation['name_zh']} — 图生视频提示词

> Generated by `tools/art_pipeline/art_pipeline.py`. The image model creates only the source still; this prompt is for an image-to-video model.

| Field | Value |
|---|---|
| Animation ID | `{animation['id']}` |
| Source asset | `{animation['source_asset_id']}` / {source_asset['name_zh']} |
| Video | `{animation['duration_seconds']}s` at source `{animation['source_fps']} fps` |
| Extraction | `{animation['target_fps']} fps`, Godot playback `{animation['godot_fps']} fps` |
| Canvas | `{animation['width']} × {animation['height']}` |
| Extracted image | `{animation['frame_width']} × {animation['frame_height']}` |
| Image budget | `{int(float(animation['duration_seconds']) * int(animation['target_fps']))}` forward images before seam trimming |
| Loop | `{animation['loop_mode']}` |
| Matte | `{animation['matte']}` |
| Anchor check | `{animation['anchor_check']}` |

## Image-to-video prompt

```text
{prompt}
```

## Post-process contract

- Accept only a source video on the exact `{animation['width']} × {animation['height']}` canvas at no less than `{animation['source_fps']}` fps.
- Extract exactly `{int(float(animation['duration_seconds']) * int(animation['target_fps']))}` forward images at `{animation['target_fps']}` fps before loop processing; trim any tolerated excess duration and reject a short clip.
- Resize every extracted image to `{animation['frame_width']} × {animation['frame_height']}`. {post_anchor}
- Use the `{animation['loop_mode']}` loop treatment defined above.
- Pack the extracted images into an atlas with no more than eight columns.
- Play the resulting atlas at `{animation['godot_fps']}` fps in Godot.
"""


def _build_index(
    static_assets: list[dict[str, Any]], animations: list[dict[str, Any]]
) -> str:
    static_rows = []
    for asset in sorted(static_assets, key=lambda item: item["id"]):
        path = _prompt_path_for_static(asset).relative_to(PROMPT_ROOT)
        static_rows.append(
            f"| `{asset['id']}` | {asset['name_zh']} | `{asset['category']}` | "
            f"[{path.name}]({path.as_posix()}) |"
        )
    animation_rows = []
    for animation in sorted(animations, key=lambda item: item["id"]):
        path = _prompt_path_for_animation(animation).relative_to(PROMPT_ROOT)
        animation_rows.append(
            f"| `{animation['id']}` | {animation['name_zh']} | "
            f"`{animation['source_asset_id']}` | [{path.name}]({path.as_posix()}) |"
        )
    return f"""# 《灵农修仙》美术生产提示词

本目录由 `tools/art_pipeline/art_pipeline.py` 从唯一资产目录生成。

- 单张母图提示词：{len(static_assets)} 份
- 图生视频提示词：{len(animations)} 份
- Image 2.0 只生产单张母图；所有动画由图生视频模型生成视频后拆分。
- 彩色参考锁定画风；线稿参考只锁定构图、透视和比例。
- 所有界面文字、数字和进度值由 Godot 实时绘制，不烘焙进图片。

## 使用命令

```bash
python3 tools/art_pipeline/art_pipeline.py build
python3 tools/art_pipeline/art_pipeline.py validate
python3 tools/art_pipeline/art_pipeline.py queue --kind static
./tools/art_pipeline/ego_batch_generate.sh --dry-run
```

## 单张母图

| ID | 名称 | 分类 | 提示词 |
|---|---|---|---|
{chr(10).join(static_rows)}

## 图生视频

| ID | 名称 | 母图 | 提示词 |
|---|---|---|---|
{chr(10).join(animation_rows)}
"""


def build_prompts(
    static_assets: list[dict[str, Any]], animations: list[dict[str, Any]]
) -> None:
    errors = validate_catalogs(static_assets, animations)
    if errors:
        raise CatalogError("\n".join(errors))

    for generated_dir in (STATIC_PROMPT_ROOT, ANIMATION_PROMPT_ROOT):
        if generated_dir.exists():
            shutil.rmtree(generated_dir)
        generated_dir.mkdir(parents=True, exist_ok=True)

    by_id = {asset["id"]: asset for asset in static_assets}
    for asset in static_assets:
        path = _prompt_path_for_static(asset)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(render_static_prompt(asset), encoding="utf-8")
    for animation in animations:
        path = _prompt_path_for_animation(animation)
        path.write_text(
            render_animation_prompt(animation, by_id[animation["source_asset_id"]]),
            encoding="utf-8",
        )
    (PROMPT_ROOT / "README.md").write_text(
        _build_index(static_assets, animations), encoding="utf-8"
    )


def _reference_paths(
    asset: dict[str, Any], static_by_id: dict[str, dict[str, Any]]
) -> list[str]:
    output: list[str] = []
    if "style" in asset["references"]:
        output.append(str(STYLE_REFERENCE.resolve()))
    if "composition" in asset["references"]:
        output.append(str(COMPOSITION_REFERENCE.resolve()))
    for reference_id in asset.get("reference_asset_ids", []):
        output.append(str(_static_output_path(static_by_id[reference_id]).resolve()))
    return output


def create_queue(
    kind: str,
    destination: Path,
    static_assets: list[dict[str, Any]],
    animations: list[dict[str, Any]],
    categories: set[str],
    reset: bool,
) -> dict[str, Any]:
    previous: dict[str, dict[str, Any]] = {}
    if destination.exists() and not reset:
        old = _read_json(destination)
        previous = {item["id"]: item for item in old.get("items", [])}

    items: list[dict[str, Any]] = []
    if kind == "static":
        static_by_id = {asset["id"]: asset for asset in static_assets}
        selected_ids = {
            asset["id"]
            for asset in static_assets
            if not categories or asset["category"] in categories
        }
        changed = True
        while changed:
            changed = False
            for asset_id in tuple(selected_ids):
                for dependency in static_by_id[asset_id].get("reference_asset_ids", []):
                    if dependency not in selected_ids:
                        selected_ids.add(dependency)
                        changed = True
        for asset in static_assets:
            if asset["id"] not in selected_ids:
                continue
            prior = previous.get(asset["id"], {})
            output_path = _static_output_path(asset)
            metadata_path = _output_metadata_path(output_path)
            prompt_path = _prompt_path_for_static(asset).resolve()
            reference_files = _reference_paths(asset, static_by_id)
            input_digest = _input_digest(
                [prompt_path, *(Path(value) for value in reference_files)]
            )
            input_changed = prior.get("input_digest", "") != input_digest
            status = prior.get("status", "pending")
            existing_valid, existing_error = _probe_existing_image(
                output_path,
                int(asset["width"]),
                int(asset["height"]),
                str(asset["background"]),
            )
            if existing_valid:
                provenance_valid, provenance_error = _validate_output_provenance(
                    asset["id"], output_path, metadata_path, input_digest
                )
                status = "done" if provenance_valid else "failed"
                existing_error = provenance_error
            elif output_path.exists():
                status = "failed"
            elif status == "done":
                status = "pending"
            if input_changed and not output_path.exists():
                status = "pending"
            items.append(
                {
                    "id": asset["id"],
                    "name_zh": asset["name_zh"],
                    "category": asset["category"],
                    "prompt_file": str(prompt_path),
                    "reference_files": reference_files,
                    "dependencies": list(asset.get("reference_asset_ids", [])),
                    "output_file": str(output_path.resolve()),
                    "output_meta_file": str(metadata_path.resolve()),
                    "prompt_digest": _sha256_file(prompt_path),
                    "input_digest": input_digest,
                    "expected_width": asset["width"],
                    "expected_height": asset["height"],
                    "background": asset["background"],
                    "status": status,
                    "attempts": 0 if input_changed else int(prior.get("attempts", 0)),
                    "last_error": existing_error or prior.get("last_error", ""),
                    "updated_at": prior.get("updated_at", ""),
                }
            )
    else:
        static_by_id = {asset["id"]: asset for asset in static_assets}
        for animation in animations:
            source = static_by_id[animation["source_asset_id"]]
            if categories and source["category"] not in categories:
                continue
            prior = previous.get(animation["id"], {})
            output_path = _animation_output_path(animation)
            metadata_path = _output_metadata_path(output_path)
            prompt_path = _prompt_path_for_animation(animation).resolve()
            prepared_source = _prepared_video_source_path(animation).resolve()
            input_digest = _input_digest([prompt_path, prepared_source])
            input_changed = prior.get("input_digest", "") != input_digest
            status = prior.get("status", "pending")
            existing_error = ""
            if output_path.exists():
                provenance_valid, provenance_error = _validate_output_provenance(
                    animation["id"], output_path, metadata_path, input_digest
                )
                status = "done" if provenance_valid else "failed"
                existing_error = provenance_error
            elif status == "done" or input_changed:
                status = "pending"
            items.append(
                {
                    "id": animation["id"],
                    "name_zh": animation["name_zh"],
                    "source_asset_id": animation["source_asset_id"],
                    "source_image": str(_static_output_path(source).resolve()),
                    "prepared_source_image": str(prepared_source),
                    "prompt_file": str(prompt_path),
                    "output_file": str(output_path.resolve()),
                    "output_meta_file": str(metadata_path.resolve()),
                    "prompt_digest": _sha256_file(prompt_path),
                    "input_digest": input_digest,
                    "duration_seconds": animation["duration_seconds"],
                    "source_fps": animation["source_fps"],
                    "target_fps": animation["target_fps"],
                    "godot_fps": animation["godot_fps"],
                    "loop_mode": animation["loop_mode"],
                    "matte": animation["matte"],
                    "anchor_check": animation["anchor_check"],
                    "width": animation["width"],
                    "height": animation["height"],
                    "frame_width": animation["frame_width"],
                    "frame_height": animation["frame_height"],
                    "estimated_frame_count": int(
                        float(animation["duration_seconds"])
                        * int(animation["target_fps"])
                    ),
                    "estimated_rgba_bytes": int(
                        float(animation["duration_seconds"])
                        * int(animation["target_fps"])
                        * int(animation["frame_width"])
                        * int(animation["frame_height"])
                        * 4
                    ),
                    "status": status,
                    "attempts": 0 if input_changed else int(prior.get("attempts", 0)),
                    "last_error": existing_error or prior.get("last_error", ""),
                    "updated_at": prior.get("updated_at", ""),
                }
            )

    queue = {
        "schema_version": 2,
        "kind": kind,
        "created_at": _now(),
        "concurrency": 1,
        "items": items,
    }
    _write_json(destination, queue)
    return queue


def queue_summary(queue: dict[str, Any]) -> dict[str, Any]:
    counts = {"pending": 0, "running": 0, "done": 0, "failed": 0}
    existing_outputs = 0
    for item in queue.get("items", []):
        status = item.get("status", "pending")
        counts[status] = counts.get(status, 0) + 1
        if Path(item["output_file"]).exists():
            existing_outputs += 1
    return {
        "kind": queue.get("kind", "unknown"),
        "total": len(queue.get("items", [])),
        **counts,
        "existing_outputs": existing_outputs,
    }


def _matches_queue_type(value: Any, expected: type | tuple[type, ...]) -> bool:
    numeric_types = expected if isinstance(expected, tuple) else (expected,)
    if isinstance(value, bool) and any(kind in {int, float} for kind in numeric_types):
        return False
    return isinstance(value, expected)


def _canonical_queue_contracts(
    kind: str,
) -> tuple[dict[str, dict[str, Any]], dict[str, str]]:
    static_assets, animations = load_catalogs()
    static_by_id = {asset["id"]: asset for asset in static_assets}
    contracts: dict[str, dict[str, Any]] = {}
    prompt_texts: dict[str, str] = {}
    if kind == "static":
        for asset in static_assets:
            output = _static_output_path(asset).resolve()
            prompt = _prompt_path_for_static(asset).resolve()
            contracts[asset["id"]] = {
                "name_zh": asset["name_zh"],
                "category": asset["category"],
                "prompt_file": str(prompt),
                "reference_files": _reference_paths(asset, static_by_id),
                "dependencies": list(asset.get("reference_asset_ids", [])),
                "output_file": str(output),
                "output_meta_file": str(_output_metadata_path(output).resolve()),
                "expected_width": int(asset["width"]),
                "expected_height": int(asset["height"]),
                "background": asset["background"],
            }
            prompt_texts[asset["id"]] = render_static_prompt(asset)
    elif kind == "animation":
        for animation in animations:
            source = static_by_id[animation["source_asset_id"]]
            output = _animation_output_path(animation).resolve()
            prompt = _prompt_path_for_animation(animation).resolve()
            duration = float(animation["duration_seconds"])
            target_fps = int(animation["target_fps"])
            frame_width = int(animation["frame_width"])
            frame_height = int(animation["frame_height"])
            contracts[animation["id"]] = {
                "name_zh": animation["name_zh"],
                "source_asset_id": animation["source_asset_id"],
                "source_image": str(_static_output_path(source).resolve()),
                "prepared_source_image": str(
                    _prepared_video_source_path(animation).resolve()
                ),
                "prompt_file": str(prompt),
                "output_file": str(output),
                "output_meta_file": str(_output_metadata_path(output).resolve()),
                "duration_seconds": animation["duration_seconds"],
                "source_fps": animation["source_fps"],
                "target_fps": animation["target_fps"],
                "godot_fps": animation["godot_fps"],
                "loop_mode": animation["loop_mode"],
                "matte": animation["matte"],
                "anchor_check": animation["anchor_check"],
                "width": int(animation["width"]),
                "height": int(animation["height"]),
                "frame_width": frame_width,
                "frame_height": frame_height,
                "estimated_frame_count": int(duration * target_fps),
                "estimated_rgba_bytes": int(
                    duration * target_fps * frame_width * frame_height * 4
                ),
            }
            prompt_texts[animation["id"]] = render_animation_prompt(
                animation, source
            )
    return contracts, prompt_texts


def validate_queue(queue: Any, source: Path) -> list[str]:
    errors: list[str] = []
    if not isinstance(queue, dict):
        return [f"queue must be a JSON object: {source}"]
    if queue.get("schema_version") != 2:
        errors.append(f"queue schema_version must be 2: {source}")
    kind = queue.get("kind")
    if kind not in {"static", "animation"}:
        errors.append(f"queue kind must be static or animation: {source}")
    if queue.get("concurrency") != 1:
        errors.append(f"queue concurrency must be 1: {source}")
    items = queue.get("items")
    if not isinstance(items, list):
        return errors + [f"queue items must be an array: {source}"]

    common_fields = {
        "id": str,
        "name_zh": str,
        "prompt_file": str,
        "output_file": str,
        "output_meta_file": str,
        "prompt_digest": str,
        "input_digest": str,
        "status": str,
        "attempts": int,
        "last_error": str,
        "updated_at": str,
    }
    static_fields = {
        "category": str,
        "reference_files": list,
        "dependencies": list,
        "expected_width": int,
        "expected_height": int,
        "background": str,
    }
    animation_fields = {
        "source_asset_id": str,
        "source_image": str,
        "prepared_source_image": str,
        "duration_seconds": (int, float),
        "source_fps": (int, float),
        "target_fps": (int, float),
        "godot_fps": (int, float),
        "loop_mode": str,
        "matte": str,
        "anchor_check": str,
        "width": int,
        "height": int,
        "frame_width": int,
        "frame_height": int,
        "estimated_frame_count": int,
        "estimated_rgba_bytes": int,
    }
    expected_fields = common_fields | (
        static_fields
        if kind == "static"
        else animation_fields if kind == "animation" else {}
    )
    try:
        canonical_contracts, canonical_prompt_texts = _canonical_queue_contracts(
            str(kind)
        )
    except CatalogError as exc:
        errors.append(str(exc))
        canonical_contracts, canonical_prompt_texts = {}, {}
    ids: set[str] = set()
    for index, item in enumerate(items):
        label = f"queue item {index}"
        if not isinstance(item, dict):
            errors.append(f"{label} must be an object")
            continue
        for field, field_type in expected_fields.items():
            if field not in item:
                errors.append(f"{label} is missing {field}")
            elif not _matches_queue_type(item[field], field_type):
                errors.append(f"{label} {field} has the wrong type")
        item_id = item.get("id")
        if isinstance(item_id, str):
            if item_id in ids:
                errors.append(f"duplicate queue item id: {item_id}")
            ids.add(item_id)
            contract = canonical_contracts.get(item_id)
            if contract is None:
                errors.append(f"{label} has unknown {kind} asset id: {item_id}")
            else:
                for field, expected_value in contract.items():
                    if item.get(field) != expected_value:
                        errors.append(
                            f"{label} {field} does not match the canonical catalog value"
                        )
                canonical_prompt = canonical_prompt_texts[item_id]
                prompt_path = Path(str(item.get("prompt_file", "")))
                if prompt_path.is_file():
                    try:
                        if prompt_path.read_text(encoding="utf-8") != canonical_prompt:
                            errors.append(
                                f"{label} prompt content does not match the canonical catalog"
                            )
                    except OSError as exc:
                        errors.append(f"{label} prompt could not be read: {exc}")
        if item.get("status") not in {"pending", "running", "done", "failed"}:
            errors.append(f"{label} has invalid status: {item.get('status')}")
        if isinstance(item.get("attempts"), int) and item["attempts"] < 0:
            errors.append(f"{label} attempts must be non-negative")
        digest = item.get("input_digest")
        if isinstance(digest, str) and digest and not re.fullmatch(r"[0-9a-f]{64}", digest):
            errors.append(f"{label} input_digest must be empty or a lowercase SHA-256")
        prompt_digest = item.get("prompt_digest")
        if isinstance(prompt_digest, str) and not re.fullmatch(
            r"[0-9a-f]{64}", prompt_digest
        ):
            errors.append(f"{label} prompt_digest must be a lowercase SHA-256")
        prompt_file = item.get("prompt_file")
        if isinstance(prompt_file, str) and not Path(prompt_file).is_file():
            errors.append(f"{label} prompt file is missing: {prompt_file}")
        elif isinstance(prompt_file, str) and isinstance(prompt_digest, str):
            try:
                if prompt_digest != _sha256_file(Path(prompt_file)):
                    errors.append(f"{label} prompt digest is stale; rebuild the queue")
            except OSError as exc:
                errors.append(f"{label} prompt could not be hashed: {exc}")
        if kind == "static":
            refs = item.get("reference_files")
            dependencies = item.get("dependencies")
            if isinstance(refs, list):
                for reference in refs:
                    generated_reference = isinstance(reference, str) and Path(
                        reference
                    ).is_relative_to((RUNTIME_ROOT / "outputs" / "static").resolve())
                    # Generated dependencies are intentionally absent until their
                    # parent item is done, so only fixed references are required now.
                    if (
                        not isinstance(reference, str)
                        or not Path(reference).is_file()
                    ) and not generated_reference:
                        errors.append(f"{label} reference file is missing: {reference}")
            if isinstance(dependencies, list) and not all(
                isinstance(value, str) for value in dependencies
            ):
                errors.append(f"{label} dependencies must contain only strings")
            if item.get("background") not in VALID_BACKGROUNDS:
                errors.append(f"{label} has invalid background: {item.get('background')}")
            for field in ("expected_width", "expected_height"):
                value = item.get(field)
                if _matches_queue_type(value, int) and value <= 0:
                    errors.append(f"{label} {field} must be greater than zero")
            if isinstance(prompt_file, str) and isinstance(refs, list) and all(
                isinstance(reference, str) for reference in refs
            ):
                current_digest = _input_digest(
                    [Path(prompt_file), *(Path(reference) for reference in refs)]
                )
                if item.get("input_digest") != current_digest:
                    errors.append(
                        f"{label} input digest is stale; rebuild the queue"
                    )
        elif kind == "animation":
            if item.get("loop_mode") not in VALID_LOOP_MODES:
                errors.append(f"{label} has invalid loop_mode: {item.get('loop_mode')}")
            if item.get("matte") not in VALID_MATTES:
                errors.append(f"{label} has invalid matte: {item.get('matte')}")
            if item.get("anchor_check") not in VALID_ANCHOR_CHECKS:
                errors.append(
                    f"{label} has invalid anchor_check: {item.get('anchor_check')}"
                )
            for field in (
                "duration_seconds",
                "source_fps",
                "target_fps",
                "godot_fps",
                "width",
                "height",
                "frame_width",
                "frame_height",
                "estimated_frame_count",
                "estimated_rgba_bytes",
            ):
                value = item.get(field)
                if _matches_queue_type(value, (int, float)) and value <= 0:
                    errors.append(f"{label} {field} must be greater than zero")
            if isinstance(prompt_file, str) and isinstance(
                item.get("prepared_source_image"), str
            ):
                current_digest = _input_digest(
                    [Path(prompt_file), Path(item["prepared_source_image"])]
                )
                if item.get("input_digest") != current_digest:
                    errors.append(f"{label} input digest is stale; rebuild the queue")

        if item.get("status") == "done":
            output_file = item.get("output_file")
            metadata_file = item.get("output_meta_file")
            input_digest = item.get("input_digest")
            if not all(
                isinstance(value, str)
                for value in (output_file, metadata_file, input_digest)
            ):
                errors.append(f"{label} cannot verify completed output provenance")
            elif not Path(output_file).is_file():
                errors.append(f"{label} completed output is missing: {output_file}")
            else:
                provenance_valid, provenance_error = _validate_output_provenance(
                    str(item.get("id")),
                    Path(output_file),
                    Path(metadata_file),
                    input_digest,
                )
                if not provenance_valid:
                    errors.append(f"{label} {provenance_error}")

    if kind == "static":
        dependency_graph: dict[str, list[str]] = {}
        for index, item in enumerate(items):
            if not isinstance(item, dict) or not isinstance(item.get("dependencies"), list):
                continue
            item_id = item.get("id")
            if isinstance(item_id, str):
                dependency_graph[item_id] = [
                    value for value in item["dependencies"] if isinstance(value, str)
                ]
            for dependency in item["dependencies"]:
                if dependency not in ids:
                    errors.append(
                        f"queue item {index} dependency is absent from this queue: {dependency}"
                    )
                if dependency == item_id:
                    errors.append(f"queue item {index} cannot depend on itself: {dependency}")

        visiting: set[str] = set()
        visited: set[str] = set()

        def visit(item_id: str, trail: list[str]) -> None:
            if item_id in visited:
                return
            if item_id in visiting:
                cycle_start = trail.index(item_id) if item_id in trail else 0
                cycle = trail[cycle_start:] + [item_id]
                errors.append(f"queue dependency cycle: {' -> '.join(cycle)}")
                return
            visiting.add(item_id)
            for dependency in dependency_graph.get(item_id, []):
                if dependency in dependency_graph:
                    visit(dependency, [*trail, item_id])
            visiting.remove(item_id)
            visited.add(item_id)

        for item_id in dependency_graph:
            visit(item_id, [])
    return errors


def validate_generated(
    static_assets: list[dict[str, Any]], animations: list[dict[str, Any]]
) -> list[str]:
    errors = validate_catalogs(static_assets, animations)
    if not STYLE_REFERENCE.exists():
        errors.append(f"missing style reference: {STYLE_REFERENCE}")
    if not COMPOSITION_REFERENCE.exists():
        errors.append(f"missing composition reference: {COMPOSITION_REFERENCE}")

    static_by_id = {asset["id"]: asset for asset in static_assets}
    expected_files: list[tuple[Path, str]] = [
        (_prompt_path_for_static(asset), render_static_prompt(asset))
        for asset in static_assets
    ]
    expected_files.extend(
        (
            _prompt_path_for_animation(item),
            render_animation_prompt(item, static_by_id[item["source_asset_id"]]),
        )
        for item in animations
    )
    expected_paths = {path.resolve() for path, _ in expected_files}
    actual_paths = {
        path.resolve()
        for root in (STATIC_PROMPT_ROOT, ANIMATION_PROMPT_ROOT)
        if root.exists()
        for path in root.rglob("*.md")
    }
    for unexpected in sorted(actual_paths - expected_paths):
        errors.append(f"unexpected stale prompt file; rebuild to remove it: {unexpected}")
    for path, expected_text in expected_files:
        if not path.exists():
            errors.append(f"missing generated prompt: {path}")
            continue
        text = path.read_text(encoding="utf-8")
        if text != expected_text:
            errors.append(f"generated prompt is stale; rebuild it: {path}")
        if PLACEHOLDER_PATTERN.search(text):
            errors.append(f"unresolved placeholder in: {path}")
        if "```text" not in text:
            errors.append(f"missing copyable prompt block in: {path}")
            continue
        match = re.search(r"```text\n([\s\S]*?)\n```", text)
        if match and re.search(r"[\u4e00-\u9fff]", match.group(1)):
            errors.append(f"generation prompt is not fully English: {path}")
    index_path = PROMPT_ROOT / "README.md"
    expected_index = _build_index(static_assets, animations)
    if not index_path.exists():
        errors.append(f"missing generated prompt index: {index_path}")
    elif index_path.read_text(encoding="utf-8") != expected_index:
        errors.append(f"generated prompt index is stale; rebuild it: {index_path}")
    return errors


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("build", help="rebuild every Markdown prompt")
    subparsers.add_parser("validate", help="validate catalogs and generated files")

    queue_parser = subparsers.add_parser("queue", help="create or resume a queue")
    queue_parser.add_argument("--kind", choices=("static", "animation"), required=True)
    queue_parser.add_argument("--output", type=Path)
    queue_parser.add_argument("--category", action="append", default=[])
    queue_parser.add_argument("--reset", action="store_true")

    report_parser = subparsers.add_parser("report", help="summarize a queue")
    report_parser.add_argument("--queue", type=Path, required=True)
    validate_queue_parser = subparsers.add_parser(
        "validate-queue", help="validate a saved queue contract"
    )
    validate_queue_parser.add_argument("--queue", type=Path, required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        static_assets, animations = load_catalogs()
        if args.command == "build":
            with _pipeline_lock():
                build_prompts(static_assets, animations)
            print(
                json.dumps(
                    {
                        "static_prompts": len(static_assets),
                        "animation_prompts": len(animations),
                        "output": str(PROMPT_ROOT),
                    },
                    ensure_ascii=False,
                )
            )
            return 0
        if args.command == "validate":
            errors = validate_generated(static_assets, animations)
            if errors:
                for error in errors:
                    print(f"ERROR: {error}", file=sys.stderr)
                return 1
            print(
                json.dumps(
                    {
                        "status": "valid",
                        "static_prompts": len(static_assets),
                        "animation_prompts": len(animations),
                    },
                    ensure_ascii=False,
                )
            )
            return 0
        if args.command == "queue":
            generated_errors = validate_generated(static_assets, animations)
            if generated_errors:
                raise CatalogError("\n".join(generated_errors))
            default_name = f"{args.kind}.json"
            destination = args.output or (RUNTIME_ROOT / "queues" / default_name)
            with _pipeline_lock():
                queue = create_queue(
                    args.kind,
                    destination,
                    static_assets,
                    animations,
                    set(args.category),
                    args.reset,
                )
            queue_errors = validate_queue(queue, destination)
            if queue_errors:
                raise CatalogError("\n".join(queue_errors))
            print(
                json.dumps(
                    {"queue": str(destination.resolve()), **queue_summary(queue)},
                    ensure_ascii=False,
                )
            )
            return 0
        if args.command == "report":
            queue = _read_json(args.queue)
            queue_errors = validate_queue(queue, args.queue)
            if queue_errors:
                raise CatalogError("\n".join(queue_errors))
            print(json.dumps(queue_summary(queue), ensure_ascii=False, indent=2))
            return 0
        if args.command == "validate-queue":
            queue = _read_json(args.queue)
            queue_errors = validate_queue(queue, args.queue)
            if queue_errors:
                raise CatalogError("\n".join(queue_errors))
            print(
                json.dumps(
                    {"status": "valid", "queue": str(args.queue.resolve())},
                    ensure_ascii=False,
                )
            )
            return 0
    except CatalogError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
