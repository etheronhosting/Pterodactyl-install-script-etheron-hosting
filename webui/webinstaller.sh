#!/bin/bash

set -e -o pipefail

# Etheron Pterodactyl-installer
#
# Copyright (C) 2026 Etheron Hosting
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
#
# Niet verbonden aan het officiële Pterodactyl-project.

# Start, controleert en ruimt de webinstaller op: een tijdelijke webwizard op
# deze server (webui/server.py), die als systemd-service draait zodat hij het
# sluiten van het SSH-venster overleeft.
#
# Gebruik:
#   webui/webinstaller.sh start               webinstaller starten
#   webui/webinstaller.sh dns <domeinnaam>    DNS-controle voor de wizard
#   webui/webinstaller.sh cleanup <werkmap>   opruimen (doet de server zelf bij afsluiten)

# shellcheck source=../lib/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/lib.sh"
require_root
detect_os

UNIT="etheron-webinstaller"
WEB_PORT="${ETHERON_WEB_PORT:-8443}"
WORK_PREFIX="/tmp/etheron-webinstaller."

# Adres voor de link: bij voorkeur het publieke IPv4-adres.
server_address() {
  local address=""
  address=$(public_addresses | grep -v ':' | head -n1) || true
  [ -n "$address" ] || address=$(local_addresses | grep -v ':' | head -n1) || true
  [ -n "$address" ] || address=$(public_addresses | head -n1) || true
  [ -n "$address" ] || address=$(local_addresses | head -n1) || true
  echo "$address"
}

port_in_use() {
  ss -ltn 2>/dev/null | awk 'NR > 1 { print $4 }' | grep -qE "[:.]$1\$"
}

# Zet de poort open als er al een firewall actief is. Stond de regel er al,
# dan blijft hij bij het opruimen staan (markering keep-port).
open_web_port() {
  local work_dir="$1"

  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
    if ufw status 2>/dev/null | grep -qE "^$WEB_PORT/tcp[[:space:]]"; then
      touch "$work_dir/keep-port"
    else
      ufw allow "$WEB_PORT/tcp" >/dev/null
    fi
  elif command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    if firewall-cmd --zone=public --permanent --query-port="$WEB_PORT/tcp" >/dev/null 2>&1; then
      touch "$work_dir/keep-port"
    else
      firewall-cmd --zone=public --permanent --add-port="$WEB_PORT/tcp" >/dev/null
      firewall-cmd --zone=public --add-port="$WEB_PORT/tcp" >/dev/null
    fi
  fi
}

close_web_port() {
  if command -v ufw >/dev/null 2>&1; then
    ufw delete allow "$WEB_PORT/tcp" >/dev/null 2>&1 || true
  fi
  if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    firewall-cmd --zone=public --permanent --remove-port="$WEB_PORT/tcp" >/dev/null 2>&1 || true
    firewall-cmd --zone=public --remove-port="$WEB_PORT/tcp" >/dev/null 2>&1 || true
  fi
}

print_instructions() {
  local url="$1" fingerprint="$2"

  print_brake 74
  output "De webinstaller draait. Open deze link in je browser:"
  output ""
  output "  $url"
  output ""
  output "Je browser waarschuwt dat de verbinding niet privé of niet vertrouwd is."
  output "Dat klopt: de installer gebruikt een tijdelijk eigen certificaat. Kies"
  output "'Geavanceerd' en daarna 'Doorgaan naar ...' om verder te gaan."
  output "Vingerafdruk van het certificaat (SHA-256):"
  output "  $fingerprint"
  output ""
  output "Je kunt dit venster nu sluiten; de rest gaat via de browser."
  output "De webinstaller stopt vanzelf na de installatie, of na een uur zonder gebruik."
  output "Zelf stoppen: systemctl stop $UNIT"
  output ""
  output "Laadt de pagina niet? Controleer of poort $WEB_PORT open staat bij je"
  output "hostingprovider (bijvoorbeeld een firewall in het klantenpaneel)."
  print_brake 74
}

