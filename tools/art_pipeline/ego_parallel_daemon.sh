#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOG_DIR="$ROOT/.art-pipeline/parallel-daemon"
PID_FILE="$LOG_DIR/pid"
STOP_FILE="$LOG_DIR/stop"
LOG_FILE="$LOG_DIR/daemon.log"
PLIST_FILE="$LOG_DIR/com.lingnong.art-pipeline.plist"
LABEL="com.lingnong.art-pipeline"
DOMAIN="gui/$(id -u)"
BATCH_COOLDOWN_SECONDS=300
mkdir -p "$LOG_DIR"

write_plist() {
  cat > "$PLIST_FILE" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$ROOT/tools/art_pipeline/ego_parallel_daemon.sh</string>
    <string>run</string>
  </array>
  <key>WorkingDirectory</key>
  <string>$ROOT</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>HOME</key>
    <string>$HOME</string>
    <key>PATH</key>
    <string>$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
  <key>ProcessType</key>
  <string>Background</string>
  <key>KeepAlive</key>
  <dict>
    <key>SuccessfulExit</key>
    <false/>
  </dict>
  <key>ThrottleInterval</key>
  <integer>30</integer>
  <key>StandardOutPath</key>
  <string>$LOG_FILE</string>
  <key>StandardErrorPath</key>
  <string>$LOG_FILE</string>
</dict>
</plist>
PLIST
}

case "${1:-start}" in
  start)
    if launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1; then
      state="$(launchctl print "$DOMAIN/$LABEL" | awk -F' = ' '/^[[:space:]]*state = / {print $2; exit}')"
      if [[ "$state" == "running" ]]; then
        printf 'already running %s/%s\n' "$DOMAIN" "$LABEL"
        exit 0
      fi
      rm -f "$STOP_FILE"
      launchctl start "$DOMAIN/$LABEL"
      printf 'restarted service=%s/%s log=%s\n' "$DOMAIN" "$LABEL" "$LOG_FILE"
      exit 0
    fi
    rm -f "$STOP_FILE"
    write_plist
    launchctl bootstrap "$DOMAIN" "$PLIST_FILE"
    deadline=$((SECONDS + 10))
    while (( SECONDS < deadline )); do
      state="$(launchctl print "$DOMAIN/$LABEL" 2>/dev/null | awk -F' = ' '/^[[:space:]]*state = / {print $2; exit}')"
      [[ "$state" == "running" ]] && break
      sleep 1
    done
    if [[ "${state:-}" != "running" ]]; then
      printf 'service failed to reach running state: %s/%s state=%s\n' \
        "$DOMAIN" "$LABEL" "${state:-unknown}" >&2
      exit 1
    fi
    printf 'started service=%s/%s log=%s\n' "$DOMAIN" "$LABEL" "$LOG_FILE"
    ;;
  run)
    printf '%s\n' "$$" > "$PID_FILE"
    trap 'rm -f "$PID_FILE"' EXIT
    while [[ ! -f "$STOP_FILE" ]]; do
      set +e
      "$ROOT/tools/art_pipeline/ego_parallel_generate.py" \
        --workers 3 --delay "$BATCH_COOLDOWN_SECONDS" --retry-failed --allow-partial
      status=$?
      set -e
      if [[ "$status" -ne 0 ]]; then
        printf '%s batch returned %s; cooling down for %s seconds\n' \
          "$(date -u +%FT%TZ)" "$status" "$BATCH_COOLDOWN_SECONDS"
        sleep "$BATCH_COOLDOWN_SECONDS"
      else
        summary="$(python3 "$ROOT/tools/art_pipeline/art_pipeline.py" report --queue "$ROOT/.art-pipeline/queues/static.json")"
        pending="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["pending"])' <<<"$summary")"
        failed="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["failed"])' <<<"$summary")"
        if [[ "$pending" == "0" && "$failed" == "0" ]]; then
          printf '%s queue complete\n' "$(date -u +%FT%TZ)"
          break
        fi
        printf '%s batch complete; cooling down for %s seconds\n' \
          "$(date -u +%FT%TZ)" "$BATCH_COOLDOWN_SECONDS"
        sleep "$BATCH_COOLDOWN_SECONDS"
      fi
    done
    ;;
  status)
    if launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1; then
      state="$(launchctl print "$DOMAIN/$LABEL" | awk -F' = ' '/^[[:space:]]*state = / {print $2; exit}')"
      pid="$(launchctl print "$DOMAIN/$LABEL" | awk -F' = ' '/^[[:space:]]*pid = / {print $2; exit}')"
      printf 'loaded state=%s pid=%s\n' "${state:-unknown}" "${pid:-none}"
    else
      printf 'stopped\n'
    fi
    tail -n 20 "$LOG_FILE" 2>/dev/null || true
    ;;
  stop)
    touch "$STOP_FILE"
    launchctl bootout "$DOMAIN/$LABEL" >/dev/null 2>&1 || true
    rm -f "$PID_FILE"
    printf 'stopped service=%s/%s\n' "$DOMAIN" "$LABEL"
    ;;
  *)
    printf 'usage: %s {start|run|status|stop}\n' "$0" >&2
    exit 2
    ;;
esac
