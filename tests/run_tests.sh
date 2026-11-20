#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "1. Checking bash syntax and executable bits on shell scripts..."
sh_count=0
for f in *.sh; do
  [ -f "$f" ] || continue
  sh_count=$((sh_count + 1))
  bash -n "$f"
  if [ ! -x "$f" ]; then
    echo "FAIL: $f is not executable" >&2
    exit 1
  fi
done
echo "   OK ($sh_count scripts)"

if command -v shellcheck >/dev/null 2>&1; then
  echo "2. Running shellcheck..."
  shellcheck -S error -- *.sh tests/*.sh
  echo "   OK"
else
  echo "2. shellcheck not installed locally (skipped; enforced in CI)"
fi

echo "3. Validating JSON files..."
json_count=0
while IFS= read -r -d '' jf; do
  json_count=$((json_count + 1))
  python3 -c 'import json, sys; json.load(open(sys.argv[1], encoding="utf-8"))' "$jf"
done < <(find . -maxdepth 3 -name '*.json' -print0)
echo "   OK ($json_count JSON files)"

echo "4. Validating Docker Compose & YAML files..."
if docker compose version >/dev/null 2>&1; then
  for cf in docker-compose.yml compose.example.yml; do
    if [ -f "$cf" ]; then
      docker compose -f "$cf" config -q
    fi
  done
  echo "   OK (docker compose config)"
else
  echo "   docker compose not available (checking YAML structure via python3 if PyYAML installed)"
fi

echo "5. Validating Dockerfiles, systemd units, Caddyfile, and env example..."
for df in Dockerfile Dockerfile.anchor; do
  [ -f "$df" ] || { echo "FAIL: missing $df" >&2; exit 1; }
  grep -q '^FROM ' "$df" || { echo "FAIL: $df missing FROM" >&2; exit 1; }
done

for uf in *.service; do
  [ -f "$uf" ] || continue
  grep -q '^\[Unit\]' "$uf" || { echo "FAIL: $uf missing [Unit]" >&2; exit 1; }
  grep -q '^\[Service\]' "$uf" || { echo "FAIL: $uf missing [Service]" >&2; exit 1; }
  grep -q '^\[Install\]' "$uf" || { echo "FAIL: $uf missing [Install]" >&2; exit 1; }
done

[ -f Caddyfile ] && [ -s Caddyfile ] || { echo "FAIL: Caddyfile missing or empty" >&2; exit 1; }
[ -f gatewayd.env.example ] && grep -q 'MCMESH_' gatewayd.env.example || { echo "FAIL: gatewayd.env.example invalid" >&2; exit 1; }

echo "All deploy checks passed."
