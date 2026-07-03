#!/bin/bash
#
# health-watch.sh - continuous server health monitor
#
# Counts "Can't keep up" warnings in recent docker logs every cycle.
# Green = 0 warnings, Yellow = 1-3, Red = 4+. Runs until Ctrl+C.
#
# Usage:
#   ./scripts/health-watch.sh           # default 15s cycle, 5min window
#   ./scripts/health-watch.sh 30         # 30s between checks
#   ./scripts/health-watch.sh 15 600     # 15s cycle, 10min window
#
set -euo pipefail
cd "$(dirname "$0")/.."

source scripts/common.sh

INTERVAL="${1:-15}"
WINDOW="${2:-300}"

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

echo -e "${CYAN}${BOLD}[health-watch]${RESET} Monitoring server health (cycle: ${INTERVAL}s, window: ${WINDOW}s)"
echo -e "${DIM}[health-watch] Counts 'Can't keep up' warnings in recent logs${RESET}"
echo ""

while true; do
  TS=$(date +%H:%M:%S)
  COUNT=$(get_health_count "$WINDOW" || echo "0")

  if [ "$COUNT" -eq 0 ]; then
    echo -e "${GREEN}[health-watch] ${TS} | lag warnings (last ${WINDOW}s): ${COUNT} -- healthy${RESET}"
  elif [ "$COUNT" -le 3 ]; then
    echo -e "${YELLOW}[health-watch] ${TS} | lag warnings (last ${WINDOW}s): ${COUNT} -- minor lag${RESET}"
  else
    echo -e "${RED}${BOLD}[health-watch] ${TS} | lag warnings (last ${WINDOW}s): ${COUNT} -- lagging${RESET}"
  fi

  sleep "$INTERVAL"
done
