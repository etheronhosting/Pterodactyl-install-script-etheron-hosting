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

# Installeert Docker en Pterodactyl Wings met de instellingen uit het opgegeven
# bestand. Met --controleren worden alleen de instellingen gecontroleerd.
# Gebruik: installers/wings.sh <instellingenbestand> [--controleren]

# shellcheck source=../lib/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/lib.sh"
require_root
detect_os

CONFIG_FILE="${1:?Gebruik: installers/wings.sh <instellingenbestand> [--controleren]}"
CHECK_ONLY=false
[ "${2:-}" == "--controleren" ] && CHECK_ONLY=true
load_config "$CONFIG_FILE" || exit 1

# ---------------- Instellingen ---------------- #

FQDN="${FQDN%.}"
EMAIL="${EMAIL:-}"
FIREWALL="${FIREWALL:-false}"
LETSENCRYPT="${LETSENCRYPT:-false}"
VERIFY_DNS="${VERIFY_DNS:-true}"
WINGS_RELEASE="${WINGS_RELEASE:-}"
DBHOST="${DBHOST:-false}"
DBHOST_USER="${DBHOST_USER:-pterodactyluser}"
DBHOST_PASSWORD="${DBHOST_PASSWORD:-}"
DBHOST_ALLOW="${DBHOST_ALLOW:-127.0.0.1}"
DBHOST_ALLOW="${DBHOST_ALLOW#[}"
DBHOST_ALLOW="${DBHOST_ALLOW%]}"
DBHOST_FIREWALL="${DBHOST_FIREWALL:-false}"

RENEW_HOOK="/etc/letsencrypt/renewal-hooks/deploy/etheron-restart-wings.sh"

validate_settings() {
  local key

  for key in FIREWALL LETSENCRYPT VERIFY_DNS DBHOST DBHOST_FIREWALL; do
    check_setting "$key" valid_bool "true of false"
  done
  if [ "$LETSENCRYPT" == true ]; then
    check_setting FQDN valid_domain "domeinnaam van deze node, geen IP-adres"
    check_setting EMAIL valid_email "e-mailadres voor Let's Encrypt"
  fi
  if [ -n "$WINGS_RELEASE" ]; then
    check_setting WINGS_RELEASE valid_release_tag "release-tag zoals v1.11.13"
  fi
  if [ "$DBHOST" == true ]; then
    check_setting DBHOST_USER valid_dbhost_user "letters, cijfers en _, maximaal 32 tekens"
    check_setting DBHOST_PASSWORD valid_db_password "geen spaties, aanhalingstekens, \\, \$, # of \`, maximaal 128 tekens"
    check_setting DBHOST_ALLOW valid_dbhost_allow "127.0.0.1, % of het IP-adres/de hostnaam van het panel"
  fi

  if [ "$CONFIG_ERRORS" -gt 0 ]; then
    error "Het instellingenbestand bevat $CONFIG_ERRORS fout(en). Er is niets geïnstalleerd."
    exit 1
  fi

  if [ "$DBHOST_FIREWALL" == true ]; then
    if [ "$DBHOST" != true ] || [ "$FIREWALL" != true ] || [ "$DBHOST_ALLOW" == "127.0.0.1" ]; then
      warning "DBHOST_FIREWALL wordt genegeerd: dat werkt alleen met FIREWALL=true, DBHOST=true en een DBHOST_ALLOW anders dan 127.0.0.1."
      DBHOST_FIREWALL=false
    fi
  fi
  return 0
}

# --------------- Afhankelijkheden --------------- #

configure_firewall() {
  local ports

  read -r -a ports <<<"$(ssh_ports)"
  ports+=(8080 2022)
  if [ "$LETSENCRYPT" == true ]; then
    ports+=(80 443)
  fi
  if [ "$DBHOST_FIREWALL" == true ] && ! is_ip_address "$DBHOST_ALLOW"; then
    warning "Poort 3306 gaat open voor iedereen; de databasegebruiker accepteert alleen verbindingen vanaf $DBHOST_ALLOW."
    ports+=(3306)
  fi

  setup_firewall "${ports[@]}"

  if [ "$DBHOST_FIREWALL" == true ] && is_ip_address "$DBHOST_ALLOW"; then
    firewall_allow_from "$DBHOST_ALLOW" 3306
  fi
}

