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

# Koppelt de Wings op deze server aan een panel: maakt (zo nodig) een locatie
# aan, daarna een node met poorten voor gameservers, zet de configuratie van
# Wings neer en start Wings.
#
#  - Panel op deze server: via de artisan-commando's van het panel.
#  - Panel op een andere server: via de Application API (PANEL_URL en
#    PANEL_API_KEY met Read & Write op Locations, Nodes en Allocations).
#
# Met --controleren worden alleen de instellingen gecontroleerd.
# Gebruik: installers/node.sh <instellingenbestand> [--controleren]

# shellcheck source=../lib/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/lib.sh"
require_root
detect_os

CONFIG_FILE="${1:?Gebruik: installers/node.sh <instellingenbestand> [--controleren]}"
CHECK_ONLY=false
[ "${2:-}" == "--controleren" ] && CHECK_ONLY=true
load_config "$CONFIG_FILE" || exit 1

# ---------------- Instellingen ---------------- #

NODE_NAME="${NODE_NAME:-$(hostname -s)}"
NODE_LOCATION="${NODE_LOCATION:-nl}"
NODE_PORTS="${NODE_PORTS:-25565-25600}"
NODE_FQDN="${NODE_FQDN%.}"
PANEL_URL="${PANEL_URL%/}"
PANEL_API_KEY="${PANEL_API_KEY:-}"

WINGS_CONFIG="/etc/pterodactyl/config.yml"
DAEMON_BASE="/var/lib/pterodactyl/volumes"

WEB_USER="www-data"
case "$OS" in
rocky | almalinux) WEB_USER="nginx" ;;
esac

validate_settings() {
  check_setting NODE_NAME valid_node_name "letters, cijfers, spaties, -, _ en ., maximaal 100 tekens"
  check_setting NODE_LOCATION valid_location_short "korte naam zoals nl of ams1: letters, cijfers, -, _ en ."
  check_setting NODE_PORTS valid_port_range "één poort of een reeks zoals 25565-25600, tussen 1025 en 65535, maximaal 1000 poorten"
  if [ -n "$NODE_FQDN" ]; then
    check_setting NODE_FQDN valid_hostname "domeinnaam of IP-adres van deze node"
  fi
  if [ -n "$PANEL_URL$PANEL_API_KEY" ]; then
    check_setting PANEL_URL valid_panel_url "adres van het panel, zoals https://panel.voorbeeld.nl"
    check_setting PANEL_API_KEY valid_api_key "Application API-sleutel uit het panel, begint met ptla_"
  fi

  if [ "$CONFIG_ERRORS" -gt 0 ]; then
    error "Het instellingenbestand bevat $CONFIG_ERRORS fout(en). Er is niets gekoppeld."
    exit 1
  fi
}

# ------------------ Hulpjes ------------------ #

# Geheugen en vrije schijfruimte in MB voor de node.
memory_mb() {
  awk '/^MemTotal:/ { print int($2 / 1024) }' /proc/meminfo
}

disk_mb() {
  mkdir -p "$DAEMON_BASE"
  df -Pm "$DAEMON_BASE" | awk 'NR == 2 { print $4 }'
}

port_start() { echo "${NODE_PORTS%-*}"; }
port_end() { echo "${NODE_PORTS#*-}"; }

# Zet de poorten voor gameservers open als er een firewall actief is (TCP en UDP).
open_game_ports() {
  local start end
  start=$(port_start)
  end=$(port_end)

  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
    ufw allow "$start:$end/tcp" >/dev/null
    ufw allow "$start:$end/udp" >/dev/null
    output "Poorten $NODE_PORTS (TCP en UDP) opengezet in UFW"
  elif command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    firewall-cmd --zone=public --permanent --add-port="$start-$end/tcp" --add-port="$start-$end/udp" >/dev/null
    firewall-cmd --reload >/dev/null
    output "Poorten $NODE_PORTS (TCP en UDP) opengezet in firewalld"
  fi
}

start_wings() {
  output "Wings starten..."
  chmod 600 "$WINGS_CONFIG"
  systemctl enable wings >/dev/null 2>&1
  systemctl restart wings
  sleep 5
  if ! systemctl is-active --quiet wings; then
    error "Wings start niet. Laatste meldingen:"
    journalctl -u wings -n 15 --no-pager -o cat || true
    exit 1
  fi
  success "Wings draait."
}

# ---------------- Panel op deze server ---------------- #

artisan() {
  runuser -u "$WEB_USER" -- "$PHP_BIN" "$PANEL_DIR/artisan" "$@" --no-interaction
}

panel_database() {
  sed -n 's/^DB_DATABASE=//p' "$PANEL_DIR/.env" | tr -d "\"'"
}

