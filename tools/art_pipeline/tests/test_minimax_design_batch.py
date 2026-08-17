from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

SCRIPT_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPT_DIR))

import minimax_design_batch as batch


class MiniMaxDesignBatchTests(unittest.TestCase):
    def test_parse_quota_selects_media_plan_and_group(self) -> None:
        wallet = {
            "wallets": [
                {"source": 0, "plan_name": "", "total_credit": "0"},
                {
                    "source": 1,
                    "plan_name": "Media Plan Starter",
                    "total_credit": "13240",
                    "url": "https://design.minimaxi.com/media-plan/subscribe?group_id=12345",
                },
            ]
        }
        trial = {
            "remainingCount": 2,
            "freeCount": 3,
            "activityActive": True,
        }

        with patch.object(batch, "now", return_value="2026-08-13T00:00:00+00:00"):
            snapshot, group_id = batch.parse_quota(wallet, trial)

        self.assertEqual(snapshot.plan_name, "Media Plan Starter")
        self.assertEqual(snapshot.total_credit, 13240)
        self.assertEqual(snapshot.free_generations_remaining, 2)
        self.assertEqual(group_id, "12345")

    def test_quota_only_stops_when_no_free_generation_can_cover_next_task(self) -> None:
        free = batch.QuotaSnapshot("now", "Media Plan", 0, 1, 3, True)
        low = batch.QuotaSnapshot("now", "Media Plan", 279, 0, 3, True)
        enough = batch.QuotaSnapshot("now", "Media Plan", 280, 0, 3, True)

        self.assertEqual(batch.quota_stop_reason(free, 280), "")
        self.assertIn("less than", batch.quota_stop_reason(low, 280))
        self.assertEqual(batch.quota_stop_reason(enough, 280), "")

    def test_build_request_uses_h3_design_i2v_contract(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            prompt = root / "prompt.md"
            prompt.write_text(
                "# fixture\n\n```text\nAnimate this as one continuous 2-second video.\n```\n",
                encoding="utf-8",
            )
            image = root / "source.png"
            image.write_bytes(b"fixture")
            item = {
                "id": "animation.fixture",
                "prompt_file": str(prompt),
                "duration_seconds": 2,
            }

            request, summary = batch.build_design_request(item, image)

        self.assertEqual(request["backend"], "minimax_v3")
        self.assertEqual(request["model_id"], "MiniMax-H3")
        self.assertEqual(request["params"]["duration"], "4")
        self.assertEqual(request["params"]["resolution"], "768P")
        self.assertEqual(request["params"]["ratio"], "adaptive")
        self.assertEqual(request["params"]["generate_audio"], "false")
        self.assertEqual(request["params"]["image_mode"], "first-last-frame")
        self.assertIn("one continuous 4-second", request["prompt"])
        self.assertEqual(summary["estimated_media_plan_credits"], 280)

    def test_result_path_must_stay_inside_design_project(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            project = Path(directory) / "project"
            project.mkdir()
            good = project / "result.mp4"
            good.write_bytes(b"video")
            outside = Path(directory) / "outside.mp4"
            outside.write_bytes(b"video")

            self.assertEqual(batch.resolve_result_path(project, "result.mp4"), good.resolve())
            with self.assertRaises(batch.DesignBatchError):
                batch.resolve_result_path(project, str(outside))

    def test_submission_transport_failure_is_not_retried_silently(self) -> None:
        client = batch.DesignGatewayClient(
            "http://127.0.0.1:1", {"x-hilo-workspace": "fixture"}
        )
        with self.assertRaises(batch.SubmissionOutcomeUnknown):
            client.submit_video({"backend": "minimax_v3"})

    def test_status_report_never_contains_gateway_identity(self) -> None:
        snapshot = batch.QuotaSnapshot("now", "Media Plan Starter", 1000, 0, 3, True)
        value = json.dumps(batch.quota_dict(snapshot))
        self.assertNotIn("workspace", value.lower())
        self.assertNotIn("token", value.lower())


if __name__ == "__main__":
    unittest.main()
