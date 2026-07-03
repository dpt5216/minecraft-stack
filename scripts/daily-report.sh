#!/bin/bash
#
# daily-report.sh — morning status report to Discord
#
# Gathers TPS, player count, memory, world size, and disk space
# into a Discord embed. Run via cron once a day.
#
# Usage:
#   ./scripts/daily-report.sh
#
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -f .env ]; then
  set -a
  source .env 2>/dev/null || true
  set +a
fi

WEBHOOK="${DISCORD_WEBHOOK:-}"
[ -z "$WEBHOOK" ] && exit 0

rcon() {
  timeout --kill-after=3 10 docker compose exec -T minecraft rcon-cli "$@" < /dev/null 2>/dev/null || echo ""
}

PLAYERS=$(rcon "list" | grep -oP '\d+/' | tr -d '/' || echo "0")
TPS=$(rcon "spark health" | grep -oiP 'tps[^:]*:\s*\K[\d.]+' | head -1 || echo "?")
MEM=$(docker stats --no-stream --format '{{.MemUsage}}' minecraft-server 2>/dev/null | cut -d'/' -f1 | tr -d ' ' || echo "?")
WORLD_SIZE=$(du -sh minecraft/data/world 2>/dev/null | cut -f1 || echo "?")
FREE=$(df -h . | tail -1 | awk '{print $4 " free (" $5 " used)"}')
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Determine color: green if TPS >= 18, orange if >= 15, red otherwise
COLOR=5763719
if echo "$TPS" | awk '{exit ($1 >= 18.0) ? 0 : 1}' 2>/dev/null; then
  COLOR=5763719
elif echo "$TPS" | awk '{exit ($1 >= 15.0) ? 0 : 1}' 2>/dev/null; then
  COLOR=16753920
else
  COLOR=15548992
fi

curl -s -X POST "$WEBHOOK" \
  -H 'Content-Type: application/json' \
  -d "{
    \"embeds\": [{
      \"title\": \"Daily Server Report\",
      \"color\": $COLOR,
      \"timestamp\": \"$TS\",
      \"fields\": [
        {\"name\": \"Players\", \"value\": \"$PLAYERS\", \"inline\": true},
        {\"name\": \"TPS\", \"value\": \"$TPS / 20.0\", \"inline\": true},
        {\"name\": \"Memory\", \"value\": \"$MEM\", \"inline\": true},
        {\"name\": \"World Size\", \"value\": \"$WORLD_SIZE\", \"inline\": true},
        {\"name\": \"Disk\", \"value\": \"$FREE\", \"inline\": true}
      ]
    }],
    \"username\": \"MC Server\"
  }" > /dev/null 2>&1
