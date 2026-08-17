#!/usr/bin/env python3
"""Generate or import animation videos made with MiniMax-H3.

The animation queue and prompt files remain the source of truth. Media Plan
jobs are created in MiniMax Design and imported with ``--import-design-video``.
Direct V2 API jobs use only the pay-as-you-go account balance. Both paths
normalize the result to the exact canvas, duration, and frame rate required by
the existing extraction pipeline.
"""

from __future__ import annotations

import argparse
import base64
import errno
import hashlib
import json
import math
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from collections.abc import Iterator
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import art_pipeline as catalog_pipeline
import prepare_video_source as video_source_pipeline

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_QUEUE = ROOT / ".art-pipeline" / "queues" / "animation.json"
TASK_STATE_ROOT = ROOT / ".art-pipeline" / "minimax-tasks"
REPORT_ROOT = ROOT / ".art-pipeline" / "reports"
PREPARE_SCRIPT = ROOT / "tools" / "art_pipeline" / "prepare_video_source.py"

API_BASE_URL = "https://api.minimaxi.com"
MODEL = "MiniMax-H3"
CREATE_PATH = "/v2/video_generation"
QUERY_PATH = "/v2/query/video_generation/{task_id}"

MEDIA_PLAN_BILLING = "media-plan"
PAYGO_BILLING = "paygo"
BILLING_SOURCES = (MEDIA_PLAN_BILLING, PAYGO_BILLING)
API_KEY_ENV_BY_BILLING = {
    PAYGO_BILLING: "MINIMAX_API_KEY",
}
MEDIA_PLAN_CREDITS_PER_SECOND = {"768P": 70, "2K": 120}

MIN_PROVIDER_DURATION = 4
MAX_PROVIDER_DURATION = 15
MAX_PROMPT_CHARS = 7000
MAX_IMAGE_BYTES = 30 * 1024 * 1024
MAX_REQUEST_BYTES = 64 * 1024 * 1024
DOWNLOAD_LIMIT_BYTES = 1024 * 1024 * 1024
RESUMABLE_PROVIDER_STATUSES = {"queued", "running", "succeeded"}
TERMINAL_PROVIDER_STATUSES = {"failed", "cancelled"}


class VideoGenerationError(RuntimeError):
    """A local or provider error that makes the current item fail."""


class ItemBlocked(VideoGenerationError):
    """An item is waiting for a local input and must not consume an attempt."""


class ResumeLater(VideoGenerationError):
    """A submitted remote task can be resumed without creating another task."""


class ProviderTaskFailed(VideoGenerationError):
    """The provider reached a failed or cancelled terminal state."""


class TransientProviderError(VideoGenerationError):
    """The provider is temporarily unavailable and the batch should pause."""


class GlobalProviderError(VideoGenerationError):
    """Authentication or account state prevents every item from running."""


class SubmissionOutcomeUnknown(VideoGenerationError):
    """A create request ended before a task ID could be recorded safely."""


