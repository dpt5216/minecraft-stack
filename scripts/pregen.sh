#!/bin/bash
#
# pregen.sh — fire-and-forget Chunky + Distant Horizons LOD pregeneration
#
# Run from the host (over SSH). Starts Chunky, waits for it to finish,
# then starts DH LOD pregen. No need to attach the server console.
#
# Usage:
#   ./scripts/pregen.sh [radius]   (default: 2500)
#
set -euo pipefail

RADIUS="${1:-2500}"
POLL_INTERVAL=30  # seconds between chunky progress checks

rcon() {
  docker compose exec -T minecraft rcon-cli "$@"
}

echo "[pregen] Starting Chunky (radius=$RADIUS)..."
rcon "chunky world minecraft:overworld"
rcon "chunky center spawn"
rcon "chunky radius $RADIUS"
rcon "chunky start"

echo "[pregen] Waiting for Chunky to finish (checking every ${POLL_INTERVAL}s)..."
while true; do
  sleep "$POLL_INTERVAL"
  OUTPUT=$(rcon "chunky progress" 2>/dev/null || echo "")
  echo "[pregen] $(date +%H:%M:%S) $OUTPUT"

  # Chunky is done when the progress output either:
  #  - contains "100" (100% complete), or
  #  - indicates no tasks are running
  if echo "$OUTPUT" | grep -qiE '100[^0-9]|no.*task|not.*running|currently.*running.*task'; then
    echo "[pregen] Chunky appears done."
    break
  fi
done

echo "[pregen] Starting DH LOD pregen (radius=$RADIUS)..."
rcon "dh pregen start minecraft:overworld 0 0 $RADIUS"

echo ""
echo "[pregen] DH pregen started. To check on it later:"
echo "  docker compose exec minecraft rcon-cli 'dh pregen stop'"
echo "  docker compose logs minecraft -f | grep -i distant"
echo "[pregen] Walk away."
