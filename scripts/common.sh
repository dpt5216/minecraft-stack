#!/bin/bash
#
# common.sh - shared functions for minecraft-stack scripts
#
# Source this from other scripts:
#   source scripts/common.sh
#

# get_health: count "Can't keep up" warnings in the last N seconds
# of docker logs. Returns a health indicator on stdout:
#
#   "healthy"  - 0 warnings
#   "minor"    - 1-3 warnings
#   "lagging"  - 4+ warnings
#   "unknown"  - couldn't read logs
#
# Optional $1: time window in seconds (default 3600 = 1 hour)
#
get_health() {
  local WINDOW="${1:-3600}"
  local COUNT

  COUNT=$(docker compose logs minecraft --since "${WINDOW}s" 2>/dev/null \
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

# get_health_count: same as get_health but returns the raw number
# of "Can't keep up" warnings in the time window.
# Optional $1: time window in seconds (default 3600)
#
get_health_count() {
  local WINDOW="${1:-3600}"
  local COUNT

  COUNT=$(docker compose logs minecraft --since "${WINDOW}s" 2>/dev/null \
    | grep -ci "Can't keep up" || true)

  echo "${COUNT:-0}"
}
