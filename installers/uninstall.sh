#!/bin/bash

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

# Verwijdert Pterodactyl Panel en/of Wings. Werkt alleen interactief: bij elke
# stap die gegevens wist, wordt eerst gevraagd wat er weg moet.

# shellcheck source=../lib/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/lib.sh"
require_root
detect_os

RM_PANEL=false
RM_WINGS=false
DATABASE=""
DB_USER=""

# ------------------ Verwijderen ------------------ #

disable_service() {
  if systemctl cat "$1" >/dev/null 2>&1; then
    systemctl disable --now "$1"
  fi
}

rm_panel_files() {
  output "Panelbestanden verwijderen..."
  rm -rf "$PANEL_DIR"
  rm -f /var/log/nginx/pterodactyl.app-access.log* /var/log/nginx/pterodactyl.app-error.log*
  case "$OS" in
  ubuntu | debian)
    [ ! -L /etc/nginx/sites-enabled/pterodactyl.conf ] || unlink /etc/nginx/sites-enabled/pterodactyl.conf
    rm -f /etc/nginx/sites-available/pterodactyl.conf
    [ -L /etc/nginx/sites-enabled/default ] || [ ! -f /etc/nginx/sites-available/default ] ||
      ln -s /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default
    ;;
  rocky | almalinux)
    rm -f /etc/nginx/conf.d/pterodactyl.conf
    ;;
  esac
  systemctl restart nginx
  success "Panelbestanden verwijderd."
}

rm_services() {
  output "Services verwijderen..."
  disable_service pteroq
  rm -f /etc/systemd/system/pteroq.service
  disable_service "$CACHE_SERVICE"
  case "$OS" in
  rocky | almalinux)
    disable_service php-fpm
    rm -f /etc/php-fpm.d/www-pterodactyl.conf
    ;;
  esac
  systemctl daemon-reload
  success "Services verwijderd."
}

rm_cron() {
  output "Cronjob verwijderen..."
  { crontab -l 2>/dev/null || true; } | {
    grep -vF "$PANEL_DIR/artisan schedule:run" || [ "$?" == 1 ]
  } | crontab -
  success "Cronjob verwijderd."
}

choose_database() {
  local databases="$1" input
  if grep -qxF panel <<<"$databases" && ask_yes_no "Database 'panel' gevonden. Is dat de database van het panel?"; then
    DATABASE=panel
    return 0
  fi
  print_list "$databases"
  while true; do
    echo -n "* Welke database hoort bij het panel? (leeg = overslaan): "
    read -r input
    [ -z "$input" ] && return 0
    if grep -qxF "$input" <<<"$databases"; then
      DATABASE="$input"
      return 0
    fi
    warning "Die database bestaat niet. Probeer het opnieuw."
  done
}

choose_db_user() {
  local users="$1" input
  if grep -qxF pterodactyl <<<"$users" && ask_yes_no "Gebruiker 'pterodactyl' gevonden. Is dat de databasegebruiker van het panel?"; then
    DB_USER=pterodactyl
    return 0
  fi
  print_list "$users"
  while true; do
    echo -n "* Welke databasegebruiker hoort bij het panel? (leeg = overslaan): "
    read -r input
    [ -z "$input" ] && return 0
    if grep -qxF "$input" <<<"$users"; then
      DB_USER="$input"
      return 0
    fi
    warning "Die gebruiker bestaat niet. Probeer het opnieuw."
  done
}

rm_database() {
  local databases users

  output "Database verwijderen..."
  if ! check_database_connection; then
    warning "Database wordt overgeslagen."
    return 0
  fi

  databases=$(mariadb -u root -N -e "SELECT schema_name FROM information_schema.schemata WHERE schema_name NOT IN ('information_schema', 'performance_schema', 'mysql', 'sys');")
  if [ -z "$databases" ]; then
    warning "Geen databases gevonden."
  else
    warning "Let op: de database die je kiest wordt definitief verwijderd!"
    choose_database "$databases"
    if [ -n "$DATABASE" ]; then
      mariadb -u root -e "DROP DATABASE \`${DATABASE//\`/\`\`}\`;" 2>/dev/null || warning "Database $DATABASE verwijderen is mislukt."
    else
      output "Geen database gekozen; overgeslagen."
    fi
  fi

  users=$(mariadb -u root -N -e "SELECT user FROM mysql.user WHERE host = '127.0.0.1' AND user != 'root';")
  if [ -z "$users" ]; then
    warning "Geen databasegebruikers gevonden."
  else
    warning "Let op: de gebruiker die je kiest wordt definitief verwijderd!"
    choose_db_user "$users"
    if [ -n "$DB_USER" ] && valid_database_identifier "$DB_USER"; then
      mariadb -u root -e "DROP USER '$DB_USER'@'127.0.0.1';" 2>/dev/null || warning "Gebruiker $DB_USER verwijderen is mislukt."
    else
      output "Geen gebruiker gekozen; overgeslagen."
    fi
  fi

  mariadb -u root -e "FLUSH PRIVILEGES;" 2>/dev/null || true
  success "Database en databasegebruiker verwijderd (voor zover gekozen)."
}

