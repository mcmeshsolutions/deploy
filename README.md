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
