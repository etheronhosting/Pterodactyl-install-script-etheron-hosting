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

# Installeert Pterodactyl Panel met de instellingen uit het opgegeven bestand.
# Met --controleren worden alleen de instellingen gecontroleerd.
# Gebruik: installers/panel.sh <instellingenbestand> [--controleren]

# shellcheck source=../lib/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/lib.sh"
require_root
detect_os

CONFIG_FILE="${1:?Gebruik: installers/panel.sh <instellingenbestand> [--controleren]}"
CHECK_ONLY=false
[ "${2:-}" == "--controleren" ] && CHECK_ONLY=true
load_config "$CONFIG_FILE" || exit 1

# ---------------- Instellingen ---------------- #

FQDN="${FQDN%.}"
EMAIL="${EMAIL:-}"
FIREWALL="${FIREWALL:-false}"
LETSENCRYPT="${LETSENCRYPT:-false}"
ASSUME_SSL="${ASSUME_SSL:-false}"
VERIFY_DNS="${VERIFY_DNS:-true}"
PANEL_VERSION="${PANEL_VERSION:-1}"
PANEL_VERSION="${PANEL_VERSION#v}"
PANEL_RELEASE="${PANEL_RELEASE:-}"
TIMEZONE="${TIMEZONE:-$DEFAULT_TIMEZONE}"
TELEMETRY="${TELEMETRY:-false}"
DB_NAME="${DB_NAME:-panel}"
DB_USER="${DB_USER:-pterodactyl}"
DB_PASSWORD="${DB_PASSWORD:-$(gen_passwd 48)}"
ADMIN_EMAIL="${ADMIN_EMAIL:-$EMAIL}"
ADMIN_USERNAME="${ADMIN_USERNAME:-}"
ADMIN_FIRSTNAME="${ADMIN_FIRSTNAME:-}"
ADMIN_LASTNAME="${ADMIN_LASTNAME:-}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-}"

WEB_USER="www-data"
case "$OS" in
rocky | almalinux) WEB_USER="nginx" ;;
esac

valid_panel_release() {
  if [ "$PANEL_VERSION" == "2" ]; then
    [[ "$1" =~ ^[0-9a-f]{40}$ ]]
  else
    [[ "$1" =~ ^v1\.[0-9]+\.[0-9]+$ ]]
  fi
}

validate_settings() {
  local key

  check_setting FQDN valid_hostname "domeinnaam of IP-adres van het panel"
  check_setting EMAIL valid_email "e-mailadres voor Let's Encrypt en het panel"
  for key in FIREWALL LETSENCRYPT ASSUME_SSL VERIFY_DNS TELEMETRY; do
    check_setting "$key" valid_bool "true of false"
  done
  check_setting PANEL_VERSION valid_panel_version "1 of 2"
  if [ -n "$PANEL_RELEASE" ]; then
    check_setting PANEL_RELEASE valid_panel_release "release-tag zoals v1.11.11 voor v1, volledige commit-hash voor v2"
  fi
  check_setting TIMEZONE valid_timezone "zie configs/valid_timezones.txt"
  check_setting DB_NAME valid_database_identifier "letters, cijfers en _, maximaal 64 tekens"
  check_setting DB_USER valid_database_identifier "letters, cijfers en _, maximaal 64 tekens"
  check_setting DB_PASSWORD valid_db_password "geen spaties, aanhalingstekens, \\, \$, # of \`, maximaal 128 tekens"
  check_setting ADMIN_EMAIL valid_email "e-mailadres van de beheerder"
  check_setting ADMIN_USERNAME valid_admin_username "3-191 tekens: letters, cijfers, -, _ en ."
  check_setting ADMIN_FIRSTNAME valid_admin_name "voornaam van de beheerder"
  check_setting ADMIN_LASTNAME valid_admin_name "achternaam van de beheerder"
  check_setting ADMIN_PASSWORD valid_admin_password "minimaal 8 tekens"

  if [ "$LETSENCRYPT" == true ] && ! valid_domain "$FQDN"; then
    error "Let's Encrypt vraagt een domeinnaam, geen IP-adres of localhost (FQDN=$FQDN)."
    CONFIG_ERRORS=$((CONFIG_ERRORS + 1))
  fi

  if [ "$CONFIG_ERRORS" -gt 0 ]; then
    error "Het instellingenbestand bevat $CONFIG_ERRORS fout(en). Er is niets geïnstalleerd."
    exit 1
  fi

  if [ "$LETSENCRYPT" == true ] && [ "$ASSUME_SSL" == true ]; then
    warning "LETSENCRYPT en ASSUME_SSL staan allebei aan; Let's Encrypt wordt gebruikt."
    ASSUME_SSL=false
  fi

  # Een IPv6-adres hoort tussen haken in een URL.
  [[ "$FQDN" != *:* || "$FQDN" == '['*']' ]] || FQDN="[$FQDN]"
  return 0
}

