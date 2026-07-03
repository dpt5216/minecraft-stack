#!/bin/bash
#
# common.sh - shared functions for minecraft-stack scripts
#
# Source this from other scripts:
#   source scripts/common.sh
#

# get_tps: trigger spark health via RCON, wait for the report to
# appear in docker logs, parse the TPS value.
#
# Spark health doesn't return data via RCON (the report is printed
# to the server console asynchronously after ~10s of sampling).
# So we send the command, wait, then grep the docker logs.
#
# Returns the TPS number on stdout (e.g. "19.8"), or empty string.
# Takes ~12 seconds to complete.
#
get_tps() {
  docker compose exec -T minecraft rcon-cli "spark health" < /dev/null 2>/dev/null || true
  sleep 12
  docker compose logs minecraft --since 20s 2>/dev/null \
    | grep -oiP 'TPS[:\s]*\K[\d.]+' \
    | tail -1 || true
}

# get_tps_fast: check recent logs for a TPS value without triggering
# a new spark health command. Useful for continuous monitoring where
# another script or cron already requested spark health.
#
# Returns the TPS number on stdout, or empty string.
# Fast (~1 second).
#
get_tps_fast() {
  docker compose logs minecraft --since 60s 2>/dev/null \
    | grep -oiP 'TPS[:\s]*\K[\d.]+' \
    | tail -1 || true
}

# get_mspt: same approach as get_tps but for MSPT (milliseconds per tick).
# Requires spark health to have been recently triggered.
#
get_mspt() {
  docker compose logs minecraft --since 20s 2>/dev/null \
    | grep -oiP 'MSPT[:\s]*\K[\d.]+' \
    | tail -1 || true
}
