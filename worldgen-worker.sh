#!/usr/bin/env bash
# A distributed worldgen worker (board/PROTOCOL.md "Distributed worldgen"): a dedicated server that claims one tile
# from the gateway, generates it, reports it and exits, then starts again on a fresh world.
# One tile per process on purpose: a world that already holds a tile and its frontier generates the next tile next
# to it differently from a fresh world, and two workers only agree when both started from nothing.
#
# SERVER_DIR   a NeoForge server folder with the pack's mods and configs, and an mcmesh-common.toml with apiUrl, a
#              token of a member allowed to host, and the pack's packId. The world folder in it is deleted every round.
# SEED         the world seed, the same as the host's (the claim's profile includes it, so a wrong seed just idles)
# SERVER_CMD   how to start the server, default ./run.sh nogui
# PORT         any free port, default 25570; the worker accepts no players
# JAVA_OPTS    extra JVM flags, for example -Xmx6G
# ONCE=1       stop after one tile instead of looping
# The pack's FML setting `maxThreads = 1` (config/fml.toml) must match the host's, see board/RESEARCH.md 1d.
set -u
: "${SERVER_DIR:?}" "${SEED:?}"
SERVER_CMD="${SERVER_CMD:-./run.sh nogui}"
PORT="${PORT:-25570}"
cd "$SERVER_DIR" || exit 2
while :; do
  rm -rf world
  echo "eula=true" > eula.txt
  # max-tick-time=-1: generating a whole tile is one long job on the server thread's side of the queue
  printf 'server-port=%s\nonline-mode=false\nlevel-seed=%s\nspawn-protection=0\nmax-tick-time=-1\nenable-command-block=false\n' "$PORT" "$SEED" > server.properties
  # shellcheck disable=SC2086
  JAVA_TOOL_OPTIONS="-Dmcmesh.worker=true ${JAVA_OPTS:-}" $SERVER_CMD
  [ -n "${ONCE:-}" ] && break
  sleep 5
done
