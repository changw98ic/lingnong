from __future__ import annotations

import json
import shutil
import sys
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import ClassVar, cast
from unittest.mock import patch

SCRIPT_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPT_DIR))

import minimax_video_generate as runner


class _CompletedVideoClient(runner.MiniMaxClient):
    def __init__(self, source_video: Path) -> None:
        self.source_video = source_video
        self.payload: dict[str, object] | None = None

    def create_video(self, payload: dict[str, object]) -> str:  # type: ignore[override]
        self.payload = payload
        return "TASK-INTEGRATION"

    def query_video(self, task_id: str) -> dict[str, object]:
        return {
            "id": task_id,
            "model": "MiniMax-H3",
            "status": "succeeded",
            "content": {"url": "https://fixture.invalid/video.mp4"},
            "resolution": "768P",
            "duration": 4,
            "ratio": "1:1",
            "usage": {"output_seconds": 4},
        }

    def download_video(self, url: str, destination: Path) -> None:
        shutil.copyfile(self.source_video, destination)


class _MiniMaxFixtureHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"
    requests: ClassVar[list[dict[str, object]]] = []

    def log_message(self, format: str, *args: object) -> None:
        return

    def _json(self, value: object) -> None:
        body = json.dumps(value).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self) -> None:
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length)
        self.__class__.requests.append(
            {
                "method": "POST",
                "path": self.path,
                "authorization": self.headers.get("Authorization"),
                "body": json.loads(body),
            }
        )
        self._json({"task_id": "TASK-123"})

    def do_GET(self) -> None:
        self.__class__.requests.append(
            {
                "method": "GET",
                "path": self.path,
                "authorization": self.headers.get("Authorization"),
            }
        )
        if self.path == "/v2/query/video_generation/TASK-123":
            server = cast(ThreadingHTTPServer, self.server)
            self._json(
                {
                    "task": {
                        "id": "TASK-123",
                        "model": "MiniMax-H3",
                        "status": "succeeded",
                        "content": {
                            "url": f"http://127.0.0.1:{server.server_port}/video.mp4"
                        },
                        "resolution": "768P",
                        "duration": 4,
                        "ratio": "1:1",
                    }
                }
            )
            return
        if self.path == "/video.mp4":
            body = b"0" * 2048
            self.send_response(200)
            self.send_header("Content-Type", "video/mp4")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        self.send_response(404)
        self.end_headers()


class _MiniMaxPaymentRequiredHandler(_MiniMaxFixtureHandler):
    def do_POST(self) -> None:
        body = json.dumps(
            {
                "type": "error",
                "error": {
                    "type": "insufficient_balance_error",
                    "message": "insufficient balance (1008)",
                    "http_code": "402",
                },
            }
        ).encode("utf-8")
        self.send_response(402)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


