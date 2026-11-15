# Running gatewayd

Two ways, both with no privileges beyond a data directory.

## systemd (a plain server such as a VPS or a home box)
1. `cargo build --release -p gatewayd`, copy `target/release/gatewayd` to `/usr/local/bin/`.
2. `install -d -m 0700 /etc/mcmesh && install -m 0600 deploy/gatewayd.env.example /etc/mcmesh/gatewayd.env`, edit it.
3. `cp deploy/gatewayd.service /etc/systemd/system/ && systemctl enable --now gatewayd`.
   The unit runs as a dynamic user, state in `/var/lib/mcmesh`, no capabilities, strict filesystem protection.
4. After the first start, switch `MCMESH_STRICT_DATA=1` on in the env file so a wrongly mounted empty disk can never turn into a fresh gateway.
5. Check the hardening with `systemd-analyze security gatewayd`.

## Container
`docker compose -f deploy/compose.example.yml run --rm gatewayd init` once, then `up -d`. Runs as UID 10001 with a read-only root filesystem, all capabilities dropped, data in a volume. The Dockerfile has not been built in CI yet.

## Behind a forwarder
See the "Behind a forwarder" section in `board/PROTOCOL.md` and the comments in `gatewayd.env.example`: without it every player looks like the forwarder to the rate limiter.

## Grafana
`grafana-dashboard.json` is an importable dashboard for the gateway's `/metrics` endpoint (Dashboards, Import, pick your Prometheus data source). It covers uptime, leases, players, tunnels, time since the last commit, worlds by state, commits and rejections, relay and blob throughput, host grants and anchor minutes. CAS hit rate (`mcmesh_blob_check_hits_total` over `mcmesh_blob_checks_total`, counted on the blob exists check) has a panel; relay RTT is not exported yet.

## NixOS
The repository root is a flake. `nix build .#gatewayd` builds the binary, and `nixosModules.default` runs it as a hardened systemd service with the same sandbox as `gatewayd.service`:

```nix
{
  inputs.mcmesh.url = "path:/path/to/mcmesh";   # or the git URL of your checkout
  # in your nixosSystem modules:
  #   mcmesh.nixosModules.default
  #   { services.mcmesh-gateway = {
  #       enable = true;
  #       environment = { MCMESH_ADDR = "127.0.0.1:8080"; MCMESH_AUTH = "mojang,key"; };
  #       environmentFile = config.sops.secrets."mcmesh.env".path;   # secrets such as MCMESH_METRICS_TOKEN
  #   }; }
}
```
State lives in `/var/lib/mcmesh` (DynamicUser, mode 0700). Open the firewall yourself for the relay ports you enable.

## Offsite backup
`gatewayd` writes an incremental backup to `MCMESH_BACKUP_DIR` (database snapshot plus content-addressed blobs). `offsite-backup.sh <backup-dir> <remote:path>` mirrors that directory to any rclone remote (S3, Backblaze B2, SFTP, a second disk): blobs are copied once and never deleted offsite, the database snapshot is stored per day under `db/` and the newest `KEEP_DB_DAYS` (default 14) stay. Configure the remote with `rclone config` for the user that runs it, then for example a daily systemd timer or cron line: `0 4 * * * /usr/local/bin/offsite-backup.sh /var/backups/mcmesh b2:my-bucket/mcmesh`. Restore: `rclone copy remote:path/cas <dir>/cas`, `rclone copyto remote:path/db/mcmesh-<day>.db <dir>/mcmesh.db`, and start `gatewayd` with `MCMESH_DB` and `MCMESH_CAS` pointing at them.

## Wake on join
`wake-on-join.sh` is a sidecar (bash, curl, jq) that follows a world's event long poll with a member token. When a player joins and nobody can host (`world.wanted`) it runs `WAKE_CMD` (for example `wakeonlan AA:BB:CC:DD:EE:FF` or a Home Assistant webhook with `curl`). With `SLEEP_CMD` set it runs that after the world has been without a host for `IDLE_MIN` minutes (default 30). Replayed history after a gateway restart never wakes anything. Run one per world, for example as a systemd service with `Restart=always`.

