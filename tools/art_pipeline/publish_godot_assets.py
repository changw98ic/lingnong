#!/usr/bin/env python3
"""Publish validated art-pipeline outputs as Godot-native project assets."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import struct
import sys
import uuid
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_PIPELINE_ROOT = ROOT / ".art-pipeline"
DEFAULT_CATALOG_ROOT = ROOT / "tools" / "art_pipeline" / "catalog"
DEFAULT_DESTINATION = ROOT / "assets" / "art"


class PublishError(RuntimeError):
    pass


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise PublishError(f"invalid JSON: {path}") from exc


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def png_dimensions(path: Path) -> tuple[int, int]:
    try:
        with path.open("rb") as handle:
            header = handle.read(24)
    except OSError as exc:
        raise PublishError(f"cannot read PNG: {path}") from exc
    if len(header) != 24 or header[:8] != b"\x89PNG\r\n\x1a\n":
        raise PublishError(f"not a PNG file: {path}")
    if header[12:16] != b"IHDR":
        raise PublishError(f"PNG has no IHDR header: {path}")
    return struct.unpack(">II", header[16:24])


def load_catalogs(catalog_root: Path) -> tuple[dict[str, Any], dict[str, Any]]:
    static_entries: dict[str, Any] = {}
    for filename in ("environment_ui.json", "gameplay_assets.json"):
        path = catalog_root / filename
        value = load_json(path)
        if not isinstance(value, list):
            raise PublishError(f"catalog must be a list: {path}")
        for entry in value:
            if not isinstance(entry, dict) or not isinstance(entry.get("id"), str):
                raise PublishError(f"catalog entry has no id: {path}")
            asset_id = entry["id"]
            if asset_id in static_entries:
                raise PublishError(f"duplicate static catalog id: {asset_id}")
            static_entries[asset_id] = entry

    animation_path = catalog_root / "animations.json"
    animation_value = load_json(animation_path)
    if not isinstance(animation_value, list):
        raise PublishError(f"catalog must be a list: {animation_path}")
    animation_entries: dict[str, Any] = {}
    for entry in animation_value:
        if not isinstance(entry, dict) or not isinstance(entry.get("id"), str):
            raise PublishError("animation catalog entry has no id")
        animation_id = entry["id"]
        if animation_id in animation_entries:
            raise PublishError(f"duplicate animation catalog id: {animation_id}")
        animation_entries[animation_id] = entry
    return static_entries, animation_entries


def validate_static_sources(
    source_root: Path, catalog: dict[str, Any]
) -> dict[str, tuple[Path, dict[str, Any]]]:
    outputs: dict[str, tuple[Path, dict[str, Any]]] = {}
    for path in sorted(source_root.glob("*/*.png")):
        metadata_path = path.with_name(path.name + ".meta.json")
        if not metadata_path.is_file():
            raise PublishError(f"static asset has no provenance metadata: {path}")
        metadata = load_json(metadata_path)
        if not isinstance(metadata, dict) or not isinstance(metadata.get("id"), str):
            raise PublishError(f"static metadata has no asset id: {metadata_path}")
        asset_id = metadata["id"]
        if asset_id in outputs:
            raise PublishError(f"duplicate static output id: {asset_id}")
        entry = catalog.get(asset_id)
        if entry is None:
            raise PublishError(f"static output is not in the catalog: {asset_id}")
        if path.parent.name != entry.get("category"):
            raise PublishError(f"static category does not match catalog: {asset_id}")
        actual_dimensions = png_dimensions(path)
        expected_dimensions = (int(entry["width"]), int(entry["height"]))
        if actual_dimensions != expected_dimensions:
            raise PublishError(
                f"static dimensions do not match catalog: {asset_id} "
                f"{actual_dimensions} != {expected_dimensions}"
            )
        if metadata.get("output_digest") != sha256_file(path):
            raise PublishError(f"static output digest does not match: {asset_id}")
        outputs[asset_id] = (path, metadata)

    missing = sorted(set(catalog) - set(outputs))
    if missing:
        raise PublishError(f"missing static outputs: {', '.join(missing)}")
    return outputs


def validate_animation_sources(
    source_root: Path, catalog: dict[str, Any]
) -> dict[str, tuple[Path, dict[str, Any]]]:
    outputs: dict[str, tuple[Path, dict[str, Any]]] = {}
    for metadata_path in sorted(source_root.glob("animation-*/animation.json")):
        metadata = load_json(metadata_path)
        if not isinstance(metadata, dict) or not isinstance(
            metadata.get("animation_id"), str
        ):
            raise PublishError(f"animation metadata has no id: {metadata_path}")
        animation_id = metadata["animation_id"]
        if animation_id in outputs:
            raise PublishError(f"duplicate animation output id: {animation_id}")
        entry = catalog.get(animation_id)
        if entry is None:
            raise PublishError(
                f"animation output is not in the catalog: {animation_id}"
            )

        expected_fields = {
            "source_asset_id": entry["source_asset_id"],
            "frame_width": int(entry["frame_width"]),
            "frame_height": int(entry["frame_height"]),
            "playback_fps": int(entry["godot_fps"]),
            "loop_mode": entry["loop_mode"],
        }
        for field, expected in expected_fields.items():
            if metadata.get(field) != expected:
                raise PublishError(
                    f"animation field does not match catalog: "
                    f"{animation_id}.{field}"
                )

        source_dir = metadata_path.parent
        atlas = source_dir / "atlas.png"
        if not atlas.is_file():
            raise PublishError(f"animation atlas is missing: {animation_id}")
        atlas_dimensions = png_dimensions(atlas)
        expected_atlas_dimensions = (
            int(metadata["atlas_width"]),
            int(metadata["atlas_height"]),
        )
        if atlas_dimensions != expected_atlas_dimensions:
            raise PublishError(
                f"animation atlas dimensions do not match metadata: {animation_id}"
            )

        frame_count = int(metadata.get("frame_count", 0))
        frame_files = sorted((source_dir / "frames").glob("frame_*.png"))
        if frame_count <= 0 or len(frame_files) != frame_count:
            raise PublishError(
                f"animation frame count is incomplete: {animation_id} "
                f"{len(frame_files)} != {frame_count}"
            )
        outputs[animation_id] = (source_dir, metadata)

    missing = sorted(set(catalog) - set(outputs))
    if missing:
        raise PublishError(f"missing animation outputs: {', '.join(missing)}")
    return outputs


def playback_sequence(frame_count: int, loop_mode: str) -> list[int]:
    sequence = list(range(frame_count))
    if loop_mode == "ping_pong" and frame_count > 2:
        sequence.extend(range(frame_count - 2, 0, -1))
    return sequence


def sprite_frames_resource(
    *,
    atlas_path: str,
    frame_count: int,
    frame_width: int,
    frame_height: int,
    columns: int,
    padding: int,
    playback_fps: int,
    loop_mode: str,
) -> tuple[str, int]:
    if frame_count <= 0 or columns <= 0:
        raise PublishError("frame_count and columns must be positive")
    lines = [
        f'[gd_resource type="SpriteFrames" load_steps={frame_count + 2} format=3]',
        "",
        f'[ext_resource type="Texture2D" path="{atlas_path}" id="1_atlas"]',
        "",
    ]
    for index in range(frame_count):
        column = index % columns
        row = index // columns
        x = padding + column * (frame_width + padding)
        y = padding + row * (frame_height + padding)
        lines.extend(
            [
                f'[sub_resource type="AtlasTexture" id="AtlasTexture_{index:04d}"]',
                'atlas = ExtResource("1_atlas")',
                f"region = Rect2({x}, {y}, {frame_width}, {frame_height})",
                "",
            ]
        )

    sequence = playback_sequence(frame_count, loop_mode)
    lines.extend(["[resource]", "animations = [{", '"frames": ['])
    for position, index in enumerate(sequence):
        comma = "," if position < len(sequence) - 1 else ""
        lines.extend(
            [
                "{",
                '"duration": 1.0,',
                f'"texture": SubResource("AtlasTexture_{index:04d}")',
                f"}}{comma}",
            ]
        )
    lines.extend(
        [
            "],",
            '"loop": true,',
            '"name": &"default",',
            f'"speed": {float(playback_fps):.1f}',
            "}]",
            "",
        ]
    )
    return "\n".join(lines), len(sequence)


def portable_animation_metadata(
    metadata: dict[str, Any],
    *,
    atlas_path: str,
    sprite_frames_path: str,
    atlas_digest: str,
    playback_frame_count: int,
) -> dict[str, Any]:
    alpha = metadata.get("alpha", {})
    blend_mode = "additive" if alpha.get("mode") == "black_additive_content" else "mix"
    return {
        "schema_version": 1,
        "animation_id": metadata["animation_id"],
        "source_asset_id": metadata["source_asset_id"],
        "atlas": atlas_path,
        "sprite_frames": sprite_frames_path,
        "atlas_sha256": atlas_digest,
        "frame_count": int(metadata["frame_count"]),
        "playback_frame_count": playback_frame_count,
        "frame_width": int(metadata["frame_width"]),
        "frame_height": int(metadata["frame_height"]),
        "columns": int(metadata["columns"]),
        "rows": int(metadata["rows"]),
        "padding": int(metadata["padding"]),
        "playback_fps": int(metadata["playback_fps"]),
        "loop_mode": metadata["loop_mode"],
        "blend_mode": blend_mode,
        "alpha": alpha,
        "anchor": metadata.get("anchor", {}),
    }


def build_publish_tree(
    stage: Path,
    *,
    static_sources: dict[str, tuple[Path, dict[str, Any]]],
    static_catalog: dict[str, Any],
    animation_sources: dict[str, tuple[Path, dict[str, Any]]],
) -> dict[str, Any]:
    static_manifest: dict[str, Any] = {}
    for asset_id in sorted(static_sources):
        source, metadata = static_sources[asset_id]
        category = str(static_catalog[asset_id]["category"])
        relative_path = Path("static") / category / source.name
        destination = stage / relative_path
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
        width, height = png_dimensions(source)
        static_manifest[asset_id] = {
            "texture": f"res://assets/art/{relative_path.as_posix()}",
            "width": width,
            "height": height,
            "sha256": metadata["output_digest"],
        }

    animation_manifest: dict[str, Any] = {}
    for animation_id in sorted(animation_sources):
        source_dir, metadata = animation_sources[animation_id]
        slug = animation_id.replace("animation.", "animation-").replace("_", "-")
        relative_dir = Path("animations") / slug
        destination_dir = stage / relative_dir
        destination_dir.mkdir(parents=True, exist_ok=True)

        source_atlas = source_dir / "atlas.png"
        destination_atlas = destination_dir / "atlas.png"
        shutil.copy2(source_atlas, destination_atlas)
        atlas_path = f"res://assets/art/{(relative_dir / 'atlas.png').as_posix()}"
        sprite_frames_path = (
            f"res://assets/art/{(relative_dir / 'sprite_frames.tres').as_posix()}"
        )
        resource_text, playback_frame_count = sprite_frames_resource(
            atlas_path=atlas_path,
            frame_count=int(metadata["frame_count"]),
            frame_width=int(metadata["frame_width"]),
            frame_height=int(metadata["frame_height"]),
            columns=int(metadata["columns"]),
            padding=int(metadata["padding"]),
            playback_fps=int(metadata["playback_fps"]),
            loop_mode=str(metadata["loop_mode"]),
        )
        (destination_dir / "sprite_frames.tres").write_text(
            resource_text, encoding="utf-8"
        )
        portable = portable_animation_metadata(
            metadata,
            atlas_path=atlas_path,
            sprite_frames_path=sprite_frames_path,
            atlas_digest=sha256_file(source_atlas),
            playback_frame_count=playback_frame_count,
        )
        write_json(destination_dir / "animation.json", portable)
        animation_manifest[animation_id] = portable

    manifest = {
        "schema_version": 1,
        "static_count": len(static_manifest),
        "animation_count": len(animation_manifest),
        "static": static_manifest,
        "animations": animation_manifest,
    }
    write_json(stage / "manifest.json", manifest)
    return manifest


def replace_tree(stage: Path, destination: Path) -> None:
    backup = destination.with_name(f".{destination.name}.backup-{uuid.uuid4().hex}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    moved_existing = False
    try:
        if destination.exists() or destination.is_symlink():
            os.replace(destination, backup)
            moved_existing = True
        os.replace(stage, destination)
    except Exception:
        if moved_existing and not destination.exists() and backup.exists():
            os.replace(backup, destination)
        raise
    if backup.exists() or backup.is_symlink():
        if backup.is_dir() and not backup.is_symlink():
            shutil.rmtree(backup)
        else:
            backup.unlink()


def publish(
    *,
    pipeline_root: Path,
    catalog_root: Path,
    destination: Path,
) -> dict[str, Any]:
    static_catalog, animation_catalog = load_catalogs(catalog_root)
    static_sources = validate_static_sources(
        pipeline_root / "outputs" / "static", static_catalog
    )
    animation_sources = validate_animation_sources(
        pipeline_root / "extracted", animation_catalog
    )

    stage = destination.with_name(f".{destination.name}.stage-{uuid.uuid4().hex}")
    stage.mkdir(parents=True)
    try:
        manifest = build_publish_tree(
            stage,
            static_sources=static_sources,
            static_catalog=static_catalog,
            animation_sources=animation_sources,
        )
        replace_tree(stage, destination)
    except Exception:
        if stage.exists():
            shutil.rmtree(stage)
        raise
    return manifest


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pipeline-root", type=Path, default=DEFAULT_PIPELINE_ROOT)
    parser.add_argument("--catalog-root", type=Path, default=DEFAULT_CATALOG_ROOT)
    parser.add_argument("--destination", type=Path, default=DEFAULT_DESTINATION)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        manifest = publish(
            pipeline_root=args.pipeline_root.resolve(),
            catalog_root=args.catalog_root.resolve(),
            destination=args.destination.resolve(),
        )
    except PublishError as exc:
        print(f"publish failed: {exc}", file=sys.stderr)
        return 1
    print(
        "published Godot art: "
        f"static={manifest['static_count']} "
        f"animations={manifest['animation_count']} "
        f"destination={args.destination.resolve()}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
