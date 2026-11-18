#!/usr/bin/env bash
# Ephemeral Hetzner Cloud anchor orchestrator for mcmesh.
# Spawns an on-demand cloud server when players want to join an unhosted world,
# and deletes it when the world has been idle for IDLE_MIN minutes.
#
# Requirements: bash, curl, jq.
# Usage:
#   HCLOUD_TOKEN="your-hcloud-api-token" \
#   GATEWAY="https://gw.example.org" \
#   WORLD="world-id" \
#   TOKEN="member-token" \
#   [SERVER_TYPE="cax21"] \
#   [LOCATION="fsn1"] \
#   [IDLE_MIN=15] \
#   ./deploy/hetzner-anchor.sh

set -euo pipefail

: "${HCLOUD_TOKEN:?Missing HCLOUD_TOKEN}"
: "${GATEWAY:?Missing GATEWAY}"
: "${WORLD:?Missing WORLD}"
: "${TOKEN:?Missing TOKEN}"

SERVER_TYPE="${SERVER_TYPE:-cax21}"
LOCATION="${LOCATION:-fsn1}"
IMAGE="${IMAGE:-ubuntu-24.04}"
IDLE_MIN="${IDLE_MIN:-15}"
LABEL_SELECTOR="mcmesh-world=${WORLD}"
SERVER_NAME="mcmesh-anchor-${WORLD}"

HCLOUD_API="https://api.hetzner.cloud/v1"

hcloud() {
  local method="$1"
  local path="$2"
  local body="${3:-}"
  if [[ -n "$body" ]]; then
    curl -fsS -X "$method" "$HCLOUD_API$path" \
      -H "Authorization: Bearer $HCLOUD_TOKEN" \
      -H "Content-Type: application/json" \
      -d "$body"
  else
    curl -fsS -X "$method" "$HCLOUD_API$path" \
      -H "Authorization: Bearer $HCLOUD_TOKEN"
  fi
}

find_server_id() {
  local resp
  resp="$(hcloud GET "/servers?label_selector=${LABEL_SELECTOR}")"
  jq -r '.servers[0].id // empty' <<<"$resp"
}

create_anchor_server() {
  local existing
  existing="$(find_server_id)"
  if [[ -n "$existing" ]]; then
    echo "anchor server already running: id=$existing"
    return 0
  fi

  echo "creating Hetzner Cloud server $SERVER_NAME ($SERVER_TYPE in $LOCATION)..."

  # Minimal cloud-init user data to configure anchor runner
  local user_data
  user_data="$(cat <<EOF
#cloud-config
package_update: true
packages:
  - openjdk-21-jre-headless
  - curl
  - jq

write_files:
  - path: /etc/mcmesh/anchor.env
    permissions: '0600'
    content: |
      MCMESH_GATEWAY=${GATEWAY}
      MCMESH_WORLD=${WORLD}
      MCMESH_TOKEN=${TOKEN}
      MCMESH_ANCHOR_STANDBY=true

runcmd:
  - echo "mcmesh anchor instance initialized"
EOF
)"

  local payload
  payload="$(jq -n \
    --arg name "$SERVER_NAME" \
    --arg server_type "$SERVER_TYPE" \
    --arg location "$LOCATION" \
    --arg image "$IMAGE" \
    --arg user_data "$user_data" \
    --arg world "$WORLD" \
    '{
      name: $name,
      server_type: $server_type,
      location: $location,
      image: $image,
      user_data: $user_data,
      start_after_create: true,
      labels: {
        "mcmesh-managed": "true",
        "mcmesh-world": $world
      }
    }')"

  local res
  res="$(hcloud POST "/servers" "$payload")"
  local new_id
  new_id="$(jq -r '.server.id // empty' <<<"$res")"
  echo "spawned anchor server: id=$new_id"
}

delete_anchor_server() {
  local id
  id="$(find_server_id)"
  if [[ -n "$id" ]]; then
    echo "deleting idle anchor server: id=$id"
    hcloud DELETE "/servers/$id" >/dev/null || true
    echo "anchor server $id deleted"
  else
    echo "no active anchor server found to delete"
  fi
}

echo "starting Hetzner Cloud anchor orchestrator for world '$WORLD'"
echo "polling $GATEWAY events (idle timeout: ${IDLE_MIN}m)..."

after=0
boot=""
released_at=0
first=1

while true; do
  url="$GATEWAY/v1/worlds/$WORLD/events?after=$after&wait=$([[ $first == 1 ]] && echo 0 || echo 25)"
  [[ -n $boot ]] && url+="&boot=$boot"

  resp="$(curl -fsS -H "Authorization: Bearer $TOKEN" "$url")" || { sleep 5; continue; }
  boot="$(jq -r .boot <<<"$resp")"
  after="$(jq -r .next <<<"$resp")"

  if [[ $first == 1 || "$(jq -r .reset <<<"$resp")" == true ]]; then
    first=0
    continue
  fi

  while read -r ev; do
    case "$ev" in
      world.wanted)
        echo "event: world.wanted received"
        create_anchor_server
        released_at=0
        ;;
      host.started)
        echo "event: host.started received"
        released_at=0
        ;;
      host.released)
        echo "event: host.released received"
        released_at="$(date +%s)"
        ;;
    esac
  done < <(jq -r '.events[].event' <<<"$resp")

  if [[ $released_at -gt 0 ]] && (( $(date +%s) - released_at >= IDLE_MIN * 60 )); then
    echo "world idle threshold reached (${IDLE_MIN}m without host)"
    delete_anchor_server
    released_at=0
  fi
done
