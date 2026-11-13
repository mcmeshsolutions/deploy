#!/usr/bin/env bash
# Wakes a sleeping host machine when a player joins a world nobody can host, and optionally puts it back to sleep
# after the world has had no host for IDLE_MIN minutes. Needs bash, curl and jq, and a token of a member of the world.
#   GATEWAY=https://gw.example.org WORLD=w1 TOKEN=... WAKE_CMD='wakeonlan AA:BB:CC:DD:EE:FF' \
#   SLEEP_CMD='ssh desktop systemctl suspend' IDLE_MIN=30 ./wake-on-join.sh
set -euo pipefail
: "${GATEWAY:?}" "${WORLD:?}" "${TOKEN:?}" "${WAKE_CMD:?}"
SLEEP_CMD="${SLEEP_CMD:-}"
IDLE_MIN="${IDLE_MIN:-30}"
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
  # the first page and a page after a gateway restart replay old history, which must never wake anything
  if [[ $first == 1 || "$(jq -r .reset <<<"$resp")" == true ]]; then
    first=0
    continue
  fi
  while read -r ev; do
    case $ev in
      world.wanted) echo "wake: $WORLD wanted"; bash -c "$WAKE_CMD" || echo "wake command failed" >&2; released_at=0 ;;
      host.started) released_at=0 ;;
      host.released) released_at="$(date +%s)" ;;
    esac
  done < <(jq -r '.events[].event' <<<"$resp")
  if [[ -n $SLEEP_CMD && $released_at -gt 0 ]] && (( $(date +%s) - released_at >= IDLE_MIN * 60 )); then
    echo "sleep: $WORLD idle for $IDLE_MIN minutes"
    bash -c "$SLEEP_CMD" || echo "sleep command failed" >&2
    released_at=0
  fi
done
