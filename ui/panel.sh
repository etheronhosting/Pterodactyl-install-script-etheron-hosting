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

# Stelt de vragen voor de panel-installatie en schrijft de antwoorden naar het
# opgegeven instellingenbestand. Gebruik: ui/panel.sh <instellingenbestand>

# shellcheck source=../lib/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/lib.sh"
require_root
detect_os

CONFIG_FILE="${1:?Gebruik: ui/panel.sh <instellingenbestand>}"

# ----------------- Vragen ----------------- #

ask_panel_version() {
  local version
  while true; do
    echo -n "* Panel-versie: 1 (stabiel) of 2 (experimenteel) [1]: "
    read -r version
    version="${version:-1}"
    version="${version#v}"
    valid_panel_version "$version" && break
    error "Kies 1 of 2."
  done

  if [ "$version" == "2" ]; then
    warning "Pterodactyl Panel v2 is nog niet officieel uitgebracht (pre-release)."
    if ! ask_yes_no "Weet je zeker dat je de experimentele v2 wilt installeren?"; then
      error "Installatie afgebroken."
      exit 1
    fi
  fi
  PANEL_VERSION="$version"
}

ask_database() {
  local random_password
  output "Database"
  output "Het panel krijgt een eigen MariaDB-database en -gebruiker. Die maakt de"
  output "installer zelf aan; je hoeft vooraf niets te doen."
  output ""

  while true; do
    required_input DB_NAME "Databasenaam [panel]: " "" "panel"
    valid_database_identifier "$DB_NAME" && break
    error "Alleen letters, cijfers en _ (maximaal 64 tekens)."
  done

  while true; do
    required_input DB_USER "Databasegebruiker [pterodactyl]: " "" "pterodactyl"
    valid_database_identifier "$DB_USER" && break
    error "Alleen letters, cijfers en _ (maximaal 64 tekens)."
  done

  random_password=$(gen_passwd 48)
  while true; do
    password_input DB_PASSWORD "Databasewachtwoord (Enter = willekeurig): " "" "$random_password"
    valid_db_password "$DB_PASSWORD" && break
    error "Geen spaties, aanhalingstekens, \\, \$, # of \` (maximaal 128 tekens)."
  done
}

ask_timezone() {
  output "Geldige tijdzones: https://www.php.net/manual/en/timezones.php"
  while true; do
    echo -n "* Tijdzone [$DEFAULT_TIMEZONE]: "
    read -r TIMEZONE
    TIMEZONE="${TIMEZONE:-$DEFAULT_TIMEZONE}"
    valid_timezone "$TIMEZONE" && break
    error "Onbekende tijdzone. Probeer het opnieuw."
  done
}

ask_admin() {
  local password_again
  output "Eerste beheerdersaccount"

  email_input ADMIN_EMAIL "E-mailadres [$EMAIL]: " "Ongeldig e-mailadres." "$EMAIL"

  while true; do
    required_input ADMIN_USERNAME "Gebruikersnaam: " "Gebruikersnaam mag niet leeg zijn."
    valid_admin_username "$ADMIN_USERNAME" && break
    error "3-191 tekens: letters, cijfers, -, _ en . en beginnen en eindigen met een letter of cijfer."
  done

  while true; do
    required_input ADMIN_FIRSTNAME "Voornaam: " "Voornaam mag niet leeg zijn."
    valid_admin_name "$ADMIN_FIRSTNAME" && break
    error "Maximaal 191 tekens, zonder stuurtekens."
  done

  while true; do
    required_input ADMIN_LASTNAME "Achternaam: " "Achternaam mag niet leeg zijn."
    valid_admin_name "$ADMIN_LASTNAME" && break
    error "Maximaal 191 tekens, zonder stuurtekens."
  done

  while true; do
    password_input ADMIN_PASSWORD "Wachtwoord (minimaal 8 tekens): " "Wachtwoord mag niet leeg zijn."
    if ! valid_admin_password "$ADMIN_PASSWORD"; then
      error "Minimaal 8 tekens, zonder stuurtekens."
      continue
    fi
    password_input password_again "Herhaal het wachtwoord: " "Wachtwoord mag niet leeg zijn."
    [ "$password_again" == "$ADMIN_PASSWORD" ] && break
    error "De wachtwoorden komen niet overeen."
  done
}

