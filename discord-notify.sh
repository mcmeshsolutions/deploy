#!/usr/bin/env bash
# Posts world events to a Discord webhook: who started or stopped hosting, rejected commits, new members.
# Needs bash, curl, jq and a member token. Replayed history (first page, gateway restart) is never posted.
#   GATEWAY=https://gw.example.org WORLD=w1 TOKEN=... DISCORD_WEBHOOK=https://discord.com/api/webhooks/... ./discord-notify.sh
set -euo pipefail
: "${GATEWAY:?}" "${WORLD:?}" "${TOKEN:?}" "${DISCORD_WEBHOOK:?}"
after=0
boot=""
first=1
say() {
  jq -n --arg c "$1" '{content: $c, allowed_mentions: {parse: []}}' | curl -fsS -H 'content-type: application/json' -d @- "$DISCORD_WEBHOOK" >/dev/null || echo "discord post failed" >&2
}
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
  while read -r line; do
    [[ -n $line ]] && say "$line"
  done < <(jq -r --arg w "$WORLD" '.events[] | select(.event != "world.wanted") |
    if .event == "host.started" then "[\($w)] \(.data.player // "someone") is now hosting"
    elif .event == "host.released" then "[\($w)] \(.data.player // "the host") stopped hosting"
    elif .event == "member.joined" then "[\($w)] \(.data.player // "someone") joined the world"
    elif .event == "commit.rejected" then "[\($w)] a save was refused by the safety gate, check the gateway"
    elif .event == "revision.committed" then "[\($w)] saved revision \(.data.rev) (\(.data.kind))"
    else empty end' <<<"$resp")
done
