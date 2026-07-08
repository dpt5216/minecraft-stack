#!/bin/bash
#
# planned-restart.sh — countdown warnings, graceful stop, host reboot
#
# Sends three in-game chat warnings (5m, 1m, 10s) before a scheduled
# restart. After the countdown:
#   1. RCON "save-all"  — flush all chunks to disk
#   2. RCON "stop"      — graceful Minecraft shutdown
#   3. docker wait      — block until the container exits
#   4. shutdown -r now  — reboot the host
#
# If any RCON command fails, the server is left running and a Discord
# alert is sent. No fallback to docker compose stop — a failed graceful
# stop means something is wrong and a human should look at it.
#
# Usage:
#   ./scripts/planned-restart.sh --test       # mock countdown, no stop/reboot
#   ./scripts/planned-restart.sh              # real countdown + stop + reboot
#
set -euo pipefail
cd "$(dirname "$0")/.."

source scripts/common.sh
source scripts/notify.sh


rcon() {
  timeout --kill-after=3 10 docker compose exec -T minecraft rcon-cli "$@" < /dev/null 2>/dev/null || echo ""
}

# Check server is running
RUNNING=$(docker compose ps minecraft --format '{{.Status}}' 2>/dev/null | head -1 || echo "")
if ! echo "$RUNNING" | grep -qi "Up"; then
  echo "planned-restart: server not running, nothing to do"
  exit 0
fi

# ─── Colors ─────────────────────────────────────────────────────────────
BASE_COLOR="aqua"       # message text
TIME_COLOR="gold"       # time-until-restart (5 minutes, 1 minute, etc.)
CLOCK_COLOR="gold"      # actual clock time of restart

# ─── Restart time (5 minutes from now, HH:MM) ───────────────────────────
RESTART_TIME=$(date -d '+5 minutes' '+%H:%M' 2>/dev/null || date -v+5M '+%H:%M' 2>/dev/null || echo "?")

# ─── Tellraw helper ─────────────────────────────────────────────────────
# Sends a tellraw @a with multiple colored segments.
# Each arg is a segment spec: "text|color" or "text|color|u" (underlined).
# [TEST] prefix is auto-prepended in test mode.
tellraw_send() {
  local extra=""
  local seg text color ul json

  for seg in "$@"; do
    text="${seg%%|*}"
    local rest="${seg#*|}"
    color="${rest%%|*}"
    ul="${rest##*|}"
    if [ "$ul" = "$color" ]; then
      ul=""
    fi
    if [ "$ul" = "u" ]; then
      json="{\"text\":\"$text\",\"color\":\"$color\",\"underlined\":true}"
    else
      json="{\"text\":\"$text\",\"color\":\"$color\"}"
    fi
    if [ -z "$extra" ]; then
      extra="$json"
    else
      extra="$extra,$json"
    fi
  done

  rcon "tellraw @a {\"text\":\"\",\"extra\":[$extra]}"
}

echo "planned-restart: starting countdown"

# ─── 5 minute warning ───────────────────────────────────────────────────
echo "  5:00 warning (restart at $RESTART_TIME)..."
tellraw_send \
  "Server restart|$BASE_COLOR|u" \
  " in |$BASE_COLOR" \
  "5 minutes|$TIME_COLOR" \
  " at |$BASE_COLOR" \
  "$RESTART_TIME|$CLOCK_COLOR"
sleep 240

# ─── 1 minute warning ───────────────────────────────────────────────────
echo "  1:00 warning..."
tellraw_send \
  "Server restart|$BASE_COLOR|u" \
  " in |$BASE_COLOR" \
  "1 minute|$TIME_COLOR"
sleep 50

# ─── 10 second warning ──────────────────────────────────────────────────
echo "  0:10 warning..."
tellraw_send \
  "Server restart|$BASE_COLOR|u" \
  " in |$BASE_COLOR" \
  "10 seconds|$TIME_COLOR"
sleep 5

# ─── Final countdown (5..1) ─────────────────────────────────────────────
for n in 5 4 3 2 1; do
  tellraw_send "$n|$TIME_COLOR"
  sleep 1
done

tellraw_send "Restarting now...|$BASE_COLOR"


# 1. save-all — flush chunks to disk
echo "  Saving world (save-all)..."
SAVE_RESULT=$(rcon "save-all")
if [ -z "$SAVE_RESULT" ]; then
  echo "  FAILED: save-all did not respond — aborting restart, server left running"
  notify_error "Planned restart aborted: RCON save-all failed (no response). Server is still running — investigate before retrying."
  exit 1
fi
sleep 2

# 2. stop — graceful Minecraft shutdown
echo "  Sending stop..."
STOP_RESULT=$(rcon "stop")
if [ -z "$STOP_RESULT" ]; then
  echo "  FAILED: stop did not respond — aborting restart, server left running"
  notify_error "Planned restart aborted: RCON stop failed (no response). Server is still running — investigate before retrying."
  exit 1
fi

# 3. docker wait — block until the container exits
echo "  Waiting for container to exit..."
if ! docker wait minecraft-server; then
  echo "  FAILED: docker wait returned error — server may still be stopping"
  notify_error "Planned restart aborted: docker wait failed. Container may be stuck — investigate manually."
  exit 1
fi
echo "  Container exited cleanly"

# 4. Reboot the host
echo "  Rebooting host..."
notify_info "Planned restart: server stopped cleanly, rebooting host now."
shutdown -r now
