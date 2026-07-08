#!/bin/bash
#
# hourly-scan.sh — hourly server status + classified log error recap
#
# Runs on a cron schedule (e.g. hourly). Always sends a Discord embed
# with server status (players, memory, health) plus a classified summary
# of new log errors since the last run.
#
# Log errors are split into three buckets:
#   LAG   — "Can't keep up" / "running behind" warnings, clustered into
#           incidents by temporal proximity (60s gap). Reports per-incident
#           start time, warning count, and max ticks-behind.
#   ERR   — /ERROR] or /FATAL] tagged lines, or Exception/Crash in message.
#           Grouped by normalized form key with one example line per form.
#   WARN  — /WARN] tagged lines (excluding lag). Same form classification.
#
# Baseline stored in logs/.error-scan-baseline. Handles docker log
# rotation: if total drops below baseline, re-baseline silently.
#
# Usage:
#   ./scripts/hourly-scan.sh
#
set -euo pipefail
cd "$(dirname "$0")/.."

source scripts/common.sh

mkdir -p logs
BASELINE_FILE="logs/.hourly-scan-baseline"

# Grep pattern: things we want to flag
WATCH='ERROR|WARN|Exception|Crash|Can.t keep up|running behind'
# Inverse pattern: noise to suppress even if it matches above
SUPPRESS='chunk load|keepalive|Setting |saved the game|Saving chunks'

# Temp working directory for this run
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

# ─── Server status ──────────────────────────────────────────────────────
rcon() {
  timeout --kill-after=3 10 docker compose exec -T minecraft rcon-cli "$@" < /dev/null 2>/dev/null || echo ""
}

RUNNING=$(docker compose ps minecraft --format '{{.Status}}' 2>/dev/null | head -1 || echo "")
SERVER_UP=false
if echo "$RUNNING" | grep -qi "Up"; then
  SERVER_UP=true
  PLAYERS=$(parse_player_count "$(rcon "list")")
  MEM=$(docker stats --no-stream --format '{{.MemUsage}}' minecraft-server 2>/dev/null | cut -d'/' -f1 | tr -d ' ' || echo "?")
  HEALTH=$(get_health || echo "unknown")
  HEALTH_COUNT=$(get_health_count || echo "0")
else
  PLAYERS="—"
  MEM="—"
  HEALTH="offline"
  HEALTH_COUNT="0"
fi

# ─── Scan logs ──────────────────────────────────────────────────────────
# Full log scan (monotonic count — NOT --tail, which slides and breaks deltas)
docker compose logs minecraft 2>/dev/null \
  | strip_ansi \
  | sed 's/\r//g' \
  | grep -iE "$WATCH" \
  | grep -ivE "$SUPPRESS" \
  > "$WORKDIR/filtered" || true

TOTAL=$(wc -l < "$WORKDIR/filtered" 2>/dev/null || echo "0")
PREV=$(cat "$BASELINE_FILE" 2>/dev/null || echo "0")
TOTAL="${TOTAL:-0}"
PREV="${PREV:-0}"

# ─── Delta ──────────────────────────────────────────────────────────────
NEW_COUNT=0
if [ "$TOTAL" -gt "$PREV" ] 2>/dev/null; then
  NEW_COUNT=$((TOTAL - PREV))
  # Append new lines to error log (paper trail)
  tail -n "$NEW_COUNT" "$WORKDIR/filtered" >> logs/errors.log
  # Save for classification
  tail -n "$NEW_COUNT" "$WORKDIR/filtered" > "$WORKDIR/new"
elif [ "$TOTAL" -lt "$PREV" ] 2>/dev/null; then
  : # log rotated or container recreated — re-baseline silently
fi

# Always update baseline
echo "$TOTAL" > "$BASELINE_FILE"

# Ensure new file exists for greps
touch "$WORKDIR/new"

# ─── Split into buckets ─────────────────────────────────────────────────
grep -iE "Can.t keep up|running behind" "$WORKDIR/new" > "$WORKDIR/lag" 2>/dev/null || true
grep -ivE "Can.t keep up|running behind" "$WORKDIR/new" > "$WORKDIR/nonlag" 2>/dev/null || true
grep -iE "/(ERROR|FATAL)\]|Exception|Crash" "$WORKDIR/nonlag" > "$WORKDIR/err" 2>/dev/null || true
grep -iE "/WARN\]" "$WORKDIR/nonlag" \
  | grep -ivE "/(ERROR|FATAL)\]|Exception|Crash" \
  > "$WORKDIR/warn" 2>/dev/null || true

LAG_COUNT=$(wc -l < "$WORKDIR/lag" 2>/dev/null || echo "0")
ERR_COUNT=$(wc -l < "$WORKDIR/err" 2>/dev/null || echo "0")
WARN_COUNT=$(wc -l < "$WORKDIR/warn" 2>/dev/null || echo "0")
LAG_COUNT="${LAG_COUNT:-0}"
ERR_COUNT="${ERR_COUNT:-0}"
WARN_COUNT="${WARN_COUNT:-0}"

