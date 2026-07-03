#!/bin/bash
#
# backup.sh — hot world backup without stopping the server
#
# Sends save-all via RCON, tars the world + DH LOD data to a
# timestamped file. Optionally rotates old backups.
#
# Usage:
#   ./scripts/backup.sh                  # backup now
#   ./scripts/backup.sh --keep 5         # keep last 5 backups
#   ./scripts/backup.sh --full           # full data backup (mods, config, everything)
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
KEEP=""
MODE="world"  # "world" or "full"

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --keep)
      KEEP="$2"
      shift 2
      ;;
    --full)
      MODE="full"
      shift
      ;;
    *)
      echo -e "${RED}Unknown argument: $1${RESET}"
      exit 1
      ;;
  esac
done

mkdir -p "$BACKUP_DIR"

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
rcon() {
  docker compose exec -T minecraft rcon-cli "$@" 2>/dev/null
}

if [ "$MODE" = "full" ]; then
  ARCHIVE="$BACKUP_DIR/full-backup-$TIMESTAMP.tar.gz"
  TARGET="minecraft/data/"
  echo -e "${CYAN}${BOLD}[backup]${RESET} Full backup of ${YELLOW}minecraft/data/${RESET}"
  echo -e "${CYAN}[backup]${RESET} Stopping server for consistent snapshot..."
  docker compose stop minecraft
  sleep 3
  tar -czf "$ARCHIVE" "$TARGET"
  echo -e "${CYAN}[backup]${RESET} Restarting server..."
  docker compose up -d
else
  ARCHIVE="$BACKUP_DIR/world-backup-$TIMESTAMP.tar.gz"
  TARGET="minecraft/data/world/"
  echo -e "${CYAN}${BOLD}[backup]${RESET} World backup (hot, no server stop)"

  # Flush chunks to disk via RCON
  echo -e "${CYAN}[backup]${RESET} Flushing world to disk (save-all)..."
  SAVE_OUTPUT=$(rcon "save-all" || echo "")
  echo -e "${DIM}[backup] ${SAVE_OUTPUT}${RESET}"
  sleep 2

  # Check for DH LOD data
  DH_DIR="minecraft/data/DistantHorizons"
  DH_ARGS=""
  if [ -d "$DH_DIR" ]; then
    DH_ARGS="minecraft/data/DistantHorizons"
    echo -e "${CYAN}[backup]${RESET} Including DH LOD data"
  fi

  tar -czf "$ARCHIVE" "$TARGET" $DH_ARGS
fi

SIZE=$(du -sh "$ARCHIVE" | cut -f1)
echo -e "${GREEN}${BOLD}[backup] ✓ Done: ${ARCHIVE} (${SIZE})${RESET}"

# Rotate old backups if --keep was specified
if [ -n "$KEEP" ] && [ "$KEEP" -gt 0 ] 2>/dev/null; then
  echo -e "${CYAN}[backup]${RESET} Rotating (keeping last ${KEEP})..."
  if [ "$MODE" = "full" ]; then
    ls -1t "$BACKUP_DIR"/full-backup-*.tar.gz 2>/dev/null | tail -n +"$((KEEP + 1))" | while read -r old; do
      rm -f "$old"
      echo -e "${DIM}[backup]   removed $(basename "$old")${RESET}"
    done
  else
    ls -1t "$BACKUP_DIR"/world-backup-*.tar.gz 2>/dev/null | tail -n +"$((KEEP + 1))" | while read -r old; do
      rm -f "$old"
      echo -e "${DIM}[backup]   removed $(basename "$old")${RESET}"
    done
  fi
fi
