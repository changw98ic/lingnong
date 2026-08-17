#!/usr/bin/env python3
"""Execute one command while holding the shared Lingnong art-pipeline lock."""

from __future__ import annotations

import fcntl
import os
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) < 3:
        print("usage: run_with_lock.py LOCK_FILE COMMAND [ARG ...]", file=sys.stderr)
        return 2

    lock_path = Path(sys.argv[1]).expanduser().resolve()
    command = sys.argv[2:]
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    handle = lock_path.open("a+", encoding="utf-8")
    try:
        fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        handle.seek(0)
        owner = handle.read().strip() or "another process"
        print(f"Another Lingnong art-pipeline run holds the lock ({owner})", file=sys.stderr)
        handle.close()
        return 3

    handle.seek(0)
    handle.truncate()
    handle.write(f"pid={os.getpid()}\n")
    handle.flush()
    os.fsync(handle.fileno())
    os.set_inheritable(handle.fileno(), True)
    environment = os.environ.copy()
    # The child must prove that it inherited this exact open descriptor.  A
    # plain boolean environment flag would let another process skip the lock.
    environment["LINGNONG_PIPELINE_LOCK_FD"] = str(handle.fileno())
    try:
        os.execvpe(command[0], command, environment)
    except OSError as exc:
        print(f"could not start locked command: {exc}", file=sys.stderr)
        handle.close()
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
