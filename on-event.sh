#!/usr/bin/env bash
# Runs a command whenever the gateway reports one of the chosen events for a world, over the server-sent event stream.
# Typical use: push a backup on every committed revision instead of once a day.
#   GATEWAY=https://gw.example.org WORLD=w1 TOKEN=... EVENTS=revision.committed MIN_GAP=300 \
#   CMD='gatewayd backup /var/backups/mcmesh && rclone sync /var/backups/mcmesh remote:mcmesh' ./on-event.sh
# The command gets EVENT (the name) and EVENT_JSON (the whole payload) in its environment. Needs bash, curl and jq, and the token of a
# member of the world. History that was already in the gateway's log when this starts is ignored. MIN_GAP seconds is the least time
# between two runs; events that arrive inside the gap cause one more run after it, so the last change is never missed.
set -uo pipefail
: "${GATEWAY:?}" "${WORLD:?}" "${TOKEN:?}" "${CMD:?}"
EVENTS="${EVENTS:-revision.committed}"
MIN_GAP="${MIN_GAP:-0}"
started="$(date +%s)"
last_id=""
boot=""
last_run=0
pending=0
ev=""
data=""

run_cmd() {
  last_run="$(date +%s)"
  pending=0
  EVENT="$1" EVENT_JSON="$2" bash -c "$CMD" || echo "command failed" >&2
}

wanted() { [[ ",$EVENTS," == *",$1,"* ]]; }

dispatch() {
  [[ -z $ev ]] && return
  if [[ $ev == reset ]]; then
    boot="$(jq -r '.boot // empty' <<<"$data" 2>/dev/null)"
    last_id=""
    return
  fi
  local ts
  ts="$(jq -r '.ts // 0' <<<"$data" 2>/dev/null || echo 0)"
  if wanted "$ev" && (( ts >= started - 2 )); then
    if (( $(date +%s) - last_run >= MIN_GAP )); then
      run_cmd "$ev" "$data"
    else
      pending=1
      pend_ev="$ev"
      pend_data="$data"
    fi
  fi
}

while true; do
  url="$GATEWAY/v1/worlds/$WORLD/events/stream"
  [[ -n $boot ]] && url+="?boot=$boot"
  hdr=(-H "Authorization: Bearer $TOKEN")
  [[ -n $last_id ]] && hdr+=(-H "Last-Event-ID: $last_id")
  while true; do
    IFS= read -r -t 5 line
    rc=$?
    if (( rc > 128 )); then
      # read timed out: nothing arrived, use the quiet moment to run the trailing command
      if (( pending )) && (( $(date +%s) - last_run >= MIN_GAP )); then
        run_cmd "$pend_ev" "$pend_data"
      fi
      continue
    fi
    (( rc != 0 )) && break
    line="${line%$'\r'}"
    case $line in
      id:*) last_id="${line#id:}"; last_id="${last_id# }" ;;
      event:*) ev="${line#event:}"; ev="${ev# }" ;;
      data:*) data="${line#data:}"; data="${data# }" ;;
      "") dispatch; ev=""; data="" ;;
    esac
  done < <(curl -fsSN "${hdr[@]}" "$url" 2>/dev/null)
  sleep 3
done
