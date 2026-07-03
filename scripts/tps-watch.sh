#!/bin/bash
#
# tps-watch.sh - continuous colorized TPS monitor
#
# Triggers spark health via RCON, waits for the report to appear
# in docker logs, prints the TPS, then repeats. Green >= 19.0,
# Yellow 15.0-18.9, Red < 15.0. Runs until Ctrl+C.
#
# Usage:
#   ./scripts/tps-watch.sh           # default ~15s cycle
#   ./scripts/tps-watch.sh 30        # 30s between cycles
#
set -euo pipefail
cd "$(dirname "$0")/.."

source scripts/common.sh

INTERVAL="${1:-15}"

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

echo -e "${CYAN}${BOLD}[tps-watch]${RESET} Monitoring TPS (cycle: ~${INTERVAL}s, Ctrl+C to stop)"
echo -e "${DIM}[tps-watch] Triggers spark health via RCON, parses result from logs${RESET}"
echo ""

while true; do
  TS=$(date +%H:%M:%S)

  # Trigger spark health
  timeout --kill-after=3 5 docker compose exec -T minecraft rcon-cli "spark health" < /dev/null 2>/dev/null || true

  # Poll logs for the TPS report (spark takes ~10s to sample)
  TPS=""
  for i in $(seq 1 15); do
    sleep 1
    TPS=$(docker compose logs minecraft --since 20s 2>/dev/null \
          | grep -oiP 'TPS[:\s]*\K[\d.]+' \
          | tail -1 || true)
    if [ -n "$TPS" ]; then
      break
    fi
  done

  MSPT=$(docker compose logs minecraft --since 20s 2>/dev/null \
         | grep -oiP 'MSPT[:\s]*\K[\d.]+' \
         | tail -1 || true)

  if [ -z "$TPS" ]; then
    echo -e "${DIM}[tps-watch] ${TS} | TPS: -- (no spark data in logs)${RESET}"
  elif echo "$TPS" | awk '{exit ($1 >= 19.0) ? 0 : 1}' 2>/dev/null; then
    echo -e "${GREEN}[tps-watch] ${TS} | TPS: ${TPS} | MSPT: ${MSPT}ms${RESET}"
  elif echo "$TPS" | awk '{exit ($1 >= 15.0) ? 0 : 1}' 2>/dev/null; then
    echo -e "${YELLOW}[tps-watch] ${TS} | TPS: ${TPS} | MSPT: ${MSPT}ms${RESET}"
  else
    echo -e "${RED}${BOLD}[tps-watch] ${TS} | TPS: ${TPS} | MSPT: ${MSPT}ms${RESET}"
  fi

  sleep "$INTERVAL"
done
