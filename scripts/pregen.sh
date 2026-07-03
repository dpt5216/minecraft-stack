#!/bin/bash
#
# pregen.sh — fire-and-forget Chunky + Distant Horizons LOD pregeneration
#
# Run from the host (over SSH). Starts Chunky, waits for it to finish,
# then starts DH LOD pregen and waits for that too. Prints colorized
# progress the whole way.
#
# Usage:
#   ./scripts/pregen.sh [radius] [centerX] [centerZ]
#
# If centerX/centerZ are omitted, the script uses world spawn
# (via `chunky spawn`).
#
# Examples:
#   ./scripts/pregen.sh 2500              # spawn-centered, radius 2500
#   ./scripts/pregen.sh 2500 100000 0     # explicit center
#
set -euo pipefail

RADIUS="${1:-2500}"
CENTER_X="${2:-}"
CENTER_Z="${3:-}"
POLL_INTERVAL=15  # seconds between progress checks

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

rcon() {
  docker compose exec -T minecraft rcon-cli "$@" 2>/dev/null
}

timestamp() {
  date +%H:%M:%S
}

# ── Phase 1: Chunky ───────────────────────────────────────────────
if [ -z "$CENTER_X" ] || [ -z "$CENTER_Z" ]; then
  echo -e "${CYAN}${BOLD}[pregen]${RESET} Starting ${BOLD}Chunky${RESET} (radius=${YELLOW}${RADIUS}${RESET}, center=${YELLOW}spawn${RESET})..."
  rcon "chunky world minecraft:overworld"
  rcon "chunky spawn"
  rcon "chunky radius $RADIUS"
  START_OUTPUT=$(rcon "chunky start")
  echo -e "${DIM}[pregen] $(timestamp) ${START_OUTPUT}${RESET}"

  # Parse center from chunky start output: "centered at X, Z"
  CENTER_X=$(echo "$START_OUTPUT" | grep -oP 'centered at \K[0-9-]+' || echo "0")
  CENTER_Z=$(echo "$START_OUTPUT" | grep -oP 'centered at [0-9-]+, \K[0-9-]+' || echo "0")
  echo -e "${CYAN}[pregen]${RESET} Parsed spawn center: ${YELLOW}${CENTER_X}, ${CENTER_Z}${RESET}"
else
  echo -e "${CYAN}${BOLD}[pregen]${RESET} Starting ${BOLD}Chunky${RESET} (radius=${YELLOW}${RADIUS}${RESET}, center=${YELLOW}${CENTER_X},${CENTER_Z}${RESET})..."
  rcon "chunky world minecraft:overworld"
  rcon "chunky center $CENTER_X $CENTER_Z"
  rcon "chunky radius $RADIUS"
  rcon "chunky start"
fi

echo -e "${CYAN}[pregen]${RESET} Waiting for Chunky to finish (polling every ${POLL_INTERVAL}s)..."
echo ""

while true; do
  sleep "$POLL_INTERVAL"
  OUTPUT=$(rcon "chunky progress" 2>/dev/null || echo "")
  TS=$(timestamp)

  if echo "$OUTPUT" | grep -qi "No tasks running"; then
    echo -e "${GREEN}${BOLD}[pregen] ${TS} ✓ Chunky complete.${RESET}"
    echo ""
    break
  elif echo "$OUTPUT" | grep -qi "Task running"; then
    INFO=$(echo "$OUTPUT" | sed 's/.*Task running.* //' | head -c 200)
    echo -e "${YELLOW}[pregen] ${TS}${RESET} Chunky: ${DIM}${INFO}${RESET}"
  else
    echo -e "${DIM}[pregen] ${TS} Chunky: ${OUTPUT}${RESET}"
  fi
done

# ── Phase 2: Distant Horizons ────────────────────────────────────
echo -e "${CYAN}${BOLD}[pregen]${RESET} Starting ${BOLD}Distant Horizons${RESET} LOD pregen (radius=${YELLOW}${RADIUS}${RESET}, center=${YELLOW}${CENTER_X},${CENTER_Z}${RESET})..."
rcon "dh pregen start minecraft:overworld $CENTER_X $CENTER_Z $RADIUS"

echo -e "${CYAN}[pregen]${RESET} Waiting for DH to finish (polling every ${POLL_INTERVAL}s)..."
echo ""

while true; do
  sleep "$POLL_INTERVAL"
  OUTPUT=$(rcon "dh pregen status" 2>/dev/null || echo "")
  TS=$(timestamp)

  if echo "$OUTPUT" | grep -qi "not running"; then
    echo -e "${GREEN}${BOLD}[pregen] ${TS} ✓ DH pregen complete.${RESET}"
    echo ""
    break
  elif echo -n "$OUTPUT" | grep -qiE '%|ETA'; then
    INFO=$(echo "$OUTPUT" | sed 's/^Generated //' | head -c 200)
    echo -e "${YELLOW}[pregen] ${TS}${RESET} DH: ${DIM}${INFO}${RESET}"
  else
    echo -e "${DIM}[pregen] ${TS} DH: ${OUTPUT}${RESET}"
  fi
done

echo -e "${GREEN}${BOLD}[pregen] All done. LODs are ready for DH clients.${RESET}"
