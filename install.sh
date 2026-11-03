#!/usr/bin/env bash
set -Eeuo pipefail

# Psiphon SOCKS5 installer for Ubuntu 22.04/24.04.
# SOCKS5 is bound only to the Docker bridge gateway, not the public interface.

APP="vps-psiphon"
IMAGE="swarupsengupta2007/psiphon:latest"
CONFIG_DIR="/opt/vps-psiphon/config"
CONFIG_FILE="${CONFIG_DIR}/psiphon.config"
WATCHDOG="/usr/local/bin/vps-psiphon-watchdog"
LOG="/var/log/vps-psiphon-watchdog.log"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo bash install.sh"
  exit 1
fi

if [[ ! -r /etc/os-release ]]; then
  echo "Cannot identify operating system."
  exit 1
fi
. /etc/os-release
if [[ "${ID:-}" != "ubuntu" ]]; then
  echo "This installer is intended for Ubuntu. Detected: ${PRETTY_NAME:-unknown}"
  exit 1
fi

REGION="${PSIPHON_REGION:-DE}"
REGION="$(printf '%s' "$REGION" | tr '[:lower:]' '[:upper:]')"
if [[ ! "$REGION" =~ ^[A-Z]{2}$ ]]; then
  echo "Region must be a two-letter country code, for example DE."
  exit 1
fi

echo "[1/7] Installing required packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y ca-certificates curl jq

if ! command -v docker >/dev/null 2>&1; then
  echo "[2/7] Docker not found. Installing Docker Engine..."
  curl -fsSL https://get.docker.com | sh
else
  echo "[2/7] Docker is already installed."
fi

systemctl enable --now docker

echo "[3/7] Detecting Docker bridge gateway..."
GATEWAY="$(docker network inspect bridge --format '{{(index .IPAM.Config 0).Gateway}}' 2>/dev/null || true)"
if [[ -z "$GATEWAY" || "$GATEWAY" == "<no value>" ]]; then
  echo "Could not determine Docker bridge gateway. Check: docker network inspect bridge"
  exit 1
fi

echo "[4/7] Creating Psiphon configuration..."
mkdir -p "$CONFIG_DIR"
chmod 700 /opt/vps-psiphon "$CONFIG_DIR"

if [[ ! -s "$CONFIG_FILE" ]]; then
  cat > "$CONFIG_FILE" <<EOF
{
  "DeviceRegion": "${REGION}",
  "EgressRegion": "${REGION}",
  "LocalSocksProxyPort": 1080,
  "LocalHttpProxyPort": 8080,
  "ListenInterface": "any"
}
EOF
  chmod 600 "$CONFIG_FILE"
else
  echo "Existing configuration found; preserving it: $CONFIG_FILE"
fi

echo "[5/7] Pulling image and starting container..."
docker pull "$IMAGE"

if docker inspect "$APP" >/dev/null 2>&1; then
  docker rm -f "$APP" >/dev/null
fi

docker run -d \
  --name "$APP" \
  --restart unless-stopped \
  -p "${GATEWAY}:1080:1080/tcp" \
  -e SOCKS_PORT=1080 \
  -e HTTP_PORT=8080 \
  -e DEVICE_REGION="$REGION" \
  -e EGRESS_REGION="$REGION" \
  -v "${CONFIG_DIR}:/config" \
  "$IMAGE"

echo "[6/7] Installing watchdog and systemd timer..."
install -m 0755 "$(dirname "$0")/scripts/watchdog.sh" "$WATCHDOG"
install -m 0644 "$(dirname "$0")/systemd/vps-psiphon-watchdog.service" \
  /etc/systemd/system/vps-psiphon-watchdog.service
install -m 0644 "$(dirname "$0")/systemd/vps-psiphon-watchdog.timer" \
  /etc/systemd/system/vps-psiphon-watchdog.timer
touch "$LOG"
chmod 600 "$LOG"

systemctl daemon-reload
systemctl enable --now vps-psiphon-watchdog.timer

echo "[7/7] Running initial health check..."
sleep 10
if ! "$WATCHDOG"; then
  echo "Initial health check did not pass yet. Check logs:"
  echo "  docker logs --tail 80 $APP"
  echo "  tail -n 40 $LOG"
else
  echo "Initial watchdog check passed."
fi

echo
echo "Installation finished."
echo "Container:       $APP"
echo "Docker gateway:  $GATEWAY"
echo "SOCKS5 endpoint: ${GATEWAY}:1080 (not exposed on public IP)"
echo "Requested region: $REGION"
echo
echo "Useful commands:"
echo "  docker ps --filter name=$APP"
echo "  docker logs -f $APP"
echo "  systemctl status vps-psiphon-watchdog.timer --no-pager"
echo "  tail -f $LOG"
echo
echo "Test SOCKS5:"
echo "  curl -sS --max-time 30 --socks5-hostname ${GATEWAY}:1080 https://ipinfo.io/json"
echo "  curl -sS -o /dev/null -w 'HTTP: %{http_code}\\n' --max-time 30 --socks5-hostname ${GATEWAY}:1080 https://gemini.google.com/"
