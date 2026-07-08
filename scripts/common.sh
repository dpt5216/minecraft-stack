#!/bin/bash
#
# common.sh - shared functions for minecraft-stack scripts
#
# Source this from other scripts:
#   source scripts/common.sh
#

# get_health: count "Can't keep up" warnings in recent docker logs.
# Returns a health indicator on stdout:
#
#   "healthy"  - 0 warnings
#   "minor"    - 1-3 warnings
#   "lagging"  - 4+ warnings
#   "unknown"  - couldn't read logs
#
get_health() {
  local COUNT

  COUNT=$(docker compose logs minecraft --tail 2000 2>/dev/null \
    | grep -ci "Can't keep up" || true)

  if [ -z "$COUNT" ]; then
    echo "unknown"
  elif [ "$COUNT" -eq 0 ]; then
    echo "healthy"
  elif [ "$COUNT" -le 3 ]; then
    echo "minor"
  else
    echo "lagging"
  fi
}

# get_health_count: same as get_health but returns the raw warning count.
get_health_count() {
  local COUNT

  COUNT=$(docker compose logs minecraft --tail 2000 2>/dev/null \
    | grep -ci "Can't keep up" || true)

  echo "${COUNT:-0}"
}

# sanitize_webhook: clean a Discord webhook URL read from .env.
# Strips surrounding quotes, carriage returns (CRLF), leading/trailing
# whitespace, and trailing slashes — the common copy-paste / Windows-edit
# corruptions that make Discord return 404 (trailing slash) or curl fail
# (trailing CR/space). Echoes the cleaned URL on stdout (may be empty).
sanitize_webhook() {
  local url="${1:-}"
  # strip a single pair of surrounding quotes (if present)
  case "$url" in
    \"*\") url="${url#\"}"; url="${url%\"}" ;;
    \'*\') url="${url#\'}"; url="${url%\'}" ;;
  esac
  # drop all CR chars (CRLF line endings in .env)
  url="${url//$'\r'/}"
  # trim leading/trailing whitespace (POSIX, no subshell)
  url="${url#"${url%%[![:space:]]*}"}"
  url="${url%"${url##*[![:space:]]}"}"
  # strip trailing slashes
  while [ -n "$url" ] && [ "${url: -1}" = "/" ]; do
    url="${url%/}"
  done
  printf '%s' "$url"
}

# strip_ansi: remove ANSI escape codes (color, cursor) from stdin.
# Docker compose logs can embed color codes depending on TTY detection;
# these break grep patterns and bracket-splitting in awk.
# Usage: docker compose logs ... | strip_ansi
strip_ansi() {
  sed 's/\x1b\[[0-9;]*[mK]//g'
}

# json_escape: escape stdin for safe embedding in a JSON string value.
# Escapes backslashes and double quotes; converts newlines to \n and
# tabs to \t. Outputs a single line (no trailing newline).
# Usage: echo "$val" | json_escape
json_escape() {
  sed 's/\\/\\\\/g; s/"/\\"/g' | awk '
    { gsub(/\t/, "\\t"); printf "%s%s", (NR > 1 ? "\\n" : ""), $0 }
  '
}

# parse_player_count: extract the online player count from `list` RCON output.
# Minecraft returns: "There are N of a max of M players online: <names>"
# Echoes N on stdout; "0" if empty/unparseable. Reads the raw `list` string
# on stdin or as $1.
parse_player_count() {
  local out="${1:-}"
  [ -z "$out" ] && out=$(cat 2>/dev/null)
  local n
  # primary: the number right after "are "
  n=$(printf '%s' "$out" | grep -oP 'are \K\d+' | head -1)
  # fallback: first integer anywhere in the string
  [ -z "$n" ] && n=$(printf '%s' "$out" | grep -oE '[0-9]+' | head -1)
  printf '%s' "${n:-0}"
}
