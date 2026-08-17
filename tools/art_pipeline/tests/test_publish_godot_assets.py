from __future__ import annotations

import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path

from PIL import Image

SCRIPT_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPT_DIR))

import publish_godot_assets as publisher


class PublishGodotAssetsTests(unittest.TestCase):
    def test_publish_builds_manifest_and_ping_pong_sprite_frames(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            pipeline = root / ".art-pipeline"
            catalogs = root / "catalog"
            destination = root / "assets" / "art"
            catalogs.mkdir(parents=True)

            static_path = pipeline / "outputs" / "static" / "crop" / "crop-a.png"
            static_path.parent.mkdir(parents=True)
            Image.new("RGBA", (16, 16), (10, 20, 30, 255)).save(static_path)
            static_digest = hashlib.sha256(static_path.read_bytes()).hexdigest()
            (static_path.parent / "crop-a.png.meta.json").write_text(
                json.dumps({"id": "crop.a", "output_digest": static_digest}),
                encoding="utf-8",
            )

            animation_dir = pipeline / "extracted" / "animation-a-sway"
            frames_dir = animation_dir / "frames"
            frames_dir.mkdir(parents=True)
            for index in range(3):
                Image.new("RGBA", (8, 8), (index, 20, 30, 255)).save(
                    frames_dir / f"frame_{index + 1:04d}.png"
                )
            Image.new("RGBA", (40, 12), (0, 0, 0, 0)).save(animation_dir / "atlas.png")
            (animation_dir / "animation.json").write_text(
                json.dumps(
                    {
                        "animation_id": "animation.a_sway",
                        "source_asset_id": "crop.a",
                        "frame_count": 3,
                        "frame_width": 8,
                        "frame_height": 8,
                        "columns": 4,
                        "rows": 1,
                        "padding": 4,
                        "atlas_width": 40,
                        "atlas_height": 12,
                        "playback_fps": 6,
                        "loop_mode": "ping_pong",
                        "alpha": {"verified": True},
                        "anchor": {"verified": True},
                    }
                ),
                encoding="utf-8",
            )

            (catalogs / "environment_ui.json").write_text("[]", encoding="utf-8")
            (catalogs / "gameplay_assets.json").write_text(
                json.dumps(
                    [
                        {
                            "id": "crop.a",
                            "category": "crop",
                            "width": 16,
                            "height": 16,
                        }
                    ]
                ),
                encoding="utf-8",
            )
            (catalogs / "animations.json").write_text(
                json.dumps(
                    [
                        {
                            "id": "animation.a_sway",
                            "source_asset_id": "crop.a",
                            "frame_width": 8,
                            "frame_height": 8,
                            "godot_fps": 6,
                            "loop_mode": "ping_pong",
                        }
                    ]
                ),
                encoding="utf-8",
            )

            manifest = publisher.publish(
                pipeline_root=pipeline,
                catalog_root=catalogs,
                destination=destination,
            )

            self.assertEqual(manifest["static_count"], 1)
            self.assertEqual(manifest["animation_count"], 1)
            animation = manifest["animations"]["animation.a_sway"]
            self.assertEqual(animation["playback_frame_count"], 4)
            resource = (
                destination / "animations" / "animation-a-sway" / "sprite_frames.tres"
            ).read_text(encoding="utf-8")
            self.assertEqual(resource.count('"texture": SubResource'), 4)
            self.assertEqual(resource.count('SubResource("AtlasTexture_0001")'), 2)
            self.assertNotIn(str(root), (destination / "manifest.json").read_text())

    def test_publish_rejects_changed_static_output(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "pipeline" / "outputs" / "static" / "crop"
            source.mkdir(parents=True)
            image_path = source / "crop-a.png"
            Image.new("RGBA", (8, 8), (0, 0, 0, 0)).save(image_path)
            (source / "crop-a.png.meta.json").write_text(
                json.dumps({"id": "crop.a", "output_digest": "wrong"}),
                encoding="utf-8",
            )
            with self.assertRaisesRegex(publisher.PublishError, "digest"):
                publisher.validate_static_sources(
                    root / "pipeline" / "outputs" / "static",
                    {
                        "crop.a": {
                            "id": "crop.a",
                            "category": "crop",
                            "width": 8,
                            "height": 8,
                        }
                    },
                )


if __name__ == "__main__":
    unittest.main()
