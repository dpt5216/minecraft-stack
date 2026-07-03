#!/bin/bash
#
# status.sh - one-command server health overview
#
# Usage:
#   ./scripts/status.sh           # full status (multi-line)
#   ./scripts/status.sh --oneline # single line, for logging
#
set -euo pipefail
cd "$(dirname "$0")/.."

ONELINE=false
if [[ "${1:-}" == "--oneline" ]]; then
  ONELINE=true
fi

source scripts/common.sh

rcon() {
  timeout --kill-after=3 10 docker compose exec -T minecraft rcon-cli "$@" < /dev/null 2>/dev/null || echo ""
}

# Check if server is running
RUNNING=$(docker compose ps minecraft --format '{{.Status}}' 2>/dev/null | head -1)

if [ "$ONELINE" = true ]; then
  TS=$(date '+%Y-%m-%d %H:%M:%S')
  if echo "$RUNNING" | grep -qi "Up"; then
    PLAYERS=$(rcon "list" | grep -oP '\d+/' | tr -d '/' || echo "0")
    TPS=$(get_tps || echo "?")
    MEM=$(docker stats --no-stream --format '{{.MemUsage}}' minecraft-server 2>/dev/null | cut -d'/' -f1 | tr -d ' ' || echo "?")
    echo "$TS | TPS:$TPS | Players:$PLAYERS | Mem:$MEM"
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

# 3. TPS (parsed from server logs after triggering spark health)
echo -e "${DIM}  TPS:        sampling (spark health via log)...${RESET}"
TPS=$(get_tps || echo "")
if [ -n "$TPS" ]; then
  if echo "$TPS" | awk '{exit ($1 >= 19.0) ? 0 : 1}' 2>/dev/null; then
    echo -e "  TPS:        ${GREEN}${TPS} / 20.0${RESET}"
  elif echo "$TPS" | awk '{exit ($1 >= 15.0) ? 0 : 1}' 2>/dev/null; then
    echo -e "  TPS:        ${YELLOW}${TPS} / 20.0${RESET}"
  else
    echo -e "  TPS:        ${RED}${TPS} / 20.0${RESET}"
  fi
else
  echo -e "  TPS:        ${DIM}(no spark data in recent logs)${RESET}"
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
