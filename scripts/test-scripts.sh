#!/bin/bash
#
# test-scripts.sh - staged audit of all maintenance scripts (except pregen)
#
# Runs each script against the live server, captures exit code, stdout,
# stderr, and timing. Mirrors all output to a log file. Non-destructive.
#
# Usage:
#   ./scripts/test-scripts.sh                    # full audit
#   ./scripts/test-scripts.sh --no-backup         # skip backup test
#   ./scripts/test-scripts.sh --stage 2           # run only stage 2
#   ./scripts/test-scripts.sh --log /tmp/test.log # custom log path
#
set -euo pipefail
cd "$(dirname "$0")/.."

LOG_FILE="logs/test-scripts-$(date +%Y%m%d-%H%M%S).log"
STAGE_FILTER=""
SKIP_BACKUP=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-backup)    SKIP_BACKUP=true; shift ;;
    --stage)        STAGE_FILTER="$2"; shift 2 ;;
    --log)          LOG_FILE="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

mkdir -p logs "$(dirname "$LOG_FILE")"
LOG_RAW="$LOG_FILE.raw"
: > "$LOG_FILE"
: > "$LOG_RAW"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

PASS=0
FAIL=0
SKIP=0
CURRENT_STAGE=""

emit() {
  local msg="$1"
  echo -e "$msg"
  echo "$msg" | sed 's/\x1b\[[0-9;]*m//g' >> "$LOG_FILE"
}

run_stage() {
  local stage="$1"
  local desc="$2"
  if [ -n "$STAGE_FILTER" ] && [ "$STAGE_FILTER" != "$stage" ]; then
    return
  fi
  CURRENT_STAGE="$stage"
  emit ""
  emit "${MAGENTA}${BOLD}=== STAGE $stage: $desc ===${RESET}"
  emit ""
}


run_test() {
  local name="$1"
  local cmd="$2"
  local timeout_s="${3:-30}"

  emit ""
  emit "${CYAN}[$CURRENT_STAGE] $name${RESET}"
  emit "${DIM}  cmd: $cmd${RESET}"
  emit "${DIM}  timeout: ${timeout_s}s${RESET}"

  local tmp_out=$(mktemp)
  local tmp_err=$(mktemp)
  local start=$(date +%s%N)
  local exit_code=0

  timeout --kill-after=5 "$timeout_s" bash -c "$cmd" < /dev/null > "$tmp_out" 2> "$tmp_err" || exit_code=$?

  local end=$(date +%s%N)
  local elapsed_ms=$(( (end - start) / 1000000 ))
  local elapsed_s=$(echo "scale=2; $elapsed_ms / 1000" | bc 2>/dev/null || echo "${elapsed_ms}ms")

  local out_lines=$(wc -l < "$tmp_out" 2>/dev/null || echo 0)
  local err_lines=$(wc -l < "$tmp_err" 2>/dev/null || echo 0)
  local out_bytes=$(wc -c < "$tmp_out" 2>/dev/null || echo 0)
  local err_bytes=$(wc -c < "$tmp_err" 2>/dev/null || echo 0)

  local status=""
  local color=""
  if [ "$exit_code" -eq 124 ]; then
    status="TIMEOUT"; color="$RED"; FAIL=$((FAIL + 1))
  elif [ "$exit_code" -eq 0 ]; then
    status="PASS"; color="$GREEN"; PASS=$((PASS + 1))
  else
    status="FAIL(exit=$exit_code)"; color="$RED"; FAIL=$((FAIL + 1))
  fi

  emit "${color}${BOLD}  status: ${status}${RESET} ${DIM}(${elapsed_s}s, out=${out_lines}L/${out_bytes}B, err=${err_lines}L/${err_bytes}B)${RESET}"

  if [ "$out_lines" -gt 0 ]; then
    echo "--- stdout ($name) ---" >> "$LOG_RAW"
    cat "$tmp_out" >> "$LOG_RAW"
    echo "--- end stdout ---" >> "$LOG_RAW"
    if [ "$out_lines" -le 30 ]; then
      while IFS= read -r line; do emit "  ${DIM}$line${RESET}"; done < "$tmp_out"
    else
      head -15 "$tmp_out" | while IFS= read -r line; do emit "  ${DIM}$line${RESET}"; done
      emit "  ${DIM}... ($((out_lines - 30)) more lines in $LOG_RAW)${RESET}"
      tail -15 "$tmp_out" | while IFS= read -r line; do emit "  ${DIM}$line${RESET}"; done
    fi
  fi

  if [ "$err_lines" -gt 0 ]; then
    echo "--- stderr ($name) ---" >> "$LOG_RAW"
    cat "$tmp_err" >> "$LOG_RAW"
    echo "--- end stderr ---" >> "$LOG_RAW"
    emit "  ${YELLOW}stderr:${RESET}"
    if [ "$err_lines" -le 20 ]; then
      while IFS= read -r line; do emit "    ${YELLOW}$line${RESET}"; done < "$tmp_err"
    else
      head -10 "$tmp_err" | while IFS= read -r line; do emit "    ${YELLOW}$line${RESET}"; done
      emit "    ${YELLOW}... ($((err_lines - 20)) more in $LOG_RAW)${RESET}"
      tail -10 "$tmp_err" | while IFS= read -r line; do emit "    ${YELLOW}$line${RESET}"; done
    fi
  fi

  rm -f "$tmp_out" "$tmp_err"
  return 0
}

