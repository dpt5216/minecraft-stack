#!/bin/bash
#
# common.sh - shared functions for minecraft-stack scripts
#
# Source this from other scripts:
#   source scripts/common.sh
#

# get_tps: trigger spark health via RCON, capture the response,
# and/or parse the TPS value from docker logs.
#
# Spark health takes ~10s to sample. The report may come back via
# the RCON response channel OR via the server console log. We check
# both: first the RCON response (captured, not discarded), then
# poll docker logs for up to 15s.
#
# Returns the TPS number on stdout (e.g. "19.8"), or empty string.
# Takes ~15 seconds worst case.
#
get_tps() {
  # Send spark health and capture the full RCON response
  RCON_OUTPUT=$(timeout --kill-after=3 15 \
    docker compose exec -T minecraft rcon-cli "spark health" \
    < /dev/null 2>/dev/null) || true

  # Try parsing TPS from the immediate RCON response
  TPS=$(echo "$RCON_OUTPUT" | grep -oiP 'tps[^:]*:\s*\K[\d.]+' | head -1 || true)
  if [ -n "$TPS" ]; then
    echo "$TPS"
    return 0
  fi

  # If not in RCON response, poll docker logs for up to 15 seconds
  for i in $(seq 1 15); do
    sleep 1
    TPS=$(docker compose logs minecraft --since 25s 2>/dev/null \
          | grep -oiP 'tps[^:]*:\s*\K[\d.]+' \
          | tail -1 || true)
    if [ -n "$TPS" ]; then
      echo "$TPS"
      return 0
    fi
  done

  # No TPS found anywhere
  return 0
}

# get_tps_fast: check recent logs for a TPS value without triggering
# a new spark health command. Useful when another script already
# requested spark health recently.
#
# Returns the TPS number on stdout, or empty string. Fast (~1s).
#
get_tps_fast() {
  docker compose logs minecraft --since 60s 2>/dev/null \
    | grep -oiP 'tps[^:]*:\s*\K[\d.]+' \
    | tail -1 || true
}

# get_mspt: check recent logs for MSPT value.
# Requires spark health to have been recently triggered.
#
get_mspt() {
  docker compose logs minecraft --since 25s 2>/dev/null \
    | grep -oiP 'mspt[^:]*:\s*\K[\d.]+' \
    | tail -1 || true
}