ask_fqdn() {
  while true; do
    echo -n "* Domeinnaam van het panel (bijv. panel.voorbeeld.nl) of IP-adres: "
    read -r FQDN
    valid_hostname "$FQDN" && break
    error "Voer een geldige domeinnaam of een geldig IP-adres in."
  done
  FQDN="${FQDN%.}"
}

ask_ssl() {
  LETSENCRYPT=false
  ASSUME_SSL=false

  if ! valid_domain "$FQDN"; then
    warning "Let's Encrypt werkt niet met een IP-adres of localhost. Het panel draait dan op HTTP."
    return 0
  fi

  if [ "$FIREWALL" == false ]; then
    warning "Let's Encrypt heeft poort 80 en 443 nodig. Zorg zelf dat die open staan."
  fi
  if ask_yes_no "HTTPS automatisch instellen met Let's Encrypt?" j; then
    LETSENCRYPT=true
  else
    output "Je kunt ook een eigen certificaat gebruiken. Zet het dan in /etc/ssl/$FQDN.pem"
    output "met de sleutel in /etc/ssl/$FQDN.key en herstart nginx na de installatie."
    ask_yes_no "Nginx instellen voor HTTPS met een eigen certificaat?" && ASSUME_SSL=true
  fi

  # De DNS-controle gebeurt hier al, dus de installer hoeft hem niet te herhalen.
  if [ "$LETSENCRYPT" == true ] || [ "$ASSUME_SSL" == true ]; then
    if ! verify_dns "$FQDN" && ! ask_yes_no "Toch doorgaan? Zonder kloppende DNS mislukt Let's Encrypt."; then
      error "Installatie afgebroken."
      exit 1
    fi
  fi
  return 0
}

ask_telemetry() {
  output "Pterodactyl kan anonieme gebruiksstatistieken verzamelen om de ontwikkeling te sturen."
  output "Meer informatie: https://docs.pterodactyl.io/v$PANEL_VERSION/panel/additional-configuration#telemetry"
  TELEMETRY=false
  ask_yes_no "Anonieme telemetrie inschakelen?" && TELEMETRY=true
  return 0
}

# ----------------- Hoofdfunctie ----------------- #

main() {
  local key

  if [ -d "$PANEL_DIR" ]; then
    error "Er staat al een panel in $PANEL_DIR. Deze installer doet alleen nieuwe installaties."
    output "Verwijder het bestaande panel via het menu, of upgrade het met de officiële handleiding:"
    output "https://docs.pterodactyl.io/v2/upgrading/upgrading-from-v1"
    exit 1
  fi

  check_arch_panel
  ask_panel_version
  print_brake 70
  ask_database
  print_brake 70
  ask_timezone
  email_input EMAIL "E-mailadres voor Let's Encrypt en het panel: " "Ongeldig e-mailadres."
  print_brake 70
  ask_admin
  print_brake 70
  ask_fqdn

  FIREWALL=false
  ask_yes_no "Firewall ($(firewall_name)) automatisch instellen?" j && FIREWALL=true

  ask_ssl
  ask_telemetry

  VERIFY_DNS=false
  for key in FQDN EMAIL FIREWALL LETSENCRYPT ASSUME_SSL VERIFY_DNS PANEL_VERSION TIMEZONE TELEMETRY \
    DB_NAME DB_USER DB_PASSWORD ADMIN_EMAIL ADMIN_USERNAME ADMIN_FIRSTNAME ADMIN_LASTNAME ADMIN_PASSWORD; do
    config_set "$CONFIG_FILE" "$key" "${!key}"
  done
}

main