# --------------- Afhankelijkheden --------------- #

ubuntu_dep() {
  install_packages software-properties-common apt-transport-https ca-certificates gnupg
  add-apt-repository universe -y

  case "$OS_VER_MAJOR" in
  22)
    LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
    ;;
  26)
    # Sury levert ook PHP 8.3 voor Ubuntu 26.04.
    debian_dep
    ;;
  esac
}

debian_dep() {
  install_packages dirmngr ca-certificates apt-transport-https gnupg

  # PHP 8.3 uit de repository van Sury
  mkdir -p /etc/apt/keyrings
  curl -fsSL https://packages.sury.org/php/apt.gpg | gpg --dearmor --yes -o /etc/apt/keyrings/php.gpg
  echo "deb [signed-by=/etc/apt/keyrings/php.gpg] https://packages.sury.org/php/ $OS_CODENAME main" >/etc/apt/sources.list.d/php.list
}

alma_rocky_dep() {
  install_packages policycoreutils selinux-policy selinux-policy-targeted epel-release

  # EL10 heeft PHP 8.3 en MariaDB 10.11 zelf; EL8 en EL9 halen PHP bij Remi.
  if [ "$OS_VER_MAJOR" != "10" ]; then
    install_packages "https://rpms.remirepo.net/enterprise/remi-release-$OS_VER_MAJOR.rpm"
    dnf module enable -y php:remi-8.3
    if ! command -v mariadbd >/dev/null 2>&1; then
      dnf module enable -y mariadb:10.11
    fi
  fi
}

enable_services() {
  systemctl enable --now "$CACHE_SERVICE"
  case "$OS" in
  ubuntu | debian)
    systemctl enable --now php8.3-fpm
    ;;
  esac
  systemctl enable nginx
  systemctl enable --now mariadb
}

selinux_allow() {
  # Deze commando's mogen mislukken, bijvoorbeeld als SELinux uit staat.
  setsebool -P httpd_can_network_connect 1 || true
  setsebool -P httpd_execmem 1 || true
  setsebool -P httpd_unified 1 || true
}

php_fpm_conf() {
  cp "$ETHERON_DIR/configs/www-pterodactyl.conf" /etc/php-fpm.d/www-pterodactyl.conf
  systemctl enable --now php-fpm
}

install_nodejs() {
  local setup_url
  case "$OS" in
  ubuntu | debian) setup_url="https://deb.nodesource.com/setup_22.x" ;;
  rocky | almalinux) setup_url="https://rpm.nodesource.com/setup_22.x" ;;
  esac
  curl -fsSL "$setup_url" | bash -
  install_packages nodejs
}

