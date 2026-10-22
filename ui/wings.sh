#!/bin/bash
# De antwoorden worden gezet met printf -v en gelezen via ${!key}; dat ziet ShellCheck niet.
# shellcheck disable=SC2034,SC2153

set -e -o pipefail

# Etheron Pterodactyl-installer
#
# Copyright (C) 2026 Etheron Hosting
# Gebaseerd op pterodactyl-installer, Copyright (C) 2018 - 2026 Vilhelm Prytz
# <vilhelm@prytznet.se> en bijdragers:
# https://github.com/pterodactyl-installer/pterodactyl-installer
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

# Stelt de vragen voor de Wings-installatie en schrijft de antwoorden naar het
# opgegeven instellingenbestand. Staan daar al panel-antwoorden in (actie
# 'beide'), dan worden firewall, domein en certificaat daarvan overgenomen.
# Gebruik: ui/wings.sh <instellingenbestand>

# shellcheck source=../lib/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/lib.sh"
require_root
detect_os

CONFIG_FILE="${1:?Gebruik: ui/wings.sh <instellingenbestand>}"

# ----------------- Vragen ----------------- #

ask_dbhost() {
  local allow

  DBHOST=false
  DBHOST_USER=""
  DBHOST_PASSWORD=""
  DBHOST_ALLOW=""
  DBHOST_FIREWALL=false

  output "Met een databasehost kunnen gameservers op deze node een eigen MySQL-database krijgen."
  if ! ask_yes_no "Automatisch een databasehost-gebruiker aanmaken?"; then
    return 0
  fi
  DBHOST=true

  while true; do
    required_input DBHOST_USER "Gebruikersnaam [pterodactyluser]: " "" "pterodactyluser"
    valid_dbhost_user "$DBHOST_USER" && break
    error "Alleen letters, cijfers en _ (maximaal 32 tekens)."
  done

  while true; do
    password_input DBHOST_PASSWORD "Wachtwoord: " "Wachtwoord mag niet leeg zijn."
    valid_db_password "$DBHOST_PASSWORD" && break
    error "Geen spaties, aanhalingstekens, \\, \$, # of \` (maximaal 128 tekens)."
  done

  DBHOST_ALLOW="127.0.0.1"
  if ! ask_yes_no "MariaDB van buitenaf bereikbaar maken (bijvoorbeeld voor een panel op een andere server)?"; then
    return 0
  fi

  while true; do
    echo -n "* IP-adres of hostnaam van het panel (leeg = elk adres): "
    read -r allow
    if [ -z "$allow" ]; then
      DBHOST_ALLOW="%"
      break
    fi
    if valid_hostname "$allow"; then
      DBHOST_ALLOW="$allow"
      break
    fi
    error "Voer een geldig IP-adres of een geldige hostnaam in."
  done

  if [ "$FIREWALL" == true ]; then
    if is_ip_address "$DBHOST_ALLOW"; then
      output "Poort 3306 wordt dan alleen opengezet voor $DBHOST_ALLOW."
    else
      warning "Poort 3306 wordt dan voor iedereen opengezet. Dat is een veiligheidsrisico als je niet weet wat je doet."
    fi
    ask_yes_no "Poort 3306 (MySQL) openzetten in de firewall?" && DBHOST_FIREWALL=true
  fi
  return 0
}

ask_letsencrypt() {
  local nip
  LETSENCRYPT=false
  VERIFY_DNS=false
  FQDN=""
  EMAIL=""
  nip=$(server_nip_name)

  output "Let's Encrypt voor Wings werkt alleen met een domeinnaam (bijv. node1.voorbeeld.nl), niet met een IP-adres."
  if [ -n "$nip" ]; then
    output "Geen domein? Het gratis adres $nip wijst automatisch naar deze server;"
    output "een eigen naam ervoor kan ook, bijvoorbeeld node1-$nip."
  fi
  if [ "$FIREWALL" == false ]; then
    output "Let's Encrypt heeft poort 80 nodig. Zorg zelf dat die open staat."
  fi
  if ! ask_yes_no "HTTPS voor Wings instellen met Let's Encrypt?"; then
    return 0
  fi
  LETSENCRYPT=true

  while true; do
    echo -n "* Domeinnaam van deze node${nip:+ [$nip]}: "
    read -r FQDN
    FQDN="${FQDN:-$nip}"
    FQDN="${FQDN%.}"
    if ! valid_domain "$FQDN"; then
      error "Voer een domeinnaam in (geen IP-adres of localhost)."
      continue
    fi
    if verify_dns "$FQDN" || ask_yes_no "Toch Let's Encrypt instellen voor $FQDN?"; then
      break
    fi
    if ! ask_yes_no "Een andere domeinnaam proberen?"; then
      LETSENCRYPT=false
      FQDN=""
      return 0
    fi
  done

  email_input EMAIL "E-mailadres voor Let's Encrypt: " "Ongeldig e-mailadres."
}

# ----------------- Hoofdfunctie ----------------- #

main() {
  local key keys from_panel=false

  if [ -d /etc/pterodactyl ]; then
    error "Wings lijkt al geïnstalleerd (/etc/pterodactyl bestaat). Verwijder het eerst via het menu."
    exit 1
  fi

  # Bij 'beide' heeft ui/panel.sh het bestand al gevuld.
  if [ -s "$CONFIG_FILE" ]; then
    load_config "$CONFIG_FILE" || exit 1
    from_panel=true
  fi

  check_virt

  print_brake 70
  output "De installer zet Docker en Wings klaar. Daarna maak je de node aan in het"
  output "panel en zet je de configuratie op deze server (handmatig of met de knop"
  output "'auto deploy' in het panel). Meer informatie:"
  output "https://docs.pterodactyl.io/v${PANEL_VERSION:-1}/wings/installing#configuring-wings"
  output ""
  output "${COLOR_RED}Let op${COLOR_NC}: Wings wordt geïnstalleerd als service, maar nog niet gestart."
  output "${COLOR_RED}Let op${COLOR_NC}: de installer zet geen swap aan voor Docker."
  print_brake 70

  if [ "$from_panel" == true ]; then
    output "Firewall, domein en certificaat worden overgenomen van de panel-installatie."
  else
    FIREWALL=false
    ask_yes_no "Firewall ($(firewall_name)) automatisch instellen?" j && FIREWALL=true
  fi

  ask_dbhost

  keys=(DBHOST)
  if [ "$DBHOST" == true ]; then
    keys+=(DBHOST_USER DBHOST_PASSWORD DBHOST_ALLOW DBHOST_FIREWALL)
  fi
  if [ "$from_panel" != true ]; then
    ask_letsencrypt
    keys+=(FIREWALL LETSENCRYPT VERIFY_DNS)
    if [ "$LETSENCRYPT" == true ]; then
      keys+=(FQDN EMAIL)
    fi
  fi

  for key in "${keys[@]}"; do
    config_set "$CONFIG_FILE" "$key" "${!key}"
  done
}

main
