#!/usr/bin/env bash
# TuitMate server installer for Ubuntu 22.04 / 24.04 (x86_64). Run as root:
#
#   curl -fsSLO https://github.com/comfysh/tuitgptclone/releases/latest/download/tuitmate-server-install.sh
#   sudo bash tuitmate-server-install.sh
#
# What it does (running it again updates the program and keeps your data):
#   - installs MySQL 8, OpenSSL and curl from Ubuntu's packages,
#   - downloads tuitmate-server from the same GitHub release and checks its SHA-256,
#   - creates the system user "tuitmate", the database "tuitmate" and the MySQL
#     user 'tuitmate'@'localhost' (random password, only this database),
#   - makes the encryption key, a self-signed TLS certificate and the settings in /etc/tuitmate,
#   - installs the systemd service tuitmate-server (HTTPS on port 8443),
#   - prints the connection code for the app.
#
# MySQL itself stays reachable only from the VPS (127.0.0.1); see the guide
# (server/README.md) for the SSH tunnel to look at it from your PC.
set -euo pipefail

REPO="comfysh/tuitgptclone"
BASE_URL="${TUITMATE_RELEASE_URL:-https://github.com/$REPO/releases/latest/download}"
PORT="${TUITMATE_PORT:-8443}"
ETC=/etc/tuitmate
DATA=/var/lib/tuitmate
BIN=/usr/local/bin/tuitmate-server
UNIT=/etc/systemd/system/tuitmate-server.service