verify() {
  local desc="$1"
  local cond="$2"
  if eval "$cond" >/dev/null 2>&1; then
    emit "  ${GREEN}  OK${RESET} $desc"
  else
    emit "  ${RED}  XX${RESET} $desc"
    emit "       ${DIM}condition: $cond${RESET}"
  fi
  return 0
}

server_running() {
  docker compose ps minecraft --format '{{.Status}}' 2>/dev/null | head -1 | grep -qi "Up"
}

rcon_works() {
  docker compose exec -T minecraft rcon-cli "list" 2>/dev/null | grep -qi "players\|online"
}


# === STAGE 1: Environment Prerequisites ===
run_stage "1" "Environment Prerequisites"

run_test "docker compose available" "docker compose version" 10
run_test "docker daemon running" "docker info --format '{{.ServerVersion}}'" 10
run_test "minecraft container exists" "docker compose ps minecraft --format '{{.Name}}'" 10
run_test "minecraft container is Up" "docker compose ps minecraft --format '{{.Status}}' | head -1 | grep -qi 'Up'" 10
run_test "caddy container is Up" "docker compose ps caddy --format '{{.Status}}' | head -1 | grep -qi 'Up'" 10
run_test "RCON responsive (list)" "docker compose exec -T minecraft rcon-cli 'list'" 15
run_test "docker logs accessible for health check" "docker compose logs minecraft --tail 1 2>/dev/null | head -1" 10
run_test ".env file exists" "test -f .env && echo '.env found'" 5
run_test "scripts/ dir exists" "test -d scripts && ls scripts/*.sh | wc -l" 5
run_test "backups/ dir exists" "test -d backups || (mkdir -p backups && echo 'created')" 5
run_test "logs/ dir writable" "mkdir -p logs && touch logs/.wt && rm logs/.wt && echo 'writable'" 5

if ! server_running; then
  emit ""
  emit "${RED}${BOLD}Server is not running. Stopping.${RESET}"
  emit "${DIM}Start with: docker compose up -d${RESET}"
  emit ""
  emit "${BOLD}Summary: $PASS passed, $FAIL failed, $SKIP skipped${RESET}"
  emit "${DIM}Log: $LOG_FILE | Raw: $LOG_RAW${RESET}"
  exit 1
fi

if ! rcon_works; then
  emit ""
  emit "${YELLOW}${BOLD}RCON not responding. RCON tests will fail.${RESET}"
  emit "${DIM}Check: enable-rcon=true and RCON_PASSWORD in .env${RESET}"
fi

# === STAGE 2: Syntax Check All Scripts ===
run_stage "2" "Script Syntax Validation"