has_mariadb() {
  type -P mariadb >/dev/null 2>&1 || type -P mysql >/dev/null 2>&1
}

dep_install() {
  output "Afhankelijkheden installeren voor $OS $OS_VER..."
  update_repos

  if [ "$FIREWALL" == true ]; then
    configure_firewall
  fi

  case "$OS" in
  ubuntu | debian)
    install_packages ca-certificates gnupg curl

    mkdir -p /etc/apt/keyrings
    curl -fsSL "https://download.docker.com/linux/$OS/gpg" | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$OS $OS_CODENAME stable" \
      >/etc/apt/sources.list.d/docker.list
    ;;
  rocky | almalinux)
    install_packages dnf-plugins-core
    # Podman en de losse runc botsen met de runtime van containerd.io.
    if rpm -q podman >/dev/null 2>&1 || rpm -q runc >/dev/null 2>&1; then
      dnf -y remove podman runc
    fi
    if [ "$OS_VER_MAJOR" == "10" ]; then
      dnf config-manager --add-repo=https://download.docker.com/linux/rhel/docker-ce.repo
    else
      dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo
    fi

    if [ "$LETSENCRYPT" == true ]; then
      install_packages epel-release
    fi

    install_packages device-mapper-persistent-data lvm2
    if [ "$OS_VER_MAJOR" == "10" ] && ! modinfo xt_addrtype >/dev/null 2>&1; then
      # De iptables-backend van Docker heeft deze module voor de draaiende kernel nodig.
      install_packages "kernel-modules-extra-$(uname -r)"
    fi
    ;;
  esac

  update_repos
  install_packages docker-ce docker-ce-cli containerd.io

  if [ "$DBHOST" == true ] && ! has_mariadb; then
    install_packages mariadb-server
    systemctl enable --now mariadb
  fi
  if [ "$LETSENCRYPT" == true ]; then
    install_packages certbot
  fi

  systemctl enable --now docker
  success "Afhankelijkheden geïnstalleerd."
}

# ------------------ Wings ------------------ #

download_wings() {
  output "Wings $WINGS_RELEASE downloaden..."
  mkdir -p /etc/pterodactyl
  curl -fsSL -o /usr/local/bin/wings "$WINGS_DL_URL"
  chmod u+x /usr/local/bin/wings
  success "Wings gedownload."
}

install_service() {
  output "Systemd-service installeren..."
  cp "$ETHERON_DIR/configs/wings.service" /etc/systemd/system/wings.service
  systemctl daemon-reload
  systemctl enable wings
  success "Systemd-service geïnstalleerd (nog niet gestart)."
}

configure_dbhost() {
  local conf_dir="/etc/mysql/mariadb.conf.d" bind_address="0.0.0.0"

  output "Databasehost-gebruiker instellen..."
  check_database_connection
  create_db_user "$DBHOST_USER" "$DBHOST_PASSWORD" "$DBHOST_ALLOW"
  grant_all_privileges "*" "$DBHOST_USER" "$DBHOST_ALLOW"

  if [ "$DBHOST_ALLOW" != "127.0.0.1" ]; then
    # Een eigen bestand overschrijft bind-address uit de standaardconfiguratie
    # en overleeft pakketupdates.
    case "$OS" in
    rocky | almalinux) conf_dir="/etc/my.cnf.d" ;;
    esac
    [[ "$DBHOST_ALLOW" == *:* ]] && bind_address="::"

    output "MariaDB laten luisteren op alle netwerkadressen..."
    mkdir -p "$conf_dir"
    printf '# Geplaatst door de Etheron-installer (databasehost voor Wings)\n[mysqld]\nbind-address=%s\n' \
      "$bind_address" >"$conf_dir/99-etheron-dbhost.cnf"
    systemctl restart mariadb
  fi

  success "Databasehost-gebruiker ingesteld."
}

# Wings leest een vernieuwd certificaat pas in na een herstart.
install_renew_hook() {
  mkdir -p "$(dirname "$RENEW_HOOK")"
  cat >"$RENEW_HOOK" <<'EOF'
#!/bin/sh
# Geplaatst door de Etheron-installer: herstart Wings zodat het een vernieuwd
# certificaat gebruikt. Lopende gameservers blijven gewoon draaien.
systemctl try-restart wings
EOF
  chmod 755 "$RENEW_HOOK"
}

