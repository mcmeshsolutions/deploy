#!/usr/bin/env bash
# 1-Command Headless Anchor Runner Installer for mcmesh
# Sets up a dedicated Minecraft anchor node that automatically idles on standby
# and hosts shared worlds when no player machine is online.
set -euo pipefail

GATEWAY=""
WORLD=""
TOKEN=""
RELAY=""
DIR="/srv/mcmesh-anchor"
USER="mcmesh-anchor"

usage() {
    echo "Usage: $0 --gateway <url> --world <world-id> --token <token> [--relay <host>] [--dir <path>]"
    echo "Example: curl -fsSL https://mcmesh.dev/anchor-install.sh | bash -s -- --gateway https://mesh.example.com --world world-xyz --token dev-token-123"
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --gateway) GATEWAY="$2"; shift 2 ;;
        --world) WORLD="$2"; shift 2 ;;
        --token) TOKEN="$2"; shift 2 ;;
        --relay) RELAY="$2"; shift 2 ;;
        --dir) DIR="$2"; shift 2 ;;
        -h|--help) usage ;;
        *) echo "Unknown parameter: $1"; usage ;;
    esac
done

if [[ -z "$GATEWAY" || -z "$WORLD" || -z "$TOKEN" ]]; then
    echo "Error: --gateway, --world, and --token are required."
    usage
fi

if [[ -z "$RELAY" ]]; then
    # default relay host to gateway hostname
    RELAY=$(echo "$GATEWAY" | sed -e 's|^[^/]*//||' -e 's|/.*$||' -e 's|:.*$||')
fi

if [[ $EUID -ne 0 ]]; then
    echo "Error: This installer must be run as root (or with sudo)."
    exit 1
fi

echo "=== Installing mcmesh Headless Anchor Node ==="
echo "Gateway: $GATEWAY"
echo "Relay:   $RELAY"
echo "World:   $WORLD"
echo "Target:  $DIR"

# 1. Install Java 21 if missing
if ! command -v java >/dev/null 2>&1 || ! java -version 2>&1 | grep -q 'version "21'; then
    echo "Installing OpenJDK 21..."
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -y && apt-get install -y openjdk-21-jre-headless curl jq
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y java-21-openjdk-headless curl jq
    elif command -v pacman >/dev/null 2>&1; then
        pacman -Sy --noconfirm jre21-openjdk-headless curl jq
    elif command -v apk >/dev/null 2>&1; then
        apk add --no-cache openjdk21-jre-headless curl jq bash
    else
        echo "Warning: Package manager not recognized. Please ensure Java 21 is installed."
    fi
fi

# 2. Setup user and working directory
if ! id -u "$USER" >/dev/null 2>&1; then
    useradd --system --no-create-home --home-dir "$DIR" --shell /usr/sbin/nologin "$USER"
fi

mkdir -p "$DIR/config/mcmesh"
chown -R "$USER:$USER" "$DIR"

# 3. Create run script and initial configs
cat << 'RUNEOF' > "$DIR/run.sh"
#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"
# If server jar exists, run it; otherwise idle until provisioned
if [[ -f "server.jar" ]]; then
    exec java -Xms2G -Xmx4G -jar server.jar nogui
else
    echo "mcmesh anchor: waiting for server pack or world hydration..."
    sleep 10
    exit 0
fi
RUNEOF
chmod +x "$DIR/run.sh"

cat << CONFEOF > "$DIR/config/mcmesh/mcmesh-server.toml"
packId = "default"
apiUrl = "${GATEWAY}"
relayHost = "${RELAY}"
relayPort = 25571
world = "${WORLD}"
token = "${TOKEN}"
anchorStandby = true
anchorWakeOnJoin = true
anchorIdleMinutes = 10
guestWarmSync = true
CONFEOF

# 4. Install systemd service
cat << SERVICEEOF > /etc/systemd/system/mcmesh-anchor.service
[Unit]
Description=mcmesh anchor node (dedicated standby server)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=${DIR}
ExecStart=${DIR}/run.sh
Restart=always
RestartSec=5
User=${USER}
SuccessExitStatus=0 143
NoNewPrivileges=yes
ProtectSystem=strict
ReadWritePaths=${DIR}
ProtectHome=yes
PrivateTmp=yes

[Install]
WantedBy=multi-user.target
SERVICEEOF

systemctl daemon-reload
systemctl enable mcmesh-anchor.service
systemctl restart mcmesh-anchor.service

echo "=== mcmesh anchor installed successfully! ==="
echo "Check status with: systemctl status mcmesh-anchor"
echo "View logs with:   journalctl -u mcmesh-anchor -f"
