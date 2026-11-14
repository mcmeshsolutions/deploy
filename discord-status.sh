#!/usr/bin/env bash
# Keeps one live status message in a Discord channel: who hosts the world, how many players, how loaded the host is.
# It posts the message once through a webhook, remembers its id in STATE_FILE and edits it every INTERVAL seconds.
# Needs bash, curl, jq and a member token. No mentions are possible, and nothing is posted when nothing changed.
#   GATEWAY=https://gw.example.org WORLD=w1 TOKEN=... DISCORD_WEBHOOK=https://discord.com/api/webhooks/ID/SECRET ./discord-status.sh
set -uo pipefail
: "${GATEWAY:?}" "${WORLD:?}" "${TOKEN:?}" "${DISCORD_WEBHOOK:?}"
INTERVAL="${INTERVAL:-60}"
STATE_FILE="${STATE_FILE:-$HOME/.mcmesh-discord-status-$WORLD}"
msg_id="$(cat "$STATE_FILE" 2>/dev/null || true)"
last=""

render() {
  jq -nc --argjson w "$1" '
    ($w.state // "UNKNOWN") as $st
    | ($w.host // null) as $h
    | {
        allowed_mentions: {parse: []},
        embeds: [{
          title: $w.name,
          color: (if $h then 3066993 elif $st == "IDLE" then 9807270 else 15105570 end),
          fields: [
            {name: "State", value: (if $h then "Hosted" elif $st == "IDLE" then "Idle, nobody is hosting" else $st end), inline: true},
            {name: "Host", value: ($h // "nobody"), inline: true},
            {name: "Players", value: (($w.host_players // "unknown") | tostring), inline: true},
            {name: "Host load", value: (if $w.host_load == null then "unknown" else (["fine","busy","struggling","overloaded"][$w.host_load] // "unknown") end), inline: true},
            {name: "Minecraft", value: ($w.mc_version // "?"), inline: true}
          ]
        }]
      }'
}

while true; do
  world="$(curl -fsS -H "Authorization: Bearer $TOKEN" "$GATEWAY/v1/worlds" | jq -c --arg id "$WORLD" '.worlds[] | select(.id == $id)' 2>/dev/null)"
  if [[ -n $world ]]; then
    body="$(render "$world")"
    if [[ $body != "$last" ]]; then
      if [[ -z $msg_id ]]; then
        resp="$(curl -fsS -H 'content-type: application/json' -d "$body" "$DISCORD_WEBHOOK?wait=true")" && msg_id="$(jq -r .id <<<"$resp")" && printf '%s' "$msg_id" > "$STATE_FILE" && last="$body"
      elif curl -fsS -X PATCH -H 'content-type: application/json' -d "$body" "$DISCORD_WEBHOOK/messages/$msg_id" >/dev/null; then
        last="$body"
      else
        # the message was deleted or the webhook changed: start a new one next round
        msg_id=""
        rm -f "$STATE_FILE"
      fi
    fi
  fi
  sleep "$INTERVAL"
done