link_local() {
  local database location_id node_id result ip values port

  database=$(panel_database)
  if ! valid_database_identifier "$database"; then
    error "Kon de database van het panel niet vinden in $PANEL_DIR/.env."
    exit 1
  fi
  check_database_connection

  location_id=$(mariadb -u root -N -e "SELECT id FROM \`$database\`.locations WHERE short = '$NODE_LOCATION';")
  if [ -n "$location_id" ]; then
    output "Bestaande locatie '$NODE_LOCATION' gebruiken."
  else
    output "Locatie '$NODE_LOCATION' aanmaken..."
    result=$(artisan p:location:make --short="$NODE_LOCATION" --long="$NODE_LOCATION")
    location_id=$(grep -oiE 'id of [0-9]+' <<<"$result" | grep -oE '[0-9]+' | tail -n1) || true
  fi
  if [ -z "$location_id" ]; then
    error "Kon de locatie niet aanmaken: $result"
    exit 1
  fi

  output "Node '$NODE_NAME' aanmaken ($NODE_SCHEME://$NODE_FQDN)..."
  result=$(artisan p:node:make \
    --name="$NODE_NAME" \
    --description="Aangemaakt door de Etheron-installer" \
    --locationId="$location_id" \
    --fqdn="$NODE_FQDN" \
    --public=1 \
    --scheme="$NODE_SCHEME" \
    --proxy=0 \
    --maintenance=0 \
    --maxMemory="$(memory_mb)" \
    --overallocateMemory=0 \
    --maxDisk="$(disk_mb)" \
    --overallocateDisk=0 \
    --uploadSize=100 \
    --daemonListeningPort=8080 \
    --daemonSFTPPort=2022 \
    --daemonBase="$DAEMON_BASE")
  node_id=$(grep -oiE 'id of [0-9]+' <<<"$result" | grep -oE '[0-9]+' | tail -n1) || true
  if [ -z "$node_id" ]; then
    error "Kon de node niet aanmaken: $result"
    exit 1
  fi

  ip="$ALLOCATION_IP"
  if [ -n "$ip" ]; then
    output "Poorten $NODE_PORTS toevoegen op $ip..."
    values=""
    for ((port = $(port_start); port <= $(port_end); port++)); do
      values+="${values:+,}($node_id, '$ip', $port, NOW(), NOW())"
    done
    mariadb -u root -e "INSERT IGNORE INTO \`$database\`.allocations (node_id, ip, port, created_at, updated_at) VALUES $values;"
  fi

  output "Configuratie van Wings schrijven..."
  (umask 077 && artisan p:node:configuration "$node_id" --format=yaml >"$WINGS_CONFIG")
  NODE_ID="$node_id"
}

# ---------------- Panel op een andere server ---------------- #

API_HEADERS=""
API_BODY=""
API_CODE=""

# Gebruik: api_call METHODE pad [json]. Zet API_CODE en API_BODY.
api_call() {
  local args=(-sS -X "$1" -H @"$API_HEADERS" -o "$WORK/body" -w '%{http_code}')
  if [ -n "${3:-}" ]; then
    args+=(--data "$3")
  fi
  API_CODE=$(curl "${args[@]}" "$PANEL_URL/api/application$2" 2>/dev/null) || API_CODE="000"
  API_BODY=$(cat "$WORK/body" 2>/dev/null || true)
}

# Stopt met een begrijpelijke melding als de laatste API-aanroep mislukte.
api_check() {
  local details
  case "$API_CODE" in
  2??) return 0 ;;
  000) error "Het panel is niet bereikbaar op $PANEL_URL. Controleer het adres en of het panel online is." ;;
  401 | 403) error "De API-sleutel is ongeldig of mist rechten. Geef de sleutel Read & Write op Locations, Nodes en Allocations." ;;
  404) error "Het panel gaf 'niet gevonden' terug. Controleer of $PANEL_URL echt het adres van je panel is." ;;
  *)
    details=$(jq -r '[.errors[]?.detail] | join(" ")' <<<"$API_BODY" 2>/dev/null || true)
    error "$1 is mislukt (HTTP $API_CODE). ${details}"
    ;;
  esac
  exit 1
}