class MiniMaxVideoGenerateTests(unittest.TestCase):
    def setUp(self) -> None:
        _MiniMaxFixtureHandler.requests = []

    def test_payload_uses_h3_v2_first_frame_contract(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            prompt = root / "prompt.md"
            prompt.write_text(
                "# test\n\n```text\nAnimate this as one continuous 2-second video.\n```\n",
                encoding="utf-8",
            )
            source = root / "source.png"
            source.write_bytes(b"\x89PNG\r\n\x1a\nfixture")
            item = {
                "prompt_file": str(prompt),
                "prepared_source_image": str(source),
                "duration_seconds": 2,
            }

            payload, summary = runner.build_payload(
                item, "768P", billing_source=runner.PAYGO_BILLING
            )

            self.assertEqual(payload["model"], "MiniMax-H3")
            self.assertEqual(payload["duration"], 4)
            self.assertEqual(payload["ratio"], "adaptive")
            self.assertFalse(payload["aigc_watermark"])
            self.assertEqual(payload["content"][1]["role"], "first_frame")
            self.assertTrue(
                payload["content"][1]["image_url"]["url"].startswith(
                    "data:image/png;base64,"
                )
            )
            self.assertIn("one continuous 4-second", payload["content"][0]["text"])
            self.assertIn("retime", payload["content"][0]["text"])
            self.assertEqual(summary["provider_duration_seconds"], 4)
            self.assertEqual(summary["billing_source"], runner.PAYGO_BILLING)
            self.assertNotIn("billing_source", payload)

    def test_media_plan_cannot_build_an_api_payload(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            prompt = root / "prompt.md"
            prompt.write_text(
                "# test\n\n```text\nAnimate this as one continuous 2-second video.\n```\n",
                encoding="utf-8",
            )
            source = root / "source.png"
            source.write_bytes(b"\x89PNG\r\n\x1a\nfixture")
            item = {
                "prompt_file": str(prompt),
                "prepared_source_image": str(source),
                "duration_seconds": 2,
            }

            with self.assertRaises(runner.VideoGenerationError) as raised:
                runner.build_payload(
                    item, "768P", billing_source=runner.MEDIA_PLAN_BILLING
                )
            self.assertIn("MiniMax Design", str(raised.exception))

    def test_client_calls_create_query_and_download_without_exposing_key(self) -> None:
        server = ThreadingHTTPServer(("127.0.0.1", 0), _MiniMaxFixtureHandler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            base_url = f"http://127.0.0.1:{server.server_port}"
            client = runner.MiniMaxClient(
                "fixture-key",
                billing_source=runner.PAYGO_BILLING,
                base_url=base_url,
                request_timeout=5,
                allow_http=True,
            )
            task_id = client.create_video(
                {
                    "model": "MiniMax-H3",
                    "content": [{"type": "text", "text": "test"}],
                    "resolution": "768P",
                    "duration": 4,
                }
            )
            task = client.query_video(task_id)
            with tempfile.TemporaryDirectory() as directory:
                output = Path(directory) / "video.mp4"
                client.download_video(task["content"]["url"], output)
                self.assertEqual(output.stat().st_size, 2048)

            self.assertEqual(task_id, "TASK-123")
            self.assertEqual(task["status"], "succeeded")
            create = _MiniMaxFixtureHandler.requests[0]
            self.assertEqual(create["path"], "/v2/video_generation")
            self.assertEqual(create["authorization"], "Bearer fixture-key")
            self.assertNotIn("fixture-key", json.dumps(create["body"]))
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=5)

    def test_create_transport_error_does_not_silently_retry(self) -> None:
        client = runner.MiniMaxClient(
            "fixture-key",
            billing_source=runner.PAYGO_BILLING,
            base_url="http://127.0.0.1:1",
            request_timeout=1,
            allow_http=True,
        )
        with (
            patch.object(
                client,
                "_json_request",
                side_effect=runner.TransientProviderError("fixture timeout"),
            ),
            self.assertRaises(runner.SubmissionOutcomeUnknown) as raised,
        ):
            client.create_video({"model": "MiniMax-H3"})
        self.assertIn("inspect the MiniMax task list", str(raised.exception))

    def test_client_rejects_media_plan_route(self) -> None:
        with self.assertRaises(runner.GlobalProviderError) as raised:
            runner.MiniMaxClient(
                "fixture-key",
                billing_source=runner.MEDIA_PLAN_BILLING,
            )
        self.assertIn("MiniMax Design", str(raised.exception))
        self.assertNotIn("fixture-key", str(raised.exception))

    @unittest.skipUnless(
        shutil.which("ffmpeg") and shutil.which("ffprobe"),
        "ffmpeg and ffprobe are required",
    )
    def test_normalize_video_retimes_to_queue_contract(self) -> None:
        ffmpeg = shutil.which("ffmpeg")
        ffprobe = shutil.which("ffprobe")
        assert ffmpeg is not None
        assert ffprobe is not None
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source.mp4"
            output = root / "output.mp4"
            runner.run_command(
                [
                    ffmpeg,
                    "-hide_banner",
                    "-loglevel",
                    "error",
                    "-f",
                    "lavfi",
                    "-i",
                    "testsrc2=size=320x240:rate=24:duration=4",
                    "-an",
                    "-c:v",
                    "libx264",
                    "-pix_fmt",
                    "yuv420p",
                    str(source),
                ],
                timeout=60,
            )
            item = {
                "id": "animation.fixture",
                "duration_seconds": 2,
                "source_fps": 24,
                "width": 256,
                "height": 256,
                "matte": "magenta",
            }

            source_probe, output_probe = runner.normalize_video(
                source,
                output,
                item,
                ffmpeg=ffmpeg,
                ffprobe=ffprobe,
            )

            self.assertEqual(int(source_probe["width"]), 320)
            self.assertEqual(int(output_probe["width"]), 256)
            self.assertEqual(int(output_probe["height"]), 256)
            self.assertAlmostEqual(float(output_probe["duration"]), 2.0, places=2)
            self.assertEqual(int(output_probe["nb_read_frames"]), 48)

    @unittest.skipUnless(
        shutil.which("ffmpeg") and shutil.which("ffprobe"),
        "ffmpeg and ffprobe are required",
    )
    def test_import_design_video_normalizes_and_records_media_plan_provenance(self) -> None:
        ffmpeg = shutil.which("ffmpeg")
        ffprobe = shutil.which("ffprobe")
        assert ffmpeg is not None
        assert ffprobe is not None
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "design-source.mp4"
            runner.run_command(
                [
                    ffmpeg, "-hide_banner", "-loglevel", "error",
                    "-f", "lavfi", "-i",
                    "testsrc2=size=768x768:rate=24:duration=4.5",
                    "-an", "-c:v", "libx264", "-pix_fmt", "yuv420p",
                    str(source),
                ],
                timeout=60,
            )
            prompt = root / "prompt.md"
            prompt.write_text(
                "# test\n\n```text\nAnimate this as one continuous 2-second video.\n```\n",
                encoding="utf-8",
            )
            prepared = root / "prepared.png"
            runner.run_command(
                [
                    ffmpeg, "-hide_banner", "-loglevel", "error",
                    "-f", "lavfi", "-i", "color=c=magenta:size=256x256",
                    "-vf", "drawbox=x=64:y=64:w=128:h=128:color=green:t=fill",
                    "-frames:v", "1", str(prepared),
                ],
                timeout=60,
            )
            output = root / "output.mp4"
            metadata = root / "output.mp4.meta.json"
            queue_path = root / "queue.json"
            item = {
                "id": "animation.fixture",
                "prompt_file": str(prompt),
                "prompt_digest": runner.sha256_file(prompt),
                "source_image": str(root / "unused-source.png"),
                "prepared_source_image": str(prepared),
                "input_digest": "",
                "output_file": str(output),
                "output_meta_file": str(metadata),
                "duration_seconds": 2,
                "source_fps": 24,
                "width": 256,
                "height": 256,
                "matte": "magenta",
                "status": "failed",
                "attempts": 1,
                "last_error": "old API failure",
                "updated_at": "",
            }
            queue = {"items": [item]}
            runner.write_json_atomic(queue_path, queue)

            result = runner.import_design_video(
                queue, queue_path, item, source,
                provider_task_id="PROVIDER-123",
                design_task_id="DESIGN-123",
                resolution="768P",
                ffmpeg=ffmpeg,
                ffprobe=ffprobe,
                actual_media_plan_credits=0,
                free_generations_before=3,
                free_generations_after=2,
            )

            saved_queue = runner.read_json(queue_path)
            saved_metadata = runner.read_json(metadata)
            self.assertEqual(result["status"], "done")
            self.assertEqual(saved_queue["items"][0]["status"], "done")
            self.assertEqual(saved_queue["items"][0]["attempts"], 0)
            self.assertEqual(saved_metadata["provider"]["surface"], "minimax-design")
            self.assertEqual(saved_metadata["provider"]["billing_source"], runner.MEDIA_PLAN_BILLING)
            self.assertEqual(saved_metadata["provider"]["task_id"], "PROVIDER-123")
            self.assertEqual(saved_metadata["provider"]["design_task_id"], "DESIGN-123")
            self.assertEqual(saved_metadata["provider"]["actual_media_plan_credits"], 0)
            self.assertEqual(saved_metadata["provider"]["free_generations_before"], 3)
            self.assertEqual(saved_metadata["provider"]["free_generations_after"], 2)
            self.assertEqual(saved_metadata["output_digest"], runner.sha256_file(output))
            self.assertEqual(int(runner.probe_video(output, ffprobe)["width"]), 256)

    def test_import_design_video_rejects_existing_output(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            output = root / "output.mp4"
            output.write_bytes(b"preserve")
            item = {"id": "animation.fixture", "output_file": str(output)}
            with self.assertRaises(runner.VideoGenerationError) as raised:
                runner.import_design_video(
                    {"items": [item]}, root / "queue.json", item,
                    root / "source.mp4", provider_task_id="",
                    design_task_id="", resolution="768P",
                    ffmpeg="ffmpeg", ffprobe="ffprobe",
                )
            self.assertIn("already exists", str(raised.exception))
            self.assertEqual(output.read_bytes(), b"preserve")

    def test_process_item_completes_queue_and_provenance(self) -> None:
        ffmpeg = shutil.which("ffmpeg")
        ffprobe = shutil.which("ffprobe")
        assert ffmpeg is not None
        assert ffprobe is not None
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            provider_video = root / "provider.mp4"
            runner.run_command(
                [
                    ffmpeg,
                    "-hide_banner",
                    "-loglevel",
                    "error",
                    "-f",
                    "lavfi",
                    "-i",
                    "testsrc2=size=320x320:rate=24:duration=4",
                    "-an",
                    "-c:v",
                    "libx264",
                    "-pix_fmt",
                    "yuv420p",
                    str(provider_video),
                ],
                timeout=60,
            )
            prompt = root / "prompt.md"
            prompt.write_text(
                "# test\n\n```text\nAnimate this as one continuous 2-second video.\n```\n",
                encoding="utf-8",
            )
            prepared = root / "prepared.png"
            runner.run_command(
                [
                    ffmpeg,
                    "-hide_banner",
                    "-loglevel",
                    "error",
                    "-f",
                    "lavfi",
                    "-i",
                    "color=c=magenta:size=256x256",
                    "-vf",
                    "drawbox=x=64:y=64:w=128:h=128:color=green:t=fill",
                    "-frames:v",
                    "1",
                    str(prepared),
                ],
                timeout=60,
            )
            output = root / "output.mp4"
            metadata = root / "output.mp4.meta.json"
            queue_path = root / "queue.json"
            item = {
                "id": "animation.fixture",
                "prompt_file": str(prompt),
                "prompt_digest": runner.sha256_file(prompt),
                "source_image": str(root / "unused-source.png"),
                "prepared_source_image": str(prepared),
                "input_digest": "",
                "output_file": str(output),
                "output_meta_file": str(metadata),
                "duration_seconds": 2,
                "source_fps": 24,
                "width": 256,
                "height": 256,
                "matte": "magenta",
                "status": "pending",
                "attempts": 0,
                "last_error": "",
                "updated_at": "",
            }
            queue = {"items": [item]}
            runner.write_json_atomic(queue_path, queue)
            client = _CompletedVideoClient(provider_video)

            with patch.object(runner, "TASK_STATE_ROOT", root / "tasks"):
                result = runner.process_item(
                    queue,
                    queue_path,
                    item,
                    client,
                    billing_source=runner.PAYGO_BILLING,
                    resolution="768P",
                    auto_prepare=False,
                    retry_failed=False,
                    poll_interval=0.001,
                    task_timeout=5,
                    ffmpeg=ffmpeg,
                    ffprobe=ffprobe,
                )

            saved_queue = runner.read_json(queue_path)
            saved_metadata = runner.read_json(metadata)
            self.assertEqual(result["status"], "done")
            self.assertEqual(saved_queue["items"][0]["status"], "done")
            self.assertEqual(saved_queue["items"][0]["attempts"], 1)
            self.assertEqual(saved_metadata["provider"]["task_id"], "TASK-INTEGRATION")
            self.assertEqual(
                saved_metadata["provider"]["billing_source"],
                runner.PAYGO_BILLING,
            )
            self.assertEqual(
                saved_metadata["output_digest"], runner.sha256_file(output)
            )
            self.assertEqual(int(runner.probe_video(output, ffprobe)["width"]), 256)
            self.assertIsNotNone(client.payload)
            assert client.payload is not None
            self.assertEqual(client.payload["model"], "MiniMax-H3")


if __name__ == "__main__":
    unittest.main()
