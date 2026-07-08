#!/bin/bash
#
# planned-restart.sh — broadcast countdown warnings before a scheduled restart
#
# Sends three in-game chat warnings at 5 minutes, 1 minute, and 10 seconds
# before a scheduled server restart. Uses tellraw for colored chat messages.
#
# This is the logging/announcement component only — it does NOT restart
# the server. A separate restart step should follow after the countdown.
#
# Usage:
#   ./scripts/planned-restart.sh              # full countdown (5m, 1m, 10s)
#   ./scripts/planned-restart.sh --test       # same, but labels messages as TEST
#
set -euo pipefail
cd "$(dirname "$0")/.."

source scripts/common.sh

TEST_MODE=false
if [ "${1:-}" = "--test" ]; then
  TEST_MODE=true
fi

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

  if [ "$TEST_MODE" = true ]; then
    extra='{"text":"[TEST] ","color":"yellow","bold":true}'
  fi

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

# echo "planned-restart: starting countdown$( [ "$TEST_MODE" = true ] && echo \" (TEST MODE)\" )"

# ─── 5 minute warning ───────────────────────────────────────────────────
echo "  5:00 warning (restart at $RESTART_TIME)..."
tellraw_send \
  "Mock |$BASE_COLOR" \
  "Server restart|$BASE_COLOR|u" \
  " in |$BASE_COLOR" \
  "5 minutes|$TIME_COLOR" \
  " at |$BASE_COLOR" \
  "$RESTART_TIME|$CLOCK_COLOR" \
  ". (won't actually restart)|$BASE_COLOR"
sleep 240

# ─── 1 minute warning ───────────────────────────────────────────────────
echo "  1:00 warning..."
tellraw_send \
  "Mock |$BASE_COLOR" \
  "Server restart|$BASE_COLOR|u" \
  " in |$BASE_COLOR" \
  "1 minute|$TIME_COLOR" \
  ". (won't actually restart)|$BASE_COLOR"
sleep 50

# ─── 10 second warning ──────────────────────────────────────────────────
echo "  0:10 warning..."
tellraw_send \
  "Mock |$BASE_COLOR" \
  "Server restart|$BASE_COLOR|u" \
  " in |$BASE_COLOR" \
  "10 seconds|$TIME_COLOR" \
  ". (won't actually restart)|$BASE_COLOR"
sleep 5

# ─── Final countdown (5..1) ─────────────────────────────────────────────
for n in 5 4 3 2 1; do
  tellraw_send "$n|$TIME_COLOR"
  sleep 1
done

tellraw_send "Restarting now (not really) |$BASE_COLOR"
echo "If this weren't a test it would restart now."
