#!/bin/bash
#
# disk-check.sh — check disk space and world size, warn on thresholds
#
# Usage:
#   ./scripts/disk-check.sh
#   ./scripts/disk-check.sh --warn-gb 10 --world-gb 20
#
set -euo pipefail
cd "$(dirname "$0")/.."

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

WARN_GB="${1:-10}"
WORLD_WARN_GB="${2:-20}"

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --warn-gb)   WARN_GB="$2"; shift 2 ;;
    --world-gb)  WORLD_WARN_GB="$2"; shift 2 ;;
    *) shift ;;
  esac
done

echo -e "${CYAN}${BOLD}[disk]${RESET} Disk space check $(date '+%Y-%m-%d %H:%M')"

# Host disk usage
FREE_KB=$(df -k . | tail -1 | awk '{print $4}')
FREE_GB=$((FREE_KB / 1024 / 1024))
TOTAL_KB=$(df -k . | tail -1 | awk '{print $2}')
TOTAL_GB=$((TOTAL_KB / 1024 / 1024))
USED_PCT=$(df -h . | tail -1 | awk '{print $5}')

if [ "$FREE_GB" -lt "$WARN_GB" ]; then
  echo -e "  ${RED}${BOLD}Free space: ${FREE_GB} GB / ${TOTAL_GB} GB (${USED_PCT} used) -- WARNING: below ${WARN_GB}GB${RESET}"
else
  echo -e "  ${GREEN}Free space: ${FREE_GB} GB / ${TOTAL_GB} GB (${USED_PCT} used)${RESET}"
fi

# Minecraft data sizes
DATA_DIR="minecraft/data"
if [ -d "$DATA_DIR" ]; then
  DATA_SIZE=$(du -sh "$DATA_DIR" 2>/dev/null | cut -f1)
  echo -e "  ${DIM}minecraft/data/:   ${DATA_SIZE}${RESET}"

  if [ -d "$DATA_DIR/world" ]; then
    WORLD_SIZE_KB=$(du -sk "$DATA_DIR/world" 2>/dev/null | cut -f1)
    WORLD_SIZE_GB=$((WORLD_SIZE_KB / 1024 / 1024))
    WORLD_SIZE_HR=$(du -sh "$DATA_DIR/world" 2>/dev/null | cut -f1)

    if [ "$WORLD_SIZE_GB" -ge "$WORLD_WARN_GB" ]; then
      echo -e "  ${YELLOW}world/:            ${WORLD_SIZE_HR} -- consider Chunky worldborder${RESET}"
    else
      echo -e "  ${DIM}world/:            ${WORLD_SIZE_HR}${RESET}"
    fi
  fi

  if [ -d "$DATA_DIR/mods" ]; then
    MODS_SIZE=$(du -sh "$DATA_DIR/mods" 2>/dev/null | cut -f1)
    echo -e "  ${DIM}mods/:             ${MODS_SIZE}${RESET}"
  fi

  # DH LOD database
  DH_DIR="$DATA_DIR/DistantHorizons"
  if [ -d "$DH_DIR" ]; then
    DH_SIZE=$(du -sh "$DH_DIR" 2>/dev/null | cut -f1)
    echo -e "  ${DIM}DistantHorizons/:  ${DH_SIZE}${RESET}"
  fi
fi

# Backups directory
if [ -d "backups" ]; then
  BK_SIZE=$(du -sh "backups" 2>/dev/null | cut -f1)
  BK_COUNT=$(ls -1 backups/*.tar.gz 2>/dev/null | wc -l)
  echo -e "  ${DIM}backups/:           ${BK_SIZE} (${BK_COUNT} archives)${RESET}"
fi

echo ""
if [ "$FREE_GB" -lt "$WARN_GB" ]; then
  echo -e "${RED}${BOLD}[disk] WARNING: Low disk space (${FREE_GB}GB free)${RESET}"
  exit 1
fi
echo -e "${GREEN}[disk] OK${RESET}"
