#!/bin/bash
#
# error-scan.sh — scan recent server logs for errors, notify if found
#
# Checks the last hour of logs for ERROR/Exception/Crash patterns.
# Writes matches to logs/errors.log and fires a Discord alert if new
# errors are detected.
#
# Usage:
#   ./scripts/error-scan.sh
#
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p logs

# Scan last hour of logs for errors
TMP=$(mktemp)
docker compose logs minecraft --since 1h 2>/dev/null \
  | grep -iE 'ERROR|Exception|Crash|Can.t keep up|running behind' \
  | grep -ivE 'chunk load|keepalive|Setting |saved the game|Saving chunks' \
  > "$TMP" || true

ERROR_COUNT=$(wc -l < "$TMP" 2>/dev/null || echo "0")

if [ "$ERROR_COUNT" -gt 0 ]; then
  # Append to error log
  cat "$TMP" >> logs/errors.log
  source scripts/notify.sh
  notify_warn "$ERROR_COUNT new error(s) in server log (last hour)"
fi

rm -f "$TMP"
