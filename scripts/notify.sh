#!/bin/bash
#
# notify.sh — shared Discord notification helper
#
# Source this from other scripts. Reads DISCORD_WEBHOOK from .env.
# No-ops silently if no webhook is configured.
#
# Usage:
#   source scripts/notify.sh
#   notify "Server is starting"
#   notify_ok "Backup complete"
#   notify_error "Disk full"
#

# Load .env if present
if [ -f .env ]; then
  set -a
  source .env 2>/dev/null || true
  set +a
fi

# pull in shared helpers (sanitize_webhook)
SCRIPT_DIR="${BASH_SOURCE[0]%/*}"
[ -f "$SCRIPT_DIR/common.sh" ] && source "$SCRIPT_DIR/common.sh"

NOTIFY_WEBHOOK="$(sanitize_webhook "${DISCORD_WEBHOOK:-}")"

notify() {
  local msg="$1"
  local color="${2:-7506394}"

  if [ -z "$NOTIFY_WEBHOOK" ]; then
    return 0
  fi

  # Escape double quotes and backslashes in the message
  msg=$(echo "$msg" | sed 's/\\/\\\\/g; s/"/\\"/g')

  local code
  code=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$NOTIFY_WEBHOOK" \
    -H 'Content-Type: application/json' \
    -d "{\"embeds\":[{\"title\":\"Minecraft Server\",\"description\":\"$msg\",\"color\":$color}],\"username\":\"MC Server\"}")
  case "$code" in
    20[04]) ;;
    *) echo "notify: webhook POST failed (HTTP $code)" >&2 ;;
  esac
}

notify_error() { notify "$1" "15548992"; }
notify_warn()  { notify "$1" "16753920"; }
notify_ok()    { notify "$1" "5763719"; }
notify_info()  { notify "$1" "7506394"; }
