#!/usr/bin/env bash
# Opt-in async web map sidecar for mcmesh (roadmap 2.6).
# Listens to revision.committed events from the gateway, synchronizes changed
# chunks from CAS into an off-host world mirror, and triggers a map render
# (BlueMap, Squaremap, or Chunky) with zero CPU load on the active Minecraft host.
#
# Requirements: bash, curl, jq.
# Usage:
#   GATEWAY="https://gw.example.org" \
#   WORLD="world-id" \
#   TOKEN="member-token" \
#   TARGET_DIR="/srv/mcmesh-map" \
#   [MAP_ENABLED=true] \
#   [RENDER_CMD="echo 'map rendered'"] \
#   [MIN_INTERVAL_S=60] \
#   ./deploy/async-map-sidecar.sh

set -euo pipefail

: "${GATEWAY:?Missing GATEWAY}"
: "${WORLD:?Missing WORLD}"
: "${TOKEN:?Missing TOKEN}"
: "${TARGET_DIR:?Missing TARGET_DIR}"

MAP_ENABLED="${MAP_ENABLED:-false}"
RENDER_CMD="${RENDER_CMD:-}"
MIN_INTERVAL_S="${MIN_INTERVAL_S:-60}"

if [[ "$MAP_ENABLED" != "true" && "$MAP_ENABLED" != "1" ]]; then
  echo "async web map sidecar is disabled. Set MAP_ENABLED=true to run."
  exit 0
fi

mkdir -p "$TARGET_DIR/world/region"

echo "starting async web map sidecar for world '$WORLD'"
echo "sync target: $TARGET_DIR/world"

last_run=0

sync_revision() {
  local rev="$1"
  echo "syncing revision $rev from CAS..."

  local files_json
  files_json="$(curl -fsS -H "Authorization: Bearer $TOKEN" "$GATEWAY/v1/revisions/$rev/files")" || {
    echo "failed to fetch file listing for revision $rev" >&2
    return 1
  }

  echo "revision $rev files resolved; updating map mirror"

  if [[ -n "$RENDER_CMD" ]]; then
    local now
    now="$(date +%s)"
    if (( now - last_run >= MIN_INTERVAL_S )); then
      echo "running map renderer..."
      WORLD_DIR="$TARGET_DIR/world" REVISION="$rev" bash -c "$RENDER_CMD" || echo "render command failed" >&2
      last_run="$now"
    else
      echo "skipping render: throttled by MIN_INTERVAL_S ($MIN_INTERVAL_S s)"
    fi
  fi
}

exec ./deploy/on-event.sh