# ─── Classify LAG bucket (temporal clustering) ──────────────────────────
# Group consecutive lag warnings within 60s into incidents. For each
# incident: start time, warning count, max ticks behind.
LAG_FIELD=""
LAG_INCIDENTS=0
LAG_MAX_TICKS=0
if [ "$LAG_COUNT" -gt 0 ]; then
  awk '
    BEGIN { gap = 60; first = 1 }
    {
      # extract [HH:MM:SS] by splitting on brackets
      n = split($0, a, /[][]/)
      if (n < 2) next
      ts = a[2]
      split(ts, t, /:/)
      sec = t[1]*3600 + t[2]*60 + t[3]

      # extract ticks: "or N ticks behind"
      m = split($0, b, / ticks behind/)
      if (m < 2) { ticks = 0 }
      else {
        p = split(b[1], c, / or /)
        ticks = c[p] + 0
      }

      # midnight wrap
      if (sec < prev) sec += 86400

      if (first) {
        cs_ts = ts; cnt = 1; mx = ticks; first = 0; prev = sec; next
      }
      if (sec - prev > gap) {
        printf "%s\t%d\t%d\n", cs_ts, cnt, mx
        cs_ts = ts; cnt = 1; mx = ticks
      } else {
        cnt++
        if (ticks > mx) mx = ticks
      }
      prev = sec
    }
    END { if (!first) printf "%s\t%d\t%d\n", cs_ts, cnt, mx }
  ' "$WORKDIR/lag" > "$WORKDIR/incidents"

  LAG_INCIDENTS=$(wc -l < "$WORKDIR/incidents" 2>/dev/null || echo "0")
  LAG_INCIDENTS="${LAG_INCIDENTS:-0}"

  # Max ticks across all incidents (for color logic and summary)
  LAG_MAX_TICKS=$(awk -F'\t' '{ if ($3 > mx) mx = $3 } END { print mx+0 }' "$WORKDIR/incidents" 2>/dev/null || echo "0")

  # Format top 5 incidents by max ticks descending
  LAG_FIELD=$(sort -t$'\t' -k3 -rn "$WORKDIR/incidents" 2>/dev/null | head -5 | awk -F'\t' '
    { if (NR > 1) printf "\n"; printf "%s  %dw  max %dt (%.1fs)", $1, $2, $3, $3/20.0 }
  ')
  # Append "+N more" if there are more than 5 incidents
  if [ "$LAG_INCIDENTS" -gt 5 ]; then
    LAG_FIELD="${LAG_FIELD}
+ $((LAG_INCIDENTS - 5)) more incidents"
  fi
fi

# ─── Classify ERR and WARN buckets (form classification) ────────────────
# Normalize each line to a stable form key (scrub timestamps, numbers,
# coordinates), count per form, keep one example line. Top 3 by count.
classify_form() {
  awk '
    {
      orig = substr($0, 1, 150)
      line = $0
      # strip docker prefix + [HH:MM:SS]
      sub(/^[^[]*\[[0-9:]+\] /, "", line)
      # strip [thread/LEVEL] (handles nested brackets like [Thread[3]/ERROR])
      sub(/^\[.*\/(ERROR|FATAL|WARN|INFO)\] /, "", line)
      # strip leading [ from logger, convert ]: to :
      sub(/^\[/, "", line)
      sub(/\]: /, ": ", line)
      # scrub volatile bits
      gsub(/[0-9]+/, "N", line)
      gsub(/\{x=N, y=N, z=N\}/, "{x,y,z}", line)
      keys[NR] = line
      origs[NR] = orig
    }
    END {
      for (i = 1; i <= NR; i++) {
        k = keys[i]
        count[k]++
        if (!(k in seen)) { seen[k] = 1; example[k] = origs[i] }
      }
      # collect for sorting
      n = 0
      for (k in count) {
        n++
        scount[n] = count[k]; skey[n] = k; sexample[n] = example[k]
      }
      # sort by count desc (small N — bubble sort)
      for (i = 1; i <= n; i++) for (j = i + 1; j <= n; j++) {
        if (scount[j] > scount[i]) {
          t = scount[i]; scount[i] = scount[j]; scount[j] = t
          t = skey[i]; skey[i] = skey[j]; skey[j] = t
          t = sexample[i]; sexample[i] = sexample[j]; sexample[j] = t
        }
      }
      max = (n < 3 ? n : 3)
      for (i = 1; i <= max; i++) {
        if (i > 1) printf "\n"
        printf "%d x %s\n e.g. %s", scount[i], skey[i], sexample[i]
      }
    }
  '
}

ERR_FIELD=""
if [ "$ERR_COUNT" -gt 0 ]; then
  ERR_FIELD=$(classify_form < "$WORKDIR/err")
fi
WARN_FIELD=""
if [ "$WARN_COUNT" -gt 0 ]; then
  WARN_FIELD=$(classify_form < "$WORKDIR/warn")
fi

# ─── Build Discord embed ────────────────────────────────────────────────
# Load webhook
if [ -f .env ]; then
  set -a
  source .env 2>/dev/null || true
  set +a
fi
WEBHOOK="$(sanitize_webhook "${DISCORD_WEBHOOK:-}")"

# Determine color: red if offline or errors, orange if severe lag, green if healthy, grey if unknown
COLOR=7506394  # grey/blue (default)
if [ "$SERVER_UP" = false ]; then
  COLOR=15548992  # red
elif [ "$ERR_COUNT" -gt 0 ]; then
  COLOR=15548992  # red
elif [ "$LAG_MAX_TICKS" -ge 100 ]; then
  COLOR=16753920  # orange
elif [ "$HEALTH" = "healthy" ] && [ "$NEW_COUNT" -eq 0 ]; then
  COLOR=5763719  # green
fi

# Title — always "Hourly Status"
TITLE="Hourly Status"

# Build fields array
FIELDS=""
add_field() {
  local name="$1" value="$2" inline="${3:-false}"
  local en ev
  en=$(printf '%s' "$name" | json_escape)
  ev=$(printf '%s' "$value" | json_escape)
  local field="{\"name\":\"$en\",\"value\":\"$ev\",\"inline\":$inline}"
  if [ -z "$FIELDS" ]; then
    FIELDS="$field"
  else
    FIELDS="$FIELDS,$field"
  fi
}

# Field 1: Server (always present, inline)
if [ "$SERVER_UP" = true ]; then
  SERVER_VAL="${PLAYERS} players | ${MEM} | ${HEALTH}"
  if [ "$HEALTH_COUNT" -gt 0 ]; then
    SERVER_VAL="${SERVER_VAL} (${HEALTH_COUNT}w)"
  fi
else
  SERVER_VAL="OFFLINE"
fi
add_field "Server" "$SERVER_VAL" true

# Field 2: Log activity (always present, inline)
if [ "$NEW_COUNT" -eq 0 ]; then
  LOG_VAL="0 new lines"
else
  LOG_VAL="${NEW_COUNT} new"
  if [ "$LAG_COUNT" -gt 0 ]; then
    LOG_VAL="${LOG_VAL} | lag ${LAG_COUNT}w/${LAG_INCIDENTS}i"
  fi
  if [ "$ERR_COUNT" -gt 0 ]; then
    LOG_VAL="${LOG_VAL} | ${ERR_COUNT} err"
  fi
  if [ "$WARN_COUNT" -gt 0 ]; then
    LOG_VAL="${LOG_VAL} | ${WARN_COUNT} warn"
  fi
fi
add_field "Log Activity" "$LOG_VAL" true

# Field 3: placeholder for row alignment (inline, so Server+LogActivity line up)
# Skip — two inline fields is fine, Discord handles it

# Detailed fields (non-inline) — only if they have content
if [ -n "$LAG_FIELD" ]; then
  add_field "Lag (${LAG_COUNT}w, ${LAG_INCIDENTS} incidents)" "$LAG_FIELD" false
fi
if [ -n "$ERR_FIELD" ]; then
  add_field "Errors ($ERR_COUNT)" "$ERR_FIELD" false
fi
if [ -n "$WARN_FIELD" ]; then
  add_field "Warnings ($WARN_COUNT)" "$WARN_FIELD" false
fi

# Summary line for stdout
if [ "$SERVER_UP" = true ]; then
  SUMMARY="hourly-status: ${PLAYERS}p ${MEM} ${HEALTH} | log: ${NEW_COUNT} new (lag=${LAG_COUNT}w/${LAG_INCIDENTS}i err=$ERR_COUNT warn=$WARN_COUNT)"
else
  SUMMARY="hourly-status: OFFLINE | log: ${NEW_COUNT} new (lag=${LAG_COUNT}w/${LAG_INCIDENTS}i err=$ERR_COUNT warn=$WARN_COUNT)"
fi

# No webhook — print summary and exit
if [ -z "$WEBHOOK" ]; then
  echo "$SUMMARY — no webhook configured"
  exit 0
fi

# Assemble JSON payload
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
PAYLOAD="{\"embeds\":[{\"title\":\"$TITLE\",\"color\":$COLOR,\"timestamp\":\"$TS\",\"fields\":[$FIELDS]}],\"username\":\"MC Server\"}"

# POST to Discord
HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$WEBHOOK" \
  -H 'Content-Type: application/json' \
  -d "$PAYLOAD")
case "$HTTP_CODE" in
  20[04]) ;;
  *) echo "hourly-status: webhook POST failed (HTTP $HTTP_CODE)" >&2 ;;
esac

echo "$SUMMARY"
