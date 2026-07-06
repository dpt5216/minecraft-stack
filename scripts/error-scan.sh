#!/bin/bash
#
# error-scan.sh — scan server logs for errors, notify on NEW ones only
#
# Counts ERROR/Exception/Crash lines across the full available container log
# and reports only the delta since the last run (stored in
# logs/.error-scan-baseline). Appends just the new lines to logs/errors.log
# and fires a Discord alert with the new count.
#
# Handles docker log rotation: if the total drops below the baseline (log
# rolled over), the baseline is reset silently and nothing is reported that
# cycle — we can't distinguish new from old after a rotation.
#
# Usage:
#   ./scripts/error-scan.sh
#
set -euo pipefail
cd "$(dirname "$0")/.."

source scripts/common.sh

mkdir -p logs
BASELINE_FILE="logs/.error-scan-baseline"

# Grep pattern: things we want to flag
WATCH='ERROR|Exception|Crash|Can.t keep up|running behind'
# Inverse pattern: noise to suppress even if it matches above
SUPPRESS='chunk load|keepalive|Setting |saved the game|Saving chunks'

# Full log scan (monotonic count — NOT --tail, which slides and breaks deltas)
TMP=$(mktemp)
docker compose logs minecraft 2>/dev/null \
  | grep -iE "$WATCH" \
  | grep -ivE "$SUPPRESS" \
  > "$TMP" || true

TOTAL=$(wc -l < "$TMP" 2>/dev/null || echo "0")
PREV=$(cat "$BASELINE_FILE" 2>/dev/null || echo "0")
TOTAL="${TOTAL:-0}"
PREV="${PREV:-0}"

if [ "$TOTAL" -gt "$PREV" ] 2>/dev/null; then
  NEW_COUNT=$((TOTAL - PREV))
  # Append only the new lines (the last NEW_COUNT matches) to the error log
  tail -n "$NEW_COUNT" "$TMP" >> logs/errors.log
  source scripts/notify.sh
  notify_warn "$NEW_COUNT new error(s) in server log (total now $TOTAL)"
elif [ "$TOTAL" -lt "$PREV" ] 2>/dev/null; then
  # Log rotated or container recreated — re-baseline silently.
  : # no alert; we can't tell new from old after rotation
fi

# Always update baseline to current total
echo "$TOTAL" > "$BASELINE_FILE"
rm -f "$TMP"
