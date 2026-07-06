#!/bin/bash
#
# daily-report.sh — morning status report to Discord
#
# Gathers Health, player count, memory, world size, and disk space
# into a Discord embed. Run via cron once a day.
#
# Usage:
#   ./scripts/daily-report.sh
#
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/common.sh

if [ -f .env ]; then
  set -a
  source .env 2>/dev/null || true
  set +a
fi

WEBHOOK="$(sanitize_webhook "${DISCORD_WEBHOOK:-}")"
[ -z "$WEBHOOK" ] && exit 0

rcon() {
  timeout --kill-after=3 10 docker compose exec -T minecraft rcon-cli "$@" < /dev/null 2>/dev/null || echo ""
}

PLAYERS=$(parse_player_count "$(rcon "list")")
HEALTH=$(get_health || echo "unknown")
HEALTH_COUNT=$(get_health_count || echo "0")

MEM=$(docker stats --no-stream --format '{{.MemUsage}}' minecraft-server 2>/dev/null | cut -d'/' -f1 | tr -d ' ' || echo "?")
WORLD_SIZE=$(du -sh minecraft/data/world 2>/dev/null | cut -f1 || echo "?")
FREE=$(df -h . | tail -1 | awk '{print $4 " free (" $5 " used)"}')
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Determine color from health indicator string
case "$HEALTH" in
  healthy)  COLOR=5763719  ;;  # green
  minor)    COLOR=16753920 ;;  # orange
  lagging)  COLOR=15548992 ;;  # red
  *)        COLOR=7506394  ;;  # grey/blue
esac

HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$WEBHOOK" \
  -H 'Content-Type: application/json' \
  -d "{
    \"embeds\": [{
      \"title\": \"Daily Server Report\",
      \"color\": $COLOR,
      \"timestamp\": \"$TS\",
      \"fields\": [
        {\"name\": \"Players\", \"value\": \"$PLAYERS\", \"inline\": true},
        {\"name\": \"Health\", \"value\": \"$HEALTH ($HEALTH_COUNT warnings)\", \"inline\": true},
        {\"name\": \"Memory\", \"value\": \"$MEM\", \"inline\": true},
        {\"name\": \"World Size\", \"value\": \"$WORLD_SIZE\", \"inline\": true},
        {\"name\": \"Disk\", \"value\": \"$FREE\", \"inline\": true}
      ]
    }],
    \"username\": \"MC Server\"
  }")
case "$HTTP_CODE" in
  20[04]) ;;  # success (Discord returns 204 No Content)
  *) echo "daily-report: webhook POST failed (HTTP $HTTP_CODE) for $WEBHOOK" >&2 ;;
esac
