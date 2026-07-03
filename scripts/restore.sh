#!/bin/bash
#
# restore.sh — restore a world backup with correct ordering
#
# Stops the server, backs up the current world as a safety net,
# restores the specified backup, and restarts. Correctly handles
# the setup.sh wipe ordering so the world doesn't get nuked.
#
# Usage:
#   ./scripts/restore.sh backups/world-backup-20250703.tar.gz
#   ./scripts/restore.sh backups/full-backup-20250703.tar.gz
#
set -euo pipefail

cd "$(dirname "$0")/.."

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

BACKUP_DIR="${BACKUP_DIR:-./backups}"

if [ $# -lt 1 ]; then
  echo -e "${RED}Usage: $0 <backup-file>${RESET}"
  echo ""
  echo "Available backups:"
  ls -1ht "$BACKUP_DIR"/*.tar.gz 2>/dev/null | head -10 | while read -r f; do
    SIZE=$(du -sh "$f" | cut -f1)
    echo "  $f ($SIZE)"
  done
  exit 1
fi

BACKUP_FILE="$1"

# Resolve relative to BACKUP_DIR if not found as-is
if [ ! -f "$BACKUP_FILE" ]; then
  BACKUP_FILE="$BACKUP_DIR/$(basename "$BACKUP_FILE")"
fi
if [ ! -f "$BACKUP_FILE" ]; then
  echo -e "${RED}Backup file not found: $1${RESET}"
  echo "Checked: $1 and $BACKUP_FILE"
  exit 1
fi

IS_FULL=false
if echo "$(basename "$BACKUP_FILE")" | grep -qi "full"; then
  IS_FULL=true
fi

echo -e "${CYAN}${BOLD}[restore]${RESET} Restoring from: ${YELLOW}${BACKUP_FILE}${RESET}"
if [ "$IS_FULL" = true ]; then
  echo -e "${CYAN}[restore]${RESET} Mode: ${YELLOW}full data restore${RESET}"
else
  echo -e "${CYAN}[restore]${RESET} Mode: ${YELLOW}world-only restore${RESET}"
fi
echo ""

# Safety net: back up the current world before overwriting
CURRENT_WORLD="minecraft/data/world"
if [ -d "$CURRENT_WORLD" ]; then
  SAFETY="$BACKUP_DIR/pre-restore-safety-$(date +%Y%m%d-%H%M%S).tar.gz"
  echo -e "${CYAN}[restore]${RESET} Safety-net backup of current world..."
  mkdir -p "$BACKUP_DIR"
  tar -czf "$SAFETY" "$CURRENT_WORLD" 2>/dev/null || true
  echo -e "${DIM}[restore]   saved to $SAFETY${RESET}"
fi

# Stop the server
echo -e "${CYAN}[restore]${RESET} Stopping server..."
docker compose stop minecraft
sleep 3

if [ "$IS_FULL" = true ]; then
  # Full restore: replace entire data dir, then re-run setup
  echo -e "${CYAN}[restore]${RESET} Removing current data..."
  rm -rf minecraft/data/*
  echo -e "${CYAN}[restore]${RESET} Extracting full backup..."
  tar -xzf "$BACKUP_FILE"
  # run.sh exists in the backup, so setup will skip Phase 1
  # and just re-sync extra mods (Phase 2)
  echo -e "${CYAN}[restore]${RESET} Starting server (setup will skip install, re-sync mods)..."
  docker compose up -d
else
  # World-only restore: remove just the world, extract new one
  echo -e "${CYAN}[restore]${RESET} Removing current world..."
  rm -rf minecraft/data/world
  echo -e "${CYAN}[restore]${RESET} Extracting world backup..."
  tar -xzf "$BACKUP_FILE" -C .
  echo -e "${CYAN}[restore]${RESET} Starting server..."
  docker compose up -d
fi

# Wait for server to be ready
echo -e "${CYAN}[restore]${RESET} Waiting for server to start..."
echo -e "${DIM}[restore]   (watch for "Done!" in the logs)${RESET}"
timeout 120 docker compose logs minecraft -f 2>/dev/null | grep -m1 "Done (" || true

echo ""
echo -e "${GREEN}${BOLD}[restore] ✓ Restore complete.${RESET}"
echo -e "${DIM}[restore] Safety-net backup: $SAFETY${RESET}"
echo -e "${DIM}[restore] If anything is wrong, you can restore from that safety file.${RESET}"