rm_docker_containers() {
  local container containers

  output "Containers van Wings verwijderen..."
  type -P docker >/dev/null 2>&1 || return 0
  containers=$(docker ps -aq --filter label=Service=Pterodactyl)
  for container in $containers; do
    docker rm -fv "$container"
  done
  success "Containers van Wings verwijderd. Gedeelde images en named volumes blijven staan."
}

rm_wings_files() {
  local conf

  output "Wings-bestanden verwijderen..."
  rm -f /etc/systemd/system/wings.service
  rm -rf /etc/pterodactyl /var/lib/pterodactyl /var/log/pterodactyl /run/wings /tmp/pterodactyl
  rm -f /usr/local/bin/wings /etc/logrotate.d/wings
  rm -f /etc/letsencrypt/renewal-hooks/deploy/etheron-restart-wings.sh
  systemctl daemon-reload

  # Door de installer opengezette MariaDB-toegang terugdraaien.
  for conf in /etc/mysql/mariadb.conf.d/99-etheron-dbhost.cnf /etc/my.cnf.d/99-etheron-dbhost.cnf; do
    if [ -f "$conf" ]; then
      rm -f "$conf"
      systemctl restart mariadb || true
      output "MariaDB luistert weer alleen lokaal. De databasehost-gebruiker zelf is blijven staan."
    fi
  done

  success "Wings-bestanden verwijderd."
}

# Vraagt per certificaat of het weg mag, behalve als iets anders het nog gebruikt.
rm_certificates() {
  local certificate
  for certificate in $CERTIFICATES; do
    [ -d "/etc/letsencrypt/live/$certificate" ] || continue
    if grep -rFq "/etc/letsencrypt/live/$certificate/" /etc/nginx /etc/pterodactyl 2>/dev/null; then
      output "Certificaat $certificate wordt nog gebruikt en blijft staan."
      continue
    fi
    if ask_yes_no "Let's Encrypt-certificaat $certificate verwijderen?"; then
      certbot delete --non-interactive --cert-name "$certificate"
    fi
  done
  return 0
}

# ----------------- Hoofdfunctie ----------------- #

main() {
  if [ -d "$PANEL_DIR" ]; then
    output "Er is een panel gevonden in $PANEL_DIR."
    ask_yes_no "Panel verwijderen?" && RM_PANEL=true
  fi
  if [ -d /etc/pterodactyl ]; then
    output "Er is een Wings-installatie gevonden."
    warning "Hiermee verwijder je ook alle gameservers op deze node!"
    ask_yes_no "Wings verwijderen?" && RM_WINGS=true
  fi

  if [ "$RM_PANEL" == false ] && [ "$RM_WINGS" == false ]; then
    error "Niets om te verwijderen."
    exit 1
  fi

  print_brake 40
  output "Panel verwijderen: $([ "$RM_PANEL" == true ] && echo ja || echo nee)"
  output "Wings verwijderen: $([ "$RM_WINGS" == true ] && echo ja || echo nee)"
  print_brake 40
  if ! ask_yes_no "Doorgaan met verwijderen?"; then
    error "Verwijderen afgebroken."
    exit 1
  fi

  # Eerst vastleggen welke certificaten erbij horen; de configs gaan zo weg.
  CERTIFICATES=$({
    if [ "$RM_PANEL" == true ]; then
      grep -hEo '/etc/letsencrypt/live/[^/[:space:]]+/' /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/conf.d/pterodactyl.conf 2>/dev/null || true
    fi
    if [ "$RM_WINGS" == true ]; then
      grep -Eo '/etc/letsencrypt/live/[^/[:space:]]+/' /etc/pterodactyl/config.yml 2>/dev/null || true
    fi
  } | cut -d/ -f5 | sort -u)

  if [ "$RM_PANEL" == true ]; then
    rm_services
    rm_panel_files
    rm_cron
    rm_database
  fi
  if [ "$RM_WINGS" == true ]; then
    disable_service wings
    rm_docker_containers
    rm_wings_files
  fi
  rm_certificates

  print_brake 62
  [ "$RM_PANEL" == true ] && output "Panel verwijderd."
  [ "$RM_WINGS" == true ] && output "Wings verwijderd."
  output "Composer, Docker, MariaDB, nginx en PHP zijn niet verwijderd."
  print_brake 62
}

main
