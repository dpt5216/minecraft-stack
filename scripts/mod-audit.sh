#!/bin/bash
#
# mod-audit.sh — list installed mods, flag duplicates, show tracked vs untracked
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

# Get tracked mod filenames from all URL lists
extract_filenames() {
  local file="$1"
  grep -v '^#' "$file" 2>/dev/null | grep -v '^$' | while read -r url; do
    filename=$(basename "$url")
    filename=$(printf '%b' "${filename//%/\\x}")
    echo "$filename"
  done
}

DEANPAC_TRACKED=$(extract_filenames minecraft/deanpac-mods.txt 2>/dev/null || echo "")
EXTRA_TRACKED=$(extract_filenames minecraft/extra-mods.txt 2>/dev/null || echo "")
ALL_TRACKED=$(printf '%s\n' "$DEANPAC_TRACKED" "$EXTRA_TRACKED")

INSTALLED_COUNT=$(echo "$INSTALLED" | grep -c '\.jar' || echo 0)
DEANPAC_COUNT=$(echo "$DEANPAC_TRACKED" | grep -c '\.jar' || echo 0)
EXTRA_COUNT=$(echo "$EXTRA_TRACKED" | grep -c '\.jar' || echo 0)

echo -e "  Installed jars:       ${BOLD}${INSTALLED_COUNT}${RESET}"
echo -e "  Tracked in DeanPAC:   ${BOLD}${DEANPAC_COUNT}${RESET}"
echo -e "  Tracked in extra:     ${BOLD}${EXTRA_COUNT}${RESET}"
echo ""

# Section 1: DeanPAC mods
echo -e "${CYAN}${BOLD}--- DeanPAC Mods (from deanpac-mods.txt) ---${RESET}"
echo "$INSTALLED" | grep '\.jar' | while read -r jar; do
  if echo "$DEANPAC_TRACKED" | grep -qiF "$jar"; then
    echo -e "  ${GREEN}✓${RESET} $jar"
  fi
done
echo ""

# Section 2: Extra mods
echo -e "${CYAN}${BOLD}--- Extra Server-Side Mods (from extra-mods.txt) ---${RESET}"
echo "$INSTALLED" | grep '\.jar' | while read -r jar; do
  if echo "$EXTRA_TRACKED" | grep -qiF "$jar"; then
    echo -e "  ${GREEN}✓${RESET} $jar"
  fi
done
echo ""

# Section 3: Tracked but not installed (should have been downloaded)
echo -e "${CYAN}${BOLD}--- Tracked but Missing ---${RESET}"
MISSING=0
echo "$ALL_TRACKED" | while read -r jar; do
  if [ -n "$jar" ] && ! echo "$INSTALLED" | grep -qiF "$jar"; then
    echo -e "  ${RED}✗ $jar${RESET}"
    MISSING=1
  fi
done
if [ "$MISSING" -eq 0 ] 2>/dev/null; then
  echo -e "  ${GREEN}All tracked mods installed.${RESET}"
fi
echo ""

# Section 4: Untracked (installed but not in any URL list)
echo -e "${CYAN}${BOLD}--- Untracked (not in any URL list) ---${RESET}"
UNTRACKED_COUNT=0
echo "$INSTALLED" | grep '\.jar' | while read -r jar; do
  if ! echo "$ALL_TRACKED" | grep -qiF "$jar"; then
    echo -e "  ${YELLOW}?${RESET} $jar"
    UNTRACKED_COUNT=$((UNTRACKED_COUNT + 1))
  fi
done
echo -e "  ${DIM}($UNTRACKED_COUNT untracked)${RESET}"
echo ""

# Section 5: Duplicate detection (same base name, different version)
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