def now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise VideoGenerationError(f"missing JSON file: {path}") from exc
    except json.JSONDecodeError as exc:
        raise VideoGenerationError(f"invalid JSON in {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise VideoGenerationError(f"JSON root must be an object: {path}")
    return value


def write_json_atomic(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.part-{os.getpid()}-{uuid.uuid4().hex}")
    temporary.write_text(
        json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    os.replace(temporary, path)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def input_digest(paths: list[Path]) -> str:
    if not paths or any(not path.is_file() for path in paths):
        return ""
    digest = hashlib.sha256(b"lingnong-input-v1\0")
    for path in paths:
        content = path.read_bytes()
        digest.update(f"bytes:{len(content)}\n".encode())
        digest.update(content)
    return digest.hexdigest()


def slug(item_id: str) -> str:
    return item_id.replace(".", "-").replace("_", "-")


def prompt_from_markdown(path: Path) -> str:
    markdown = path.read_text(encoding="utf-8")
    match = re.search(r"```text\r?\n([\s\S]*?)\r?\n```", markdown)
    if match is None:
        raise VideoGenerationError(f"no copyable text prompt in {path}")
    prompt = match.group(1).strip()
    if not prompt:
        raise VideoGenerationError(f"empty video prompt in {path}")
    return prompt


def provider_duration(target_duration: float) -> int:
    if target_duration <= 0:
        raise VideoGenerationError(
            "target animation duration must be greater than zero"
        )
    duration = max(MIN_PROVIDER_DURATION, math.ceil(target_duration))
    if duration > MAX_PROVIDER_DURATION:
        raise VideoGenerationError(
            f"target animation duration {target_duration:g}s exceeds MiniMax-H3's "
            f"{MAX_PROVIDER_DURATION}s limit"
        )
    return duration


def provider_prompt(prompt: str, target_duration: float, api_duration: int) -> str:
    if math.isclose(target_duration, api_duration, rel_tol=0.0, abs_tol=1e-9):
        result = prompt
    else:
        target_label = f"{target_duration:g}"
        timing_pattern = re.compile(
            rf"one continuous\s+{re.escape(target_label)}-second\b", re.IGNORECASE
        )
        adapted, replacements = timing_pattern.subn(
            f"one continuous {api_duration}-second", prompt, count=1
        )
        if replacements == 0:
            adapted = prompt
        result = (
            f"{adapted}\n\n"
            "Provider timing adaptation:\n"
            f"- Distribute the complete requested motion cycle evenly across the full "
            f"{api_duration}-second output.\n"
            f"- Post-processing will retime the full {api_duration}-second result to "
            f"{target_label} seconds. Do not finish early, freeze, or add an idle hold."
        )
    if len(result) > MAX_PROMPT_CHARS:
        raise VideoGenerationError(
            f"MiniMax prompt is {len(result)} characters; limit is {MAX_PROMPT_CHARS}"
        )
    return result


def api_key_env_name(billing_source: str) -> str:
    try:
        return API_KEY_ENV_BY_BILLING[billing_source]
    except KeyError as exc:
        raise VideoGenerationError(
            f"unknown MiniMax billing source: {billing_source}"
        ) from exc


def media_plan_credit_estimate(resolution: str, api_duration: int) -> int:
    try:
        rate = MEDIA_PLAN_CREDITS_PER_SECOND[resolution]
    except KeyError as exc:
        raise VideoGenerationError(
            f"no Media Plan credit estimate for H3 resolution {resolution}"
        ) from exc
    return rate * api_duration


def image_data_url(path: Path) -> str:
    size = path.stat().st_size
    if size <= 0:
        raise VideoGenerationError(f"prepared source image is empty: {path}")
    if size > MAX_IMAGE_BYTES:
        raise VideoGenerationError(
            f"prepared source image is {size} bytes; MiniMax limit is {MAX_IMAGE_BYTES}"
        )
    suffix = path.suffix.lower()
    mime = {
        ".png": "image/png",
        ".jpg": "image/jpeg",
        ".jpeg": "image/jpeg",
        ".webp": "image/webp",
        ".heic": "image/heic",
        ".heif": "image/heif",
    }.get(suffix)
    if mime is None:
        raise VideoGenerationError(f"unsupported MiniMax source image format: {path}")
    encoded = base64.b64encode(path.read_bytes()).decode("ascii")
    return f"data:{mime};base64,{encoded}"


def build_payload(
    item: dict[str, Any], resolution: str, *, billing_source: str
) -> tuple[dict[str, Any], dict[str, Any]]:
    if billing_source != PAYGO_BILLING:
        raise VideoGenerationError(
            "Media Plan is available through MiniMax Design, not the H3 API; "
            "use --import-design-video"
        )
    api_key_env_name(billing_source)
    target_duration = float(item["duration_seconds"])
    api_duration = provider_duration(target_duration)
    prompt_path = Path(str(item["prompt_file"]))
    source_path = Path(str(item["prepared_source_image"]))
    prompt = provider_prompt(
        prompt_from_markdown(prompt_path), target_duration, api_duration
    )
    data_url = image_data_url(source_path)
    payload = {
        "model": MODEL,
        "content": [
            {"type": "text", "text": prompt},
            {
                "type": "image_url",
                "image_url": {"url": data_url},
                "role": "first_frame",
            },
        ],
        "resolution": resolution,
        "duration": api_duration,
        "ratio": "adaptive",
        "aigc_watermark": False,
    }
    encoded_size = len(
        json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    )
    if encoded_size > MAX_REQUEST_BYTES:
        raise VideoGenerationError(
            f"MiniMax request is {encoded_size} bytes; limit is {MAX_REQUEST_BYTES}"
        )
    summary = {
        "model": MODEL,
        "billing_source": billing_source,
        "resolution": resolution,
        "ratio": "adaptive",
        "target_duration_seconds": target_duration,
        "provider_duration_seconds": api_duration,
        "prompt_characters": len(prompt),
        "source_image_bytes": source_path.stat().st_size,
        "request_bytes": encoded_size,
        "role": "first_frame",
    }
    return payload, summary


def _provider_error_message(status: int, body: bytes) -> tuple[str, str]:
    error_type = ""
    message = body.decode("utf-8", "replace").strip()
    try:
        value = json.loads(body)
        if isinstance(value, dict):
            error = value.get("error")
            if isinstance(error, dict):
                error_type = str(error.get("type", ""))
                message = str(error.get("message", message))
            elif value.get("message"):
                message = str(value["message"])
    except json.JSONDecodeError:
        pass
    return error_type, f"MiniMax HTTP {status}: {message or 'empty error response'}"


class MiniMaxClient:
    def __init__(
        self,
        api_key: str,
        *,
        billing_source: str,
        base_url: str = API_BASE_URL,
        request_timeout: float = 60.0,
        allow_http: bool = False,
    ) -> None:
        if billing_source != PAYGO_BILLING:
            raise GlobalProviderError(
                "Media Plan is available through MiniMax Design, not the H3 API"
            )
        api_key_env_name(billing_source)
        if not api_key.strip():
            raise GlobalProviderError(
                f"{api_key_env_name(billing_source)} is empty"
            )
        parsed = urllib.parse.urlsplit(base_url)
        if parsed.scheme != "https" and not allow_http:
            raise GlobalProviderError("MiniMax API base URL must use HTTPS")
        self._api_key = api_key.strip()
        self._billing_source = billing_source
        self._base_url = base_url.rstrip("/")
        self._request_timeout = request_timeout
        self._allow_http = allow_http

    def _json_request(
        self, method: str, path: str, payload: dict[str, Any] | None = None
    ) -> dict[str, Any]:
        data = None
        headers = {
            "Authorization": f"Bearer {self._api_key}",
            "Accept": "application/json",
        }
        if payload is not None:
            data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
            headers["Content-Type"] = "application/json"
        request = urllib.request.Request(
            f"{self._base_url}{path}", data=data, headers=headers, method=method
        )
        try:
            with urllib.request.urlopen(
                request, timeout=self._request_timeout
            ) as response:
                body = response.read()
        except urllib.error.HTTPError as exc:
            body = exc.read()
            error_type, message = _provider_error_message(exc.code, body)
            if exc.code in {401, 402} or error_type in {
                "authorized_error",
                "insufficient_balance_error",
            }:
                raise GlobalProviderError(message) from exc
            if exc.code == 429 or exc.code >= 500:
                raise TransientProviderError(message) from exc
            raise VideoGenerationError(message) from exc
        except (urllib.error.URLError, TimeoutError, OSError) as exc:
            raise TransientProviderError(
                f"MiniMax request did not complete: {exc}"
            ) from exc
        try:
            value = json.loads(body)
        except json.JSONDecodeError as exc:
            raise VideoGenerationError("MiniMax returned invalid JSON") from exc
        if not isinstance(value, dict):
            raise VideoGenerationError("MiniMax returned a non-object JSON response")
        return value

    def create_video(self, payload: dict[str, Any]) -> str:
        try:
            value = self._json_request("POST", CREATE_PATH, payload)
        except TransientProviderError as exc:
            raise SubmissionOutcomeUnknown(
                "MiniMax submission ended before a task ID was returned. The request may "
                "already exist; inspect the MiniMax task list before using --retry-failed. "
                f"Original error: {exc}"
            ) from exc
        task_id = value.get("task_id")
        if not isinstance(task_id, str) or not task_id:
            raise VideoGenerationError("MiniMax create response has no task_id")
        return task_id

    def query_video(self, task_id: str) -> dict[str, Any]:
        encoded = urllib.parse.quote(task_id, safe="")
        value = self._json_request("GET", QUERY_PATH.format(task_id=encoded))
        task = value.get("task")
        if not isinstance(task, dict):
            raise VideoGenerationError("MiniMax query response has no task object")
        status = task.get("status")
        if status not in {
            "queued",
            "running",
            "succeeded",
            "failed",
            "cancelled",
        }:
            raise VideoGenerationError(
                f"MiniMax query returned an unknown task status: {status}"
            )
        return task

    def download_video(self, url: str, destination: Path) -> None:
        parsed = urllib.parse.urlsplit(url)
        if parsed.scheme != "https" and not self._allow_http:
            raise VideoGenerationError("MiniMax result URL must use HTTPS")
        request = urllib.request.Request(url, headers={"Accept": "video/*"})
        temporary = destination.with_name(
            f".{destination.name}.download-{os.getpid()}-{uuid.uuid4().hex}"
        )
        total = 0
        try:
            with urllib.request.urlopen(
                request, timeout=self._request_timeout
            ) as response:
                temporary.parent.mkdir(parents=True, exist_ok=True)
                with temporary.open("wb") as output:
                    while True:
                        chunk = response.read(1024 * 1024)
                        if not chunk:
                            break
                        total += len(chunk)
                        if total > DOWNLOAD_LIMIT_BYTES:
                            raise VideoGenerationError(
                                "MiniMax video download exceeded the 1 GiB local limit"
                            )
                        output.write(chunk)
            if total < 1024:
                raise VideoGenerationError(
                    f"MiniMax video download is unexpectedly small: {total} bytes"
                )
            os.replace(temporary, destination)
        except urllib.error.HTTPError as exc:
            raise TransientProviderError(
                f"MiniMax video download returned HTTP {exc.code}"
            ) from exc
        except (urllib.error.URLError, TimeoutError, OSError) as exc:
            raise TransientProviderError(
                f"MiniMax video download did not complete: {exc}"
            ) from exc
        finally:
            temporary.unlink(missing_ok=True)


def run_command(
    command: list[str], timeout: float = 300.0
) -> subprocess.CompletedProcess[str]:
    try:
        result = subprocess.run(
            command,
            check=False,
            text=True,
            capture_output=True,
            timeout=timeout,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise VideoGenerationError(f"could not run {command[0]}: {exc}") from exc
    if result.returncode != 0:
        detail = (
            result.stderr.strip()
            or result.stdout.strip()
            or f"exit {result.returncode}"
        )
        raise VideoGenerationError(f"{command[0]} failed: {detail}")
    return result


def require_media_tools() -> tuple[str, str]:
    ffmpeg = shutil.which("ffmpeg")
    ffprobe = shutil.which("ffprobe")
    if ffmpeg is None or ffprobe is None:
        raise VideoGenerationError("ffmpeg and ffprobe are required")
    return ffmpeg, ffprobe


def probe_video(path: Path, ffprobe: str) -> dict[str, Any]:
    result = run_command(
        [
            ffprobe,
            "-v",
            "error",
            "-count_frames",
            "-select_streams",
            "v:0",
            "-show_entries",
            "stream=width,height,r_frame_rate,duration,nb_frames,nb_read_frames,codec_name,pix_fmt",
            "-of",
            "json",
            str(path),
        ],
        timeout=60.0,
    )
    try:
        streams = json.loads(result.stdout).get("streams", [])
    except json.JSONDecodeError as exc:
        raise VideoGenerationError(f"ffprobe returned invalid JSON for {path}") from exc
    if not streams or not isinstance(streams[0], dict):
        raise VideoGenerationError(f"no video stream in {path}")
    return streams[0]


def parse_rate(value: Any) -> float:
    text = str(value or "0")
    if "/" in text:
        numerator, denominator = text.split("/", 1)
        return float(numerator) / max(1.0, float(denominator))
    return float(text)


def matte_color(matte: str) -> str:
    return {
        "magenta": "0xFF00FF",
        "cyan": "0x00FFFF",
        "red": "0xFF0000",
        "black": "0x000000",
        "none": "0x000000",
    }.get(matte, "0x000000")


def normalize_video(
    source: Path,
    destination: Path,
    item: dict[str, Any],
    *,
    ffmpeg: str,
    ffprobe: str,
) -> tuple[dict[str, Any], dict[str, Any]]:
    source_probe = probe_video(source, ffprobe)
    source_duration = float(source_probe.get("duration", 0.0))
    if source_duration <= 0:
        raise VideoGenerationError(
            f"downloaded video has no positive duration: {source}"
        )
    target_duration = float(item["duration_seconds"])
    target_fps = int(item["source_fps"])
    width = int(item["width"])
    height = int(item["height"])
    if target_fps <= 0 or width <= 0 or height <= 0:
        raise VideoGenerationError(
            f"invalid animation output contract for {item['id']}"
        )
    expected_frames = max(1, round(target_duration * target_fps))
    timing_factor = target_duration / source_duration
    filter_chain = ",".join(
        [
            f"setpts={timing_factor:.12f}*(PTS-STARTPTS)",
            f"fps={target_fps}",
            f"scale={width}:{height}:force_original_aspect_ratio=decrease:flags=lanczos",
            (
                f"pad={width}:{height}:(ow-iw)/2:(oh-ih)/2:"
                f"color={matte_color(str(item['matte']))}"
            ),
            "setsar=1",
            f"trim=duration={target_duration:.9f}",
            "setpts=PTS-STARTPTS",
        ]
    )
    destination.parent.mkdir(parents=True, exist_ok=True)
    run_command(
        [
            ffmpeg,
            "-hide_banner",
            "-loglevel",
            "error",
            "-y",
            "-i",
            str(source),
            "-an",
            "-vf",
            filter_chain,
            "-frames:v",
            str(expected_frames),
            "-c:v",
            "libx264",
            "-preset",
            "medium",
            "-crf",
            "12",
            "-pix_fmt",
            "yuv420p",
            "-movflags",
            "+faststart",
            str(destination),
        ],
        timeout=600.0,
    )
    output_probe = probe_video(destination, ffprobe)
    output_width = int(output_probe.get("width", 0))
    output_height = int(output_probe.get("height", 0))
    output_rate = parse_rate(output_probe.get("r_frame_rate"))
    output_duration = float(output_probe.get("duration", 0.0))
    frame_count = int(
        output_probe.get("nb_read_frames") or output_probe.get("nb_frames") or 0
    )
    if (output_width, output_height) != (width, height):
        raise VideoGenerationError(
            f"normalized video is {output_width}x{output_height}; expected {width}x{height}"
        )
    if output_rate + 0.01 < target_fps:
        raise VideoGenerationError(
            f"normalized video is {output_rate:.3f} fps; expected at least {target_fps}"
        )
    if abs(output_duration - target_duration) > max(0.05, 1.5 / target_fps):
        raise VideoGenerationError(
            f"normalized video is {output_duration:.3f}s; expected {target_duration:.3f}s"
        )
    if frame_count and frame_count != expected_frames:
        raise VideoGenerationError(
            f"normalized video has {frame_count} frames; expected {expected_frames}"
        )
    return source_probe, output_probe


def validate_existing_video(
    item: dict[str, Any], output: Path, ffprobe: str
) -> dict[str, Any]:
    probe = probe_video(output, ffprobe)
    width = int(probe.get("width", 0))
    height = int(probe.get("height", 0))
    expected = (int(item["width"]), int(item["height"]))
    if (width, height) != expected:
        raise VideoGenerationError(
            f"existing video is {width}x{height}; expected {expected[0]}x{expected[1]}"
        )
    duration = float(probe.get("duration", 0.0))
    expected_duration = float(item["duration_seconds"])
    fps = parse_rate(probe.get("r_frame_rate"))
    expected_fps = int(item["source_fps"])
    if abs(duration - expected_duration) > max(0.05, 1.5 / expected_fps):
        raise VideoGenerationError(
            f"existing video is {duration:.3f}s; expected {expected_duration:.3f}s"
        )
    if fps + 0.01 < expected_fps:
        raise VideoGenerationError(
            f"existing video is {fps:.3f} fps; expected at least {expected_fps}"
        )
    return probe


def task_state_path(item_id: str) -> Path:
    return TASK_STATE_ROOT / f"{slug(item_id)}.json"


def load_task_state(item_id: str) -> dict[str, Any] | None:
    path = task_state_path(item_id)
    if not path.is_file():
        return None
    try:
        value = read_json(path)
    except VideoGenerationError:
        return None
    if (
        value.get("schema_version") != 2
        or value.get("id") != item_id
        or not isinstance(value.get("task_id"), str)
        or value.get("billing_source") != PAYGO_BILLING
    ):
        return None
    return value


def save_task_state(item: dict[str, Any], state: dict[str, Any]) -> None:
    state = dict(state)
    state["id"] = item["id"]
    state["updated_at"] = now()
    write_json_atomic(task_state_path(str(item["id"])), state)


def current_item_digest(item: dict[str, Any]) -> str:
    return input_digest(
        [Path(str(item["prompt_file"])), Path(str(item["prepared_source_image"]))]
    )


def validate_prompt_digest(item: dict[str, Any]) -> None:
    prompt_path = Path(str(item["prompt_file"]))
    if not prompt_path.is_file():
        raise ItemBlocked(f"video prompt is missing: {prompt_path}")
    current = sha256_file(prompt_path)
    if item.get("prompt_digest") != current:
        raise VideoGenerationError(
            f"canonical prompt changed for {item['id']}; rebuild the animation queue"
        )


def validate_prepared_source(item: dict[str, Any], path: Path) -> None:
    try:
        width, height = video_source_pipeline.probe_image(path)
    except (video_source_pipeline.PreparationError, json.JSONDecodeError) as exc:
        raise VideoGenerationError(f"prepared first frame is invalid: {exc}") from exc
    expected_width = int(item["width"])
    expected_height = int(item["height"])
    if (width, height) != (expected_width, expected_height):
        raise VideoGenerationError(
            f"prepared first frame is {width}x{height}; expected "
            f"{expected_width}x{expected_height}"
        )
    if not (256 <= width <= 5760 and 256 <= height <= 5760):
        raise VideoGenerationError(
            f"prepared first frame is {width}x{height}; MiniMax requires both sides "
            "between 256 and 5760 pixels"
        )
    ratio = width / float(height)
    if not 0.4 <= ratio <= 2.5:
        raise VideoGenerationError(
            f"prepared first-frame ratio is {ratio:.4f}; MiniMax accepts 0.4 through 2.5"
        )
    matte = str(item["matte"])
    if matte in {"magenta", "cyan", "red", "black"}:
        try:
            video_source_pipeline.validate_prepared_matte(path, matte)
        except (video_source_pipeline.PreparationError, json.JSONDecodeError) as exc:
            raise VideoGenerationError(
                f"prepared first-frame matte is invalid: {exc}"
            ) from exc


def ensure_prepared_source(
    queue: dict[str, Any],
    queue_path: Path,
    item: dict[str, Any],
    *,
    auto_prepare: bool,
) -> str:
    validate_prompt_digest(item)
    prepared = Path(str(item["prepared_source_image"]))
    if not prepared.is_file():
        source = Path(str(item["source_image"]))
        if not source.is_file():
            raise ItemBlocked(f"source still is not generated yet: {source}")
        if not auto_prepare:
            raise ItemBlocked(f"prepared first frame is missing: {prepared}")
        run_command(
            [
                sys.executable,
                str(PREPARE_SCRIPT),
                "--animation-id",
                str(item["id"]),
                "--input",
                str(source),
            ],
            timeout=300.0,
        )
        if not prepared.is_file():
            raise VideoGenerationError(
                f"prepare_video_source.py did not create {prepared}"
            )
    validate_prepared_source(item, prepared)
    current = current_item_digest(item)
    if not current:
        raise ItemBlocked(f"video inputs are incomplete for {item['id']}")
    recorded = str(item.get("input_digest", ""))
    if recorded and recorded != current:
        raise VideoGenerationError(
            f"prompt or prepared first frame changed for {item['id']}; "
            "rebuild the animation queue"
        )
    if not recorded:
        item["input_digest"] = current
        item["attempts"] = 0
        if not Path(str(item["output_file"])).exists():
            item["status"] = "pending"
        item["last_error"] = ""
        item["updated_at"] = now()
        write_json_atomic(queue_path, queue)
    return current


def validate_output_provenance(item: dict[str, Any], output: Path) -> None:
    metadata_path = Path(str(item["output_meta_file"]))
    if not metadata_path.is_file():
        raise VideoGenerationError(f"video provenance is missing: {metadata_path}")
    metadata = read_json(metadata_path)
    if metadata.get("id") != item["id"]:
        raise VideoGenerationError("video provenance asset id does not match")
    if metadata.get("input_digest") != item.get("input_digest"):
        raise VideoGenerationError("video prompt or prepared first frame changed")
    if metadata.get("output_digest") != sha256_file(output):
        raise VideoGenerationError("completed video content changed")


def reconcile_queue(queue: dict[str, Any], queue_path: Path, ffprobe: str) -> bool:
    changed = False
    for item in queue.get("items", []):
        output = Path(str(item.get("output_file", "")))
        if output.is_file():
            try:
                validate_existing_video(item, output, ffprobe)
                validate_output_provenance(item, output)
                if item.get("status") != "done" or item.get("last_error"):
                    item["status"] = "done"
                    item["last_error"] = ""
                    item["updated_at"] = now()
                    changed = True
            except VideoGenerationError as exc:
                message = f"existing video is invalid and was preserved: {exc}"
                if item.get("status") != "failed" or item.get("last_error") != message:
                    item["status"] = "failed"
                    item["last_error"] = message
                    item["updated_at"] = now()
                    changed = True
            continue
        if item.get("status") == "done":
            item["status"] = "pending"
            item["last_error"] = "completed video is missing; it will be regenerated"
            item["updated_at"] = now()
            changed = True
        if item.get("status") == "running":
            state = load_task_state(str(item.get("id", "")))
            if not state or state.get("status") not in RESUMABLE_PROVIDER_STATUSES:
                item["status"] = "pending"
                item["attempts"] = max(0, int(item.get("attempts", 0)) - 1)
                item["last_error"] = (
                    "recovered an interrupted item before a MiniMax task was recorded"
                )
                item["updated_at"] = now()
                changed = True
    if changed:
        write_json_atomic(queue_path, queue)
    return changed


def publish_video(
    temporary: Path,
    output: Path,
    item: dict[str, Any],
    metadata: dict[str, Any],
) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    try:
        os.link(temporary, output)
    except OSError as exc:
        if exc.errno != errno.EEXIST:
            raise
        validate_output_provenance(item, output)
        return
    finally:
        temporary.unlink(missing_ok=True)
    write_json_atomic(Path(str(item["output_meta_file"])), metadata)


def import_design_video(
    queue: dict[str, Any],
    queue_path: Path,
    item: dict[str, Any],
    source: Path,
    *,
    provider_task_id: str,
    design_task_id: str,
    resolution: str,
    ffmpeg: str,
    ffprobe: str,
    actual_media_plan_credits: int | None = None,
    free_generations_before: int | None = None,
    free_generations_after: int | None = None,
) -> dict[str, Any]:
    """Import one H3 result created by the MiniMax Design Media Plan surface."""
    billing_values = {
        "actual Media Plan credits": actual_media_plan_credits,
        "free generations before": free_generations_before,
        "free generations after": free_generations_after,
    }
    for label, value in billing_values.items():
        if value is not None and value < 0:
            raise VideoGenerationError(f"{label} must be non-negative")
    output = Path(str(item["output_file"]))
    if output.exists() or output.is_symlink():
        raise VideoGenerationError(
            f"output already exists and was preserved: {output}"
        )
    if not source.is_file():
        raise VideoGenerationError(f"MiniMax Design video does not exist: {source}")
    if source.resolve() == output.resolve():
        raise VideoGenerationError("MiniMax Design import source and output are identical")

    input_hash = ensure_prepared_source(
        queue, queue_path, item, auto_prepare=False
    )
    source_probe = probe_video(source, ffprobe)
    source_model = "MiniMax-H3"
    normalized = output.with_name(
        f".{output.name}.part-{os.getpid()}-{uuid.uuid4().hex}.mp4"
    )
    try:
        _, output_probe = normalize_video(
            source,
            normalized,
            item,
            ffmpeg=ffmpeg,
            ffprobe=ffprobe,
        )
        estimated_credits = media_plan_credit_estimate(
            resolution,
            provider_duration(float(item["duration_seconds"])),
        )
        provider_metadata: dict[str, Any] = {
            "name": "minimax",
            "surface": "minimax-design",
            "model": source_model,
            "billing_source": MEDIA_PLAN_BILLING,
            "task_id": provider_task_id or None,
            "design_task_id": design_task_id or None,
            "status": "succeeded",
            "resolution": resolution,
            "estimated_media_plan_credits": estimated_credits,
            "source_video": str(source.resolve()),
        }
        if actual_media_plan_credits is not None:
            provider_metadata["actual_media_plan_credits"] = (
                actual_media_plan_credits
            )
        if free_generations_before is not None:
            provider_metadata["free_generations_before"] = free_generations_before
        if free_generations_after is not None:
            provider_metadata["free_generations_after"] = free_generations_after
        metadata = {
            "schema_version": 1,
            "id": item["id"],
            "input_digest": input_hash,
            "output_digest": sha256_file(normalized),
            "completed_at": now(),
            "provider": provider_metadata,
            "normalization": {
                "source_probe": source_probe,
                "output_probe": output_probe,
                "target_width": int(item["width"]),
                "target_height": int(item["height"]),
                "target_duration_seconds": float(item["duration_seconds"]),
                "target_source_fps": int(item["source_fps"]),
            },
        }
        publish_video(normalized, output, item, metadata)
    finally:
        normalized.unlink(missing_ok=True)

    item["status"] = "done"
    item["last_error"] = ""
    if provider_task_id:
        item["provider_task_id"] = provider_task_id
    if design_task_id:
        item["design_task_id"] = design_task_id
    item["updated_at"] = now()
    write_json_atomic(queue_path, queue)
    return {
        "id": item["id"],
        "status": "done",
        "provider_surface": "minimax-design",
        "provider_task_id": provider_task_id,
        "design_task_id": design_task_id,
        "output_file": str(output),
    }


def poll_task(
    client: MiniMaxClient,
    task_id: str,
    item: dict[str, Any],
    state: dict[str, Any],
    *,
    poll_interval: float,
    task_timeout: float,
) -> dict[str, Any]:
    deadline = time.monotonic() + task_timeout
    transient_errors = 0
    last_status = ""
    while True:
        if time.monotonic() >= deadline:
            raise ResumeLater(
                f"MiniMax task {task_id} is still running; rerun to resume it"
            )
        try:
            task = client.query_video(task_id)
            transient_errors = 0
        except TransientProviderError as exc:
            transient_errors += 1
            if transient_errors >= 5:
                raise ResumeLater(
                    f"MiniMax task {task_id} could not be queried; rerun to resume: {exc}"
                ) from exc
            time.sleep(min(poll_interval * transient_errors, 60.0))
            continue
        status = str(task["status"])
        state["status"] = status
        state["task"] = {
            key: task[key]
            for key in (
                "id",
                "model",
                "status",
                "created_at",
                "updated_at",
                "resolution",
                "duration",
                "ratio",
                "task_type",
                "modality",
                "usage",
                "error",
            )
            if key in task
        }
        save_task_state(item, state)
        if status != last_status:
            print(
                json.dumps(
                    {"id": item["id"], "provider_status": status}, ensure_ascii=False
                )
            )
            last_status = status
        if status == "succeeded":
            content = task.get("content")
            if not isinstance(content, dict) or not isinstance(content.get("url"), str):
                raise VideoGenerationError(
                    f"MiniMax task {task_id} succeeded without content.url"
                )
            return task
        if status in TERMINAL_PROVIDER_STATUSES:
            error = task.get("error")
            raise ProviderTaskFailed(
                f"MiniMax task {task_id} ended as {status}: {error or 'no error detail'}"
            )
        time.sleep(poll_interval)


def process_item(
    queue: dict[str, Any],
    queue_path: Path,
    item: dict[str, Any],
    client: MiniMaxClient,
    *,
    billing_source: str,
    resolution: str,
    auto_prepare: bool,
    retry_failed: bool,
    poll_interval: float,
    task_timeout: float,
    ffmpeg: str,
    ffprobe: str,
) -> dict[str, Any]:
    input_hash = ensure_prepared_source(
        queue, queue_path, item, auto_prepare=auto_prepare
    )
    output = Path(str(item["output_file"]))
    if output.is_file():
        validate_existing_video(item, output, ffprobe)
        validate_output_provenance(item, output)
        item["status"] = "done"
        item["last_error"] = ""
        item["updated_at"] = now()
        write_json_atomic(queue_path, queue)
        return {"id": item["id"], "status": "done", "reused_output": True}

    state = load_task_state(str(item["id"]))
    state_matches = bool(
        state
        and state.get("input_digest") == input_hash
        and state.get("billing_source") == billing_source
    )
    resumable = bool(
        state_matches and state and state.get("status") in RESUMABLE_PROVIDER_STATUSES
    )
    if item.get("status") == "failed" and retry_failed:
        resumable = bool(resumable and state and state.get("status") == "succeeded")

    if resumable and state is not None:
        task_id = str(state["task_id"])
        item["status"] = "running"
        item["last_error"] = ""
        item["provider_task_id"] = task_id
        item["updated_at"] = now()
        write_json_atomic(queue_path, queue)
    else:
        if (
            state
            and state.get("status") in {"queued", "running"}
            and (
                state.get("input_digest") != input_hash
                or state.get("billing_source") != billing_source
            )
        ):
            raise VideoGenerationError(
                f"an active MiniMax task for {item['id']} uses different inputs or "
                "billing; wait for it to finish before starting another task"
            )
        payload, payload_summary = build_payload(
            item, resolution, billing_source=billing_source
        )
        item["status"] = "running"
        item["attempts"] = int(item.get("attempts", 0)) + 1
        item["last_error"] = ""
        item["updated_at"] = now()
        write_json_atomic(queue_path, queue)
        try:
            task_id = client.create_video(payload)
        except GlobalProviderError as exc:
            item["status"] = "pending"
            item["attempts"] = max(0, int(item["attempts"]) - 1)
            item["last_error"] = f"MiniMax batch paused before submission: {exc}"
            item["updated_at"] = now()
            write_json_atomic(queue_path, queue)
            raise
        except VideoGenerationError as exc:
            item["status"] = "failed"
            item["last_error"] = str(exc)
            item["updated_at"] = now()
            write_json_atomic(queue_path, queue)
            raise
        state = {
            "schema_version": 2,
            "id": item["id"],
            "task_id": task_id,
            "input_digest": input_hash,
            "billing_source": billing_source,
            "status": "queued",
            "submitted_at": now(),
            "request": payload_summary,
        }
        save_task_state(item, state)
        item["provider_task_id"] = task_id
        item["updated_at"] = now()
        write_json_atomic(queue_path, queue)
        print(json.dumps({"id": item["id"], "task_id": task_id}, ensure_ascii=False))

    assert state is not None
    task = poll_task(
        client,
        task_id,
        item,
        state,
        poll_interval=poll_interval,
        task_timeout=task_timeout,
    )
    content = task["content"]
    download_url = str(content["url"])
    output.parent.mkdir(parents=True, exist_ok=True)
    raw = output.with_name(f".{output.name}.raw-{os.getpid()}-{uuid.uuid4().hex}.mp4")
    normalized = output.with_name(
        f".{output.name}.part-{os.getpid()}-{uuid.uuid4().hex}.mp4"
    )
    try:
        client.download_video(download_url, raw)
        source_probe, output_probe = normalize_video(
            raw,
            normalized,
            item,
            ffmpeg=ffmpeg,
            ffprobe=ffprobe,
        )
        effective_billing_source = str(state["billing_source"])
        request_summary = state.get("request")
        estimated_media_plan_credits = None
        if isinstance(request_summary, dict):
            estimated_media_plan_credits = request_summary.get(
                "estimated_media_plan_credits"
            )
        metadata = {
            "schema_version": 1,
            "id": item["id"],
            "input_digest": input_hash,
            "output_digest": sha256_file(normalized),
            "completed_at": now(),
            "provider": {
                "name": "minimax",
                "model": MODEL,
                "api_version": "v2",
                "billing_source": effective_billing_source,
                "task_id": task_id,
                "status": task.get("status"),
                "resolution": task.get("resolution"),
                "duration": task.get("duration"),
                "ratio": task.get("ratio"),
                "usage": task.get("usage"),
                "estimated_media_plan_credits": estimated_media_plan_credits,
            },
            "normalization": {
                "source_probe": source_probe,
                "output_probe": output_probe,
                "target_width": int(item["width"]),
                "target_height": int(item["height"]),
                "target_duration_seconds": float(item["duration_seconds"]),
                "target_source_fps": int(item["source_fps"]),
            },
        }
        publish_video(normalized, output, item, metadata)
    finally:
        raw.unlink(missing_ok=True)
        normalized.unlink(missing_ok=True)

    state["status"] = "succeeded"
    state["output_file"] = str(output.resolve())
    state["output_digest"] = sha256_file(output)
    save_task_state(item, state)
    item["status"] = "done"
    item["last_error"] = ""
    item["updated_at"] = now()
    write_json_atomic(queue_path, queue)
    return {
        "id": item["id"],
        "status": "done",
        "task_id": task_id,
        "output_file": str(output),
    }


def queue_counts(queue: dict[str, Any]) -> dict[str, int]:
    counts = {"pending": 0, "running": 0, "done": 0, "failed": 0}
    for item in queue.get("items", []):
        status = str(item.get("status", "pending"))
        counts[status] = counts.get(status, 0) + 1
    return counts


def select_items(
    queue: dict[str, Any],
    *,
    billing_source: str,
    animation_ids: set[str],
    retry_failed: bool,
    max_attempts: int,
    max_items: int,
) -> list[dict[str, Any]]:
    selected: list[dict[str, Any]] = []
    known_ids = {str(item.get("id")) for item in queue.get("items", [])}
    unknown = sorted(animation_ids - known_ids)
    if unknown:
        raise VideoGenerationError(f"unknown animation IDs: {', '.join(unknown)}")
    for item in queue.get("items", []):
        if animation_ids and item.get("id") not in animation_ids:
            continue
        state = load_task_state(str(item.get("id", "")))
        has_resumable_task = bool(
            state
            and state.get("status") in RESUMABLE_PROVIDER_STATUSES
            and state.get("billing_source") == billing_source
            and (
                not item.get("input_digest")
                or state.get("input_digest") == item.get("input_digest")
            )
        )
        status = item.get("status")
        eligible = (
            has_resumable_task
            or status == "pending"
            or (retry_failed and status == "failed")
        )
        if not eligible:
            continue
        if not has_resumable_task and int(item.get("attempts", 0)) >= max_attempts:
            continue
        selected.append(item)
        if max_items > 0 and len(selected) >= max_items:
            break
    return selected


def dry_run_summary(
    queue: dict[str, Any],
    selected: list[dict[str, Any]],
    *,
    billing_source: str,
    resolution: str,
    api_key_configured: bool,
) -> dict[str, Any]:
    items: list[dict[str, Any]] = []
    for item in selected:
        prepared = Path(str(item["prepared_source_image"]))
        source = Path(str(item["source_image"]))
        state = load_task_state(str(item["id"]))
        if (
            state
            and state.get("status") in RESUMABLE_PROVIDER_STATUSES
            and state.get("billing_source") == billing_source
        ):
            action = "resume"
            blocked_reason = ""
        elif prepared.is_file():
            action = "submit"
            blocked_reason = ""
        elif source.is_file():
            action = "prepare_then_submit"
            blocked_reason = ""
        else:
            action = "blocked"
            blocked_reason = "source still is not generated yet"
        duration = provider_duration(float(item["duration_seconds"]))
        item_summary = {
            "id": item["id"],
            "action": action,
            "blocked_reason": blocked_reason,
            "source_image": str(source),
            "prepared_source_image": str(prepared),
            "output_file": str(item["output_file"]),
            "target_duration_seconds": item["duration_seconds"],
            "provider_duration_seconds": duration,
            "resolution": resolution,
        }
        if billing_source == MEDIA_PLAN_BILLING and action != "resume":
            item_summary["estimated_media_plan_credits"] = (
                media_plan_credit_estimate(resolution, duration)
            )
        items.append(item_summary)
    return {
        "dry_run": True,
        "provider": (
            "MiniMax Design / MiniMax-H3"
            if billing_source == MEDIA_PLAN_BILLING
            else "MiniMax-H3 V2 API"
        ),
        "billing_source": billing_source,
        "api_key_environment_variable": (
            None
            if billing_source == MEDIA_PLAN_BILLING
            else api_key_env_name(billing_source)
        ),
        "api_key_configured": (
            None if billing_source == MEDIA_PLAN_BILLING else api_key_configured
        ),
        "queue_counts": queue_counts(queue),
        "selected": items,
    }


@contextmanager
def pipeline_lock() -> Iterator[None]:
    try:
        with catalog_pipeline._pipeline_lock():
            yield
    except catalog_pipeline.CatalogError as exc:
        raise VideoGenerationError(str(exc)) from exc


def validate_queue(queue: dict[str, Any], queue_path: Path) -> None:
    if queue.get("kind") != "animation":
        raise VideoGenerationError(
            f"expected an animation queue, got {queue.get('kind')}: {queue_path}"
        )
    errors = catalog_pipeline.validate_queue(queue, queue_path)
    if errors:
        raise VideoGenerationError("\n".join(errors))


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--queue", type=Path, default=DEFAULT_QUEUE)
    parser.add_argument(
        "--animation-id",
        action="append",
        default=[],
        help="only process this animation ID; repeat to select more",
    )
    parser.add_argument("--resolution", choices=("768P", "2K"), default="768P")
    parser.add_argument(
        "--billing-source",
        choices=BILLING_SOURCES,
        default=MEDIA_PLAN_BILLING,
        help=(
            "billing route: media-plan imports a result made in MiniMax Design; "
            "paygo calls the H3 API using MINIMAX_API_KEY (default: media-plan)"
        ),
    )
    parser.add_argument(
        "--max-items",
        type=int,
        default=1,
        help="maximum items in this run; 0 means all eligible items (default: 1)",
    )
    parser.add_argument("--max-attempts", type=int, default=2)
    parser.add_argument("--retry-failed", action="store_true")
    parser.add_argument("--no-auto-prepare", action="store_true")
    parser.add_argument("--poll-interval", type=float, default=10.0)
    parser.add_argument("--task-timeout", type=float, default=1800.0)
    parser.add_argument("--request-timeout", type=float, default=60.0)
    parser.add_argument(
        "--import-design-video",
        type=Path,
        help=(
            "import an H3 MP4 generated inside MiniMax Design; this uses Media Plan "
            "provenance and does not submit an API request"
        ),
    )
    parser.add_argument(
        "--provider-task-id",
        default="",
        help="MiniMax provider task ID recorded by MiniMax Design",
    )
    parser.add_argument(
        "--design-task-id",
        default="",
        help="MiniMax Design task ID recorded by its local project",
    )
    parser.add_argument(
        "--actual-media-plan-credits",
        type=int,
        help="actual video credits reported by Design; use 0 for a free generation",
    )
    parser.add_argument(
        "--free-generations-before",
        type=int,
        help="Design H3 free-generation count immediately before submission",
    )
    parser.add_argument(
        "--free-generations-after",
        type=int,
        help="Design H3 free-generation count immediately after submission",
    )
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    queue_path = args.queue.expanduser().resolve()
    try:
        if args.max_items < 0:
            raise VideoGenerationError("--max-items must be non-negative")
        if args.max_attempts <= 0:
            raise VideoGenerationError("--max-attempts must be greater than zero")
        if args.poll_interval <= 0:
            raise VideoGenerationError("--poll-interval must be greater than zero")
        if args.task_timeout <= 0 or args.request_timeout <= 0:
            raise VideoGenerationError("timeouts must be greater than zero")
        if args.import_design_video and args.billing_source != MEDIA_PLAN_BILLING:
            raise VideoGenerationError(
                "--import-design-video requires --billing-source media-plan"
            )
        if args.import_design_video and args.dry_run:
            raise VideoGenerationError(
                "--import-design-video and --dry-run cannot be used together"
            )
        if args.import_design_video and len(args.animation_id) != 1:
            raise VideoGenerationError(
                "--import-design-video requires exactly one --animation-id"
            )
        billing_evidence_supplied = any(
            value is not None
            for value in (
                args.actual_media_plan_credits,
                args.free_generations_before,
                args.free_generations_after,
            )
        )
        if billing_evidence_supplied and not args.import_design_video:
            raise VideoGenerationError(
                "Design billing evidence requires --import-design-video"
            )
        if (
            args.billing_source == MEDIA_PLAN_BILLING
            and not args.import_design_video
            and not args.dry_run
        ):
            raise VideoGenerationError(
                "Media Plan runs through MiniMax Design; generate there, then pass "
                "the MP4 with --import-design-video"
            )

        queue = read_json(queue_path)
        validate_queue(queue, queue_path)
        animation_ids = set(args.animation_id)
        if args.import_design_video:
            selected = [
                item
                for item in queue.get("items", [])
                if item.get("id") in animation_ids
            ]
            if len(selected) != 1:
                raise VideoGenerationError(
                    f"unknown animation ID: {args.animation_id[0]}"
                )
        else:
            selected = select_items(
                queue,
                billing_source=args.billing_source,
                animation_ids=animation_ids,
                retry_failed=args.retry_failed,
                max_attempts=args.max_attempts,
                max_items=args.max_items,
            )
        if args.dry_run:
            key_environment_variable = (
                api_key_env_name(args.billing_source)
                if args.billing_source == PAYGO_BILLING
                else ""
            )
            print(
                json.dumps(
                    dry_run_summary(
                        queue,
                        selected,
                        billing_source=args.billing_source,
                        resolution=args.resolution,
                        api_key_configured=bool(
                            os.environ.get(key_environment_variable, "").strip()
                        ),
                    ),
                    ensure_ascii=False,
                    indent=2,
                )
            )
            return 0

        key_environment_variable = (
            api_key_env_name(args.billing_source)
            if args.billing_source == PAYGO_BILLING
            else ""
        )
        api_key = os.environ.get(key_environment_variable, "").strip()
        if args.billing_source == PAYGO_BILLING and not api_key:
            raise GlobalProviderError(
                f"{key_environment_variable} is not set; export the key for the "
                f"selected {args.billing_source} billing source before starting a "
                "paid video run"
            )
        ffmpeg, ffprobe = require_media_tools()
        report: dict[str, Any] = {
            "started_at": now(),
            "queue": str(queue_path),
            "provider": (
                "MiniMax Design / MiniMax-H3"
                if args.import_design_video
                else "MiniMax-H3 V2"
            ),
            "billing_source": args.billing_source,
            "resolution": args.resolution,
            "selected": len(selected),
            "done": [],
            "failed": [],
            "blocked": [],
            "resumable": [],
        }
        with pipeline_lock():
            queue = read_json(queue_path)
            validate_queue(queue, queue_path)
            reconcile_queue(queue, queue_path, ffprobe)
            if args.import_design_video:
                selected = [
                    item
                    for item in queue.get("items", [])
                    if item.get("id") in animation_ids
                ]
                if len(selected) != 1:
                    raise VideoGenerationError(
                        f"unknown animation ID: {args.animation_id[0]}"
                    )
                client = None
            else:
                selected = select_items(
                    queue,
                    billing_source=args.billing_source,
                    animation_ids=animation_ids,
                    retry_failed=args.retry_failed,
                    max_attempts=args.max_attempts,
                    max_items=args.max_items,
                )
                client = MiniMaxClient(
                    api_key,
                    billing_source=args.billing_source,
                    request_timeout=args.request_timeout,
                )
            for item in selected:
                try:
                    if args.import_design_video:
                        result = import_design_video(
                            queue,
                            queue_path,
                            item,
                            args.import_design_video.expanduser().resolve(),
                            provider_task_id=args.provider_task_id,
                            design_task_id=args.design_task_id,
                            resolution=args.resolution,
                            ffmpeg=ffmpeg,
                            ffprobe=ffprobe,
                            actual_media_plan_credits=(
                                args.actual_media_plan_credits
                            ),
                            free_generations_before=args.free_generations_before,
                            free_generations_after=args.free_generations_after,
                        )
                    else:
                        assert client is not None
                        result = process_item(
                            queue,
                            queue_path,
                            item,
                            client,
                            billing_source=args.billing_source,
                            resolution=args.resolution,
                            auto_prepare=not args.no_auto_prepare,
                            retry_failed=args.retry_failed,
                            poll_interval=args.poll_interval,
                            task_timeout=args.task_timeout,
                            ffmpeg=ffmpeg,
                            ffprobe=ffprobe,
                        )
                    report["done"].append(result)
                except ItemBlocked as exc:
                    item["status"] = "pending"
                    item["last_error"] = f"waiting without consuming an attempt: {exc}"
                    item["updated_at"] = now()
                    write_json_atomic(queue_path, queue)
                    report["blocked"].append({"id": item["id"], "error": str(exc)})
                except ResumeLater as exc:
                    item["status"] = "running"
                    item["last_error"] = str(exc)
                    item["updated_at"] = now()
                    write_json_atomic(queue_path, queue)
                    report["resumable"].append({"id": item["id"], "error": str(exc)})
                except ProviderTaskFailed as exc:
                    item["status"] = "failed"
                    item["last_error"] = str(exc)
                    item["updated_at"] = now()
                    write_json_atomic(queue_path, queue)
                    report["failed"].append({"id": item["id"], "error": str(exc)})
                except GlobalProviderError:
                    raise
                except TransientProviderError as exc:
                    report["resumable"].append({"id": item["id"], "error": str(exc)})
                    break
                except VideoGenerationError as exc:
                    item["status"] = "failed"
                    item["last_error"] = str(exc)
                    item["updated_at"] = now()
                    write_json_atomic(queue_path, queue)
                    report["failed"].append({"id": item["id"], "error": str(exc)})
            report["finished_at"] = now()
            report["queue_counts"] = queue_counts(queue)
            report_path = REPORT_ROOT / "minimax-video-latest.json"
            write_json_atomic(report_path, report)
            report["report"] = str(report_path.resolve())
        print(json.dumps(report, ensure_ascii=False, indent=2))
        if report["failed"]:
            return 4
        if report["resumable"]:
            return 5
        if report["blocked"]:
            return 6
        return 0
    except (VideoGenerationError, OSError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
