#!/bin/bash
#
# restart-warn.sh — broadcast countdown warnings before a scheduled restart
#
# Sends three in-game chat warnings at 5 minutes, 1 minute, and 10 seconds
# before a scheduled server restart. Uses tellraw for colored chat messages.
#
# This is the logging/announcement component only — it does NOT restart
# the server. A separate restart step should follow after the countdown.
#
# Usage:
#   ./scripts/restart-warn.sh              # full countdown (5m, 1m, 10s)
#   ./scripts/restart-warn.sh --test       # same, but labels messages as TEST
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
  echo "restart-warn: server not running, nothing to do"
  exit 0
fi

# Build a tellraw JSON payload for a colored chat message.
# Args: $1 = color (e.g. "gold"), $2 = message text
tellraw_msg() {
  local color="$1" msg="$2"
  local prefix=""
  if [ "$TEST_MODE" = true ]; then
    prefix='{"text":"[TEST] ","color":"yellow","bold":true},'
  fi
  rcon "tellraw @a {\"text\":\"\",\"extra\":[$prefix{\"text\":\"$msg\",\"color\":\"$color\"}]}"
}

# echo "restart-warn: starting countdown$( [ "$TEST_MODE" = true ] && echo " (TEST MODE)" )"

# ─── 5 minute warning ──────────────────────────────────────────────────
echo "  5:00 warning..."
tellraw_msg "gold" "Mock Server restart in 5 minutes. (won't actually restart)"
sleep 240

# ─── 1 minute warning ──────────────────────────────────────────────────
echo "  1:00 warning..."
tellraw_msg "red" "Mock Server restart in 1 minute. (won't actually restart)"
sleep 50

# ─── 10 second warning ─────────────────────────────────────────────────
echo "  0:10 warning..."
tellraw_msg "red" "Mock Server restart in 10 seconds . (won't actually restart)"
sleep 10

echo "If this weren't a test it would restart now."
