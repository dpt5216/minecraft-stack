#!/bin/bash
#
# log-watch.sh — filtered live log watcher
#
# Tails minecraft logs, surfaces only warnings/errors/exceptions.
# Skips the noise (chunk load spam, keepalive, etc.)
#
# Usage:
#   ./scripts/log-watch.sh              # live tail
#   ./scripts/log-watch.sh --since 1h   # last hour only, then exit
#
set -euo pipefail
cd "$(dirname "$0")/.."

SINCE=""
if [[ "${1:-}" == "--since" ]]; then
  SINCE="--since ${2:-1h}"
fi

CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

echo -e "${CYAN}${BOLD}[log-watch]${RESET} Filtering for: WARN ERROR Exception Crash 'Can't keep up' 'running behind'"
echo -e "${CYAN}[log-watch]${RESET} Suppressing: chunk load, keepalive, setting, save"
echo ""

# Grep pattern: things we want to see
WATCH='WARN|ERROR|FATAL|Exception|Crash|Can.t keep up|running behind|Skipping|failed|Failed'

# Inverse pattern: things to suppress even if they match above
SUPPRESS='chunk load|keepalive|Setting |saved the game|Saving chunks'

if [ -n "$SINCE" ]; then
  docker compose logs minecraft $SINCE 2>/dev/null \
    | grep -iE "$WATCH" \
    | grep -ivE "$SUPPRESS" \
    | sed 's/^/[log] /'
  echo -e "${CYAN}[log-watch]${RESET} End of history."
else
  docker compose logs minecraft -f 2>/dev/null \
    | grep -iE "$WATCH" \
    | grep -ivE "$SUPPRESS" \
    | sed 's/^/[log] /'
fi