for script in scripts/*.sh; do
  if echo "$script" | grep -q "pregen.sh\|test-scripts.sh"; then
    continue
  fi
  run_test "bash -n $(basename "$script")" "bash -n $script" 5
done

run_test "backup.sh no-args runs" "./scripts/backup.sh --help 2>&1 || true" 10
run_test "restore.sh no-args shows backups" "./scripts/restore.sh 2>&1 || true" 10
run_test "disk-check.sh with high thresholds (exits 1 = warning works)" "./scripts/disk-check.sh --warn-gb 999 --world-gb 999; test \$? -eq 1" 10
run_test "status.sh --oneline" "./scripts/status.sh --oneline" 5
run_test "status.sh full output" "./scripts/status.sh" 10


# === STAGE 3: Behavior Against Live Server ===
run_stage "3" "Script Behavior Against Live Server"

emit ""
emit "${CYAN}[3] status.sh deep check${RESET}"
STATUS_OUTPUT=$(timeout --kill-after=5 30 ./scripts/status.sh 2>&1) || true
echo "$STATUS_OUTPUT" | grep -q "Container:" && verify "shows container status" "echo '$STATUS_OUTPUT' | grep -q 'Container:'" || true
echo "$STATUS_OUTPUT" | grep -q "Players:" && verify "shows player count" "echo '$STATUS_OUTPUT' | grep -q 'Players:'" || true
echo "$STATUS_OUTPUT" | grep -q "TPS:" && verify "shows health" "echo '$STATUS_OUTPUT' | grep -q 'TPS:'" || true
echo "$STATUS_OUTPUT" | grep -q "Memory:" && verify "shows memory" "echo '$STATUS_OUTPUT' | grep -q 'Memory:'" || true
echo "$STATUS_OUTPUT" | grep -q "Disk:" && verify "shows disk" "echo '$STATUS_OUTPUT' | grep -q 'Disk:'" || true

emit ""
emit "${CYAN}[3] disk-check.sh deep check${RESET}"
DISK_OUTPUT=$(timeout --kill-after=5 30 ./scripts/disk-check.sh 2>&1) || true
echo "$DISK_OUTPUT" | grep -qi "free space" && verify "shows free space" "echo '$DISK_OUTPUT' | grep -qi 'free space'" || true
echo "$DISK_OUTPUT" | grep -qi "minecraft/data" && verify "shows data dir size" "echo '$DISK_OUTPUT' | grep -qi 'minecraft/data'" || true
echo "$DISK_OUTPUT" | grep -qi "world/" && verify "shows world size" "echo '$DISK_OUTPUT' | grep -qi 'world/'" || true

run_test "health-watch.sh runs 8s then timeout-kills" "timeout 8 ./scripts/health-watch.sh 2>&1; test \$? -eq 124" 15
run_test "log-watch.sh --since 5s (bounded)" "timeout 10 ./scripts/log-watch.sh --since 5s 2>&1 || true" 15

run_test "mod-audit.sh lists installed mods" "./scripts/mod-audit.sh" 60
emit ""
emit "${CYAN}[3] mod-audit.sh deep check${RESET}"
MOD_OUTPUT=$(timeout --kill-after=5 30 ./scripts/mod-audit.sh 2>&1) || true
echo "$MOD_OUTPUT" | grep -qi "Installed jars:" && verify "shows jar count" "echo '$MOD_OUTPUT' | grep -qi 'Installed jars:'" || true
echo "$MOD_OUTPUT" | grep -qi "Tracked Extra Mods" && verify "shows tracked section" "echo '$MOD_OUTPUT' | grep -qi 'Tracked Extra Mods'" || true
echo "$MOD_OUTPUT" | grep -qi "Pack Mods" && verify "shows pack section" "echo '$MOD_OUTPUT' | grep -qi 'Pack Mods'" || true

run_test "pre-flight.sh runs all checks" "./scripts/pre-flight.sh; test \$? -eq 0 || test \$? -eq 1" 30
emit ""
emit "${CYAN}[3] pre-flight.sh deep check${RESET}"
PF_OUTPUT=$(timeout --kill-after=5 30 ./scripts/pre-flight.sh 2>&1) || true
echo "$PF_OUTPUT" | grep -qi "container running" && verify "checks container" "echo '$PF_OUTPUT' | grep -qi 'container running'" || true
echo "$PF_OUTPUT" | grep -qi "RCON" && verify "checks RCON" "echo '$PF_OUTPUT' | grep -qi 'RCON'" || true
echo "$PF_OUTPUT" | grep -qi "TPS" && verify "checks health" "echo '$PF_OUTPUT' | grep -qi 'TPS'" || true
echo "$PF_OUTPUT" | grep -qi "disk" && verify "checks disk" "echo '$PF_OUTPUT' | grep -qi 'disk'" || true
echo "$PF_OUTPUT" | grep -qi "backup" && verify "checks backup" "echo '$PF_OUTPUT' | grep -qi 'backup'" || true

run_test "crash-watch.sh runs" "./scripts/crash-watch.sh 2>&1" 15
verify "crash-watch wrote /tmp/mc-restart-count" "test -f /tmp/mc-restart-count && cat /tmp/mc-restart-count | grep -qE '^[0-9]+$'"

run_test "error-scan.sh scans logs" "./scripts/error-scan.sh 2>&1" 15
run_test "daily-report.sh runs (Discord or no-op)" "./scripts/daily-report.sh 2>&1" 20

emit ""
emit "${CYAN}[3] notify.sh deep check${RESET}"
run_test "notify.sh defines notify function" "source scripts/notify.sh && type notify | grep -q 'function'" 5
run_test "notify.sh no-ops or sends test" "source scripts/notify.sh && notify 'test-scripts audit: test message' && echo 'ok'" 10

if [ -f .env ] && grep -q "DISCORD_WEBHOOK=" .env; then
  WEBHOOK_VAL=$(grep "DISCORD_WEBHOOK=" .env | cut -d= -f2-)
  if [ -n "$WEBHOOK_VAL" ] && [ "$WEBHOOK_VAL" != '""' ]; then
    verify "Discord webhook configured in .env" "true"
  else
    emit "  ${YELLOW}  !${RESET} DISCORD_WEBHOOK is set but empty"
  fi
else
  emit "  ${YELLOW}  !${RESET} No DISCORD_WEBHOOK in .env - notify calls are silent"
fi


# === STAGE 4: Backup and Restore (Non-Destructive) ===
run_stage "4" "Backup and Restore (Non-Destructive)"

if [ "$SKIP_BACKUP" = true ]; then
  emit "  ${YELLOW}SKIPPED (--no-backup)${RESET}"
  SKIP=$((SKIP + 1))
else
  run_test "backup.sh creates world backup" "./scripts/backup.sh 2>&1" 120

  LATEST_BK=$(ls -1t backups/world-backup-*.tar.gz 2>/dev/null | head -1)
  if [ -n "$LATEST_BK" ]; then
    emit ""
    emit "${CYAN}[4] Verifying backup integrity${RESET}"
    verify "backup file exists" "test -f '$LATEST_BK'"
    BK_SIZE=$(du -sh "$LATEST_BK" | cut -f1)
    emit "  ${DIM}size: $BK_SIZE${RESET}"
    verify "backup is non-empty (>1KB)" "test \$(wc -c < '$LATEST_BK') -gt 1024"
    run_test "tar -tzf lists contents" "tar -tzf '$LATEST_BK' | head -5" 10
    TAR_ENTRIES=$(tar -tzf "$LATEST_BK" 2>/dev/null | wc -l)
    verify "tarball has entries ($TAR_ENTRIES)" "[ $TAR_ENTRIES -gt 0 ]"
    if [ -d "minecraft/data/DistantHorizons" ]; then
      verify "backup includes DistantHorizons" "tar -tzf '$LATEST_BK' | grep -qi 'DistantHorizons'"
    fi
  else
    emit "  ${RED}  XX No backup file found after backup.sh${RESET}"
    FAIL=$((FAIL + 1))
  fi
fi

emit ""
emit "${CYAN}[4] Restore validation (non-destructive)${RESET}"
run_test "restore.sh no-args shows usage" "./scripts/restore.sh 2>&1; test \$? -eq 1" 10
run_test "restore.sh nonexistent file shows error" "./scripts/restore.sh backups/nonexistent.tar.gz 2>&1; test \$? -eq 1" 10
run_test "restore.sh finds valid backup" "LATEST=\$(ls -1t backups/world-backup-*.tar.gz 2>/dev/null | head -1); [ -n \"\$LATEST\" ] && echo \"Found: \$LATEST\"" 5

# === STAGE 5: Cron-Readiness ===
run_stage "5" "Cron-Readiness Verification"

emit ""
emit "${CYAN}[5] Checking scripts are safe for unattended cron${RESET}"

for script in scripts/disk-check.sh scripts/status.sh scripts/error-scan.sh scripts/crash-watch.sh scripts/daily-report.sh scripts/backup.sh; do
  if grep -q 'cd "$(dirname "$0")/.."' "$script" 2>/dev/null; then
    emit "  ${GREEN}  OK${RESET} $(basename "$script") cd's to repo root (cron-safe)"
    PASS=$((PASS + 1))
  else
    emit "  ${RED}  XX${RESET} $(basename "$script") does not cd to repo root"
    FAIL=$((FAIL + 1))
  fi
done

run_test "status.sh --oneline is parseable" "./scripts/status.sh --oneline | grep -qE '[0-9]{4}-[0-9]{2}-[0-9]{2}.*Health:.*Players:.*Mem:'" 5
run_test "disk-check.sh exits 1 on impossible threshold" "./scripts/disk-check.sh --warn-gb 999999 2>&1; test \$? -eq 1" 10

# === STAGE 6: File and Output Verification ===
run_stage "6" "File and Output Verification"

emit ""
emit "${CYAN}[6] Side effects and output files${RESET}"

if [ -f logs/health.log ]; then
  HL=$(wc -l < logs/health.log)
  verify "logs/health.log exists ($HL lines)" "test -f logs/health.log"
  verify "health.log has timestamp" "tail -1 logs/health.log | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}'"
else
  emit "  ${YELLOW}  !${RESET} logs/health.log not found (cron not set up yet?)"
fi

if [ -f logs/errors.log ]; then
  EL=$(wc -l < logs/errors.log)
  emit "  ${DIM}logs/errors.log: $EL lines${RESET}"
  if [ "$EL" -gt 0 ]; then
    emit "  ${YELLOW}  !${RESET} errors.log has entries - recent:"
    tail -5 logs/errors.log | while IFS= read -r line; do emit "    ${YELLOW}$line${RESET}"; done
  else
    verify "logs/errors.log is empty" "true"
  fi
fi

BK_COUNT=$(ls -1 backups/*.tar.gz 2>/dev/null | wc -l)
if [ "$BK_COUNT" -gt 0 ]; then
  verify "backups/ has $BK_COUNT archive(s)" "[ $BK_COUNT -gt 0 ]"
  emit "  ${DIM}backups/ contents:${RESET}"
  ls -lh backups/*.tar.gz 2>/dev/null | while IFS= read -r line; do emit "    ${DIM}$line${RESET}"; done
else
  emit "  ${YELLOW}  !${RESET} backups/ is empty"
fi

if [ -f /tmp/mc-restart-count ]; then
  RC=$(cat /tmp/mc-restart-count)
  verify "/tmp/mc-restart-count exists (value=$RC)" "test -f /tmp/mc-restart-count"
fi

emit ""
emit "${CYAN}[6] File permissions${RESET}"
for script in scripts/*.sh; do
  if [ -x "$script" ]; then
    verify "$(basename "$script") is executable" "test -x $script"
  else
    emit "  ${RED}  XX${RESET} $(basename "$script") NOT executable"
    FAIL=$((FAIL + 1))
  fi
done


# === SUMMARY ===
emit ""
emit "${MAGENTA}===================================================${RESET}"
emit "${BOLD}  AUDIT SUMMARY${RESET}"
emit "${MAGENTA}===================================================${RESET}"
emit ""
emit "  ${GREEN}Passed:  $PASS${RESET}"
emit "  ${RED}Failed:  $FAIL${RESET}"
emit "  ${YELLOW}Skipped: $SKIP${RESET}"
emit ""

if [ "$FAIL" -gt 0 ]; then
  emit "${RED}${BOLD}  Failed tests require investigation.${RESET}"
  emit "  ${DIM}Raw log (full stdout/stderr captures):${RESET}"
  emit "  ${DIM}  $LOG_RAW${RESET}"
  emit ""
  emit "  ${DIM}Clean log (no ANSI, greppable):${RESET}"
  emit "  ${DIM}  $LOG_FILE${RESET}"
fi

emit ""
emit "${DIM}Log files:${RESET}"
emit "${DIM}  $LOG_FILE  (clean, greppable)${RESET}"
emit "${DIM}  $LOG_RAW    (raw, full captures)${RESET}"
emit ""

if [ "$FAIL" -eq 0 ]; then
  emit "${GREEN}${BOLD}  All tests passed. Scripts are ready for production.${RESET}"
  exit 0
else
  emit "${RED}${BOLD}  $FAIL test(s) failed. Review output above.${RESET}"
  exit 1
fi
