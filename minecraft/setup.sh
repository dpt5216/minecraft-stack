#!/bin/bash
set -e
set -o pipefail

# Tools needed for the install.
# Always installed (idempotent — apt-get install is a no-op if present).
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq && apt-get install -y -qq wget unzip

# ── Phase 1: NeoForge install — only on fresh setup ──────────────
# On restart (run.sh already exists) this entire block is skipped.
if [ ! -f /data/run.sh ]; then
  echo "[setup] Downloading server pack..."
  wget -q -O /tmp/pack.zip "https://mediafilez.forgecdn.net/files/7978/707/ATFG11%20v11.2.1hf%20Server%20Files.zip"
  mkdir -p /tmp/pack
  unzip -q -o /tmp/pack.zip -d /tmp/pack

  # Find the folder containing the NeoForge installer
  INSTALLERS=$(find /tmp/pack -name "neoforge-*-installer.jar")
  INSTALLER_COUNT=$(printf '%s\n' "$INSTALLERS" | grep -c .)
  if [ "$INSTALLER_COUNT" -eq 0 ]; then
    echo "[setup] ERROR: Could not find NeoForge installer"
    exit 1
  fi
  if [ "$INSTALLER_COUNT" -gt 1 ]; then
    echo "[setup] ERROR: Found $INSTALLER_COUNT installers, expected 1:"
    printf '%s\n' "$INSTALLERS"
    exit 1
  fi
  EXTRACTED_DIR=$(dirname "$INSTALLERS")

  # Clean /data of any previous partial extraction
  echo "[setup] Cleaning /data..."
  rm -rf /data/* /data/.[!.]* /data/..?*

  # Copy files (cp handles cross-filesystem, unlike mv)
  echo "[setup] Copying server files..."
  shopt -s dotglob
  cp -r "$EXTRACTED_DIR"/* /data/
  shopt -u dotglob

  cd /data
  echo "[setup] Running NeoForge installer..."
  java -jar neoforge-*-installer.jar --installServer

fi

# Always apply tracked config (server.properties + icon) so changes
# take effect with a simple compose down -> up, no wipe needed.
cp /tmp/server.properties /data/server.properties
cp /tmp/server-icon.png /data/server-icon.png

# Extra mods are managed by MODRINTH_PROJECTS in docker-compose.yml.
# The itzg image auto-downloads and cleans up stale versions at boot.

chown -R 1000:1000 /data
rm -rf /tmp/pack /tmp/pack.zip
echo "[setup] Done!"
