#!/bin/bash
set -euo pipefail
# --- Load .env ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$SCRIPT_DIR/../.env" ]; then
  set -a
  source "$SCRIPT_DIR/../.env" 2>/dev/null || true
  set +a
fi
# --- RCON wrapper (skill pattern: -T + timeout + /dev/null) ---
rcon() {
  timeout --kill-after=3 10 docker compose -f "$SCRIPT_DIR/../docker-compose.yml" exec -T minecraft rcon-cli "$@" < /dev/null 2>/dev/null
}
# --- Colorized tellraw ---
# purple message + aqua mod name + aqua underlined link
TELLRAW='{"text":"","extra":[{"text":"This server now supports ","color":"light_purple"},{"text":"Simple Voice Chat","color":"aqua","bold":true},{"text":"! Install clientside to start chatting in game. See instructions on our website ","color":"light_purple"},{"text":"https://minecraft.dthasno.website","color":"aqua","underlined":true}]}'
echo -e "\033[36mSending Simple Voice Chat announcement...\033[0m"
rcon "tellraw @a $TELLRAW"
echo -e "\033[32mDone.\033[0m"
