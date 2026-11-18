#!/usr/bin/env bash
# MCMesh 1-Command Production Self-Host Wizard
# Sets up gatewayd with Docker Compose, automated Caddy TLS, and prints the admin claim link.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

info() {
    printf "\033[1;34m[mcmesh]\033[0m %s\n" "$*"
}

success() {
    printf "\033[1;32m[mcmesh]\033[0m %s\n" "$*"
}

warn() {
    printf "\033[1;33m[mcmesh:warn]\033[0m %s\n" "$*"
}

error() {
    printf "\033[1;31m[mcmesh:error]\033[0m %s\n" "$*" >&2
    exit 1
}

# 1. Verify Docker & Compose
if ! command -v docker >/dev/null 2>&1; then
    error "Docker is not installed or not in PATH. Please install Docker first: https://docs.docker.com/engine/install/"
fi

COMPOSE_CMD=""
if docker compose version >/dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
    COMPOSE_CMD="docker-compose"
else
    error "Docker Compose (v2 or v1) is not installed. Please install Docker Compose: https://docs.docker.com/compose/install/"
fi

info "Detected container engine: Docker with $COMPOSE_CMD"

# 2. Random secret generator
gen_secret() {
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -hex 16
    elif [ -r /dev/urandom ]; then
        LC_ALL=C tr -dc 'a-f0-9' < /dev/urandom | head -c 32 || true
    else
        date +%s%N | sha256sum | head -c 32
    fi
}

# 3. Detect or prompt for domain and configuration
ENV_FILE="$SCRIPT_DIR/.env"
if [ ! -f "$ENV_FILE" ]; then
    info "Generating initial production configuration..."

    DEFAULT_DOMAIN="${DOMAIN:-localhost}"
    if [ -t 0 ] && [ -z "${DOMAIN:-}" ]; then
        printf "Enter your gateway domain (FQDN e.g. mesh.example.com or localhost) [%s]: " "$DEFAULT_DOMAIN"
        read -r USER_DOMAIN
        DOMAIN="${USER_DOMAIN:-$DEFAULT_DOMAIN}"
    else
        DOMAIN="$DEFAULT_DOMAIN"
    fi

    DEFAULT_EMAIL="${TLS_EMAIL:-}"
    if [ "$DOMAIN" != "localhost" ] && [ -z "$DEFAULT_EMAIL" ] && [ -t 0 ]; then
        printf "Enter admin email for Let's Encrypt TLS certificate: "
        read -r USER_EMAIL
        TLS_EMAIL="${USER_EMAIL:-}"
    else
        TLS_EMAIL="${DEFAULT_EMAIL:-}"
    fi

    COMMUNITY_NAME="${MCMESH_COMMUNITY_NAME:-MCMesh Community}"
    PACK_NAME="${MCMESH_PACK_NAME:-MCMesh}"
    METRICS_TOKEN="$(gen_secret)"
    WEBHOOK_SECRET="$(gen_secret)"

    cat > "$ENV_FILE" <<EOF
# MCMesh Self-Host Environment Configuration
DOMAIN=${DOMAIN}
TLS_EMAIL=${TLS_EMAIL}
MCMESH_COMMUNITY_NAME=${COMMUNITY_NAME}
MCMESH_PACK_NAME=${PACK_NAME}
MCMESH_METRICS_TOKEN=${METRICS_TOKEN}
MCMESH_WEBHOOK_SECRET=${WEBHOOK_SECRET}
MCMESH_AUTH=mojang,key
MCMESH_RELAY=all
MCMESH_CREATE=open
MCMESH_STRICT_DATA=0
PORT_MC=25565
PORT_RELAY=9000
PORT_VOICE=24454
EOF
    success "Saved configuration to $ENV_FILE"
else
    info "Using existing configuration from $ENV_FILE"
    # shellcheck disable=SC1090
    set -a; source "$ENV_FILE"; set +a
fi

# 4. Initialize storage volume
info "Initializing gateway storage and database..."
$COMPOSE_CMD run --rm gatewayd init || true

# 5. Start stack
info "Launching MCMesh stack (gatewayd + Caddy)..."
$COMPOSE_CMD up -d

# 6. Wait for service health
info "Waiting for gatewayd to be ready..."
ATTEMPTS=0
MAX_ATTEMPTS=30
HEALTHY=0
while [ $ATTEMPTS -lt $MAX_ATTEMPTS ]; do
    if $COMPOSE_CMD ps gatewayd | grep -qi "healthy\|running"; then
        HEALTHY=1
        break
    fi
    sleep 1
    ATTEMPTS=$((ATTEMPTS + 1))
done

if [ "$HEALTHY" -eq 1 ]; then
    success "MCMesh Gateway is online and healthy!"
else
    warn "Gateway container started but health status is pending. Check logs with: $COMPOSE_CMD logs gatewayd"
fi

# 7. Print summary and admin claim link
SCHEME="https"
if [ "$DOMAIN" = "localhost" ] || [[ "$DOMAIN" =~ ^127\. ]] || [[ "$DOMAIN" =~ ^192\.168\. ]] || [[ "$DOMAIN" =~ ^10\. ]]; then
    SCHEME="http"
fi

BASE_URL="${SCHEME}://${DOMAIN}"
if [ "$SCHEME" = "http" ] && [ "$DOMAIN" = "localhost" ]; then
    BASE_URL="http://localhost:80"
fi

CLAIM_LINK="${BASE_URL}/panel"

cat <<EOF

======================================================================
  MCMesh Gateway: 1-Command Production Self-Host Ready
======================================================================

  Web Panel / Dashboard:
    ${BASE_URL}/panel

  Initial Superadmin Claim:
    ${CLAIM_LINK}
    (The first account registered on a fresh gateway is automatically
     granted full Superadmin privileges.)

  In-Game Connection Address (/meshwizard or Title Screen):
    ${BASE_URL}

  Minecraft Relay Port:
    ${DOMAIN}:25565

  Simple Voice Chat (UDP):
    ${DOMAIN}:24454/udp

  Prometheus Metrics:
    ${BASE_URL}/metrics (Bearer: \${MCMESH_METRICS_TOKEN})

----------------------------------------------------------------------
  Useful Management Commands:
    View Logs:           $COMPOSE_CMD logs -f
    Gateway Status:      $COMPOSE_CMD exec gatewayd gatewayd status
    Set In-Game Admin:   $COMPOSE_CMD exec gatewayd gatewayd set-admin <PlayerName> admin
    Stop Gateway:        $COMPOSE_CMD down
======================================================================

EOF