start_webinstaller() {
  local work_dir address host san fingerprint token url python

  if systemctl is-active --quiet "$UNIT"; then
    error "De webinstaller draait al. Gebruik de link van toen, of stop hem met: systemctl stop $UNIT"
    exit 1
  fi
  if [[ ! "$WEB_PORT" =~ ^[0-9]+$ ]] || ((WEB_PORT < 1 || WEB_PORT > 65535)); then
    error "Ongeldige poort: $WEB_PORT"
    exit 1
  fi
  if port_in_use "$WEB_PORT"; then
    error "Poort $WEB_PORT is al in gebruik. Kies een andere, bijvoorbeeld: ETHERON_WEB_PORT=9443"
    exit 1
  fi

  output "Webinstaller voorbereiden..."
  ensure_curl
  ensure_command python3 python3 python3
  ensure_command openssl openssl openssl
  python=$(command -v python3)

  work_dir=$(mktemp -d "${WORK_PREFIX}XXXXXX")
  printf '%s\n' "$WEB_PORT" >"$work_dir/port"

  # Eigen kopie van de installer: bij de one-liner verdwijnt de downloadmap
  # zodra dit script klaar is, terwijl de webinstaller blijft draaien.
  mkdir "$work_dir/installer"
  tar -C "$ETHERON_DIR" --exclude=.git -cf - . | tar -C "$work_dir/installer" -xf -

  address=$(server_address)
  if [ -z "$address" ]; then
    error "Kon het IP-adres van deze server niet bepalen."
    rm -rf "$work_dir"
    exit 1
  fi
  host="$address"
  [[ "$address" == *:* ]] && host="[$address]"
  san="IP:$address"

  output "Tijdelijk certificaat maken voor $address..."
  openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 2 \
    -subj "/CN=Etheron webinstaller" -addext "subjectAltName=$san" \
    -keyout "$work_dir/key.pem" -out "$work_dir/cert.pem" >/dev/null 2>&1
  chmod 600 "$work_dir/key.pem"
  fingerprint=$(openssl x509 -in "$work_dir/cert.pem" -noout -fingerprint -sha256 | cut -d= -f2)

  token=$(gen_passwd 32)
  (umask 077 && printf '%s\n' "$token" >"$work_dir/token")

  open_web_port "$work_dir"

  systemd-run --unit="$UNIT" --collect --quiet \
    --setenv=HOME=/root --setenv=LANG=C.UTF-8 --setenv=PYTHONIOENCODING=utf-8 \
    --setenv=ETHERON_VERSION="$ETHERON_VERSION" \
    "$python" "$work_dir/installer/webui/server.py" \
    --work-dir "$work_dir" --port "$WEB_PORT" --address "$address" --firewall-name "$(firewall_name)"

  for _ in {1..20}; do
    if port_in_use "$WEB_PORT"; then
      break
    fi
    if ! systemctl is-active --quiet "$UNIT"; then
      break
    fi
    sleep 0.5
  done
  if ! port_in_use "$WEB_PORT"; then
    error "De webinstaller is niet gestart. Laatste meldingen:"
    journalctl -u "$UNIT" -n 20 --no-pager -o cat || true
    systemctl stop "$UNIT" >/dev/null 2>&1 || true
    if [ -d "$work_dir" ]; then
      cleanup_webinstaller "$work_dir"
    fi
    exit 1
  fi

  url="https://$host:$WEB_PORT/?token=$token"
  # De link bevat het token: liever naar de terminal dan naar het logbestand.
  { print_instructions "$url" "$fingerprint" >/dev/tty; } 2>/dev/null || print_instructions "$url" "$fingerprint"
}

cleanup_webinstaller() {
  local work_dir="$1"

  # Veiligheidsgrens voor rm -rf: alleen een werkmap van de webinstaller.
  if [[ "$work_dir" != "$WORK_PREFIX"* || "$work_dir" == *..* || ! -d "$work_dir" ]]; then
    error "Ongeldige werkmap: $work_dir"
    exit 1
  fi
  WEB_PORT=$(cat "$work_dir/port" 2>/dev/null || echo "$WEB_PORT")
  if [ ! -f "$work_dir/keep-port" ]; then
    close_web_port
  fi
  rm -rf "$work_dir"
}

case "${1:-}" in
start)
  start_webinstaller
  ;;
dns)
  if ! valid_domain "${2:-}"; then
    error "Vul een domeinnaam in (geen IP-adres)."
    exit 1
  fi
  verify_dns "$2"
  ;;
cleanup)
  cleanup_webinstaller "${2:-}"
  ;;
*)
  echo "Gebruik: $0 start | dns <domeinnaam> | cleanup <werkmap>" >&2
  exit 1
  ;;
esac