say() { printf '\n\033[1m%s\033[0m\n' "$*"; }
die() { printf '\n\033[31mError:\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "run as root: sudo bash $0"
. /etc/os-release 2>/dev/null || true
[ "${ID:-}" = "ubuntu" ] || die "this installer supports Ubuntu 22.04 or newer (found: ${PRETTY_NAME:-unknown})."
[ "$(uname -m)" = "x86_64" ] || die "the server program is built for x86_64 (this VPS: $(uname -m))."

# Test hooks: a local binary instead of the download, and no systemd (containers).
LOCAL_BINARY="${TUITMATE_BINARY:-}"
USE_SYSTEMD=1
[ "${TUITMATE_SKIP_SYSTEMD:-0}" = "1" ] && USE_SYSTEMD=0

say "1/7  Packages (MySQL 8, OpenSSL, curl)"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq mysql-server openssl curl ca-certificates >/dev/null
if [ "$USE_SYSTEMD" = 1 ]; then
  systemctl enable --now mysql >/dev/null
else
  service mysql start >/dev/null 2>&1 || true
fi
mysql --version

say "2/7  The tuitmate-server program"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
if [ -n "$LOCAL_BINARY" ]; then
  cp "$LOCAL_BINARY" "$tmp/tuitmate-server-linux-x64"
else
  curl -fsSL -o "$tmp/tuitmate-server-linux-x64" "$BASE_URL/tuitmate-server-linux-x64"
  curl -fsSL -o "$tmp/SHA256SUMS.txt" "$BASE_URL/SHA256SUMS.txt"
  (cd "$tmp" && grep ' tuitmate-server-linux-x64$' SHA256SUMS.txt | sha256sum -c -) || die "checksum mismatch: download again"
fi
install -m 0755 "$tmp/tuitmate-server-linux-x64" "$BIN"
echo "installed $BIN ($("$BIN" version))"

say "3/7  System user and folders"
id tuitmate >/dev/null 2>&1 || useradd --system --home-dir "$DATA" --shell /usr/sbin/nologin tuitmate
install -d -m 0750 -o root -g tuitmate "$ETC" "$ETC/tls"
install -d -m 0700 -o tuitmate -g tuitmate "$DATA"

say "4/7  Database"
db_password=""
if [ -f "$ETC/server.env" ]; then
  db_password=$(sed -n 's/^DB_PASSWORD=//p' "$ETC/server.env")
fi
[ -n "$db_password" ] || db_password=$(openssl rand -base64 30 | tr -d '/+=\n' | head -c 32)
mysql <<SQL
CREATE DATABASE IF NOT EXISTS tuitmate CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
CREATE USER IF NOT EXISTS 'tuitmate'@'localhost' IDENTIFIED BY '$db_password';
ALTER USER 'tuitmate'@'localhost' IDENTIFIED BY '$db_password';
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, ALTER, INDEX, REFERENCES ON tuitmate.* TO 'tuitmate'@'localhost';
FLUSH PRIVILEGES;
SQL
echo "database 'tuitmate' and user 'tuitmate'@'localhost' are ready"

say "5/7  Key, certificate and settings"
if [ ! -f "$ETC/secret.key" ]; then
  head -c 32 /dev/urandom | base64 > "$ETC/secret.key"
fi
chown root:tuitmate "$ETC/secret.key" && chmod 0640 "$ETC/secret.key"

public_ip="${TUITMATE_PUBLIC_IP:-}"
[ -n "$public_ip" ] || public_ip=$(curl -fsS --max-time 10 https://api.ipify.org 2>/dev/null || true)
[ -n "$public_ip" ] || public_ip=$(hostname -I | awk '{print $1}')
[ -n "$public_ip" ] || die "could not find this VPS's public IP; run again with TUITMATE_PUBLIC_IP=<ip>"

if [ ! -f "$ETC/tls/cert.pem" ]; then
  openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes \
    -keyout "$ETC/tls/key.pem" -out "$ETC/tls/cert.pem" -days 3650 \
    -subj "/CN=tuitmate-server" -addext "subjectAltName=IP:$public_ip" 2>/dev/null
fi
chown root:tuitmate "$ETC/tls/key.pem" "$ETC/tls/cert.pem"
chmod 0640 "$ETC/tls/key.pem" && chmod 0644 "$ETC/tls/cert.pem"

cat > "$ETC/server.env" <<ENV
# TuitMate server settings (written by install.sh; running it again keeps the password).
DB_HOST=127.0.0.1
DB_PORT=3306
DB_NAME=tuitmate
DB_USER=tuitmate
DB_PASSWORD=$db_password
SECRET_KEY_FILE=$ETC/secret.key
TLS_CERT=$ETC/tls/cert.pem
TLS_KEY=$ETC/tls/key.pem
LISTEN_ADDRESS=0.0.0.0
LISTEN_PORT=$PORT
PUBLIC_URL=https://$public_ip:$PORT
DATA_DIR=$DATA
FETCH_MINUTES=5
ENV
chown root:tuitmate "$ETC/server.env" && chmod 0640 "$ETC/server.env"

as_service() { if command -v runuser >/dev/null; then runuser -u tuitmate -- "$@"; else su -s /bin/sh tuitmate -c "$*"; fi; }
as_service "$BIN" init

say "6/7  Service"
if [ "$USE_SYSTEMD" = 1 ]; then
  cat > "$UNIT" <<UNIT
[Unit]
Description=TuitMate server (LMS checks and API for the app)
After=network-online.target mysql.service
Wants=network-online.target
Requires=mysql.service

[Service]
User=tuitmate
Group=tuitmate
ExecStart=$BIN serve
Restart=always
RestartSec=10
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
ReadWritePaths=$DATA
ProtectKernelTunables=true
ProtectControlGroups=true
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
CapabilityBoundingSet=
LockPersonality=true

[Install]
WantedBy=multi-user.target
UNIT
  systemctl daemon-reload
  systemctl enable tuitmate-server >/dev/null
  systemctl restart tuitmate-server
  sleep 2
  systemctl is-active --quiet tuitmate-server || die "the service did not start: journalctl -u tuitmate-server -n 50"
  echo "tuitmate-server is running"
  if command -v ufw >/dev/null && ufw status | grep -q "Status: active"; then
    ufw allow "$PORT/tcp" >/dev/null && echo "firewall (ufw): opened $PORT/tcp"
  fi
else
  echo "(systemd skipped)"
fi

say "7/7  Connection code for the app"
code=$(as_service "$BIN" new-token phone | grep '^tmsrv1\.')

cat <<DONE

Done. In TuitMate: Profile › Sync › TuitMate server › Connect, and paste:

  $code

Keep this code private (it gives access to your LMS data on this server).
More codes: sudo -u tuitmate tuitmate-server new-token <name>

Where things are:
  Database      MySQL 8 on this VPS, 127.0.0.1:3306, database "tuitmate"
                (files in /var/lib/mysql/tuitmate/). Open it: sudo mysql tuitmate
  Settings      $ETC/server.env   (MySQL password for the user 'tuitmate')
  Key           $ETC/secret.key   (encrypts the LMS session in the database)
  API           https://$public_ip:$PORT
  Logs          journalctl -u tuitmate-server -f
  Status        sudo -u tuitmate tuitmate-server status

If your VPS provider has its own firewall, allow TCP $PORT there too.
DONE
