# VPS Psiphon Installer

Installs a Psiphon SOCKS5 container on Ubuntu 22.04/24.04 and a systemd watchdog.

## What it does

- Runs `swarupsengupta2007/psiphon:latest` as `vps-psiphon`.
- Publishes SOCKS5 TCP port 1080 **only on the Docker bridge gateway** (normally `172.17.0.1`).
- Does not publish the HTTP proxy port 8080.
- Creates `/opt/vps-psiphon/config/psiphon.config`.
- Installs a watchdog that checks the SOCKS5 proxy via `ipinfo.io` and checks access to `gemini.google.com`.
- Runs the watchdog every 3 minutes. After 3 consecutive failed checks, it restarts the Psiphon container and verifies recovery.

The watchdog is for availability/recovery. It does not rotate exit IPs or guarantee access to third-party services.

## Quick install

On a fresh Ubuntu server, download/extract this repository, then run:

```bash
chmod +x install.sh
sudo ./install.sh
```

After publishing this repository publicly on GitHub, install from a new server with:

```bash
apt-get update && apt-get install -y git && git clone https://github.com/OWNER/vps-psiphon-installer.git && cd vps-psiphon-installer && bash install.sh
```

Replace `OWNER` with your GitHub username. This single command installs Git if needed, downloads the complete repository (including watchdog and systemd files), and starts the installer.

## Region

Default requested region is `DE`. Override it before running:

```bash
PSIPHON_REGION=DE bash install.sh
```

Use a two-letter country code. The actual Psiphon exit region/IP is determined by Psiphon's available network and should be verified after startup.

## Verify

```bash
docker ps --filter name=vps-psiphon
docker logs --tail 100 vps-psiphon
systemctl status vps-psiphon-watchdog.timer --no-pager
tail -n 30 /var/log/vps-psiphon-watchdog.log

GATEWAY="$(docker network inspect bridge --format '{{(index .IPAM.Config 0).Gateway}}')"
curl -sS --max-time 30 --socks5-hostname "${GATEWAY}:1080" https://ipinfo.io/json
curl -sS -o /dev/null -w 'HTTP: %{http_code}\n' --max-time 30 \
  --socks5-hostname "${GATEWAY}:1080" https://gemini.google.com/
```

## Files and services

- Configuration: `/opt/vps-psiphon/config/psiphon.config`
- Watchdog: `/usr/local/bin/vps-psiphon-watchdog`
- Watchdog log: `/var/log/vps-psiphon-watchdog.log`
- systemd service: `vps-psiphon-watchdog.service`
- systemd timer: `vps-psiphon-watchdog.timer`

## Important notes

- The installer removes and recreates an existing container named `vps-psiphon`. Back up its configuration first if re-running on a server where it is already in use.
- Existing config is preserved if the config file already exists.
- Do not expose port 1080 publicly. The installer binds it to the Docker bridge gateway address.
- The installer downloads Docker using Docker's official convenience script if Docker is not already installed. Review that script if your environment requires a stricter installation process.
- The Psiphon image is a third-party image, not an official OpenAI or Psiphon Inc. image. Review and pin a trusted image digest before production use.