## Discord notices
`discord-notify.sh` follows a world's event long poll with a member token and posts to a Discord webhook: who started or stopped hosting, new members, refused saves (`commit.rejected`) and non-autosave revisions. Mentions are disabled in the posts. Set `GATEWAY`, `WORLD`, `TOKEN` and `DISCORD_WEBHOOK`; run one per world. Replayed history after a restart is never posted. Slash commands and a live status embed are not built.

## Run a command on every event

`on-event.sh` (bash, curl, jq) follows a world's server-sent event stream with a member token and runs `CMD` when one of the events in `EVENTS` arrives (default `revision.committed`). The command sees `EVENT` and `EVENT_JSON`. `MIN_GAP` seconds is the least time between runs and the last event inside a gap still causes one run after it. History that was in the gateway's log before the script started is ignored, and a dropped connection resumes from the last event id. The use it was written for is pushing a backup on every commit instead of once a day:

```
GATEWAY=https://gw.example.org WORLD=w1 TOKEN=... EVENTS=revision.committed MIN_GAP=300 \
CMD='gatewayd backup /var/backups/mcmesh && rclone sync /var/backups/mcmesh remote:mcmesh' ./on-event.sh
```

Run it on the machine that has the gateway database, one per world, as a systemd service with `Restart=always`. Behind a reverse proxy the stream path must not be buffered (nginx: `proxy_buffering off`).

## Live status message in Discord

`discord-status.sh` (bash, curl, jq) keeps one embed in a channel up to date through a webhook: state, host, players, host load, Minecraft version. It posts the message once, stores its id in `STATE_FILE` (default `~/.mcmesh-discord-status-<world>`), then edits it every `INTERVAL` seconds (default 60) but only when something changed, so it does not hit Discord's rate limits. If the message is deleted it posts a new one. The embed cannot mention anybody. Needs a member token of the world.

```
GATEWAY=https://gw.example.org WORLD=w1 TOKEN=... DISCORD_WEBHOOK=https://discord.com/api/webhooks/ID/SECRET ./discord-status.sh
```

Slash commands are not provided: they need a registered Discord application and a public HTTPS endpoint that verifies Discord's Ed25519 signatures, which is a service of its own, not a script.

## One-click templates

`deploy/templates/` holds app definitions for CasaOS, Umbrel, Runtipi, Unraid, Portainer and a Pterodactyl or Pelican egg. They all run the same container as `compose.example.yml` (unprivileged user 10001, ports 8080 web and API, 9000 relay tunnel, 25565 Minecraft, 24454/udp voice, one data volume) with strict-data mode off so the first start creates an empty gateway. None of them has been loaded into its platform yet, and the image `ghcr.io/mcmesh/gatewayd` they name is not published: build `deploy/Dockerfile` and change the image line, or wait for the first release. Coolify and Dokploy take `compose.example.yml` as it is. TrueNAS SCALE apps are Helm charts and are not provided. Players outside your network need an HTTPS address in front of port 8080.

## Worldgen worker
`worldgen-worker.sh` turns a spare machine into a distributed worldgen worker (board/PROTOCOL.md "Distributed worldgen", measurements in board/RESEARCH.md 1b to 1e). It runs a dedicated server of the same pack as the host, which claims one 32 x 32 chunk tile from the gateway, generates it, uploads it (or only reports a digest when it is the second opinion) and exits; the script wipes the world folder and starts it again, because a world that already holds a tile generates the next one differently. Set `SERVER_DIR` (the pack's server folder with an `mcmesh-common.toml` holding `apiUrl`, a token of a member allowed to host, and `packId`), `SEED` (the host's world seed), and `SERVER_CMD` if the server is not started by `./run.sh nogui`. Both ends must have the same `maxThreads = 1` in `config/fml.toml`, or the pack's biome regions are numbered in a different order on each machine and nothing agrees (RESEARCH.md 1d). Nothing happens until the world owner turns it on (`PUT /v1/worlds/<id>/worldgen {"enabled": true}`) and the host sets `distributeWorldgen = true`. A tile needs two workers, one to generate and one to check it, or `quorum` 1 for workers you trust.
