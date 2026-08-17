#!/usr/bin/env python3
"""Process the animation queue through MiniMax Design's Media Plan surface.

The runner submits one H3 task at a time through Design's loopback workspace
gateway, persists each task id before polling, imports the raw MP4 through the
canonical normalizer, and then extracts the Godot frames and atlas. Workspace
identity headers are read from the live Design process and are never logged.
"""

from __future__ import annotations

import argparse
import hashlib
import json
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
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import minimax_video_generate as video_runner

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_QUEUE = ROOT / ".art-pipeline" / "queues" / "animation.json"
DEFAULT_PROJECT = Path.home() / "Movies" / "Hub" / "Projects" / "H3 PlayGround"
STATE_ROOT = ROOT / ".art-pipeline" / "minimax-design-batch"
TASK_ROOT = STATE_ROOT / "tasks"
REPORT_PATH = ROOT / ".art-pipeline" / "reports" / "minimax-design-batch-latest.json"
STOP_FILE = STATE_ROOT / "stop"
QUOTA_EXHAUSTED_PATH = STATE_ROOT / "quota-exhausted.json"

MODEL = "MiniMax-H3"
BACKEND = "minimax_v3"
RESOLUTION = "768P"
MEDIA_CREDITS_PER_SECOND = 70
SUBMIT_PATH = "/api/generate/video/submit"
QUERY_PATH = "/api/generate/tasks/{task_id}/query"
WALLET_PATH = "/api/v1/credit/wallet"
FREE_TRIAL_PATH = "/api/v1/promotions/hailuo03-video-trial/status"
TRACK_PATH = "/api/files/track"
WORKSPACE_PATH = "/api/workspace"
MAX_RESPONSE_BYTES = 16 * 1024 * 1024
SENSITIVE_ERROR_PATTERN = re.compile(
    r"(?i)(bearer\s+|(?:api[_-]?key|token|secret|password|"
    r"HILO_WORKSPACE_CLAIM)\s*[=:]\s*)[^\s&\"']+"
)


class DesignBatchError(RuntimeError):
    """A local batch invariant failed."""


class GatewayUnavailable(DesignBatchError):
    """MiniMax Design's local workspace gateway is temporarily unavailable."""


class GatewayHTTPError(DesignBatchError):
    """The local gateway returned a definite HTTP response."""

    def __init__(
        self,
        message: str,
        *,
        status: int,
        error_code: str = "",
        cloud_error_type: str = "",
    ) -> None:
        super().__init__(message)
        self.status = status
        self.error_code = error_code
        self.cloud_error_type = cloud_error_type


class SubmissionOutcomeUnknown(DesignBatchError):
    """A submit connection ended before a task id could be persisted."""


class QuotaReadError(DesignBatchError):
    """A new paid task must not start until quota can be verified."""


class ExtractionFailed(DesignBatchError):
    """The Design MP4 was preserved, but frame/atlas validation failed."""


@dataclass(frozen=True)
class QuotaSnapshot:
    checked_at: str
    plan_name: str
    total_credit: int
    free_generations_remaining: int
    free_generations_total: int
    activity_active: bool


def now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def sanitize_error(value: object) -> str:
    text = str(value).replace(str(Path.home()), "~")
    return SENSITIVE_ERROR_PATTERN.sub(lambda match: f"{match.group(1)}<redacted>", text)[
        :2000
    ]


