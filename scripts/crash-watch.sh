#!/bin/bash
#
# crash-watch.sh — detect unexpected container restarts
#
# Run via cron every 5 minutes. Compares the container's restart
# count to a stored value. If it increased, fires a Discord alert
# with the last 10 log lines for context.
#
# Usage:
#   ./scripts/crash-watch.sh
#
set -euo pipefail
cd "$(dirname "$0")/.."

STATE_FILE="/tmp/mc-restart-count"

source scripts/notify.sh

RESTART_COUNT=$(docker compose ps minecraft --format '{{.RestartCount}}' 2>/dev/null | head -1 || echo "0")

# Handle empty/null
RESTART_COUNT="${RESTART_COUNT:-0}"

PREV_COUNT=$(cat "$STATE_FILE" 2>/dev/null || echo "0")
PREV_COUNT="${PREV_COUNT:-0}"

if [ "$RESTART_COUNT" -gt "$PREV_COUNT" ] 2>/dev/null; then
  notify_error "Server container restarted unexpectedly (restart count: $RESTART_COUNT)"
  LOGS=$(docker compose logs minecraft --tail 10 2>/dev/null | head -10)
  notify_info "Last 10 log lines:
\`\`\`
$LOGS
\`\`\`"
fi

echo "$RESTART_COUNT" > "$STATE_FILE"
