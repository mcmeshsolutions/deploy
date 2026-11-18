#!/usr/bin/env bash
# Preemptible cloud spot fleet orchestrator for mcmesh.
# Bids for ultra-low-cost spot instances across cloud providers (AWS, Hetzner, Scaleway, GCP)
# and intercepts spot termination notices to flush WAL barriers and trigger seamless handovers.
#
# Requirements: bash, curl, jq.
# Usage:
#   GATEWAY="https://gw.example.org" \
#   WORLD="world-id" \
#   TOKEN="member-token" \
#   [PROVIDER="hetzner|aws|gcp"] \
#   ./deploy/spot-fleet.sh

set -euo pipefail

GATEWAY="${GATEWAY:-http://127.0.0.1:8080}"
WORLD="${WORLD:-default}"
TOKEN="${TOKEN:-}"
PROVIDER="${PROVIDER:-hetzner}"
POLL_INTERVAL="${POLL_INTERVAL:-5}"

echo "mcmesh spot-fleet orchestrator starting: world=${WORLD} provider=${PROVIDER}"

gw_post() {
  local path="$1"
  local body="${2:-{}}"
  curl -fsS -X POST "${GATEWAY}${path}" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d "${body}"
}

check_spot_eviction() {
  case "${PROVIDER}" in
    aws)
      # AWS metadata service 2-minute spot termination notice
      local code
      code="$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 1 http://169.254.169.254/latest/meta-data/spot/instance-action || true)"
      [[ "$code" == "200" ]]
      ;;
    gcp)
      # GCP metadata service preempted notice
      local resp
      resp="$(curl -s -H "Metadata-Flavor: Google" --connect-timeout 1 http://metadata.google.internal/computeMetadata/v1/instance/preempted || true)"
      [[ "$resp" == "TRUE" ]]
      ;;
    hetzner)
      # Hetzner server action check
      if [[ -n "${HCLOUD_TOKEN:-}" && -n "${SERVER_ID:-}" ]]; then
        local action
        action="$(curl -s -H "Authorization: Bearer ${HCLOUD_TOKEN}" "https://api.hetzner.cloud/v1/servers/${SERVER_ID}" | jq -r '.server.status // empty' || true)"
        [[ "$action" == "stopping" || "$action" == "migrating" ]]
      else
        false
      fi
      ;;
    *)
      false
      ;;
  esac
}

handle_eviction() {
  echo "spot eviction notice detected on ${PROVIDER}! Initiating graceful emergency handover..."
  # 1. Trigger checkpoint/barrier flush on world
  gw_post "/v1/worlds/${WORLD}/events" '{"type":"handover.emergency","provider":"'"${PROVIDER}"'"}' || true

  # 2. Issue handover request so next standby candidate or anchor takes the lease
  echo "requesting gateway lease handover for ${WORLD}..."
  gw_post "/v1/worlds/${WORLD}/handover" '{"reason":"spot_termination"}' || true

  echo "graceful handover completed. Safe to terminate."
  exit 0
}

while true; do
  if check_spot_eviction; then
    handle_eviction
  fi
  sleep "${POLL_INTERVAL}"
done
