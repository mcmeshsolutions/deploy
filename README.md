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