dep_install() {
  local ports

  output "Afhankelijkheden installeren voor $OS $OS_VER..."
  update_repos

  if [ "$FIREWALL" == true ]; then
    read -r -a ports <<<"$(ssh_ports)"
    setup_firewall "${ports[@]}" 80 443
  fi

  case "$OS" in
  ubuntu | debian)
    if [ "$OS" == "ubuntu" ]; then
      ubuntu_dep
      if [ "$OS_VER_MAJOR" == "22" ] && ! command -v mariadbd >/dev/null 2>&1; then
        curl -fsSL "$MARIADB_URL" | bash -s -- --mariadb-server-version=mariadb-10.11 --skip-maxscale --skip-tools
      fi
    else
      debian_dep
    fi

    update_repos

    install_packages php8.3 php8.3-{cli,common,gd,mysql,mbstring,bcmath,xml,fpm,curl,zip,intl} \
      mariadb-common mariadb-server mariadb-client \
      nginx \
      redis-server \
      zip unzip tar \
      git cron

    if [ "$LETSENCRYPT" == true ]; then
      install_packages certbot python3-certbot-nginx
    fi
    ;;
  rocky | almalinux)
    alma_rocky_dep

    install_packages php php-{common,fpm,cli,mysqlnd,gd,mbstring,pdo,zip,bcmath,xml,opcache,process,sodium,intl} \
      mariadb mariadb-server \
      nginx \
      "$CACHE_SERVICE" \
      zip unzip tar \
      git cronie

    if [ "$LETSENCRYPT" == true ]; then
      install_packages certbot python3-certbot-nginx
    fi

    selinux_allow
    php_fpm_conf
    ;;
  esac

  # Panel v2 bouwt de frontend tijdens de installatie.
  if [ "$PANEL_VERSION" == "2" ]; then
    install_nodejs
  fi

  enable_services
  success "Afhankelijkheden geïnstalleerd."
}

# ------------------ Panel ------------------ #

