#!/bin/bash
set -e
set -o pipefail

MANIFEST="/data/.extra-mods-manifest.txt"

# Tools needed for both the install and the extra-mods download.
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

  # Apply tracked config files
  cp /tmp/server.properties /data/server.properties
  cp /tmp/server-icon.png /data/server-icon.png
fi

# ── Phase 2: Extra server-side mods — always run ─────────────────
# Re-downloads every boot so URL changes / version bumps in
# extra-mods.txt take effect with a simple compose down → up.
# A manifest tracks previously-installed jars so stale versions
# (different filename) are removed before the new ones land.
if [ -f /tmp/extra-mods.txt ]; then
  echo "[setup] Updating extra mods..."
  mkdir -p /data/mods

  # Remove jars from the previous run
  if [ -f "$MANIFEST" ]; then
    while IFS= read -r oldfile; do
      if [ -n "$oldfile" ] && [ -f "/data/mods/$oldfile" ]; then
        echo "[setup]   removing stale: $oldfile"
        rm -f "/data/mods/$oldfile"
      fi
    done < "$MANIFEST"
  fi
  : > "$MANIFEST"

  grep -v '^#' /tmp/extra-mods.txt | grep -v '^$' | while read -r url; do
    echo "[setup]   -> $url"
    filename=$(basename "$url")
    # decode percent-encoding so %2B -> +, %20 -> space, etc.
    filename=$(printf '%b' "${filename//%/\\x}")
    wget -q -O "/data/mods/$filename" "$url"
    echo "$filename" >> "$MANIFEST"
  done || true
fi

chown -R 1000:1000 /data
rm -rf /tmp/pack /tmp/pack.zip
echo "[setup] Done!"