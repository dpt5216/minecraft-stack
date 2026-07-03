#!/bin/bash
set -e
set -o pipefail

NEOFORGE_VERSION="21.1.228"
NEOFORGE_URL="https://maven.neoforged.net/releases/net/neoforged/neoforge/${NEOFORGE_VERSION}/neoforge-${NEOFORGE_VERSION}-installer.jar"

MOD_MANIFEST="/data/.deanpac-mods-manifest.txt"
EXTRA_MANIFEST="/data/.extra-mods-manifest.txt"
DP_MANIFEST="/data/.deanpac-datapacks-manifest.txt"

# Tools needed for downloads.
# Always installed (idempotent — apt-get install is a no-op if present).
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq && apt-get install -y -qq wget

# Helper: download a URL list, removing stale jars from previous run.
# Args: $1 = list file path, $2 = manifest file path, $3 = dest dir
sync_url_list() {
  local LIST_FILE="$1"
  local MANIFEST="$2"
  local DEST_DIR="$3"

  if [ ! -f "$LIST_FILE" ]; then
    return 0
  fi

  mkdir -p "$DEST_DIR"

  # Remove jars from the previous run
  if [ -f "$MANIFEST" ]; then
    while IFS= read -r oldfile; do
      if [ -n "$oldfile" ] && [ -f "$DEST_DIR/$oldfile" ]; then
        echo "[setup]   removing stale: $oldfile"
        rm -f "$DEST_DIR/$oldfile"
      fi
    done < "$MANIFEST"
  fi
  : > "$MANIFEST"

  grep -v '^#' "$LIST_FILE" | grep -v '^$' | while read -r url; do
    echo "[setup]   -> $url"
    filename=$(basename "$url")
    # decode percent-encoding so %2B -> +, %20 -> space, etc.
    filename=$(printf '%b' "${filename//%/\\x}")
    wget -q -O "$DEST_DIR/$filename" "$url"
    echo "$filename" >> "$MANIFEST"
  done || true
}

# ── Phase 1: NeoForge install — only on fresh setup ──────────────
# On restart (run.sh already exists) this entire block is skipped.
if [ ! -f /data/run.sh ]; then
  echo "[setup] Downloading NeoForge ${NEOFORGE_VERSION} installer..."
  wget -q -O /tmp/neoforge-installer.jar "$NEOFORGE_URL"

  # Clean /data of any previous partial install
  echo "[setup] Cleaning /data..."
  rm -rf /data/* /data/.[!.]* /data/..?*

  cd /data
  echo "[setup] Running NeoForge installer..."
  java -jar /tmp/neoforge-installer.jar --installServer
  rm -f /tmp/neoforge-installer.jar

fi

# Always apply tracked config (server.properties + icon) so changes
# take effect with a simple compose down -> up, no wipe needed.
cp /tmp/server.properties /data/server.properties
cp /tmp/server-icon.png /data/server-icon.png

# ── Phase 2: DeanPAC mods — always run ───────────────────────────
# Re-downloads every boot so URL changes / version bumps in
# deanpac-mods.txt take effect with a simple compose down → up.
# A manifest tracks previously-installed jars so stale versions
# (different filename) are removed before the new ones land.
echo "[setup] Syncing DeanPAC mods..."
sync_url_list /tmp/deanpac-mods.txt "$MOD_MANIFEST" /data/mods

# ── Phase 2b: Extra server-side mods — always run ────────────────
# Same mechanism, separate manifest. These are mods not included
# in the DeanPAC mod list (e.g. Chunky, Spark).
if [ -f /tmp/extra-mods.txt ]; then
  echo "[setup] Syncing extra mods..."
  sync_url_list /tmp/extra-mods.txt "$EXTRA_MANIFEST" /data/mods
fi

# ── Phase 3: Config files — always run ──────────────────────────
# Copies the tracked config tree from the repo into /data/config/.
# This ensures config changes take effect with compose down → up.
# We clean the target first so deleted configs don't linger.
if [ -d /deanpac-config ]; then
  echo "[setup] Syncing config files..."
  rm -rf /data/config
  cp -r /deanpac-config /data/config
fi

# ── Phase 4: Datapacks — always run ─────────────────────────────
# Downloads server-side datapacks into the world's datapacks folder.
# The world dir is created by the server on first boot, but we
# pre-create the datapacks dir so the zips are ready when it starts.
echo "[setup] Syncing datapacks..."
sync_url_list /tmp/deanpac-datapacks.txt "$DP_MANIFEST" /data/world/datapacks

chown -R 1000:1000 /data
echo "[setup] Done!"
