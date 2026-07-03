#!/bin/bash
#
# status.sh - one-command server health overview
#
# Usage:
#   ./scripts/status.sh           # full status (multi-line)
#   ./scripts/status.sh --oneline # single line, for cron logging
#
set -euo pipefail
cd "$(dirname "$0")/.."

source scripts/common.sh

ONELINE=false
if [[ "${1:-}" == "--oneline" ]]; then
  ONELINE=true
fi

rcon() {
  timeout --kill-after=3 10 docker compose exec -T minecraft rcon-cli "$@" < /dev/null 2>/dev/null || echo ""
}

# Check if server is running
RUNNING=$(docker compose ps minecraft --format '{{.Status}}' 2>/dev/null | head -1)

if [ "$ONELINE" = true ]; then
  TS=$(date '+%Y-%m-%d %H:%M:%S')
  if echo "$RUNNING" | grep -qi "Up"; then
    PLAYERS=$(rcon "list" | grep -oP '\d+/' | tr -d '/' || echo "0")
    HEALTH=$(get_health || echo "unknown")
    MEM=$(docker stats --no-stream --format '{{.MemUsage}}' minecraft-server 2>/dev/null | cut -d'/' -f1 | tr -d ' ' || echo "?")
    echo "$TS | Health:$HEALTH | Players:$PLAYERS | Mem:$MEM"
  else
    echo "$TS | OFFLINE"
  fi
  exit 0
fi

# Full multi-line output
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

echo -e "${CYAN}${BOLD}=== Server Status: $(date '+%Y-%m-%d %H:%M:%S') ===${RESET}"
echo ""

# 1. Container status
if echo "$RUNNING" | grep -qi "Up"; then
  echo -e "${GREEN}  Container:  Up${RESET}"
else
  echo -e "${RED}  Container:  DOWN${RESET}"
  exit 1
fi

# 2. Players
PLAYERS=$(rcon "list" 2>/dev/null || echo "No response")
echo -e "  Players:    ${PLAYERS}"

# 3. Health (from "Can't keep up" warning count)
HEALTH=$(get_health || echo "unknown")
HEALTH_COUNT=$(get_health_count || echo "?")
if [ "$HEALTH" = "healthy" ]; then
  echo -e "  Health:     ${GREEN}${HEALTH}${RESET} (0 lag warnings in last hour)"
elif [ "$HEALTH" = "minor" ]; then
  echo -e "  Health:     ${YELLOW}${HEALTH}${RESET} (${HEALTH_COUNT} lag warnings in last hour)"
elif [ "$HEALTH" = "lagging" ]; then
  echo -e "  Health:     ${RED}${BOLD}${HEALTH}${RESET} (${HEALTH_COUNT} lag warnings in last hour)"
else
  echo -e "  Health:     ${DIM}${HEALTH}${RESET} (couldn't read logs)"
fi

# 4. Memory (docker stats)
MEM=$(docker stats --no-stream --format '{{.MemUsage}}' minecraft-server 2>/dev/null || echo "?")
CPU=$(docker stats --no-stream --format '{{.CPUPerc}}' minecraft-server 2>/dev/null || echo "?")
echo -e "  Memory:     ${MEM}"
echo -e "  CPU:        ${CPU}"

# 5. Disk
DATA_SIZE=$(du -sh minecraft/data 2>/dev/null | cut -f1 || echo "?")
WORLD_SIZE=$(du -sh minecraft/data/world 2>/dev/null | cut -f1 || echo "?")
FREE=$(df -h . | tail -1 | awk '{print $4 " free (" $5 " used)"}')
echo -e "  Data dir:   ${DATA_SIZE}"
echo -e "  World:      ${WORLD_SIZE}"
echo -e "  Disk:       ${FREE}"

# 6. Last 5 log lines
echo -e "  ${DIM}--- last 5 log lines ---${RESET}"
docker compose logs minecraft --tail 5 2>/dev/null | sed 's/^/  /' || echo "  (no logs)"
echo ""