letsencrypt() {
  local args=(certonly --standalone --no-eff-email --email "$EMAIL" -d "$FQDN")

  output "Let's Encrypt-certificaat instellen voor $FQDN..."
  install_renew_hook

  if [ -f "/etc/letsencrypt/live/$FQDN/fullchain.pem" ] && [ -f "/etc/letsencrypt/live/$FQDN/privkey.pem" ]; then
    success "Het bestaande certificaat voor $FQDN wordt gebruikt."
    return 0
  fi

  # Draait nginx op deze server, dan moet poort 80 vrij zijn tijdens het
  # aanvragen en ook bij elke automatische verlenging.
  if systemctl is-active --quiet nginx; then
    args+=(--pre-hook "systemctl stop nginx" --post-hook "systemctl start nginx")
  fi
  # Onbegeleid gaat de beheerder met LETSENCRYPT=true akkoord met de voorwaarden.
  if [ "$UNATTENDED" == true ]; then
    args+=(--non-interactive --agree-tos)
  fi

  if certbot "${args[@]}" && [ -d "/etc/letsencrypt/live/$FQDN/" ]; then
    success "Let's Encrypt-certificaat aangevraagd."
  else
    warning "Het aanvragen van een Let's Encrypt-certificaat is mislukt. Wings werkt dan zonder SSL tot je zelf een certificaat regelt."
  fi
}

# ------------------ Afronding ------------------ #

goodbye() {
  print_brake 70
  output "Wings-installatie voltooid ($WINGS_RELEASE)"
  output ""
  output "Volgende stappen:"
  output "1. Maak in het panel een node aan voor deze server."
  output "2. Zet de configuratie in /etc/pterodactyl/config.yml, of voer het"
  output "   'auto deploy'-commando uit het panel uit in deze terminal."
  output "3. Test Wings eerst in de voorgrond:  wings"
  output "4. Werkt het? Stop met CTRL+C en start de service:  systemctl start wings"
  output ""
  output "Handleiding: https://docs.pterodactyl.io/v${PANEL_VERSION:-1}/wings/installing#configuring-wings"
  if [ "$LETSENCRYPT" == true ] && [ -d "/etc/letsencrypt/live/$FQDN/" ]; then
    output ""
    output "Certificaat voor de node (vink 'Communicate over SSL' aan in het panel):"
    output "  /etc/letsencrypt/live/$FQDN/fullchain.pem"
    output "  /etc/letsencrypt/live/$FQDN/privkey.pem"
  fi
  if [ "$DBHOST" == true ]; then
    output ""
    output "Databasehost: gebruiker $DBHOST_USER, toegang vanaf $DBHOST_ALLOW."
    output "Voeg hem toe in het panel onder Admin > Databases."
  fi
  output ""
  output "${COLOR_RED}Let op${COLOR_NC}: zet swap aan voor Docker (zie de officiële documentatie)."
  if [ "$FIREWALL" == false ]; then
    output "${COLOR_RED}Let op${COLOR_NC}: de firewall is niet ingesteld. Poort 8080 en 2022 moeten open staan."
  fi
  output ""
  output "Log: $LOG_PATH"
  print_brake 70
}

perform_install() {
  validate_settings

  if [ -d /etc/pterodactyl ]; then
    error "Wings lijkt al geïnstalleerd (/etc/pterodactyl bestaat). Verwijder het eerst."
    exit 1
  fi
  if [ "$CHECK_ONLY" == true ]; then
    output "Instellingen voor Wings zijn in orde."
    exit 0
  fi
  # Interactief heeft ui/wings.sh dit al gevraagd.
  if [ "$UNATTENDED" == true ]; then
    check_virt
  fi
  if [ "$LETSENCRYPT" == true ] && [ "$VERIFY_DNS" == true ] && ! verify_dns "$FQDN"; then
    error "Zet VERIFY_DNS=false in het instellingenbestand om deze controle over te slaan."
    exit 1
  fi
  if ! resolve_wings_version; then
    error "Kon de Wings-versie niet bepalen. Controleer WINGS_RELEASE en of GitHub bereikbaar is."
    exit 1
  fi

  output "Wings $WINGS_RELEASE installeren. Dit duurt even..."
  dep_install
  download_wings
  install_service
  if [ "$DBHOST" == true ]; then
    configure_dbhost
  fi
  if [ "$LETSENCRYPT" == true ]; then
    letsencrypt
  fi
  goodbye
}

perform_install
