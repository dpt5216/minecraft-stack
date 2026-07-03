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

NOTIFY_WEBHOOK="${DISCORD_WEBHOOK:-}"

notify() {
  local msg="$1"
  local color="${2:-7506394}"

  if [ -z "$NOTIFY_WEBHOOK" ]; then
    return 0
  fi

  # Escape double quotes and backslashes in the message
  msg=$(echo "$msg" | sed 's/\\/\\\\/g; s/"/\\"/g')

  curl -s -X POST "$NOTIFY_WEBHOOK" \
    -H 'Content-Type: application/json' \
    -d "{\"embeds\":[{\"title\":\"Minecraft Server\",\"description\":\"$msg\",\"color\":$color}],\"username\":\"MC Server\"}" \
    > /dev/null 2>&1
}

notify_error() { notify "$1" "15548992"; }
notify_warn()  { notify "$1" "16753920"; }
notify_ok()    { notify "$1" "5763719"; }
notify_info()  { notify "$1" "7506394"; }