# De installer van Composer wordt gecontroleerd met de officiële controlesom.
install_composer() {
  local tmp expected actual

  output "Composer installeren..."
  tmp=$(mktemp -d)
  curl -fsSL -o "$tmp/composer-setup.php" https://getcomposer.org/installer
  expected=$(curl -fsSL https://composer.github.io/installer.sig)
  actual=$(sha384sum "$tmp/composer-setup.php" | cut -d' ' -f1)
  if [ -z "$expected" ] || [ "$expected" != "$actual" ]; then
    rm -rf "$tmp"
    error "De controlesom van de Composer-installer klopt niet. Installatie gestopt."
    exit 1
  fi

  "$PHP_BIN" "$tmp/composer-setup.php" --quiet --2 --install-dir=/usr/local/bin --filename=composer
  rm -rf "$tmp"
  success "Composer geïnstalleerd."
}

download_panel() {
  output "Panel $PANEL_VERSION_LABEL downloaden..."
  mkdir -p "$PANEL_DIR"
  cd "$PANEL_DIR"

  curl -fsSL -o panel.tar.gz "$PANEL_DL_URL"
  if [ "$PANEL_VERSION" == "2" ]; then
    tar -xzf panel.tar.gz --strip-components=1
  else
    tar -xzf panel.tar.gz
  fi
  rm -f panel.tar.gz
  chmod -R 755 storage/* bootstrap/cache/

  cp .env.example .env
  success "Panelbestanden gedownload."
}

install_composer_deps() {
  output "Composer-afhankelijkheden installeren..."
  export COMPOSER_ALLOW_SUPERUSER=1
  "$PHP_BIN" /usr/local/bin/composer install --no-dev --optimize-autoloader --no-interaction
  "$PHP_BIN" /usr/local/bin/composer check-platform-reqs --no-dev
  success "Composer-afhankelijkheden geïnstalleerd."

  if [ "$PANEL_VERSION" == "2" ]; then
    output "Frontend van Panel v2 bouwen..."
    npm ci --include=dev
    npm run build:production
    success "Frontend gebouwd."
  fi
}

configure() {
  local app_url="http://$FQDN"
  if [ "$ASSUME_SSL" == true ] || [ "$LETSENCRYPT" == true ]; then
    app_url="https://$FQDN"
  fi

  output "Omgeving van het panel instellen..."
  cd "$PANEL_DIR"

  "$PHP_BIN" artisan key:generate --force --no-interaction

  "$PHP_BIN" artisan p:environment:setup --no-interaction \
    --author="$EMAIL" \
    --url="$app_url" \
    --timezone="$TIMEZONE" \
    --cache="redis" \
    --session="redis" \
    --queue="redis" \
    --redis-host="localhost" \
    --redis-pass="null" \
    --redis-port="6379" \
    --telemetry="$TELEMETRY" \
    --settings-ui=true

  "$PHP_BIN" artisan p:environment:database --no-interaction \
    --host="127.0.0.1" \
    --port="3306" \
    --database="$DB_NAME" \
    --username="$DB_USER" \
    --password="$DB_PASSWORD"

  "$PHP_BIN" artisan migrate --seed --force --no-interaction

  "$PHP_BIN" artisan p:user:make --no-interaction \
    --email="$ADMIN_EMAIL" \
    --username="$ADMIN_USERNAME" \
    --name-first="$ADMIN_FIRSTNAME" \
    --name-last="$ADMIN_LASTNAME" \
    --password="$ADMIN_PASSWORD" \
    --admin=1

  success "Omgeving ingesteld."
}

# .env bevat de app-sleutel en het databasewachtwoord: niet leesbaar voor iedereen.
set_folder_permissions() {
  chown -R "$WEB_USER:$WEB_USER" "$PANEL_DIR"
  chmod 640 "$PANEL_DIR/.env"
}

insert_cronjob() {
  local job="* * * * * $PHP_BIN $PANEL_DIR/artisan schedule:run >> /dev/null 2>&1"

  output "Cronjob installeren..."
  {
    crontab -l 2>/dev/null | grep -vF "$PANEL_DIR/artisan schedule:run" || true
    echo "$job"
  } | crontab -

  case "$OS" in
  ubuntu | debian) systemctl enable --now cron ;;
  rocky | almalinux) systemctl enable --now crond ;;
  esac
  success "Cronjob geïnstalleerd."
}

install_pteroq() {
  output "Queue-worker (pteroq) installeren..."
  cp "$ETHERON_DIR/configs/pteroq.service" /etc/systemd/system/pteroq.service
  sed -i -e "s@redis-server.service@${CACHE_SERVICE}.service@g" \
    -e "s@/usr/bin/php @$PHP_BIN @g" \
    -e "s@<user>@$WEB_USER@g" /etc/systemd/system/pteroq.service

  systemctl daemon-reload
  systemctl enable --now pteroq.service
  success "Queue-worker geïnstalleerd."
}

# ------------------ Webserver ------------------ #

configure_nginx() {
  local config_file php_socket config_path_avail config_path_enabl

  output "Nginx instellen..."

  if [ "$ASSUME_SSL" == true ] && [ "$LETSENCRYPT" == false ]; then
    config_file="nginx_ssl.conf"
  else
    config_file="nginx.conf"
  fi

  case "$OS" in
  ubuntu | debian)
    php_socket="/run/php/php8.3-fpm.sock"
    config_path_avail="/etc/nginx/sites-available"
    config_path_enabl="/etc/nginx/sites-enabled"
    ;;
  rocky | almalinux)
    php_socket="/var/run/php-fpm/pterodactyl.sock"
    config_path_avail="/etc/nginx/conf.d"
    config_path_enabl="$config_path_avail"
    ;;
  esac

  rm -rf "$config_path_enabl"/default

  cp "$ETHERON_DIR/configs/$config_file" "$config_path_avail/pterodactyl.conf"
  sed -i -e "s@<domain>@${FQDN}@g" -e "s@<php_socket>@${php_socket}@g" "$config_path_avail/pterodactyl.conf"

  if [ "$PANEL_VERSION" == "2" ]; then
    # ^~ voorkomt dat assets bij de PHP-handler terechtkomen.
    # shellcheck disable=SC2016
    sed -i '/    location ~ \\.php\$ {/i\
    location ^~ /assets/ {\n\
        location ~ /\\. { deny all; }\n\
        try_files $uri =404;\n\
    }\n' "$config_path_avail/pterodactyl.conf"
  fi

  case "$OS" in
  ubuntu | debian)
    ln -sf "$config_path_avail/pterodactyl.conf" "$config_path_enabl/pterodactyl.conf"
    ;;
  esac

  # Met een eigen certificaat start nginx pas als dat certificaat er staat.
  if [ "$ASSUME_SSL" == false ]; then
    nginx -t
    systemctl restart nginx
  fi

  success "Nginx ingesteld."
}

letsencrypt() {
  local args=(--nginx --redirect --no-eff-email --email "$EMAIL" -d "$FQDN")

  output "Let's Encrypt-certificaat aanvragen..."
  # Onbegeleid gaat de beheerder met LETSENCRYPT=true akkoord met de voorwaarden.
  if [ "$UNATTENDED" == true ]; then
    args+=(--non-interactive --agree-tos)
  fi

  if certbot "${args[@]}" && [ -d "/etc/letsencrypt/live/$FQDN/" ]; then
    success "Let's Encrypt-certificaat aangevraagd en ingesteld."
    return 0
  fi

  warning "Het aanvragen van een Let's Encrypt-certificaat is mislukt."
  LETSENCRYPT=false
  if [ "$UNATTENDED" != true ] && ask_yes_no "Toch uitgaan van HTTPS (je regelt zelf een certificaat)?"; then
    ASSUME_SSL=true
  else
    ASSUME_SSL=false
    sed -i "s@^APP_URL=.*@APP_URL=http://$FQDN@" "$PANEL_DIR/.env"
    "$PHP_BIN" "$PANEL_DIR/artisan" config:clear
    "$PHP_BIN" "$PANEL_DIR/artisan" queue:restart
    warning "Het panel is nu via HTTP bereikbaar. Vraag later alsnog een certificaat aan met: certbot --nginx -d $FQDN"
  fi
  configure_nginx
}

# ------------------ Afronding ------------------ #

goodbye() {
  local url="http://$FQDN"
  if [ "$LETSENCRYPT" == true ] || [ "$ASSUME_SSL" == true ]; then
    url="https://$FQDN"
  fi

  print_brake 70
  output "Panel-installatie voltooid ($PANEL_VERSION_LABEL)"
  output ""
  output "Adres:      $url"
  output "Beheerder:  $ADMIN_USERNAME ($ADMIN_EMAIL)"
  output "Database:   $DB_NAME, gebruiker $DB_USER (wachtwoord staat in $PANEL_DIR/.env)"
  if [ "$ASSUME_SSL" == true ]; then
    output ""
    output "Je gebruikt een eigen certificaat. Het panel werkt pas als dat er staat:"
    output "  /etc/ssl/$FQDN.pem en /etc/ssl/$FQDN.key"
    output "Voer daarna uit: nginx -t && systemctl restart nginx"
  fi
  if [ "$FIREWALL" == false ]; then
    output ""
    output "${COLOR_RED}Let op${COLOR_NC}: de firewall is niet ingesteld. Poort 80 en 443 moeten open staan."
  fi
  output ""
  output "Log: $LOG_PATH"
  print_brake 70
}

perform_install() {
  validate_settings

  if [ -d "$PANEL_DIR" ]; then
    error "Er staat al een panel in $PANEL_DIR. Deze installer doet alleen nieuwe installaties."
    exit 1
  fi
  if [ "$CHECK_ONLY" == true ]; then
    output "Instellingen voor het panel zijn in orde."
    exit 0
  fi
  if [ "$ARCH" != "amd64" ]; then
    warning "CPU-architectuur $CPU_ARCHITECTURE: het panel is vooral getest op x86_64."
  fi
  if [ "$VERIFY_DNS" == true ] && { [ "$LETSENCRYPT" == true ] || [ "$ASSUME_SSL" == true ]; }; then
    if ! verify_dns "$FQDN"; then
      error "Zet VERIFY_DNS=false in het instellingenbestand om deze controle over te slaan."
      exit 1
    fi
  fi
  if ! resolve_panel_version; then
    error "Kon de panelversie niet bepalen. Controleer PANEL_RELEASE en of GitHub bereikbaar is."
    exit 1
  fi

  output "Panel $PANEL_VERSION_LABEL installeren op $FQDN. Dit duurt even..."
  dep_install
  check_database_connection
  install_composer
  download_panel
  install_composer_deps
  create_db_user "$DB_USER" "$DB_PASSWORD"
  create_db "$DB_NAME" "$DB_USER"
  configure
  set_folder_permissions
  insert_cronjob
  install_pteroq
  configure_nginx
  if [ "$LETSENCRYPT" == true ]; then
    letsencrypt
  fi
  goodbye
}

perform_install
