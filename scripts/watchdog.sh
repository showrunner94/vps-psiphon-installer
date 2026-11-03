#!/usr/bin/env bash
set -u

CONTAINER="vps-psiphon"
LOG="/var/log/vps-psiphon-watchdog.log"
STATE="/run/vps-psiphon-failures"
LOCK="/run/lock/vps-psiphon-watchdog.lock"
SOCKS_PORT="1080"
IP_FILE="/run/vps-psiphon-ip.json"

log() {
  printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$LOG"
}

# Prevent overlapping checks.
exec 9>"$LOCK"
if ! flock -n 9; then
  exit 0
fi

if ! command -v docker >/dev/null 2>&1 || ! docker inspect "$CONTAINER" >/dev/null 2>&1; then
  log "ERROR: Docker or container $CONTAINER not found"
  exit 1
fi

GATEWAY="$(docker network inspect bridge --format '{{(index .IPAM.Config 0).Gateway}}' 2>/dev/null || true)"
if [[ -z "$GATEWAY" || "$GATEWAY" == "<no value>" ]]; then
  log "ERROR: cannot determine Docker bridge gateway"
  exit 1
fi
SOCKS="${GATEWAY}:${SOCKS_PORT}"

check_service() {
  curl -fsS --max-time 25 --socks5-hostname "$SOCKS" \
    https://ipinfo.io/json -o "$IP_FILE" &&
  curl -fsS -o /dev/null --max-time 30 --socks5-hostname "$SOCKS" \
    https://gemini.google.com/
}

if check_service; then
  IP="$(jq -r '.ip // "unknown"' "$IP_FILE" 2>/dev/null || echo unknown)"
  COUNTRY="$(jq -r '.country // "unknown"' "$IP_FILE" 2>/dev/null || echo unknown)"
  log "OK: Psiphon SOCKS and Gemini reachable; IP=$IP COUNTRY=$COUNTRY"
  echo 0 > "$STATE"
  exit 0
fi

FAILS="$(cat "$STATE" 2>/dev/null || echo 0)"
[[ "$FAILS" =~ ^[0-9]+$ ]] || FAILS=0
FAILS=$((FAILS + 1))
echo "$FAILS" > "$STATE"
log "WARNING: health check failed $FAILS/3"

if (( FAILS >= 3 )); then
  log "RECOVERY: restarting $CONTAINER"
  if docker restart "$CONTAINER" >/dev/null 2>&1; then
    sleep 35
    if check_service; then
      IP="$(jq -r '.ip // "unknown"' "$IP_FILE" 2>/dev/null || echo unknown)"
      COUNTRY="$(jq -r '.country // "unknown"' "$IP_FILE" 2>/dev/null || echo unknown)"
      log "RECOVERED: SOCKS and Gemini reachable; IP=$IP COUNTRY=$COUNTRY"
      echo 0 > "$STATE"
    else
      log "ERROR: restart completed but health check still fails"
    fi
  else
    log "ERROR: docker restart failed"
  fi
fi
