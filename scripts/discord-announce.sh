#!/bin/bash
set -euo pipefail
# --- Load .env ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$SCRIPT_DIR/../.env" ]; then
  set -a
  source "$SCRIPT_DIR/../.env" 2>/dev/null || true
  set +a
fi
DISCORD_INVITE="${DISCORD_INVITE:-}"
if [ -z "$DISCORD_INVITE" ]; then
  echo -e "\033[31mError: DISCORD_INVITE is not set in .env\033[0m"
  exit 1
fi
# --- RCON wrapper (skill pattern: -T + timeout + /dev/null) ---
rcon() {
  timeout --kill-after=3 10 docker compose -f "$SCRIPT_DIR/../docker-compose.yml" exec -T minecraft rcon-cli "$@" < /dev/null 2>/dev/null
}
# --- Colorized tellraw ---
# gold prefix + aqua bold link + reset
TELLRAW='{"text":"","extra":[{"text":"Join our Discord server! ","color":"magenta"},{"text":"'"$DISCORD_INVITE"'","color":"aqua","bold":true,"underlined":true}]}'
echo -e "\033[36mSending Discord announcement...\033[0m"
rcon "tellraw @a $TELLRAW"
echo -e "\033[32mDone.\033[0m"