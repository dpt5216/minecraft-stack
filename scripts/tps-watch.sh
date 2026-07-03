#!/bin/bash
#
# tps-watch.sh — continuous colorized TPS monitor
#
# Prints a single-line TPS update every few seconds.
# Green >= 19.0, Yellow 15.0-18.9, Red < 15.0.
# Runs until Ctrl+C.
#
# Usage:
#   ./scripts/tps-watch.sh           # default 5s interval
#   ./scripts/tps-watch.sh 10        # 10s interval
#
set -euo pipefail
cd "$(dirname "$0")/.."

INTERVAL="${1:-5}"

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

rcon() {
  docker compose exec -T minecraft rcon-cli "$@" 2>/dev/null || echo ""
}

echo -e "${CYAN}${BOLD}[tps-watch]${RESET} Monitoring TPS every ${INTERVAL}s (Ctrl+C to stop)"
echo -e "${DIM}[tps-watch] Tip: spark health takes ~10s to sample, so values may lag one cycle${RESET}"
echo ""

while true; do
  TS=$(date +%H:%M:%S)
  OUTPUT=$(rcon "spark health" 2>/dev/null || echo "")

  TPS=$(echo "$OUTPUT" | grep -oiP 'tps[^:]*:\s*\K[\d.]+' | head -1 || echo "")
  MSPT=$(echo "$OUTPUT" | grep -oiP 'mspt[^:]*:\s*\K[\d.]+' | head -1 || echo "")

  if [ -z "$TPS" ]; then
    echo -e "${DIM}[tps-watch] ${TS} | TPS: -- (spark sampling...)${RESET}"
  elif echo "$TPS" | awk '{exit ($1 >= 19.0) ? 0 : 1}'; then
    echo -e "${GREEN}[tps-watch] ${TS} | TPS: ${TPS} | MSPT: ${MSPT}ms${RESET}"
  elif echo "$TPS" | awk '{exit ($1 >= 15.0) ? 0 : 1}'; then
    echo -e "${YELLOW}[tps-watch] ${TS} | TPS: ${TPS} | MSPT: ${MSPT}ms${RESET}"
  else
    echo -e "${RED}${BOLD}[tps-watch] ${TS} | TPS: ${TPS} | MSPT: ${MSPT}ms${RESET}"
  fi

  sleep "$INTERVAL"
done
