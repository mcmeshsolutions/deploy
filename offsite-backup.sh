#!/usr/bin/env bash
# Mirrors a `gatewayd backup` directory to any rclone remote. Blobs are immutable so they are copied once and never
# deleted offsite; the database snapshot is kept per day and the newest KEEP_DB_DAYS days stay.
# usage: offsite-backup.sh <backup-dir> <rclone-remote:path>   (env: KEEP_DB_DAYS=14, RCLONE=rclone)
set -euo pipefail
src="${1:?backup dir}"
dst="${2:?rclone destination}"
keep="${KEEP_DB_DAYS:-14}"
rc="${RCLONE:-rclone}"
[[ -f $src/mcmesh.db ]] || { echo "no $src/mcmesh.db, run gatewayd backup first" >&2; exit 1; }
"$rc" copy "$src/cas" "$dst/cas" --ignore-existing --transfers 8 --checksum
day="$(date -u +%F)"
"$rc" copyto "$src/mcmesh.db" "$dst/db/mcmesh-$day.db" --checksum
"$rc" lsf "$dst/db" --files-only | sort | head -n "-$keep" | while read -r old; do
  "$rc" deletefile "$dst/db/$old"
done
echo "offsite ok: $dst ($day)"
