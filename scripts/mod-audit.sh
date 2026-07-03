#!/bin/bash
#
# mod-audit.sh — list installed mods, flag duplicates, show tracked vs pack
#
# Usage:
#   ./scripts/mod-audit.sh
#
set -euo pipefail
cd "$(dirname "$0")/.."

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

echo -e "${CYAN}${BOLD}=== Mod Audit: $(date '+%Y-%m-%d %H:%M') ===${RESET}"
echo ""

# Get installed jars
INSTALLED=$(docker compose exec -T minecraft ls /data/mods/ 2>/dev/null || echo "")
if [ -z "$INSTALLED" ]; then
  echo -e "${RED}Cannot list /data/mods/ -- is the server running?${RESET}"
  exit 1
fi

# Get tracked mod filenames from extra-mods.txt
TRACKED=$(grep -v '^#' minecraft/extra-mods.txt 2>/dev/null | grep -v '^$' | while read -r url; do
  filename=$(basename "$url")
  filename=$(printf '%b' "${filename//%/\\x}")
  echo "$filename"
done)

INSTALLED_COUNT=$(echo "$INSTALLED" | grep -c '\.jar' || echo 0)
TRACKED_COUNT=$(echo "$TRACKED" | grep -c '\.jar' || echo 0)

echo -e "  Installed jars: ${BOLD}${INSTALLED_COUNT}${RESET}"
echo -e "  Tracked in extra-mods.txt: ${BOLD}${TRACKED_COUNT}${RESET}"
echo ""

# Section 1: Tracked extra mods
echo -e "${CYAN}${BOLD}--- Tracked Extra Mods (from extra-mods.txt) ---${RESET}"
echo "$INSTALLED" | grep '\.jar' | while read -r jar; do
  if echo "$TRACKED" | grep -qiF "$jar"; then
    echo -e "  ${GREEN}✓${RESET} $jar"
  fi
done
echo ""

# Section 2: Pack mods (installed but not in extra-mods.txt)
echo -e "${CYAN}${BOLD}--- Pack Mods (from modpack, not tracked) ---${RESET}"
PACK_COUNT=0
echo "$INSTALLED" | grep '\.jar' | while read -r jar; do
  if ! echo "$TRACKED" | grep -qiF "$jar"; then
    echo -e "  ${DIM}$jar${RESET}"
    PACK_COUNT=$((PACK_COUNT + 1))
  fi
done
echo -e "  ${DIM}($PACK_COUNT pack mods)${RESET}"
echo ""

# Section 3: Tracked but not installed (should have been downloaded)
echo -e "${CYAN}${BOLD}--- Tracked but Missing ---${RESET}"
MISSING=0
echo "$TRACKED" | while read -r jar; do
  if [ -n "$jar" ] && ! echo "$INSTALLED" | grep -qiF "$jar"; then
    echo -e "  ${RED}✗ $jar${RESET}"
    MISSING=1
  fi
done
if [ "$MISSING" -eq 0 ] 2>/dev/null; then
  echo -e "  ${GREEN}All tracked mods installed.${RESET}"
fi
echo ""

# Section 4: Duplicate detection (same base name, different version)
echo -e "${CYAN}${BOLD}--- Potential Duplicates ---${RESET}"
# Extract base name (strip version numbers and extensions)
echo "$INSTALLED" | grep '\.jar' | sed 's/-[0-9].*\.jar//' | sed 's/_[0-9].*\.jar//' | sort | uniq -d | while read -r base; do
  if [ -n "$base" ]; then
    echo -e "  ${YELLOW}Duplicate base: ${base}${RESET}"
    echo "$INSTALLED" | grep "$base" | grep '\.jar' | while read -r dup; do
      echo -e "    ${DIM}$dup${RESET}"
    done
  fi
done
echo ""
echo -e "${DIM}Note: duplicate detection is heuristic (strips version suffixes from filenames).${RESET}"
echo -e "${DIM}      False positives are possible. Verify before removing jars.${RESET}"
