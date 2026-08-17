#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STATE_DIR="$ROOT/.art-pipeline/minimax-design-batch"
STOP_FILE="$STATE_DIR/stop"
LOG_FILE="$STATE_DIR/daemon.log"
PLIST_FILE="$STATE_DIR/com.lingnong.minimax-design-batch.plist"
LABEL="com.lingnong.minimax-design-batch"
DOMAIN="gui/$(id -u)"
mkdir -p "$STATE_DIR"

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
    <string>$ROOT/tools/art_pipeline/minimax_design_batch_daemon.sh</string>
    <string>run</string>
  </array>
  <key>WorkingDirectory</key>
  <string>$ROOT</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>HOME</key>
    <string>$HOME</string>
    <key>PATH</key>
    <string>/opt/anaconda3/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
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
    rm -f "$STOP_FILE" "$STATE_DIR/quota-exhausted.json"
    write_plist
    if launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1; then
      launchctl kickstart -k "$DOMAIN/$LABEL"
    else
      launchctl bootstrap "$DOMAIN" "$PLIST_FILE"
    fi
    deadline=$((SECONDS + 15))
    state=""
    while (( SECONDS < deadline )); do
      state="$(launchctl print "$DOMAIN/$LABEL" 2>/dev/null | awk -F' = ' '/^[[:space:]]*state = / {print $2; exit}')"
      [[ "$state" == "running" ]] && break
      sleep 1
    done
    if [[ "$state" != "running" ]]; then
      printf 'service failed to reach running state: %s/%s state=%s\n' \
        "$DOMAIN" "$LABEL" "${state:-unknown}" >&2
      exit 1
    fi
    printf 'started service=%s/%s log=%s\n' "$DOMAIN" "$LABEL" "$LOG_FILE"
    ;;
  run)
    exec python3 "$ROOT/tools/art_pipeline/minimax_design_batch.py" \
      --quota-check-interval 600 \
      --poll-interval 15 \
      --gateway-retry-seconds 60
    ;;
  status)
    if launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1; then
      state="$(launchctl print "$DOMAIN/$LABEL" | awk -F' = ' '/^[[:space:]]*state = / {print $2; exit}')"
      pid="$(launchctl print "$DOMAIN/$LABEL" | awk -F' = ' '/^[[:space:]]*pid = / {print $2; exit}')"
      printf 'loaded state=%s pid=%s\n' "${state:-unknown}" "${pid:-none}"
    else
      printf 'stopped\n'
    fi
    python3 "$ROOT/tools/art_pipeline/minimax_design_batch.py" --status
    tail -n 12 "$LOG_FILE" 2>/dev/null || true
    ;;
  stop)
    touch "$STOP_FILE"
    launchctl bootout "$DOMAIN/$LABEL" >/dev/null 2>&1 || true
    printf 'stopped service=%s/%s\n' "$DOMAIN" "$LABEL"
    ;;
  *)
    printf 'usage: %s {start|run|status|stop}\n' "$0" >&2
    exit 2
    ;;
esac
