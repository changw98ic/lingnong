from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

from PIL import Image, ImageDraw

SCRIPT_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPT_DIR))

import extract_video as extract


class ExtractVideoTests(unittest.TestCase):
    def test_adaptive_filter_defers_keying_until_frames_exist(self) -> None:
        animation = {
            "duration_seconds": 2,
            "target_fps": 4,
            "frame_width": 64,
            "frame_height": 64,
            "matte": "magenta",
        }

        fixed = extract.extraction_filter(animation, 0.12)
        adaptive = extract.extraction_filter(
            animation, 0.12, adaptive_reference_matte=True
        )

        self.assertIn("chromakey=0xFF00FF", fixed)
        self.assertNotIn("chromakey", adaptive)
        self.assertIn("format=rgba", adaptive)

    def test_adaptive_reference_matte_handles_background_hue_drift(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source.png"
            frames = root / "frames"
            frames.mkdir()

            reference = Image.new("RGB", (64, 64), (255, 0, 255))
            draw = ImageDraw.Draw(reference)
            draw.rounded_rectangle((18, 12, 46, 54), radius=8, fill=(20, 180, 120))
            reference.save(source)

            for index, background in enumerate(
                ((255, 0, 255), (195, 230, 205)), start=1
            ):
                frame = Image.new("RGB", (64, 64), background)
                frame_draw = ImageDraw.Draw(frame)
                offset = index - 1
                frame_draw.rounded_rectangle(
                    (18 + offset, 12, 46 + offset, 54),
                    radius=8,
                    fill=(20, 180, 120),
                )
                frame.save(frames / f"frame_{index:04d}.png")

            report = extract.apply_adaptive_reference_matte(
                frames,
                source,
                {
                    "frame_width": 64,
                    "frame_height": 64,
                    "matte": "magenta",
                },
            )

            self.assertEqual(report["strategy"], "adaptive_reference")
            for frame_path in extract.frame_files(frames):
                with Image.open(frame_path) as frame:
                    alpha = frame.convert("RGBA").getchannel("A")
                    self.assertLess(alpha.getpixel((0, 0)), 16)
                    self.assertGreater(alpha.getpixel((32, 30)), 240)


if __name__ == "__main__":
    unittest.main()
