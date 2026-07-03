#!/bin/bash
#
# pre-flight.sh - 30-second "is the server ready for tonight" check
#
# Runs health check, disk space, backup verification, and boot-error scan.
# Prints a pass/fail summary.
#
# Usage:
#   ./scripts/pre-flight.sh
#
set -euo pipefail
cd "$(dirname "$0")/.."

source scripts/common.sh

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

PASS=0
FAIL=0

check() {
  local label="$1"
  local result="$2"
  if [ "$result" = "pass" ]; then
    echo -e "  ${GREEN}OK${RESET} $label"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}XX${RESET} $label"
    FAIL=$((FAIL + 1))
  fi
}

echo -e "${CYAN}${BOLD}=== Pre-Flight Check: $(date '+%Y-%m-%d %H:%M') ===${RESET}"
echo ""

# 1. Container running?
RUNNING=$(docker compose ps minecraft --format '{{.Status}}' 2>/dev/null | head -1)
if echo "$RUNNING" | grep -qi "Up"; then
  check "Server container running" pass
else
  check "Server container running" fail
  echo -e "  ${RED}Server is down -- fix this first.${RESET}"
  exit 1
fi

# 2. RCON responsive?
RCON_TEST=$(timeout --kill-after=3 10 docker compose exec -T minecraft rcon-cli "list" < /dev/null 2>/dev/null || echo "")
if [ -n "$RCON_TEST" ]; then
  check "RCON responsive" pass
else
  check "RCON responsive" fail
fi

# 3. Health: "Can't keep up" count in last hour
echo -e "${DIM}  Health: checking recent lag warnings...${RESET}"
HEALTH=$(get_health || echo "unknown")
HEALTH_COUNT=$(get_health_count || echo "0")
if [ "$HEALTH" = "healthy" ]; then
  check "Server healthy (0 lag warnings in last hour)" pass
elif [ "$HEALTH" = "minor" ]; then
  check "Server health: minor lag (${HEALTH_COUNT} warnings in last hour)" pass
elif [ "$HEALTH" = "lagging" ]; then
  check "Server health: lagging (${HEALTH_COUNT} warnings in last hour)" fail
else
  check "Server health: couldn't read logs" fail
fi

# 4. Disk space
FREE_KB=$(df -k . | tail -1 | awk '{print $4}')
FREE_GB=$((FREE_KB / 1024 / 1024))
if [ "$FREE_GB" -ge 10 ]; then
  check "Disk space (${FREE_GB} GB free)" pass
else
  check "Disk space (${FREE_GB} GB free)" fail
fi

# 5. Recent backup exists?
LATEST=$(find backups -name '*.tar.gz' 2>/dev/null | sort -r | head -1)
if [ -n "$LATEST" ]; then
  BK_AGE=$(( ($(date +%s) - $(date -r "$LATEST" +%s)) / 3600 ))
  if [ "$BK_AGE" -le 48 ]; then
    check "Recent backup (${BK_AGE}h ago: $(basename "$LATEST"))" pass
  else
    check "Recent backup (${BK_AGE}h ago -- older than 48h)" fail
  fi
else
  check "Recent backup (none found)" fail
fi

# 6. Boot errors in last 50 log lines?
ERRORS=$(docker compose logs minecraft --tail 50 2>/dev/null | grep -ciE 'ERROR|Exception|Crash' || echo "0")
if [ "$ERRORS" -eq 0 ]; then
  check "No boot errors in recent logs" pass
else
  check "Boot errors found ($ERRORS lines)" fail
fi

echo ""
if [ "$FAIL" -eq 0 ]; then
  echo -e "${GREEN}${BOLD}=== All checks passed. Server is ready. ===${RESET}"
  exit 0
else
  echo -e "${RED}${BOLD}=== $FAIL check(s) failed. Review above. ===${RESET}"
  exit 1
fi