link_remote() {
  local location_id node_id json

  ensure_command jq jq jq
  WORK=$(mktemp -d)
  trap 'rm -rf "$WORK"' EXIT
  API_HEADERS="$WORK/headers"
  (umask 077 && printf 'Authorization: Bearer %s\nAccept: application/vnd.pterodactyl.v1+json\nContent-Type: application/json\n' \
    "$PANEL_API_KEY" >"$API_HEADERS")

  output "Verbinding maken met het panel op $PANEL_URL..."
  api_call GET "/locations?filter%5Bshort%5D=$NODE_LOCATION&per_page=100"
  api_check "Locaties opvragen"
  location_id=$(jq -r --arg short "$NODE_LOCATION" \
    '[.data[].attributes | select(.short == $short) | .id][0] // empty' <<<"$API_BODY")

  if [ -n "$location_id" ]; then
    output "Bestaande locatie '$NODE_LOCATION' gebruiken."
  else
    output "Locatie '$NODE_LOCATION' aanmaken..."
    json=$(jq -n --arg short "$NODE_LOCATION" '{short: $short, long: $short}')
    api_call POST /locations "$json"
    api_check "Locatie aanmaken"
    location_id=$(jq -r '.attributes.id' <<<"$API_BODY")
  fi

  output "Node '$NODE_NAME' aanmaken ($NODE_SCHEME://$NODE_FQDN)..."
  json=$(jq -n \
    --arg name "$NODE_NAME" --arg fqdn "$NODE_FQDN" --arg scheme "$NODE_SCHEME" --arg base "$DAEMON_BASE" \
    --argjson location "$location_id" --argjson memory "$(memory_mb)" --argjson disk "$(disk_mb)" \
    '{name: $name, description: "Aangemaakt door de Etheron-installer", location_id: $location,
      fqdn: $fqdn, scheme: $scheme, public: true, behind_proxy: false, maintenance_mode: false,
      memory: $memory, memory_overallocate: 0, disk: $disk, disk_overallocate: 0,
      upload_size: 100, daemon_listen: 8080, daemon_sftp: 2022, daemon_base: $base}')
  api_call POST /nodes "$json"
  api_check "Node aanmaken"
  node_id=$(jq -r '.attributes.id' <<<"$API_BODY")

  if [ -n "$ALLOCATION_IP" ]; then
    output "Poorten $NODE_PORTS toevoegen op $ALLOCATION_IP..."
    json=$(jq -n --arg ip "$ALLOCATION_IP" --arg ports "$NODE_PORTS" '{ip: $ip, ports: [$ports]}')
    api_call POST "/nodes/$node_id/allocations" "$json"
    api_check "Poorten toevoegen"
  fi

  output "Configuratie van Wings ophalen..."
  wings configure --panel-url "$PANEL_URL" --token "$PANEL_API_KEY" --node "$node_id" --config-path "$WINGS_CONFIG"
  NODE_ID="$node_id"
}

# ------------------ Afronding ------------------ #

goodbye() {
  print_brake 70
  output "Node gekoppeld"
  output ""
  output "Node:      $NODE_NAME (id $NODE_ID) in locatie $NODE_LOCATION"
  output "Adres:     $NODE_SCHEME://$NODE_FQDN:8080"
  if [ -n "$ALLOCATION_IP" ]; then
    output "Poorten:   $NODE_PORTS op $ALLOCATION_IP"
  fi
  output ""
  output "In het panel staat de node onder Admin > Nodes; het hartje wordt binnen een minuut groen."
  print_brake 70
}

perform_link() {
  validate_settings

  if [ "$CHECK_ONLY" == true ]; then
    output "Instellingen voor de node zijn in orde."
    exit 0
  fi

  if [ ! -x /usr/local/bin/wings ]; then
    error "Wings is nog niet geïnstalleerd op deze server."
    exit 1
  fi
  if [ -s "$WINGS_CONFIG" ]; then
    error "Wings is al gekoppeld ($WINGS_CONFIG bestaat). Verwijder dat bestand als je opnieuw wilt koppelen."
    exit 1
  fi
  if [ -z "$PANEL_URL" ] && [ ! -f "$PANEL_DIR/artisan" ]; then
    error "Er staat geen panel op deze server. Vul het adres van je panel en een API-sleutel in."
    exit 1
  fi

  ALLOCATION_IP=$(server_address | grep -v ':' || true)
  # Zonder NODE_FQDN: het domein met certificaat uit dezelfde installatie, anders het IP-adres.
  if [ -z "$NODE_FQDN" ] && [ -n "${FQDN:-}" ] && [ -f "/etc/letsencrypt/live/${FQDN%.}/fullchain.pem" ]; then
    NODE_FQDN="${FQDN%.}"
  fi
  [ -n "$NODE_FQDN" ] || NODE_FQDN="${ALLOCATION_IP:-$(server_address)}"
  if [ -z "$ALLOCATION_IP" ]; then
    warning "Geen IPv4-adres gevonden; poorten voor gameservers voeg je zelf toe in het panel."
  fi

  # HTTPS alleen als er een certificaat voor dit domein op de server staat.
  NODE_SCHEME="http"
  if valid_domain "$NODE_FQDN" && [ -f "/etc/letsencrypt/live/$NODE_FQDN/fullchain.pem" ]; then
    NODE_SCHEME="https"
  elif [[ "$PANEL_URL" == https://* ]] || grep -q '^APP_URL=https://' "$PANEL_DIR/.env" 2>/dev/null; then
    warning "Je panel gebruikt HTTPS, deze node niet. Browsers blokkeren dan de console van gameservers. Gebruik Let's Encrypt voor de node om dat op te lossen."
  fi

  if [ -n "$PANEL_URL" ]; then
    link_remote
  else
    link_local
  fi

  if [ -n "$ALLOCATION_IP" ]; then
    open_game_ports
  fi
  start_wings
  goodbye
}

perform_link
