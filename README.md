# Minecraft Server Stack — "All the Forge"

A fully reproducible, Docker-based Minecraft server running the **All the Forge 11** modpack (v11.2.1hf) on **NeoForge 21.1.219** for **Minecraft 1.21.1**. Zero-friction redeploys: wipe the data directory, run `docker compose up`, and the server rebuilds itself — no manual jar downloads, no API keys.

---

## Table of Contents

- [Architecture](#architecture)
- [Directory Structure](#directory-structure)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Boot Sequence](#boot-sequence)
- [Configuration](#configuration)
  - [server.properties](#serverproperties)
  - [server-icon.png](#server-iconpng)
  - [Memory & JVM Tuning](#memory--jvm-tuning)
  - [Environment Variables](#environment-variables)
- [Extra Server-Side Mods](#extra-server-side-mods)
- [Server Management](#server-management)
  - [Console Access](#console-access)
  - [RCON](#rcon)
  - [Safe Shutdown](#safe-shutdown)
  - [Ops & Whitelist](#ops--whitelist)
- [Performance Tuning](#performance-tuning)
  - [Chunk Pre-Generation](#chunk-pre-generation)
  - [Distant Horizons](#distant-horizons)
  - [View & Simulation Distance](#view--simulation-distance)
  - [Included Performance Mods](#included-performance-mods)
- [Backups & Restore](#backups--restore)
- [Maintenance & Monitoring](#maintenance--monitoring)
- [Script Reference](#script-reference)
- [Updating the Modpack](#updating-the-modpack)
- [The Landing Page](#the-landing-page)
- [Troubleshooting](#troubleshooting)
- [Network](#network)

---

## Architecture

```
┌──────────────┐     ┌─────────────────────┐     ┌──────────────────┐
│   Caddy      │     │  minecraft-setup    │     │   minecraft      │
│  (reverse    │     │  (one-shot init)    │     │   (game server)  │
│   proxy)     │     │                     │     │                  │
│  :80/:443    │     │  1. downloads pack  │     │  TYPE: CUSTOM    │
│  web + TLS   │     │  2. extracts files  │     │  runs /data/     │
│              │     │  3. installs NeoF.  │──┬──│  run.sh          │
│              │     │  4. copies config   │  │  │                  │
└──────────────┘     │  5. downloads extra │  │  │  :25565          │
                     │     mods            │  │  │  16 GB RAM       │
                     └─────────────────────┘  │  └──────────────────┘
                              │               │
                              └─── ./minecraft/data (persistent volume)
```

### Three containers

| Container | Image | Purpose | Lifecycle |
|---|---|---|---|
| **caddy** | `caddy:2.11` | Reverse proxy with automatic HTTPS (Let's Encrypt) for the static landing page | Always running |
| **minecraft-setup** | `eclipse-temurin:21` | One-shot init: downloads the server pack, installs NeoForge, applies tracked config, pulls extra mods | Runs once on fresh install; Phase 2 re-runs on every `compose down → up` |
| **minecraft** | `itzg/minecraft-server:2026.6.1-java21` | The game server. Waits for setup to finish, then runs `/data/run.sh` | Always running (restarts on crash) |

### Why this design?

The standard itzg CurseForge integration (`TYPE: CURSEFORGE` with `CF_SLUG` + `CF_API_KEY`) requires a CurseForge API key. API keys often contain `$` and other special characters that break Docker Compose's `.env` parsing, and the fallback mechanism expects a pre-installed server, not a raw server pack zip with an installer jar.

This stack sidesteps all of that by using a dedicated init container that:

1. Downloads the **server pack zip** directly from CurseForge's CDN (no API key needed).
2. Extracts it and locates the NeoForge installer.
3. Runs `--installServer` to generate the actual server launcher (`run.sh`).
4. Applies our tracked `server.properties`, `server-icon.png`, and extra mods.

The main server then uses `TYPE: CUSTOM` with `CUSTOM_SERVER: /data/run.sh` — a clean, simple startup with no API dependency.

---

## Directory Structure

```
minecraft-stack/
├── docker-compose.yml          # All services, volumes, networks
├── Caddyfile                   # Reverse proxy config + TLS for the landing page
├── .gitignore                  # Ignores data/, secrets, backups, logs
├── README.md                   # This file
├── scripts/                    # Maintenance and monitoring scripts
│   ├── backup.sh               # Hot world backup or full data backup
│   ├── restore.sh              # Restore from backup archive
│   ├── status.sh               # Server health overview (--oneline for cron)
│   ├── disk-check.sh           # Disk space and world size check
│   ├── health-watch.sh         # Continuous health monitor (tmux)
│   ├── log-watch.sh            # Filtered live log tail (tmux)
│   ├── pre-flight.sh           # Pre-session readiness check
│   ├── crash-watch.sh          # Container restart detection
│   ├── error-scan.sh           # Scan logs for errors
│   ├── daily-report.sh         # Morning Discord status embed
│   ├── mod-audit.sh            # List installed mods, flag duplicates
│   ├── pregen.sh               # Chunky + DH pregen chaining
│   ├── notify.sh               # Discord webhook helper
│   ├── common.sh               # Shared functions (health checking)
│   └── test-scripts.sh         # Staged audit of all scripts
└── minecraft/
    ├── setup.sh                # Init container script (two-phase)
    ├── server.properties       # Tracked server config
    ├── server-icon.png         # Tracked server list icon (64x64 PNG)
    ├── extra-mods.txt          # Download URLs for extra server-side mods
    └── data/                   # Runtime data (gitignored, persistent)
        ├── run.sh              # Generated by NeoForge installer
        ├── libraries/          # NeoForge runtime libraries
        ├── mods/               # All mod jars (pack + extra-mods.txt)
        ├── config/             # Mod configuration files
        ├── world/              # The actual Minecraft world
        │   └── data/
        │       └── DistantHorizons.sqlite  # DH LOD database
        ├── server.properties   # Copied from tracked version
        ├── server-icon.png     # Copied from tracked version
        ├── ops.json            # Operator list
        ├── whitelist.json      # Whitelist (if enabled)
        └── logs/               # Server logs
```

Everything in `minecraft/` **except** `data/` is git-tracked. The `data/` directory is the persistent runtime state — it survives container restarts but is wiped during a full rebuild.

---

## Prerequisites

### Host machine

- **Linux server** (Ubuntu/Debian recommended) with:
  - **Docker Engine** 24+ and **Docker Compose** v2
  - **24 GB RAM** minimum (16 GB allocated to the JVM, 8 GB for the OS + overhead)
  - **50 GB+ disk space** (server pack + world data + Docker images)
  - **Open ports**: `25565` (Minecraft), `80` and `443` (web)

### Install Docker if needed

```bash
curl -fsSL https://get.docker.com | sh
```

### DNS

Point an A record for `minecraft.dthasno.website` to your server's public IP. Caddy will automatically provision a TLS certificate via Let's Encrypt on first boot.

---

## Quick Start

```bash
# Clone the repo
git clone <repo-url> minecraft-stack
cd minecraft-stack

# Create .env with an RCON password (required for scripts)
echo "RCON_PASSWORD=*** rand -base64 18)" > .env

# Start everything
docker compose up -d
```

### What happens on first boot

The `minecraft-setup` container starts and runs `setup.sh`, which takes **3-5 minutes**:

1. Installs `wget` and `unzip` in the container.
2. Downloads the ~240 MB server pack zip from CurseForge's CDN.
3. Extracts it and finds the NeoForge installer directory.
4. Cleans `/data` of any leftover files.
5. Copies all server files (mods, config, installer jar) into `/data/`.
6. Runs `java -jar neoforge-*-installer.jar --installServer` — generates `run.sh`.
7. Overwrites `server.properties` and `server-icon.png` with tracked versions.
8. Reads `extra-mods.txt` and downloads each listed mod jar into `/data/mods/`.
9. Sets ownership to `1000:1000` (the itzg image's default user).

> Steps 1-7 only run on first boot (when `/data/run.sh` doesn't exist). Steps 8-9 run on **every** boot so extra-mods updates take effect with a simple `compose down -> up`. See [Boot Sequence](#boot-sequence).

The `minecraft` container waits for setup to complete, then starts the server.

### Watch the progress

```bash
# Watch setup (first boot only)
docker compose logs minecraft-setup -f

# Once setup is done, watch the server start
docker compose logs minecraft -f
```

You'll know the server is ready when you see:

```
[Server thread/INFO] [minecraft/MinecraftServer]: Done (X.XXXs)! For help, type "help"
```

### Subsequent boots

1. **NeoForge install** (skipped) — `/data/run.sh` already exists. World and server files untouched.
2. **Extra mods** (always runs) — reads `extra-mods.txt`, removes stale jars via manifest, re-downloads all listed mods. URL changes take effect with `compose down -> git pull -> up` — no wipe needed.

Setup finishes in seconds (just the mod downloads), then the server starts.

---

## Boot Sequence

### Flow diagram

```
docker compose up -d
        │
        ├──► minecraft-setup starts
        │         │
        │         ├── apt-get install wget unzip  (always)
        │         │
        │         ├── Phase 1: NeoForge install
        │         │     ├── /data/run.sh exists?
        │         │     │     ├── YES → skip to Phase 2
        │         │     │     └── NO  → continue ↓
        │         │     ├── wget server pack zip
        │         │     ├── unzip → find neoforge-*-installer.jar
        │         │     ├── rm -rf /data/*          (clean slate)
        │         │     ├── cp -r extracted/* /data/ (copy server files)
        │         │     ├── java -jar neoforge-installer.jar --installServer
        │         │     └── cp server.properties + server-icon.png → /data/
        │         │
        │         ├── Phase 2: Extra mods (always runs)
        │         │     ├── remove jars from previous run (via manifest)
        │         │     ├── wget each URL from extra-mods.txt → /data/mods/
        │         │     └── write manifest for next boot
        │         │
        │         ├── chown -R 1000:1000 /data
        │         └── exit 0
        │
        ├──► minecraft starts (after setup exits successfully)
        │         │
        │         ├── itzg image runs /data/run.sh
        │         ├── JVM launches with Aikar's flags + 16 GB heap
        │         ├── NeoForge loads all mods from /data/mods/
        │         └── Server listens on :25565
        │
        └──► caddy starts (independent)
                  │
                  ├── Provisions TLS cert from Let's Encrypt
                  └── Serves site/ at https://minecraft.dthasno.website
```

### Idempotency

- **`docker compose restart`** — setup container does not re-run. Server restarts with existing mods.
- **`docker compose down && up`** — Phase 1 skipped (data persists), Phase 2 re-runs extra-mods. Updated URLs in `extra-mods.txt` take effect.
- **`rm -rf minecraft/data/* && docker compose up`** — full rebuild from scratch (both phases).

### Wiping and rebuilding

```bash
docker compose down
rm -rf minecraft/data/*
docker compose up -d
```

> ⚠️ This deletes the world. See [Backups & Restore](#backups--restore) if you want to preserve it.

---

## Configuration

### server.properties

The tracked `minecraft/server.properties` is copied into `/data/` during setup, overwriting whatever the modpack shipped with. This ensures your settings are consistent across rebuilds.

**To change settings:**

1. Edit `minecraft/server.properties` in the repo.
2. Commit and push.
3. Either wipe + redeploy, or apply live:

```bash
cp minecraft/server.properties minecraft/data/server.properties
docker compose restart minecraft
```

**Full reference of tracked values:**

| Property | Current Value | Notes |
|---|---|---|
| `motd` | `§5§lDean's Modded Minecraft §r§d— All the Forge v11.2.1hf` | Uses Minecraft color codes |
| `difficulty` | `hard` | Options: `peaceful`, `easy`, `normal`, `hard` |
| `gamemode` | `survival` | Options: `survival`, `creative`, `adventure`, `spectator` |
| `max-players` | `20` | Max concurrent players |
| `view-distance` | `12` | Chunk radius sent to clients. Lower to 8 if lagging |
| `simulation-distance` | `8` | Chunk radius for entity/tick simulation. Lower to 6 if lagging |
| `online-mode` | `true` | Validates player against Mojang session servers |
| `enable-rcon` | `true` | RCON enabled. Port 25575 not exposed — use `docker compose exec` |
| `enable-query` | `true` | Allows server listing tools to query the server |
| `enforce-whitelist` | `false` | Set to `true` to require whitelisting |
| `snooper-enabled` | `true` | Sends hardware/server stats to Mojang. Set to `false` for privacy |

### server-icon.png

The icon shown next to the server in the multiplayer server list. Must be a **64x64 pixel PNG**. Replace `minecraft/server-icon.png` with your own image.

Applied during setup, or apply live:

```bash
cp minecraft/server-icon.png minecraft/data/server-icon.png
docker compose restart minecraft
```

### Memory & JVM Tuning

Configured in `docker-compose.yml` under the `minecraft` service environment:

```yaml
MEMORY: "16G"
USE_AIKAR_FLAGS: "TRUE"
```

**Aikar's flags** are the community-standard JVM tuning for Minecraft servers, optimized for GC pause times and throughput. The `MEMORY` variable sets both the initial (`-Xms`) and max (`-Xmx`) heap size.

The container also has a memory limit of 20 GB (`mem_limit: 20g`) to prevent the JVM's off-heap allocations (metaspace, direct buffers, NeoForge class data) from OOMing the host.

**Recommended memory by player count:**

| Players | RAM | Notes |
|---|---|---|
| 1-5 | 8 GB | Fine for small groups |
| 5-15 | 12-16 GB | Current setting |
| 15-30 | 16-24 GB | May need a beefier host |

> ⚠️ Don't allocate more than ~75% of host RAM to the JVM — the OS, Docker, and Caddy need memory too. On a 24 GB host, 16 GB is the sweet spot.

### Environment Variables

| Variable | Value | Purpose |
|---|---|---|
| `EULA` | `TRUE` | Accepts the Minecraft EULA (required) |
| `TYPE` | `CUSTOM` | Tells itzg to use a custom launch script |
| `CUSTOM_SERVER` | `/data/run.sh` | The script to execute to start the server |
| `MEMORY` | `16G` | JVM heap size (sets both -Xms and -Xmx) |
| `USE_AIKAR_FLAGS` | `TRUE` | Enables Aikar's optimized GC flags |
| `RCON_PASSWORD` | (from `.env`) | RCON authentication password |

---

## Extra Server-Side Mods

The `minecraft/extra-mods.txt` file contains a list of direct-download URLs for server-side mods. These are downloaded into `/data/mods/` during setup and **re-synced on every boot** — no binaries committed to git. Adding, updating, or removing a mod only requires editing the file and running `docker compose down && up`.

### Format

```
# Comments start with # and are ignored
# Blank lines are also ignored

# One URL per line
https://cdn.modrinth.com/data/.../mod-name.jar
```

### Currently included mods

| Mod | Version | Purpose |
|---|---|---|
| **Chunky** | 1.4.23 | World pre-generation — eliminates chunk-gen lag |
| **Lithium** | 0.15.3 | Optimizes game physics, mob AI, block tick scheduling |
| **FerriteCore** | 7.0.3 | Reduces memory usage by optimizing object storage |
| **ModernFix** | 5.26.1 | Improves load times, fixes performance bugs |
| **Spark** | 1.10.124 | In-game performance profiler. Use `/spark health` and `/spark profiler` **in-game only** — does not work via RCON |
| **Distant Horizons** | 3.1.2-b | Server-side LOD generation + streaming to DH clients |

### Adding a new mod

1. Find the mod on [Modrinth](https://modrinth.com) or [CurseForge](https://www.curseforge.com).
2. Make sure it's the **NeoForge** version for **1.21.1**.
3. Copy the direct download URL (right-click the download button → copy link).
4. Add it to `minecraft/extra-mods.txt`.
5. Commit and push.
6. Apply: `docker compose down && docker compose up -d` (no wipe needed).

### Removing a mod

1. Delete the line from `minecraft/extra-mods.txt`.
2. Commit and push.
3. `docker compose down && docker compose up -d` — the manifest system removes the stale jar automatically.

### Installing on a running server (no restart needed)

```bash
docker compose exec minecraft wget -O /data/mods/ModName.jar "https://cdn.modrinth.com/.../ModName.jar"
docker compose restart minecraft
```

Then add the URL to `extra-mods.txt` so it's tracked for future boots.

---

## Server Management

### Console Access

```bash
docker attach minecraft-server
```

This connects you to the server's stdin/stdout. You'll see live logs and can type commands directly:

```
say Server restarting in 5 minutes!
whitelist add PlayerName
op PlayerName
stop
```

**To detach without stopping the server:** press **Ctrl+P, then Ctrl+Q**.

> ⚠️ **Ctrl+C will kill the server.** Don't use it. Always use Ctrl+P, Ctrl+Q to detach.

### RCON

RCON is **enabled** in this stack. The RCON port (25575) is not exposed to the host or the public internet — it's only accessible from inside the container. Use it via `docker compose exec` from the host (typically over SSH):

```bash
# One-off command (always use -T and < /dev/null in scripts)
docker compose exec -T minecraft rcon-cli "list" < /dev/null
docker compose exec -T minecraft rcon-cli "chunky start" < /dev/null

# Interactive prompt (with command history)
docker compose exec minecraft rcon-cli
```

The password is stored in a `.env` file (gitignored) and injected via the `RCON_PASSWORD` environment variable. The tracked `server.properties` has `rcon.password=` (empty) — the itzg image fills it in from the env var at startup.

**Setup:**

```bash
# Create .env (not tracked by git)
echo "RCON_PASSWORD=*** rand -base64 18)" > .env
```

Port 25575 is deliberately not mapped — RCON is plaintext TCP with no TLS, so it stays container-internal. To change the password, edit `.env` and restart:

```bash
docker compose down && docker compose up -d
```

> ⚠️ RCON commands that send chat messages (like `spark health`) won't return the result via RCON — the output goes to the in-game chat channel. Only commands that write to stdout (like `list`, `chunky`, `dh pregen`) return useful data via RCON.

### Safe Shutdown

```bash
# Option 1: Via console
docker attach minecraft-server
stop

# Option 2: Via mc-send-to-console
docker compose exec minecraft mc-send-to-console "stop"

# Option 3: Via Docker (less graceful, but works)
docker compose stop minecraft
```

Always use `stop` when possible — it saves the world cleanly.

### Ops & Whitelist

**Make someone an operator:**

```bash
docker attach minecraft-server
op PlayerName
```

Or edit `minecraft/data/ops.json` directly and restart.

**Enable whitelist:**

1. Edit `minecraft/server.properties`:
   ```properties
   enforce-whitelist=true
   white-list=true
   ```
2. Apply and restart.
3. Add players:
   ```bash
   docker compose exec -T minecraft rcon-cli "whitelist add PlayerName" < /dev/null
   docker compose exec -T minecraft rcon-cli "whitelist reload" < /dev/null
   ```

The `ops.json` and `whitelist.json` files persist in `minecraft/data/` across restarts (but not across wipes — back them up if needed).

---

## Performance Tuning

### Chunk Pre-Generation

**This is the single most impactful performance fix for modded servers.** When a player explores into ungenerated territory, the server must generate new chunks in real-time, which causes lag spikes and rubberbanding. Pre-generating the world eliminates this entirely.

Use the pregen script to run Chunky + Distant Horizons pregen in sequence:

```bash
# Spawn-centered pregen (uses world spawn as center)
./scripts/pregen.sh 2500

# Explicit center
./scripts/pregen.sh 2500 100000 0
```

Or run Chunky manually via RCON:

```bash
# Set a world border (optional)
docker compose exec -T minecraft rcon-cli "worldborder set 5000" < /dev/null

# Generate chunks within a 2500-block radius of spawn
docker compose exec -T minecraft rcon-cli "chunky radius 2500" < /dev/null
docker compose exec -T minecraft rcon-cli "chunky start" < /dev/null

# Check progress
docker compose exec -T minecraft rcon-cli "chunky progress" < /dev/null
```

**How long does it take?** A 2500-block radius is ~78 million blocks (196 million chunks). Expect **2-8 hours** depending on your CPU. The server remains fully playable during generation.

**Tips:**
- Run pre-gen during off-hours or while no players are online.
- Start with a smaller radius (1000) if you want players on sooner.
- Once complete, players exploring within the pre-generated area experience zero chunk-generation lag.

### Distant Horizons

[Distant Horizons](https://modrinth.com/mod/distanthorizons) (DH) renders simplified terrain beyond Minecraft's vanilla view distance. The server-side jar generates LOD (Level of Detail) data and streams it to clients running the DH mod.

DH pre-generation requires Chunky to run first — Chunky writes the vanilla chunks, then DH reads those to build LOD geometry. The pregen script handles this sequencing automatically.

**Manual DH pregen:**

```bash
docker compose exec -T minecraft rcon-cli "dh pregen start minecraft:overworld 0 0 2500" < /dev/null
docker compose exec -T minecraft rcon-cli "dh pregen status" < /dev/null
docker compose exec -T minecraft rcon-cli "dh pregen stop" < /dev/null
```

**After that, it's mostly automatic.** DH reactively generates LODs for new chunks as players explore. The pregen is a one-time primer; you only need to rerun it after a world wipe or if you expand the pregen radius.

> ⚠️ The DH LOD database lives in `minecraft/data/world/data/DistantHorizons.sqlite` and survives restarts but **not** a wipe. Back it up alongside the world if you want to avoid re-running pregen after a rebuild.

### View & Simulation Distance

If rubberbanding persists even after pre-generation, lower these in `server.properties`:

```properties
view-distance=8
simulation-distance=6
```

| Setting | Default | Recommended | Effect |
|---|---|---|---|
| `view-distance` | 12 | 8 | How far players can see. Each step roughly doubles chunk count |
| `simulation-distance` | 8 | 6 | How far entities/Redstone are ticked. Lower = less CPU |

Going from 12 to 8 reduces loaded chunks from **625 to 289** — a 54% reduction in per-player server load.

### Included Performance Mods

| Mod | What it does | In-game commands |
|---|---|---|
| **Lithium** | Rewrites game physics, mob AI, and block tick scheduling. No config needed. | None — passive |
| **FerriteCore** | Reduces memory usage by optimizing object storage. | None — passive |
| **ModernFix** | Speeds up server startup and fixes performance bugs. | `/modernfix` |
| **Spark** | Real-time profiler. | `/spark health`, `/spark profiler` — **in-game only** |

**Using Spark to diagnose lag (in-game only):**

Type in the in-game chat:

```
spark health
```

Shows memory, GC, TPS, and MSPT. If MSPT is high, run:

```
spark profiler --thread server
```

Runs a CPU profiler for 60 seconds, then gives you a web link with a flame graph.

> ⚠️ Spark health does not work via RCON. The report goes to the command sender's chat channel, which RCON cannot capture. Use it in-game only.

---

## Backups & Restore

### World backup (hot, no server stop)

```bash
./scripts/backup.sh
```

Sends `save-all` via RCON to flush chunks to disk, then `save-off` to pause auto-saving during the tar, then tars `minecraft/data/world/` (including the DH LOD database) to `backups/world-backup-YYYYMMDD-HHMMSS.tar.gz`. After the tar completes, `save-on` resumes auto-saving. The server stays running the whole time.

The `save-off` / `save-on` bracket prevents "file changed as we read it" warnings — the world files are frozen for the ~60 seconds the tar takes. Players can still move and interact (changes stay in memory and are saved on the next auto-save tick after `save-on`).

### Full data backup (server stopped)

```bash
./scripts/backup.sh --full
```

Stops the server, tars the entire `minecraft/data/` directory (world, mods, config, DH LODs, ops.json, whitelist), restarts. Use this for a complete snapshot before a modpack update or major change.

### Backup rotation

```bash
./scripts/backup.sh --keep 5         # keep last 5 world backups
./scripts/backup.sh --full --keep 3  # keep last 3 full backups
```

### Automated nightly backups (cron)

```bash
crontab -e
```

```cron
# Nightly world backup at 4am, keep last 7
0 4 * * * /path/to/minecraft-stack/scripts/backup.sh --keep 7 >> /path/to/minecraft-stack/logs/cron.log 2>&1

# Weekly full backup Sunday 5am, keep last 3
0 5 * * 0 /path/to/minecraft-stack/scripts/backup.sh --full --keep 3
```

### Restore

```bash
# World-only restore (most common)
./scripts/restore.sh backups/world-backup-20250703-040000.tar.gz

# Full restore (world + mods + config)
./scripts/restore.sh backups/full-backup-20250703-040000.tar.gz

# No arguments — lists available backups
./scripts/restore.sh
```

The script:
1. Makes a safety-net backup of the current world.
2. Stops the server.
3. Removes the current world (or full data for `--full`).
4. Extracts the backup archive.
5. Starts the server.
6. Waits for "Done!" in the logs.

> ⚠️ **The safety net:** Before overwriting anything, `restore.sh` saves the current world to `backups/pre-restore-safety-YYYYMMDD-HHMMSS.tar.gz`. If the restore goes wrong, re-run `restore.sh` against that safety file.

> 💡 **Full restore and setup.sh:** When restoring a full backup, `setup.sh` sees `/data/run.sh` already exists and skips the NeoForge install (Phase 1). It still re-syncs extra mods (Phase 2). Your world, mods, and config are preserved from the backup.

---

## Maintenance & Monitoring

### How health monitoring works

Scripts do **not** use spark health for TPS monitoring. Spark health sends its report to the in-game chat channel, which RCON cannot capture, and polling it via RCON causes server freezes. Instead, scripts count **"Can't keep up" warnings** in docker logs — a proven TPS proxy:

| Warning count (last hour) | Health indicator | Approximate TPS |
|---|---|---|
| 0 | `healthy` | ~20 TPS (nominal) |
| 1-3 | `minor` | 15-19 TPS (spikes) |
| 4+ | `lagging` | < 15 TPS (significant lag) |

This data is already collected by `error-scan.sh` into `logs/errors.log`.

### Scheduled routines (cron)

```bash
crontab -e
```

```cron
# === Daily ===
# Nightly world backup at 4am, keep last 7
0 4 * * * /path/to/minecraft-stack/scripts/backup.sh --keep 7 >> /path/to/minecraft-stack/logs/cron.log 2>&1

# Disk space check at 6am
0 6 * * * /path/to/minecraft-stack/scripts/disk-check.sh >> /path/to/minecraft-stack/logs/cron.log 2>&1

# Daily Discord status report at 8am (requires DISCORD_WEBHOOK in .env)
0 8 * * * /path/to/minecraft-stack/scripts/daily-report.sh

# === Hourly ===
# Health snapshot to log file (health trend over time)
0 * * * * /path/to/minecraft-stack/scripts/status.sh --oneline >> /path/to/minecraft-stack/logs/health.log 2>&1

# Error scan (last hour of logs)
30 * * * * /path/to/minecraft-stack/scripts/error-scan.sh

# === Every 5 minutes ===
# Crash detection (container restart monitoring)
*/5 * * * * /path/to/minecraft-stack/scripts/crash-watch.sh

# === Weekly ===
# Full data backup Sunday 5am, keep last 3
0 5 * * 0 /path/to/minecraft-stack/scripts/backup.sh --full --keep 3
```

Replace `/path/to/minecraft-stack` with your actual repo path.

### Continuous monitoring (tmux)

Run these manually in a tmux pane while playing or testing:

```bash
# Real-time health monitor (green/yellow/red, updates every 15s)
./scripts/health-watch.sh

# Filtered log watcher (errors/warnings only, no chunk-load spam)
./scripts/log-watch.sh
```

### On-demand scripts

```bash
# One-shot server health overview (health, memory, disk, players, logs)
./scripts/status.sh

# Disk space and world size check
./scripts/disk-check.sh

# Pre-flight check before a player session (pass/fail summary)
./scripts/pre-flight.sh

# List installed mods, flag duplicates, show tracked vs pack
./scripts/mod-audit.sh

# Test all scripts against the live server (staged audit)
./scripts/test-scripts.sh
```

### Discord notifications

Scripts can push alerts to a Discord channel via webhook. See `ignored/discord-hooks.md` for full setup. The short version:

1. Create a webhook in your Discord channel settings.
2. Add `DISCORD_WEBHOOK=https://discord.com/api/webhooks/...` to `.env`.
3. Scripts that source `scripts/notify.sh` will automatically send alerts.

Scripts with Discord hooks:
- `crash-watch.sh` — red alert on unexpected container restart
- `error-scan.sh` — orange alert when new log errors are detected
- `backup.sh` / `restore.sh` — green on success, red on failure
- `pre-flight.sh` — orange if any check fails
- `daily-report.sh` — morning status embed

---

## Script Reference

All scripts live in `scripts/` and are executable. They source `scripts/common.sh` for shared functions and `scripts/notify.sh` for Discord integration.

| Script | Purpose | Cron? | Discord? |
|---|---|---|---|
| `backup.sh` | Hot world backup or full data backup with rotation | Yes | Yes |
| `restore.sh` | Restore world or full data from a backup archive | No | Yes |
| `status.sh` | One-screen server health overview (or `--oneline` for cron) | Yes | No |
| `disk-check.sh` | Disk space and world/data size check with thresholds | Yes | No |
| `health-watch.sh` | Continuous health monitor (green/yellow/red) | No (tmux) | No |
| `log-watch.sh` | Filtered live log tail (errors/warnings only) | No (tmux) | No |
| `pre-flight.sh` | Pre-session readiness check (pass/fail summary) | No | Yes |
| `crash-watch.sh` | Container restart detection and alerting | Yes (5 min) | Yes |
| `error-scan.sh` | Scan docker logs for errors, alert on new ones | Yes (hourly) | Yes |
| `daily-report.sh` | Morning Discord embed with server status | Yes (8am) | Yes |
| `mod-audit.sh` | List installed jars, flag duplicates, tracked vs pack | No | No |
| `pregen.sh` | Chunky + DH pregen chaining with progress polling | No | No |
| `notify.sh` | Discord webhook helper (sourced by other scripts) | N/A | N/A |
| `common.sh` | Shared functions: `get_health()`, `get_health_count()` | N/A | N/A |
| `test-scripts.sh` | Staged audit of all scripts against the live server | No | No |

---

## Updating the Modpack

When a new version of "All the Forge" is released:

1. **Find the new server pack URL.**
   - Go to [CurseForge files page](https://www.curseforge.com/minecraft/modpacks/all-the-forge/files)
   - Filter by **"Server Pack"** type
   - Find the version matching the new release
   - Right-click the download button → copy link address

2. **Update `minecraft/setup.sh`** with the new download URL:

   ```bash
   wget -q -O /tmp/pack.zip "https://mediafilez.forgecdn.net/files/XXXX/XXX/NewPack.zip"
   ```

3. **Update the MOTD** in `minecraft/server.properties` if the version changed.

4. **Back up the world** (see [Backups & Restore](#backups--restore)).

5. **Wipe and redeploy:**

   ```bash
   docker compose down
   rm -rf minecraft/data/*
   docker compose up -d
   docker compose logs minecraft-setup -f
   ```

6. **Restore the world** if you backed it up:

   ```bash
   # After setup completes but before players join:
   cp -r world-backup/world minecraft/data/world
   docker compose restart minecraft
   ```

7. **Update the landing page** in `site/index.html` with the new version number.

> ⚠️ Modpack updates may change mod configs, world generation, or block IDs. Always test on a copy of the world before committing.

---

## The Landing Page

Caddy serves the static site in `site/` at `https://minecraft.dthasno.website`. This is a player-facing page with step-by-step instructions for:

1. Installing CurseForge (with video tutorial)
2. Installing the "All the Forge" modpack
3. Launching the game and joining the server

The Caddyfile is minimal — it just serves static files with gzip compression, security headers (HSTS, CSP), and automatic TLS via Let's Encrypt. No backend, no database.

To update the page, edit `site/index.html` and Caddy will serve it immediately (the volume is mounted read-only, so changes are live on next page load).

---

## Troubleshooting

### Common errors

| Symptom | Likely cause | Fix |
|---|---|---|
| `CF_SERVER_MOD is required` | Old compose file using API-based approach | Pull latest `docker-compose.yml` from this repo |
| `mv: inter-device move failed` | Docker overlay + volume boundary issue | Fixed in current `setup.sh` (uses `cp -r` instead of `mv`) |
| `syntax error: unexpected end of file` | YAML multiline string parsing issue | Fixed — setup now uses a separate `setup.sh` script mounted as a volume |
| `Modpack missing start script` | Server pack has only the installer, not `run.sh` | Fixed — `setup.sh` runs `--installServer` to generate `run.sh` |
| `Can't keep up! Running Xms behind` | Chunk generation lag on first player join | Pre-generate chunks with Chunky; lower view distance |
| `moved too quickly!` | Server tick lag causing position desync | Fix the "Can't keep up!" issue (see [Performance Tuning](#performance-tuning)) |
| Container exits with code 1 | Setup script failed | Check `docker compose logs minecraft-setup` for the error |
| Container exits with code 2 | Server crashed during startup | Check `docker compose logs minecraft` for the stack trace |
| RCON command returns empty | Command sends output to chat, not stdout | Use in-game console instead (spark health, tellraw, etc.) |
| Players can't connect | Firewall or DNS issue | Ensure port `25565` is open; check DNS resolves to your server IP |

### Useful diagnostic commands

```bash
# Check container status
docker compose ps

# Check resource usage
docker stats minecraft-server

# View all logs
docker compose logs

# Inspect resolved compose config
docker compose config

# Check if the server is listening
curl -s http://localhost:25565 | xxd | head -5
```

### Reading "Can't keep up" warnings

The server logs "Can't keep up! Is the server overloaded? Running Xms or Y ticks behind" when it can't maintain 20 TPS. This is normal during chunk generation, mod loading, or when many players are online. The health monitoring scripts count these warnings as a TPS proxy:

- **0 warnings in the last hour** — server is healthy
- **1-3** — minor lag spikes (usually transient)
- **4+** — significant lag, investigate with `/spark profiler` in-game

To see recent warnings:

```bash
./scripts/error-scan.sh
# or
docker compose logs minecraft --since 1h 2>&1 | grep "Can't keep up"
```

---

## Network

### Port mapping

| Port | Protocol | Service | Purpose |
|---|---|---|---|
| 25565 | TCP | minecraft | Java Edition game traffic |
| 80 | TCP | caddy | HTTP → redirects to HTTPS |
| 443 | TCP/UDP | caddy | HTTPS (TLS) + HTTP/3 (QUIC) |

### Firewall configuration

```bash
# UFW (Ubuntu/Debian)
ufw allow 25565/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 443/udp

# Cloud provider: also check security group / firewall rules in your
# provider's dashboard (AWS, Hetzner, DigitalOcean, etc.)
```

### DNS

| Record | Type | Value |
|---|---|---|
| `minecraft.dthasno.website` | A | Your server's public IP |

Caddy automatically provisions and renews the TLS certificate via Let's Encrypt. No manual certificate management needed.

### Internal networking

Caddy is on the `proxy-net` bridge network. The `minecraft` container is on the default bridge — it only needs host-port publishing for game traffic (25565). The `minecraft-setup` container is not on any network — it only downloads from the internet during setup.
