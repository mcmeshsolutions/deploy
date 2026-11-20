<div align="center">

# mcmesh-deploy

**Production deployment automation, Docker Compose stacks, hardened systemd units, and homelab templates for mcmesh.**

[![CI](https://github.com/mcmeshsolutions/deploy/actions/workflows/ci.yml/badge.svg)](https://github.com/mcmeshsolutions/deploy/actions/workflows/ci.yml)
[![Docker](https://img.shields.io/badge/Docker-Compose-2496ED.svg?logo=docker&logoColor=white)](https://docs.docker.com/compose/)
[![Caddy](https://img.shields.io/badge/TLS-Caddy-1F88C0.svg?logo=caddy)](https://caddyserver.com)
[![systemd](https://img.shields.io/badge/Init-systemd-FCC624.svg?logo=linux&logoColor=black)](https://systemd.io)
[![Grafana](https://img.shields.io/badge/Metrics-Grafana-F46800.svg?logo=grafana&logoColor=white)](./grafana-dashboard.json)

[1-Command Quickstart](#1-command-production-quickstart) | [Deployment Options](#deployment-options) | [Sidecar Automation](#sidecar-automation-scripts) | [Homelab Templates](#homelab-app-templates) | [Testing](#testing)

</div>

---

## Overview

`mcmesh-deploy` packages everything needed to self-host [gatewayd](https://github.com/mcmeshsolutions/gatewayd) and headless anchor/worker nodes in production, from a 1-command Docker Compose + Caddy TLS setup to hardened systemd units, Grafana dashboards, and homelab app templates.

## 1-Command Production Quickstart

For a production gateway with automated Let's Encrypt / ZeroSSL TLS certificates via Caddy:

```bash
./quickstart.sh
```

Or run non-interactively with your domain:

```bash
DOMAIN=mesh.example.com TLS_EMAIL=admin@example.com ./quickstart.sh
```

`quickstart.sh` will:
1. Validate Docker and Docker Compose v2.
2. Generate cryptographically random secrets in `.env`.
3. Configure `Caddyfile` for automatic HTTPS on ports `80` and `443`.
4. Initialize storage volumes and start `gatewayd` and `caddy`.
5. Print the formatted connection card and initial superadmin claim link (`https://<DOMAIN>/panel`).

## Deployment Options

| Method | Files | Highlights |
|---|---|---|
| **Docker Compose + Caddy TLS** | `docker-compose.yml`, `Caddyfile`, `quickstart.sh` | Automated HTTPS, healthchecks, persistent volumes |
| **Hardened Container** | `Dockerfile`, `compose.example.yml` | Unprivileged UID `10001`, read-only rootfs, all capabilities dropped |
| **systemd (VPS / Bare Metal)** | `gatewayd.service`, `gatewayd.env.example` | `DynamicUser`, `/var/lib/mcmesh` state dir, strict FS isolation |
| **Headless Anchor Node** | `Dockerfile.anchor`, `anchor-install.sh`, `hetzner-anchor.sh` | Standby host node with `mcmesh-anchor.service` |
| **NixOS Module** | `flake.nix` (monorepo root) | `services.mcmesh-gateway` with matching systemd sandbox |

### Hardened systemd Setup

```bash
# 1. Build gatewayd binary and install
cargo build --release -p gatewayd
sudo install -m 0755 target/release/gatewayd /usr/local/bin/gatewayd

# 2. Configure environment
sudo install -d -m 0700 /etc/mcmesh
sudo install -m 0600 gatewayd.env.example /etc/mcmesh/gatewayd.env
# Edit /etc/mcmesh/gatewayd.env (enable MCMESH_STRICT_DATA=1 after first start)

# 3. Enable and start service
sudo cp gatewayd.service /etc/systemd/system/
sudo systemctl enable --now gatewayd
systemd-analyze security gatewayd
```

## Monitoring (Grafana & Prometheus)

Import [`grafana-dashboard.json`](./grafana-dashboard.json) into Grafana and point it at your Prometheus data source scraping `gatewayd`'s `/metrics` endpoint (`MCMESH_METRICS_TOKEN`). Panels include uptime, active leases, connected players, relay tunnels, time since last commit, worlds by state, commit/rejection rates, CAS blob hit rate, and anchor minutes.

## Sidecar Automation Scripts

| Script | Purpose |
|---|---|
| `offsite-backup.sh` | Mirrors incremental `gatewayd backup` snapshots and CAS blobs to any `rclone` remote (S3, B2, SFTP) with daily DB retention (`KEEP_DB_DAYS=14`) |
| `wake-on-join.sh` | Watches `world.wanted` events and triggers `WAKE_CMD` (Wake-on-LAN / Home Assistant) or `SLEEP_CMD` after `IDLE_MIN` idle minutes |
| `discord-notify.sh` | Streams world events to a Discord webhook (host changes, new members, rejected commits, manual saves) |
| `discord-status.sh` | Maintains a live-updating Discord embed with world state, active host, player count, and load |
| `on-event.sh` | Runs an arbitrary `CMD` on matching SSE events (e.g. `revision.committed`) with rate-limiting (`MIN_GAP`) |
| `async-map-sidecar.sh` | Sidecar helper for asynchronous map exports |
| `worldgen-worker.sh` | Dedicated headless worldgen worker claiming 32x32 chunk tiles from the gateway |
| `spot-fleet.sh` | Cloud spot instance orchestration helper for burst anchor/worker capacity |

## Homelab App Templates

`templates/` provides ready-to-adapt app definitions for self-hosting platforms:

- **CasaOS** (`templates/casaos/`)
- **Umbrel** (`templates/umbrel/`)
- **Runtipi** (`templates/runtipi/`)
- **Unraid** (`templates/unraid/`)
- **Portainer** (`templates/portainer/`)
- **Pterodactyl / Pelican** (`templates/pterodactyl/`)

All templates run the unprivileged `gatewayd` container (UID `10001`) exposing ports `8080` (HTTP/WebUI), `9000` (host tunnel), `25565` (Minecraft TCP), and `24454/udp` (Simple Voice Chat).

## Testing

Validate shell script syntax, `shellcheck`, JSON/YAML manifests, Dockerfiles, and systemd units:

```bash
bash tests/run_tests.sh
```

## Ecosystem

| Repository | Description |
|---|---|
| [mcmeshsolutions/gatewayd](https://github.com/mcmeshsolutions/gatewayd) | Coordination gateway daemon, CAS store, and relay |
| [mcmeshsolutions/mod](https://github.com/mcmeshsolutions/mod) | Minecraft NeoForge 1.21.1 client and host mod |
| [mcmeshsolutions/web](https://github.com/mcmeshsolutions/web) | WebUI panel, 3D voxel viewer, and spatial inspectors |
| [mcmeshsolutions/deploy](https://github.com/mcmeshsolutions/deploy) | Docker Compose, systemd, Caddy TLS, and homelab templates (this repo) |
| [mcmeshsolutions/docs](https://github.com/mcmeshsolutions/docs) | OpenAPI 3.1.0 spec, JSON schemas, and mod API docs |

---

<div align="center">
<sub>Not affiliated with Mojang or Microsoft.</sub>
</div>
