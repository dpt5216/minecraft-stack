#!/bin/bash
set -e

if [ -f /data/run.sh ]; then
  echo "[setup] Server already installed, skipping."
  exit 0
fi

echo "[setup] Downloading server pack..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq && apt-get install -y -qq wget unzip

wget -q -O /tmp/pack.zip "https://mediafilez.forgecdn.net/files/7978/707/ATFG11%20v11.2.1hf%20Server%20Files.zip"
mkdir -p /tmp/pack
unzip -q -o /tmp/pack.zip -d /tmp/pack

# Find the folder containing the NeoForge installer
EXTRACTED_DIR=$(find /tmp/pack -name "neoforge-*-installer.jar" -exec dirname {} \; | head -1)
if [ -z "$EXTRACTED_DIR" ]; then
  echo "[setup] ERROR: Could not find NeoForge installer"
  exit 1
fi

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

# Apply our tracked server.properties
cp /tmp/server.properties /data/server.properties

chown -R 1000:1000 /data
rm -rf /tmp/pack /tmp/pack.zip
echo "[setup] Done!"
