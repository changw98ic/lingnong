#!/usr/bin/env python3
"""Run exactly three independent ego image workers, then merge their results."""

from __future__ import annotations

import argparse
import fcntl
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
MAIN_QUEUE = ROOT / ".art-pipeline" / "queues" / "static.json"
RUN_ROOT = ROOT / ".art-pipeline" / "parallel-runs"
LOCK = Path.home() / ".cache" / "lingnong-art-pipeline" / "pipeline.lock"
RUNNER = ROOT / "tools" / "art_pipeline" / "ego_batch_generate.sh"


class ParallelError(RuntimeError):
    pass


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.part-{os.getpid()}")
    temporary.write_text(
        json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    os.replace(temporary, path)


def now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--queue", type=Path, default=MAIN_QUEUE)
    parser.add_argument("--workers", type=int, default=3, choices=(3,))
    parser.add_argument("--delay", type=int, default=60)
    parser.add_argument("--max-attempts", type=int, default=2)
    parser.add_argument("--retry-failed", action="store_true")
    parser.add_argument(
        "--allow-partial",
        action="store_true",
        help="run one or two ready items when fewer than three remain",
    )
    return parser.parse_args()


def select_items(
    queue: dict[str, Any], retry_failed: bool, max_attempts: int
) -> list[dict[str, Any]]:
    statuses = {"pending"}
    if retry_failed:
        statuses.add("failed")
    by_id = {item["id"]: item for item in queue.get("items", [])}
    selected: list[dict[str, Any]] = []
    for item in queue.get("items", []):
        if item.get("status") not in statuses:
            continue
        if int(item.get("attempts", 0)) >= max_attempts:
            continue
        dependencies = [by_id.get(value) for value in item.get("dependencies", [])]
        if any(
            dependency is None
            or dependency.get("status") != "done"
            or not Path(str(dependency.get("output_file", ""))).is_file()
            for dependency in dependencies
        ):
            continue
        selected.append(item)
        if len(selected) == 3:
            break
    return selected


def dependency_closure(
    item: dict[str, Any], by_id: dict[str, dict[str, Any]]
) -> list[dict[str, Any]]:
    ordered: list[dict[str, Any]] = []
    seen: set[str] = set()

    def visit(current: dict[str, Any]) -> None:
        for dependency_id in current.get("dependencies", []):
            dependency = by_id[dependency_id]
            if dependency_id not in seen:
                visit(dependency)
                seen.add(dependency_id)
                ordered.append(dependency)

    visit(item)
    ordered.append(item)
    return ordered


def recover_finished_runs(queue_path: Path) -> list[dict[str, Any]]:
    """Merge fully finished worker queues left behind by an interrupted parent."""
    if not RUN_ROOT.is_dir():
        return []
    main_queue = read_json(queue_path)
    main_by_id = {item["id"]: item for item in main_queue.get("items", [])}
    recovered: list[dict[str, Any]] = []
    changed = False
    for run_dir in sorted(path for path in RUN_ROOT.iterdir() if path.is_dir()):
        report_path = run_dir / "report.json"
        if report_path.exists():
            continue
        worker_paths = sorted(run_dir.glob("worker-*.json"))
        if not worker_paths:
            continue
        results: list[dict[str, Any]] = []
        recoverable = True
        for index, worker_path in enumerate(worker_paths, start=1):
            try:
                worker_queue = read_json(worker_path)
                worker_items = worker_queue.get("items", [])
                target = worker_items[-1]
            except (OSError, json.JSONDecodeError, IndexError, KeyError, TypeError):
                recoverable = False
                break
            item_id = target.get("id")
            if item_id not in main_by_id or target.get("status") not in {
                "done",
                "failed",
            }:
                recoverable = False
                break
            if target.get("status") == "done":
                validation = subprocess.run(
                    [
                        sys.executable,
                        str(ROOT / "tools" / "art_pipeline" / "art_pipeline.py"),
                        "validate-queue",
                        "--queue",
                        str(worker_path),
                    ],
                    cwd=ROOT,
                    text=True,
                    capture_output=True,
                    check=False,
                )
                if validation.returncode != 0:
                    recoverable = False
                    break
            main_by_id[item_id] = target
            results.append(
                {
                    "worker": index,
                    "id": item_id,
                    "returncode": 0 if target.get("status") == "done" else 1,
                    "status": target["status"],
                    "error": target.get("last_error", ""),
                    "output": target.get("output_file", ""),
                }
            )
        if not recoverable:
            continue
        main_queue["items"] = [
            main_by_id[item["id"]] for item in main_queue["items"]
        ]
        write_json(queue_path, main_queue)
        report = {
            "run_id": run_dir.name,
            "started_items": [result["id"] for result in results],
            "workers": len(results),
            "results": results,
            "finished_at": now(),
            "recovered_after_parent_interruption": True,
        }
        write_json(report_path, report)
        recovered.append(report)
        changed = True
    if changed:
        subprocess.run(
            [
                sys.executable,
                str(ROOT / "tools" / "art_pipeline" / "art_pipeline.py"),
                "validate-queue",
                "--queue",
                str(queue_path),
            ],
            cwd=ROOT,
            check=True,
        )
    return recovered


def main() -> int:
    args = parse_args()
    if args.delay < 0 or args.max_attempts < 1:
        print("ERROR: delay must be non-negative and max-attempts must be positive", file=sys.stderr)
        return 2
    queue_path = args.queue.resolve()
    LOCK.parent.mkdir(parents=True, exist_ok=True)
    lock_handle = LOCK.open("a+", encoding="utf-8")
    try:
        fcntl.flock(lock_handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        print("ERROR: another art-pipeline run is active", file=sys.stderr)
        lock_handle.close()
        return 3

    try:
        recovered = recover_finished_runs(queue_path)
        if recovered:
            print(
                json.dumps(
                    {
                        "status": "recovered",
                        "runs": [report["run_id"] for report in recovered],
                        "items": sum(report["workers"] for report in recovered),
                    },
                    ensure_ascii=False,
                ),
                flush=True,
            )
        subprocess.run(
            [
                sys.executable,
                str(ROOT / "tools" / "art_pipeline" / "art_pipeline.py"),
                "validate-queue",
                "--queue",
                str(queue_path),
            ],
            cwd=ROOT,
            check=True,
        )
        main_queue = read_json(queue_path)
        selected = select_items(main_queue, args.retry_failed, args.max_attempts)
        if not selected:
            print(json.dumps({"status": "idle", "ready": 0}, ensure_ascii=False))
            return 0
        if len(selected) < 3 and not args.allow_partial:
            raise ParallelError(
                f"need three ready items, found {len(selected)}; pass --allow-partial"
            )
        run_id = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
        run_dir = RUN_ROOT / run_id
        run_dir.mkdir(parents=True, exist_ok=False)
        workers: list[dict[str, Any]] = []
        main_by_id = {item["id"]: item for item in main_queue["items"]}
        for index, item in enumerate(selected, start=1):
            worker_queue_path = run_dir / f"worker-{index}.json"
            worker_queue = {
                "schema_version": main_queue["schema_version"],
                "kind": "static",
                "created_at": now(),
                "concurrency": 1,
                "items": dependency_closure(item, main_by_id),
            }
            write_json(worker_queue_path, worker_queue)
            stdout_path = run_dir / f"worker-{index}.stdout.log"
            stderr_path = run_dir / f"worker-{index}.stderr.log"
            stdout_handle = stdout_path.open("w", encoding="utf-8")
            stderr_handle = stderr_path.open("w", encoding="utf-8")
            command = [
                str(RUNNER),
                "--queue",
                str(worker_queue_path),
                "--task-space",
                f"lingnong-art-parallel-{run_id}-{index}",
                "--max-items",
                "1",
                "--delay",
                str(args.delay),
                "--max-attempts",
                str(args.max_attempts),
            ]
            if args.retry_failed:
                command.append("--retry-failed")
            environment = os.environ.copy()
            environment["LINGNONG_PARALLEL_WORKER"] = "1"
            process = subprocess.Popen(
                command,
                cwd=ROOT,
                env=environment,
                stdout=stdout_handle,
                stderr=stderr_handle,
                text=True,
            )
            workers.append(
                {
                    "index": index,
                    "id": item["id"],
                    "queue": str(worker_queue_path),
                    "stdout": str(stdout_path),
                    "stderr": str(stderr_path),
                    "process": process,
                    "stdout_handle": stdout_handle,
                    "stderr_handle": stderr_handle,
                }
            )
            print(f"START worker-{index} {item['id']} pid={process.pid}", flush=True)

        for worker in workers:
            worker["returncode"] = worker["process"].wait()
            worker["stdout_handle"].close()
            worker["stderr_handle"].close()

        latest_main = read_json(queue_path)
        main_by_id = {item["id"]: item for item in latest_main["items"]}
        results: list[dict[str, Any]] = []
        for worker in workers:
            worker_queue = read_json(Path(worker["queue"]))
            result_item = next(
                item for item in worker_queue["items"] if item["id"] == worker["id"]
            )
            main_by_id[result_item["id"]] = result_item
            results.append(
                {
                    "worker": worker["index"],
                    "id": worker["id"],
                    "returncode": worker["returncode"],
                    "status": result_item["status"],
                    "error": result_item.get("last_error", ""),
                    "output": result_item["output_file"],
                }
            )
        latest_main["items"] = [main_by_id[item["id"]] for item in latest_main["items"]]
        write_json(queue_path, latest_main)
        report = {
            "run_id": run_id,
            "started_items": [item["id"] for item in selected],
            "workers": len(workers),
            "results": results,
            "finished_at": now(),
        }
        write_json(run_dir / "report.json", report)
        print(json.dumps({"run_dir": str(run_dir), **report}, ensure_ascii=False))
        return 0 if all(result["status"] == "done" for result in results) else 1
    except (ParallelError, OSError, json.JSONDecodeError, subprocess.CalledProcessError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    finally:
        fcntl.flock(lock_handle.fileno(), fcntl.LOCK_UN)
        lock_handle.close()


if __name__ == "__main__":
    raise SystemExit(main())