def write_json_atomic(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.part-{os.getpid()}-{uuid.uuid4().hex}")
    temporary.write_text(
        json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    os.replace(temporary, path)


def read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise DesignBatchError(f"missing JSON file: {path}") from exc
    except json.JSONDecodeError as exc:
        raise DesignBatchError(f"invalid JSON file {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise DesignBatchError(f"JSON root must be an object: {path}")
    return value


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def slug(item_id: str) -> str:
    return item_id.replace(".", "-").replace("_", "-")


def log_event(event: str, **values: Any) -> None:
    print(
        json.dumps(
            {"timestamp": now(), "event": event, **values},
            ensure_ascii=False,
            separators=(",", ":"),
        ),
        flush=True,
    )


def _process_environment(pid: int) -> dict[str, str]:
    try:
        command = subprocess.check_output(
            ["ps", "eww", "-p", str(pid), "-o", "command="],
            text=True,
            stderr=subprocess.DEVNULL,
            timeout=5,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        raise GatewayUnavailable("could not inspect MiniMax Design workspace process") from exc
    names = (
        "HILO_GATEWAY_ROLE",
        "PORT",
        "HILO_WORKSPACE_CLAIM",
        "HILO_WORKSPACE_INSTANCE_ID",
        "HILO_WORKSPACE_GENERATION",
    )
    values: dict[str, str] = {}
    for name in names:
        match = re.search(rf"(?:^|\s){re.escape(name)}=([^\s]*)", command)
        values[name] = match.group(1) if match else ""
    return values


def _gateway_process_ids() -> list[int]:
    try:
        output = subprocess.check_output(
            ["ps", "-axo", "pid=,command="],
            text=True,
            stderr=subprocess.DEVNULL,
            timeout=5,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        raise GatewayUnavailable("could not list MiniMax Design processes") from exc
    result: list[int] = []
    for line in output.splitlines():
        if "MiniMax Design.app" not in line or "gateway/dist/main.js" not in line:
            continue
        try:
            result.append(int(line.strip().split(None, 1)[0]))
        except (IndexError, ValueError):
            continue
    return sorted(set(result), reverse=True)


class DesignGatewayClient:
    def __init__(self, base_url: str, headers: dict[str, str]) -> None:
        parsed = urllib.parse.urlsplit(base_url)
        if parsed.scheme != "http" or parsed.hostname not in {"127.0.0.1", "localhost"}:
            raise GatewayUnavailable("MiniMax Design gateway must be loopback HTTP")
        self.base_url = base_url.rstrip("/")
        self.headers = dict(headers)

    def request(
        self,
        method: str,
        path: str,
        payload: dict[str, Any] | None = None,
        *,
        timeout: float = 20.0,
        submission: bool = False,
    ) -> dict[str, Any]:
        data = None
        headers = {**self.headers, "Accept": "application/json"}
        if payload is not None:
            data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
            headers["Content-Type"] = "application/json"
        request = urllib.request.Request(
            f"{self.base_url}{path}", data=data, headers=headers, method=method
        )
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                body = response.read(MAX_RESPONSE_BYTES + 1)
        except urllib.error.HTTPError as exc:
            body = exc.read(MAX_RESPONSE_BYTES)
            message, error_code, cloud_error_type = parse_gateway_error(body)
            raise GatewayHTTPError(
                f"MiniMax Design HTTP {exc.code}: {message}",
                status=exc.code,
                error_code=error_code,
                cloud_error_type=cloud_error_type,
            ) from exc
        except (urllib.error.URLError, TimeoutError, OSError) as exc:
            message = sanitize_error(exc)
            if submission:
                raise SubmissionOutcomeUnknown(
                    "MiniMax Design submission ended before a task id was returned; "
                    "the queue was stopped to prevent a duplicate charge. "
                    f"Original error: {message}"
                ) from exc
            raise GatewayUnavailable(f"MiniMax Design gateway request failed: {message}") from exc
        if len(body) > MAX_RESPONSE_BYTES:
            raise GatewayUnavailable("MiniMax Design gateway response exceeded 16 MiB")
        try:
            value = json.loads(body)
        except json.JSONDecodeError as exc:
            raise GatewayUnavailable("MiniMax Design gateway returned invalid JSON") from exc
        if not isinstance(value, dict):
            raise GatewayUnavailable("MiniMax Design gateway returned non-object JSON")
        return value

    def workspace(self) -> Path:
        value = self.request("GET", WORKSPACE_PATH)
        directory = value.get("dir")
        if not isinstance(directory, str) or not directory:
            raise GatewayUnavailable("MiniMax Design workspace response has no directory")
        return Path(directory).resolve()

    def quota(self) -> QuotaSnapshot:
        try:
            wallet = self.request("GET", WALLET_PATH)
            trial = self.request("GET", FREE_TRIAL_PATH)
            snapshot, group_id = parse_quota(wallet, trial)
        except (GatewayUnavailable, GatewayHTTPError, TypeError, ValueError) as exc:
            raise QuotaReadError(
                f"MiniMax Design quota could not be verified: {sanitize_error(exc)}"
            ) from exc
        if group_id:
            self.headers["x-group-id"] = group_id
        return snapshot

    def track_file(self, relative_path: str, description: str) -> dict[str, Any]:
        return self.request(
            "POST",
            TRACK_PATH,
            {"path": relative_path, "description": description},
            timeout=60,
        )

    def submit_video(self, payload: dict[str, Any]) -> str:
        value = self.request(
            "POST", SUBMIT_PATH, payload, timeout=60, submission=True
        )
        if value.get("ok") is not True:
            raise DesignBatchError("MiniMax Design submit response was not successful")
        task_id = value.get("task_id")
        if not isinstance(task_id, str) or not task_id:
            raise DesignBatchError("MiniMax Design submit response has no task_id")
        return task_id

    def query_video(self, task_id: str) -> dict[str, Any]:
        encoded = urllib.parse.quote(task_id, safe="")
        return self.request("GET", QUERY_PATH.format(task_id=encoded), timeout=60)


def parse_gateway_error(body: bytes) -> tuple[str, str, str]:
    text = body.decode("utf-8", "replace").strip()
    error_code = ""
    cloud_error_type = ""
    try:
        value = json.loads(body)
        if isinstance(value, dict):
            error_code = str(value.get("error_code") or "")
            cloud_error_type = str(value.get("cloud_error_type") or "")
            text = str(
                value.get("user_message")
                or value.get("error")
                or value.get("message")
                or text
            )
    except json.JSONDecodeError:
        pass
    return sanitize_error(text or "empty response"), error_code, cloud_error_type


def parse_quota(
    wallet: dict[str, Any], trial: dict[str, Any]
) -> tuple[QuotaSnapshot, str]:
    wallets = wallet.get("wallets")
    if not isinstance(wallets, list):
        raise TypeError("wallet response has no wallets list")
    media_wallet: dict[str, Any] | None = None
    for candidate in wallets:
        if not isinstance(candidate, dict):
            continue
        if candidate.get("source") == 1 or str(candidate.get("plan_name", "")).startswith(
            "Media Plan"
        ):
            media_wallet = candidate
            break
    if media_wallet is None:
        raise ValueError("Media Plan wallet was not found")
    try:
        total_credit = int(str(media_wallet.get("total_credit", "")))
        free_remaining = int(trial["remainingCount"])
        free_total = int(trial["freeCount"])
    except (KeyError, TypeError, ValueError) as exc:
        raise ValueError("quota response contains invalid credit counts") from exc
    if total_credit < 0 or free_remaining < 0 or free_total < 0:
        raise ValueError("quota response contains negative credit counts")
    group_id = ""
    url = str(media_wallet.get("url") or "")
    if url:
        values = urllib.parse.parse_qs(urllib.parse.urlsplit(url).query)
        candidate = values.get("group_id", [""])[0]
        if re.fullmatch(r"[1-9]\d*", candidate):
            group_id = candidate
    return (
        QuotaSnapshot(
            checked_at=now(),
            plan_name=str(media_wallet.get("plan_name") or "Media Plan"),
            total_credit=total_credit,
            free_generations_remaining=free_remaining,
            free_generations_total=free_total,
            activity_active=bool(trial.get("activityActive", False)),
        ),
        group_id,
    )


def discover_client(project: Path) -> DesignGatewayClient:
    expected = project.resolve()
    saw_workspace = False
    for pid in _gateway_process_ids():
        try:
            env = _process_environment(pid)
        except GatewayUnavailable:
            continue
        if env.get("HILO_GATEWAY_ROLE") != "workspace":
            continue
        saw_workspace = True
        port = env.get("PORT", "")
        if not port.isdigit() or not (1 <= int(port) <= 65535):
            continue
        identity = {
            "x-hilo-workspace": env.get("HILO_WORKSPACE_CLAIM", ""),
            "x-hilo-workspace-instance": env.get("HILO_WORKSPACE_INSTANCE_ID", ""),
            "x-hilo-workspace-generation": env.get("HILO_WORKSPACE_GENERATION", ""),
            "x-hilo-source": "canvas",
        }
        if any(not value for key, value in identity.items() if key != "x-hilo-source"):
            continue
        client = DesignGatewayClient(f"http://127.0.0.1:{port}", identity)
        try:
            actual = client.workspace()
        except (GatewayUnavailable, GatewayHTTPError):
            continue
        if actual == expected:
            return client
    if saw_workspace:
        raise GatewayUnavailable(
            f"MiniMax Design is open, but its active workspace is not {expected}"
        )
    raise GatewayUnavailable(
        "MiniMax Design workspace gateway is not running; keep the H3 PlayGround project open"
    )


def estimated_credits(item: dict[str, Any]) -> int:
    duration = video_runner.provider_duration(float(item["duration_seconds"]))
    return MEDIA_CREDITS_PER_SECOND * duration


def quota_stop_reason(snapshot: QuotaSnapshot, next_cost: int) -> str:
    if snapshot.free_generations_remaining > 0:
        return ""
    if snapshot.total_credit <= 0:
        return "MiniMax Design Media Plan credits are exhausted"
    if snapshot.total_credit < next_cost:
        return (
            f"MiniMax Design has {snapshot.total_credit} credits, less than the "
            f"next H3 task estimate of {next_cost}"
        )
    return ""


def build_design_request(
    item: dict[str, Any], project_image: Path
) -> tuple[dict[str, Any], dict[str, Any]]:
    target_duration = float(item["duration_seconds"])
    duration = video_runner.provider_duration(target_duration)
    prompt = video_runner.provider_prompt(
        video_runner.prompt_from_markdown(Path(str(item["prompt_file"]))),
        target_duration,
        duration,
    )
    item_slug = slug(str(item["id"]))
    request = {
        "backend": BACKEND,
        "model_id": MODEL,
        "prompt": prompt,
        "filename": f"{item_slug}-original",
        "image_paths": [str(project_image.resolve())],
        "params": {
            "duration": str(duration),
            "ratio": "adaptive",
            "resolution": RESOLUTION,
            "generate_audio": "false",
            "image_mode": "first-last-frame",
        },
        "source_tool": "hub_generate_video:MiniMax:i2v",
    }
    return request, {
        "backend": BACKEND,
        "model_id": MODEL,
        "mode": "i2v",
        "duration": duration,
        "ratio": "adaptive",
        "resolution": RESOLUTION,
        "generate_audio": False,
        "project_image": str(project_image.resolve()),
        "prompt_characters": len(prompt),
        "estimated_media_plan_credits": estimated_credits(item),
    }


def task_path(item_id: str) -> Path:
    return TASK_ROOT / f"{slug(item_id)}.json"


def load_task(item_id: str) -> dict[str, Any] | None:
    path = task_path(item_id)
    if not path.is_file():
        return None
    try:
        value = read_json(path)
    except DesignBatchError:
        return None
    if value.get("schema_version") != 1 or value.get("id") != item_id:
        return None
    return value


def save_task(item_id: str, state: dict[str, Any]) -> None:
    value = dict(state)
    value["schema_version"] = 1
    value["id"] = item_id
    value["updated_at"] = now()
    write_json_atomic(task_path(item_id), value)


def quota_dict(snapshot: QuotaSnapshot | None) -> dict[str, Any] | None:
    return asdict(snapshot) if snapshot else None


def queue_counts(queue: dict[str, Any]) -> dict[str, int]:
    counts = {"pending": 0, "running": 0, "done": 0, "failed": 0}
    for item in queue.get("items", []):
        status = str(item.get("status", "pending"))
        counts[status] = counts.get(status, 0) + 1
    return counts


def extraction_path(item_id: str) -> Path:
    return ROOT / ".art-pipeline" / "extracted" / slug(item_id)


def extraction_complete(item_id: str) -> bool:
    root = extraction_path(item_id)
    metadata_path = root / "animation.json"
    atlas = root / "atlas.png"
    frames = root / "frames"
    if not metadata_path.is_file() or not atlas.is_file() or not frames.is_dir():
        return False
    try:
        metadata = read_json(metadata_path)
        count = int(metadata.get("frame_count", 0))
    except (DesignBatchError, TypeError, ValueError):
        return False
    return (
        metadata.get("animation_id") == item_id
        and count > 0
        and len(list(frames.glob("*.png"))) == count
    )


def extracted_counts(queue: dict[str, Any]) -> dict[str, int]:
    complete = sum(
        1
        for item in queue.get("items", [])
        if extraction_complete(str(item.get("id", "")))
    )
    total = len(queue.get("items", []))
    return {"done": complete, "remaining": max(0, total - complete), "total": total}


def write_report(
    queue: dict[str, Any],
    *,
    status: str,
    quota: QuotaSnapshot | None,
    active: dict[str, Any] | None = None,
    stop_reason: str = "",
    last_error: str = "",
) -> None:
    active_summary = None
    if active:
        active_summary = {
            key: active.get(key)
            for key in ("id", "status", "design_task_id", "submitted_at")
            if active.get(key) is not None
        }
    item_failures = sum(
        1
        for item in queue.get("items", [])
        if (state := load_task(str(item.get("id", ""))))
        and state.get("status")
        in {"failed", "extraction_failed", "submission_unknown"}
    )
    write_json_atomic(
        REPORT_PATH,
        {
            "schema_version": 1,
            "updated_at": now(),
            "status": status,
            "queue": queue_counts(queue),
            "extraction": extracted_counts(queue),
            "item_failures": item_failures,
            "quota": quota_dict(quota),
            "active_task": active_summary,
            "stop_reason": stop_reason,
            "last_error": sanitize_error(last_error),
        },
    )


def stage_project_image(
    client: DesignGatewayClient,
    project: Path,
    item: dict[str, Any],
    input_digest: str,
) -> Path:
    source = Path(str(item["prepared_source_image"]))
    if not source.is_file():
        raise DesignBatchError(f"prepared source image is missing: {source}")
    relative = Path("batch-inputs") / f"{slug(str(item['id']))}-{input_digest[:12]}.png"
    destination = project / relative
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.is_file():
        if sha256_file(destination) != sha256_file(source):
            raise DesignBatchError(
                f"staged Design image has different content and was preserved: {destination}"
            )
    else:
        temporary = destination.with_name(
            f".{destination.name}.part-{os.getpid()}-{uuid.uuid4().hex}"
        )
        shutil.copyfile(source, temporary)
        os.replace(temporary, destination)
    tracked = client.track_file(
        relative.as_posix(), f"First frame for {item['id']} MiniMax H3 batch generation"
    )
    if tracked.get("ok") is not True:
        raise DesignBatchError(f"MiniMax Design did not track {relative.as_posix()}")
    return destination


def resolve_result_path(project: Path, result_path: object) -> Path:
    if not isinstance(result_path, str) or not result_path:
        raise DesignBatchError("MiniMax Design task succeeded without a result path")
    candidate = Path(result_path)
    resolved = (candidate if candidate.is_absolute() else project / candidate).resolve()
    project_root = project.resolve()
    try:
        resolved.relative_to(project_root)
    except ValueError as exc:
        raise DesignBatchError(
            "MiniMax Design returned a result outside the active project"
        ) from exc
    if not resolved.is_file():
        raise DesignBatchError(f"MiniMax Design result file is missing: {resolved}")
    return resolved


def run_command(command: list[str], *, timeout: float) -> str:
    try:
        result = subprocess.run(
            command,
            text=True,
            capture_output=True,
            timeout=timeout,
            check=False,
            cwd=ROOT,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise DesignBatchError(f"could not run {command[0]}: {sanitize_error(exc)}") from exc
    if result.returncode:
        detail = result.stderr.strip() or result.stdout.strip() or f"exit {result.returncode}"
        raise DesignBatchError(f"{Path(command[1]).name} failed: {sanitize_error(detail)}")
    return result.stdout


def import_and_extract(
    item: dict[str, Any],
    raw_video: Path,
    state: dict[str, Any],
    before: QuotaSnapshot,
    after: QuotaSnapshot,
) -> None:
    item_id = str(item["id"])
    output = Path(str(item["output_file"]))
    if not output.is_file():
        if after.free_generations_remaining < before.free_generations_remaining:
            actual_credits = 0
        else:
            actual_credits = max(0, before.total_credit - after.total_credit)
        command = [
            sys.executable,
            str(ROOT / "tools" / "art_pipeline" / "minimax_video_generate.py"),
            "--animation-id",
            item_id,
            "--billing-source",
            video_runner.MEDIA_PLAN_BILLING,
            "--resolution",
            RESOLUTION,
            "--import-design-video",
            str(raw_video),
            "--provider-task-id",
            str(state.get("provider_task_id") or ""),
            "--design-task-id",
            str(state.get("design_task_id") or ""),
            "--actual-media-plan-credits",
            str(actual_credits),
            "--free-generations-before",
            str(before.free_generations_remaining),
            "--free-generations-after",
            str(after.free_generations_remaining),
        ]
        run_command(command, timeout=1200)
    if not extraction_complete(item_id):
        try:
            run_command(
                [
                    sys.executable,
                    str(ROOT / "tools" / "art_pipeline" / "extract_video.py"),
                    "--animation-id",
                    item_id,
                    "--input",
                    str(output),
                ],
                timeout=1200,
            )
        except DesignBatchError as exc:
            raise ExtractionFailed(str(exc)) from exc
    if not extraction_complete(item_id):
        raise DesignBatchError(f"frame extraction did not complete for {item_id}")


def is_billing_error(exc: GatewayHTTPError) -> bool:
    fields = f"{exc.error_code} {exc.cloud_error_type} {exc}".lower()
    return any(
        token in fields
        for token in (
            "billing_insufficient_balance",
            "insufficient_quota",
            "insufficient balance",
            "insufficient credit",
            "余额不足",
            "额度不足",
        )
    )


def terminal_item_failure(
    queue: dict[str, Any], queue_path: Path, item: dict[str, Any], error: object
) -> None:
    item["status"] = "failed"
    item["last_error"] = sanitize_error(error)
    item["updated_at"] = now()
    video_runner.write_json_atomic(queue_path, queue)


def query_until_terminal(
    client: DesignGatewayClient,
    project: Path,
    queue_path: Path,
    item: dict[str, Any],
    state: dict[str, Any],
    *,
    poll_interval: float,
    quota_check_interval: float,
    last_quota: QuotaSnapshot,
) -> tuple[Path, QuotaSnapshot, dict[str, Any], bool]:
    item_id = str(item["id"])
    task_id = str(state["design_task_id"])
    last_quota_monotonic = time.monotonic()
    stop_after_active = False
    transient_errors = 0
    while True:
        if STOP_FILE.exists():
            raise DesignBatchError("batch stop was requested")
        if time.monotonic() - last_quota_monotonic >= quota_check_interval:
            try:
                last_quota = client.quota()
                last_quota_monotonic = time.monotonic()
                reason = quota_stop_reason(last_quota, estimated_credits(item))
                if reason:
                    stop_after_active = True
                write_report(
                    read_json(queue_path),
                    status="processing",
                    quota=last_quota,
                    active=state,
                    stop_reason=reason,
                )
            except QuotaReadError as exc:
                log_event(
                    "quota_check_failed_during_active_task",
                    id=item_id,
                    error=sanitize_error(exc),
                )
        try:
            response = client.query_video(task_id)
            transient_errors = 0
        except GatewayHTTPError as exc:
            if exc.status not in {408, 429} and exc.status < 500:
                raise
            transient_errors += 1
            if transient_errors >= 5:
                raise GatewayUnavailable(str(exc)) from exc
            log_event(
                "query_retry",
                id=item_id,
                design_task_id=task_id,
                attempt=transient_errors,
                error=sanitize_error(exc),
            )
            time.sleep(min(60.0, poll_interval * transient_errors))
            continue
        except GatewayUnavailable as exc:
            transient_errors += 1
            if transient_errors >= 5:
                raise
            log_event(
                "query_retry",
                id=item_id,
                design_task_id=task_id,
                attempt=transient_errors,
                error=sanitize_error(exc),
            )
            time.sleep(min(60.0, poll_interval * transient_errors))
            continue
        status = str(response.get("status") or "")
        if response.get("ok") is True and status == "processing":
            state["status"] = "processing"
            save_task(item_id, state)
            time.sleep(poll_interval)
            continue
        if response.get("ok") is True and status == "succeeded":
            result = response.get("result")
            if not isinstance(result, dict):
                result = {}
            raw_video = resolve_result_path(project, result.get("path"))
            state["status"] = "succeeded"
            state["result"] = {
                key: result.get(key)
                for key in (
                    "path",
                    "width",
                    "height",
                    "duration",
                    "provider_task_id",
                    "node_id",
                )
                if result.get(key) is not None
            }
            if result.get("provider_task_id"):
                state["provider_task_id"] = str(result["provider_task_id"])
            state["raw_video"] = str(raw_video)
            save_task(item_id, state)
            return raw_video, last_quota, state, stop_after_active
        error_code = str(response.get("error_code") or "")
        message = str(response.get("user_message") or response.get("error") or response)
        if response.get("ok") is False and status == "failed":
            state["status"] = "failed"
            state["error_code"] = error_code
            state["last_error"] = sanitize_error(message)
            save_task(item_id, state)
            if "billing_insufficient_balance" in error_code:
                raise GatewayHTTPError(message, status=402, error_code=error_code)
            raise DesignBatchError(message)
        raise GatewayUnavailable(f"unknown MiniMax Design query response: {sanitize_error(response)}")


def process_item(
    client: DesignGatewayClient,
    project: Path,
    queue: dict[str, Any],
    queue_path: Path,
    item: dict[str, Any],
    quota_before: QuotaSnapshot,
    *,
    poll_interval: float,
    quota_check_interval: float,
) -> tuple[QuotaSnapshot, bool]:
    item_id = str(item["id"])
    input_digest = video_runner.ensure_prepared_source(
        queue, queue_path, item, auto_prepare=False
    )
    state = load_task(item_id)
    output = Path(str(item["output_file"]))

    if output.is_file():
        if extraction_complete(item_id):
            if not state or state.get("status") != "done":
                save_task(item_id, {"status": "done", "input_digest": input_digest})
            return quota_before, False
        if not state:
            metadata = read_json(Path(str(item["output_meta_file"])))
            raw_provider = metadata.get("provider")
            provider: dict[str, Any] = (
                raw_provider if isinstance(raw_provider, dict) else {}
            )
            state = {
                "status": "succeeded",
                "input_digest": input_digest,
                "design_task_id": provider.get("design_task_id", ""),
                "provider_task_id": provider.get("task_id", ""),
            }
        import_and_extract(item, output, state, quota_before, quota_before)
        state["status"] = "done"
        state["completed_at"] = now()
        save_task(item_id, state)
        return quota_before, False

    resumable = bool(
        state
        and state.get("input_digest") == input_digest
        and state.get("status") in {"submitted", "processing", "succeeded"}
        and state.get("design_task_id")
    )
    if state and state.get("status") in {"submission_unknown", "submitting"}:
        raise SubmissionOutcomeUnknown(
            str(state.get("last_error") or "submission outcome is unknown after restart")
        )
    if state and state.get("status") == "failed":
        raise DesignBatchError(
            str(state.get("last_error") or "previous MiniMax Design task failed")
        )

    if resumable and state is not None and state.get("status") == "succeeded":
        raw_video = resolve_result_path(project, state.get("raw_video"))
        quota_after = client.quota()
        stop_after_active = bool(quota_stop_reason(quota_after, estimated_credits(item)))
    else:
        if not resumable:
            project_image = stage_project_image(client, project, item, input_digest)
            request, request_summary = build_design_request(item, project_image)
            state = {
                "status": "submitting",
                "input_digest": input_digest,
                "quota_before": quota_dict(quota_before),
                "request": request_summary,
            }
            save_task(item_id, state)
            try:
                task_id = client.submit_video(request)
            except SubmissionOutcomeUnknown as exc:
                state["status"] = "submission_unknown"
                state["last_error"] = sanitize_error(exc)
                save_task(item_id, state)
                raise
            except GatewayHTTPError:
                state["status"] = "submit_failed"
                save_task(item_id, state)
                raise
            state["status"] = "submitted"
            state["design_task_id"] = task_id
            state["submitted_at"] = now()
            save_task(item_id, state)
            write_report(
                read_json(queue_path),
                status="processing",
                quota=quota_before,
                active=load_task(item_id),
            )
            log_event("submitted", id=item_id, design_task_id=task_id)
        assert state is not None
        raw_video, _, state, stop_after_active = query_until_terminal(
            client,
            project,
            queue_path,
            item,
            state,
            poll_interval=poll_interval,
            quota_check_interval=quota_check_interval,
            last_quota=quota_before,
        )
        quota_after = client.quota()
        if quota_stop_reason(quota_after, estimated_credits(item)):
            stop_after_active = True

    assert state is not None
    import_and_extract(item, raw_video, state, quota_before, quota_after)
    state["status"] = "done"
    state["completed_at"] = now()
    state["quota_after"] = quota_dict(quota_after)
    save_task(item_id, state)
    log_event(
        "completed",
        id=item_id,
        design_task_id=state.get("design_task_id"),
        provider_task_id=state.get("provider_task_id"),
        total_credit=quota_after.total_credit,
        free_generations_remaining=quota_after.free_generations_remaining,
    )
    return quota_after, stop_after_active


def active_state(queue: dict[str, Any]) -> dict[str, Any] | None:
    for item in queue.get("items", []):
        state = load_task(str(item.get("id", "")))
        if state and state.get("status") in {
            "submitting",
            "submitted",
            "processing",
            "succeeded",
            "submission_unknown",
        }:
            return state
    return None


def next_item(queue: dict[str, Any]) -> dict[str, Any] | None:
    # A persisted remote task always wins over a fresh queue item.
    for item in queue.get("items", []):
        state = load_task(str(item.get("id", "")))
        if state and state.get("status") in {"submitted", "processing", "succeeded"}:
            return item
    for item in queue.get("items", []):
        item_id = str(item.get("id", ""))
        if extraction_complete(item_id):
            continue
        state = load_task(item_id)
        if state and state.get("status") in {
            "failed",
            "extraction_failed",
            "submission_unknown",
        }:
            continue
        if item.get("status") in {"pending", "running", "done"}:
            return item
    return None


def record_quota_stop(
    queue: dict[str, Any], snapshot: QuotaSnapshot, reason: str
) -> None:
    payload = {
        "schema_version": 1,
        "stopped_at": now(),
        "reason": reason,
        "quota": quota_dict(snapshot),
        "queue": queue_counts(queue),
        "extraction": extracted_counts(queue),
    }
    write_json_atomic(QUOTA_EXHAUSTED_PATH, payload)
    write_report(queue, status="quota_exhausted", quota=snapshot, stop_reason=reason)
    log_event(
        "quota_exhausted",
        reason=reason,
        total_credit=snapshot.total_credit,
        free_generations_remaining=snapshot.free_generations_remaining,
    )


def run_batch(args: argparse.Namespace) -> int:
    queue_path = Path(args.queue).resolve()
    project = Path(args.project).resolve()
    STATE_ROOT.mkdir(parents=True, exist_ok=True)
    TASK_ROOT.mkdir(parents=True, exist_ok=True)
    REPORT_PATH.parent.mkdir(parents=True, exist_ok=True)
    QUOTA_EXHAUSTED_PATH.unlink(missing_ok=True)
    processed = 0
    last_quota: QuotaSnapshot | None = None

    while not STOP_FILE.exists():
        queue = read_json(queue_path)
        item = next_item(queue)
        if item is None:
            failures = sum(
                1
                for candidate in queue.get("items", [])
                if (state := load_task(str(candidate.get("id", ""))))
                and state.get("status")
                in {"failed", "extraction_failed", "submission_unknown"}
            )
            status = "complete" if failures == 0 else "complete_with_failures"
            write_report(queue, status=status, quota=last_quota)
            log_event(status, **queue_counts(queue), extraction=extracted_counts(queue))
            return 0

        if args.max_items > 0 and processed >= args.max_items:
            write_report(queue, status="item_limit_reached", quota=last_quota)
            return 0

        try:
            client = discover_client(project)
            quota = client.quota()
            last_quota = quota
        except (GatewayUnavailable, QuotaReadError) as exc:
            write_report(
                queue,
                status="waiting_for_design",
                quota=last_quota,
                active=active_state(queue),
                last_error=str(exc),
            )
            log_event("waiting_for_design", error=sanitize_error(exc))
            time.sleep(args.gateway_retry_seconds)
            continue

        state = load_task(str(item["id"]))
        has_remote_task = bool(
            state
            and state.get("status") in {"submitted", "processing", "succeeded"}
            and state.get("design_task_id")
        )
        reason = quota_stop_reason(quota, estimated_credits(item))
        if reason and not has_remote_task:
            record_quota_stop(queue, quota, reason)
            return 0

        write_report(
            queue,
            status="processing",
            quota=quota,
            active=state,
            stop_reason=reason if has_remote_task else "",
        )
        try:
            last_quota, stop_after_active = process_item(
                client,
                project,
                queue,
                queue_path,
                item,
                quota,
                poll_interval=args.poll_interval,
                quota_check_interval=args.quota_check_interval,
            )
            processed += 1
        except SubmissionOutcomeUnknown as exc:
            queue = read_json(queue_path)
            write_report(
                queue,
                status="stopped_submission_unknown",
                quota=last_quota,
                active=load_task(str(item["id"])),
                stop_reason=str(exc),
            )
            log_event(
                "stopped_submission_unknown", id=item["id"], error=sanitize_error(exc)
            )
            return 0
        except QuotaReadError as exc:
            write_report(
                read_json(queue_path),
                status="waiting_for_quota",
                quota=last_quota,
                active=load_task(str(item["id"])),
                last_error=str(exc),
            )
            log_event("waiting_for_quota", id=item["id"], error=sanitize_error(exc))
            time.sleep(args.gateway_retry_seconds)
            continue
        except GatewayHTTPError as exc:
            if is_billing_error(exc):
                try:
                    last_quota = client.quota()
                except QuotaReadError:
                    pass
                if last_quota is None:
                    last_quota = quota
                record_quota_stop(read_json(queue_path), last_quota, sanitize_error(exc))
                return 0
            terminal_item_failure(queue, queue_path, item, exc)
            state = load_task(str(item["id"])) or {}
            state["status"] = "failed"
            state["last_error"] = sanitize_error(exc)
            save_task(str(item["id"]), state)
            log_event("item_failed", id=item["id"], error=sanitize_error(exc))
            continue
        except ExtractionFailed as exc:
            # The paid Design result and normalized MP4 remain valid and the
            # canonical queue remains done. Only the derived frames/atlas are
            # marked failed, so the batch can continue without regenerating or
            # paying for the same video again.
            state = load_task(str(item["id"])) or {}
            state["status"] = "extraction_failed"
            state["last_error"] = sanitize_error(exc)
            state["video_file"] = str(item.get("output_file", ""))
            save_task(str(item["id"]), state)
            current_queue = read_json(queue_path)
            write_report(
                current_queue,
                status="processing",
                quota=last_quota,
                last_error=str(exc),
            )
            log_event("extraction_failed", id=item["id"], error=sanitize_error(exc))
            processed += 1
            continue
        except GatewayUnavailable as exc:
            write_report(
                read_json(queue_path),
                status="waiting_for_design",
                quota=last_quota,
                active=load_task(str(item["id"])),
                last_error=str(exc),
            )
            log_event("waiting_for_design", id=item["id"], error=sanitize_error(exc))
            time.sleep(args.gateway_retry_seconds)
            continue
        except DesignBatchError as exc:
            if str(exc) == "batch stop was requested":
                break
            terminal_item_failure(queue, queue_path, item, exc)
            state = load_task(str(item["id"])) or {}
            state["status"] = "failed"
            state["last_error"] = sanitize_error(exc)
            save_task(str(item["id"]), state)
            log_event("item_failed", id=item["id"], error=sanitize_error(exc))
            continue

        if stop_after_active and last_quota is not None:
            reason = quota_stop_reason(last_quota, estimated_credits(item))
            if reason:
                record_quota_stop(read_json(queue_path), last_quota, reason)
                return 0

    queue = read_json(queue_path)
    write_report(queue, status="stopped", quota=last_quota, stop_reason="stop requested")
    log_event("stopped")
    return 0


def print_status(queue_path: Path) -> int:
    queue = read_json(queue_path)
    report = (
        read_json(REPORT_PATH)
        if REPORT_PATH.is_file()
        else {
            "schema_version": 1,
            "updated_at": now(),
            "status": "not_started",
            "queue": queue_counts(queue),
            "extraction": extracted_counts(queue),
            "quota": None,
            "active_task": active_state(queue),
            "stop_reason": "",
            "last_error": "",
        }
    )
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--queue", default=str(DEFAULT_QUEUE))
    parser.add_argument("--project", default=str(DEFAULT_PROJECT))
    parser.add_argument("--poll-interval", type=float, default=15.0)
    parser.add_argument("--quota-check-interval", type=float, default=600.0)
    parser.add_argument("--gateway-retry-seconds", type=float, default=60.0)
    parser.add_argument(
        "--max-items",
        type=int,
        default=0,
        help="maximum completed items for a bounded run; 0 means all",
    )
    parser.add_argument("--status", action="store_true")
    return parser


def main() -> int:
    args = build_parser().parse_args()
    if args.poll_interval <= 0 or args.quota_check_interval <= 0:
        raise SystemExit("poll and quota intervals must be greater than zero")
    if args.gateway_retry_seconds <= 0 or args.max_items < 0:
        raise SystemExit("retry seconds must be positive and max-items must be non-negative")
    if args.status:
        return print_status(Path(args.queue).resolve())
    return run_batch(args)


if __name__ == "__main__":
    raise SystemExit(main())
