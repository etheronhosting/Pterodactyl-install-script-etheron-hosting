#!/bin/bash
# shellcheck disable=SC2034

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

# Gedeelde functies voor install.sh, ui/ en installers/. Dit bestand wordt alleen
# gesourced en voert bij het laden zelf niets uit.

# ------------------ Variabelen ----------------- #

ETHERON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export ETHERON_DIR
export ETHERON_VERSION="${ETHERON_VERSION:-onbekend}"

# Onbegeleide modus: geen vragen, alle instellingen komen uit het instellingenbestand.
export UNATTENDED="${UNATTENDED:-false}"

LOG_PATH="/var/log/etheron-installer.log"

# Niet elke root-shell heeft de sbin-mappen in PATH.
export PATH="$PATH:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin"

# Etheron-standaarden
DEFAULT_TIMEZONE="Europe/Amsterdam"
PANEL_DIR="/var/www/pterodactyl"

# Externe bronnen
MARIADB_URL="https://downloads.mariadb.com/MariaDB/mariadb_repo_setup"
DNS_RESOLVER="8.8.8.8"
CHECKIP_URL_V4="${CHECKIP_URL_V4:-https://ipv4.icanhazip.com}"
CHECKIP_URL_V6="${CHECKIP_URL_V6:-https://ipv6.icanhazip.com}"

# Systeem, ingevuld door detect_os
OS=""
OS_VER=""
OS_VER_MAJOR=""
OS_CODENAME=""
CPU_ARCHITECTURE=""
ARCH=""
CACHE_SERVICE=""
PHP_BIN=""

# Kleuren
COLOR_YELLOW=$'\033[1;33m'
COLOR_GREEN=$'\033[0;32m'
COLOR_RED=$'\033[0;31m'
COLOR_NC=$'\033[0m'

email_regex="^[A-Za-z0-9_+-]+(\.[A-Za-z0-9_+-]+)*@([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$"

# Sleutels die in een instellingenbestand mogen staan (zie voorbeelden/).
CONFIG_KEYS=(
  FQDN EMAIL FIREWALL LETSENCRYPT ASSUME_SSL VERIFY_DNS
  PANEL_VERSION PANEL_RELEASE TIMEZONE TELEMETRY
  DB_NAME DB_USER DB_PASSWORD
  ADMIN_EMAIL ADMIN_USERNAME ADMIN_FIRSTNAME ADMIN_LASTNAME ADMIN_PASSWORD
  WINGS_RELEASE DBHOST DBHOST_USER DBHOST_PASSWORD DBHOST_ALLOW DBHOST_FIREWALL
  NODE_NAME NODE_LOCATION NODE_PORTS NODE_FQDN PANEL_URL PANEL_API_KEY
)

# Aantal fouten gevonden door check_setting.
CONFIG_ERRORS=0

# ------------------ Weergave ------------------ #

output() {
  printf '* %s\n' "$1"
}

success() {
  echo ""
  output "${COLOR_GREEN}GELUKT${COLOR_NC}: $1"
  echo ""
}

error() {
  echo ""
  printf '* %sFOUT%s: %s\n' "$COLOR_RED" "$COLOR_NC" "$1" 1>&2
  echo ""
}

warning() {
  echo ""
  output "${COLOR_YELLOW}LET OP${COLOR_NC}: $1"
  echo ""
}

print_brake() {
  local line
  printf -v line '%*s' "$1" ''
  echo "${line// /#}"
}

print_list() {
  local item
  print_brake 30
  for item in $1; do
    output "$item"
  done
  print_brake 30
  echo ""
}

# Zet meerdere regels op één regel, gescheiden door spaties.
join_lines() {
  tr '\n' ' ' <<<"$1" | sed 's/ *$//'
}

welcome() {
  print_brake 70
  output "Etheron Pterodactyl-installer $ETHERON_VERSION"
  output ""
  output "Gebaseerd op pterodactyl-installer door Vilhelm Prytz en bijdragers (GPLv3)."
  output "Niet verbonden aan het officiële Pterodactyl-project."
  output ""
  output "Systeem: $OS $OS_VER ($CPU_ARCHITECTURE)"
  print_brake 70
}

# ------------------- Systeem ------------------ #

require_root() {
  if [[ $EUID -ne 0 ]]; then
    error "Dit script moet als root draaien (bijvoorbeeld na 'sudo -i')."
    exit 1
  fi
  if [ -z "${HOME:-}" ]; then
    error "De omgevingsvariabele HOME moet ingesteld zijn."
    exit 1
  fi
}

detect_os() {
  local supported=false

  if [ -f /etc/os-release ]; then
    OS=$(. /etc/os-release && echo "${ID:-}")
    OS_VER=$(. /etc/os-release && echo "${VERSION_ID:-}")
    OS_CODENAME=$(. /etc/os-release && echo "${VERSION_CODENAME:-}")
  fi
  OS="${OS,,}"
  if [ "$OS" == "debian" ] && [ -z "$OS_VER" ] && [ -f /etc/debian_version ]; then
    OS_VER=$(cat /etc/debian_version)
  fi
  OS_VER_MAJOR="${OS_VER%%.*}"
  CPU_ARCHITECTURE=$(uname -m)

  case "$CPU_ARCHITECTURE" in
  x86_64) ARCH=amd64 ;;
  arm64 | aarch64) ARCH=arm64 ;;
  *)
    error "Alleen x86_64 en arm64 worden ondersteund."
    exit 1
    ;;
  esac

  # Pakket- en servicenamen verschillen per distributiefamilie.
  CACHE_SERVICE="redis-server"
  PHP_BIN="/usr/bin/php8.3"
  case "$OS" in
  ubuntu)
    [[ "$OS_VER_MAJOR" =~ ^(22|24|26)$ ]] && supported=true
    export DEBIAN_FRONTEND=noninteractive
    ;;
  debian)
    [[ "$OS_VER_MAJOR" =~ ^(12|13)$ ]] && supported=true
    export DEBIAN_FRONTEND=noninteractive
    ;;
  rocky | almalinux)
    [[ "$OS_VER_MAJOR" =~ ^(8|9|10)$ ]] && supported=true
    PHP_BIN="/usr/bin/php"
    CACHE_SERVICE="redis"
    [ "$OS_VER_MAJOR" == "10" ] && CACHE_SERVICE="valkey"
    ;;
  esac

  if [ "$supported" != true ]; then
    error "${OS:-Dit besturingssysteem} ${OS_VER} wordt niet ondersteund."
    exit 1
  fi
}

# Het panel is vooral getest op x86_64.
check_arch_panel() {
  if [ "$ARCH" == "amd64" ]; then
    return 0
  fi
  warning "CPU-architectuur $CPU_ARCHITECTURE gedetecteerd. Het panel is vooral getest op x86_64; andere architecturen kunnen problemen geven."
  if [ "$UNATTENDED" != true ] && ! ask_yes_no "Toch doorgaan?"; then
    error "Installatie afgebroken."
    exit 1
  fi
  return 0
}

# Docker werkt niet (goed) op OpenVZ en alleen met nesting op LXC.
check_virt() {
  local virt
  output "Virtualisatie controleren..."
  ensure_command virt-what virt-what virt-what
  virt=$(virt-what 2>/dev/null || true)

  case "$virt" in
  *openvz* | *lxc*)
    warning "Virtualisatie '$(join_lines "$virt")' gedetecteerd. Docker werkt hier vaak niet of alleen met nesting; vraag dit na bij de hostingprovider."
    if [ "$UNATTENDED" != true ] && ! ask_yes_no "Toch doorgaan?"; then
      error "Installatie afgebroken."
      exit 1
    fi
    ;;
  "")
    output "Geen virtualisatie gedetecteerd (fysieke server)."
    ;;
  *)
    output "Virtualisatie: $(join_lines "$virt")."
    ;;
  esac
  return 0
}

# --------------- Pakketbeheer --------------- #

# Gebruik: update_repos [--quiet]
update_repos() {
  local args=()
  [ "${1:-}" == "--quiet" ] && args+=(-qq)

  case "$OS" in
  ubuntu | debian)
    output "Pakketbronnen bijwerken..."
    apt-get update -y "${args[@]}"
    ;;
  esac
}

# Gebruik: install_packages [--quiet] pakket...
install_packages() {
  local args=(-y)
  if [ "${1:-}" == "--quiet" ]; then
    shift
    case "$OS" in
    ubuntu | debian) args+=(-qq) ;;
    *) args+=(-q) ;;
    esac
  fi

  case "$OS" in
  ubuntu | debian) apt-get "${args[@]}" install "$@" ;;
  rocky | almalinux) dnf "${args[@]}" install "$@" ;;
  esac
}

# Installeert een pakket als een commando ontbreekt.
# Gebruik: ensure_command commando pakket-debian pakket-el
ensure_command() {
  if command -v "$1" >/dev/null 2>&1; then
    return 0
  fi
  case "$OS" in
  ubuntu | debian)
    update_repos --quiet
    install_packages --quiet "$2"
    ;;
  rocky | almalinux)
    install_packages --quiet "$3"
    ;;
  esac
}

# Minimale installaties hebben soms geen curl, en dan vaak ook geen CA-certificaten.
ensure_curl() {
  if command -v curl >/dev/null 2>&1; then
    return 0
  fi
  case "$OS" in
  ubuntu | debian)
    update_repos --quiet
    install_packages --quiet curl ca-certificates
    ;;
  rocky | almalinux)
    install_packages --quiet curl ca-certificates
    ;;
  esac
}

# ------------------ Versies ------------------- #

github_api() {
  curl -fsSL -H "Accept: application/vnd.github+json" "https://api.github.com/$1"
}

# Nieuwste stabiele release-tag van een GitHub-repository, optioneel binnen één
# hoofdversie. Gebruik: get_latest_release eigenaar/naam [hoofdversie]
get_latest_release() {
  local repo="$1" major="${2:-}" releases tag page=1

  if [ -z "$major" ]; then
    releases=$(github_api "repos/$repo/releases/latest") || return 1
    tag=$(jq -er 'select(.draft == false and .prerelease == false) | .tag_name' <<<"$releases") || return 1
  else
    while true; do
      releases=$(github_api "repos/$repo/releases?per_page=100&page=$page") || return 1
      jq -e 'type == "array" and length > 0' <<<"$releases" >/dev/null || return 1
      tag=$(jq -r --arg major "$major" '[.[] | select(.draft == false and .prerelease == false) |
        .tag_name | select(test("^v" + $major + "\\.[0-9]+\\.[0-9]+$"))] |
        sort_by(ltrimstr("v") | split(".") | map(tonumber)) | last // empty' <<<"$releases") || return 1
      [ -n "$tag" ] && break
      page=$((page + 1))
    done
  fi

  [[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  echo "$tag"
}

# Bepaalt PANEL_RELEASE (tag of commit), PANEL_VERSION_LABEL en PANEL_DL_URL.
resolve_panel_version() {
  ensure_curl
  ensure_command jq jq jq
  output "Versie-informatie van het panel ophalen..."

  if [ "$PANEL_VERSION" == "2" ]; then
    if [ -z "$PANEL_RELEASE" ]; then
      PANEL_RELEASE=$(github_api repos/pterodactyl/panel/commits/2.0-develop | jq -er '.sha') || return 1
    fi
    [[ "$PANEL_RELEASE" =~ ^[0-9a-f]{40}$ ]] || return 1
    PANEL_VERSION_LABEL="2.0-develop@${PANEL_RELEASE:0:12} (experimenteel)"
    PANEL_DL_URL="https://github.com/pterodactyl/panel/archive/$PANEL_RELEASE.tar.gz"
  else
    if [ -z "$PANEL_RELEASE" ]; then
      PANEL_RELEASE=$(get_latest_release pterodactyl/panel 1) || return 1
    fi
    [[ "$PANEL_RELEASE" =~ ^v1\.[0-9]+\.[0-9]+$ ]] || return 1
    PANEL_VERSION_LABEL="$PANEL_RELEASE"
    PANEL_DL_URL="https://github.com/pterodactyl/panel/releases/download/$PANEL_RELEASE/panel.tar.gz"
  fi
}

# Bepaalt WINGS_RELEASE en WINGS_DL_URL.
resolve_wings_version() {
  ensure_curl
  ensure_command jq jq jq
  output "Versie-informatie van Wings ophalen..."

  if [ -z "$WINGS_RELEASE" ]; then
    WINGS_RELEASE=$(get_latest_release pterodactyl/wings) || return 1
  fi
  valid_release_tag "$WINGS_RELEASE" || return 1
  WINGS_DL_URL="https://github.com/pterodactyl/wings/releases/download/$WINGS_RELEASE/wings_linux_$ARCH"
}

# ----------------- Validatie ------------------ #

array_contains_element() {
  local e match="$1"
  shift
  for e; do [[ "$e" == "$match" ]] && return 0; done
  return 1
}

is_yes() {
  [[ "$1" =~ ^([JjYy]|[Jj][Aa]|[Yy][Ee][Ss])$ ]]
}

valid_bool() {
  [[ "$1" == "true" || "$1" == "false" ]]
}

valid_email() {
  local local_part="${1%@*}"
  [[ ${#1} -le 191 && ${#local_part} -le 64 && "$1" =~ ${email_regex} ]]
}

is_ip_address() {
  local address="$1"
  if [[ "$address" == '['* || "$address" == *']' ]]; then
    [[ "$address" == '['*']' && "$address" == *:* ]] || return 1
    address="${address#[}"
    address="${address%]}"
  fi
  local part
  local parts
  local count=0
  if [[ "$address" == *:* ]]; then
    if [[ "$address" == *.* ]]; then
      is_ip_address "${address##*:}" || return 1
      address="${address%:*}:0:0"
    fi
    [[ "$address" != *[!0-9a-fA-F:]* && "$address" != *:::* ]] || return 1
    [[ "$address" != :* || "$address" == ::* ]] || return 1
    [[ "$address" != *: || "$address" == *:: ]] || return 1
    if [[ "$address" == *::* ]]; then
      [[ "${address#*::}" != *::* ]] || return 1
    fi
    IFS=: read -r -a parts <<<"$address"
    for part in "${parts[@]}"; do
      [ -z "$part" ] && continue
      [ "${#part}" -le 4 ] || return 1
      count=$((count + 1))
    done
    [[ "$address" == *::* && "$count" -lt 8 || "$count" == 8 && "$address" != *::* ]]
  else
    [[ "$address" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || return 1
    IFS=. read -r -a parts <<<"$address"
    for part in "${parts[@]}"; do
      [[ "$part" == 0 || "$part" != 0* ]] || return 1
      ((10#$part <= 255)) || return 1
    done
  fi
}

# Hostnaam of IP-adres.
valid_hostname() {
  if is_ip_address "$1"; then
    return 0
  fi
  [[ ${#1} -le 253 && ! "$1" =~ ^[0-9.]+$ && "$1" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)*[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.?$ ]]
}

# Publieke domeinnaam: geen IP-adres en geen localhost. Nodig voor Let's Encrypt.
valid_domain() {
  valid_hostname "$1" && ! is_ip_address "$1" && [[ "${1%.}" == *.* ]]
}

valid_release_tag() {
  [[ "$1" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

valid_panel_version() {
  [[ "$1" =~ ^[12]$ ]]
}

valid_timezone() {
  [ -n "$1" ] && grep -qxF -- "$1" "$ETHERON_DIR/configs/valid_timezones.txt"
}

valid_database_identifier() {
  [[ "$1" =~ ^[a-zA-Z0-9_]+$ && ${#1} -le 64 ]]
}

# Databasewachtwoorden komen in SQL en in .env terecht: geen tekens die daar
# geëscaped moeten worden.
valid_db_password() {
  [[ -n "$1" && ${#1} -le 128 && ! "$1" =~ [[:space:][:cntrl:]] && "$1" != *[\'\"\\\$\`\#]* ]]
}

valid_dbhost_allow() {
  [[ "$1" == "%" ]] || valid_hostname "$1"
}

valid_node_name() {
  local re='^[A-Za-z0-9_ .-]{1,100}$'
  [[ "$1" =~ $re ]]
}

valid_location_short() {
  [[ "$1" =~ ^[A-Za-z0-9_.-]{1,60}$ ]]
}

# Eén poort of een reeks (bijv. 25565-25600) tussen 1025 en 65535, maximaal 1000 poorten.
valid_port_range() {
  local start end
  [[ "$1" =~ ^([0-9]{4,5})(-([0-9]{4,5}))?$ ]] || return 1
  start=$((10#${BASH_REMATCH[1]}))
  end=$((10#${BASH_REMATCH[3]:-${BASH_REMATCH[1]}}))
  ((start >= 1025 && end <= 65535 && start <= end && end - start < 1000))
}

valid_panel_url() {
  [[ "$1" =~ ^https?://[A-Za-z0-9.-]+(:[0-9]{1,5})?/?$ ]]
}

valid_api_key() {
  [[ "$1" =~ ^ptla_[A-Za-z0-9]{20,}$ ]]
}

valid_admin_username() {
  [[ "$1" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]+[a-zA-Z0-9]$ && ${#1} -le 191 ]]
}

valid_admin_name() {
  [[ "$1" =~ [^[:space:]] && ! "$1" =~ [[:cntrl:]] && ${#1} -le 191 ]]
}

valid_admin_password() {
  [[ ${#1} -ge 8 && "$1" =~ [^[:space:]] && ! "$1" =~ [[:cntrl:]] ]]
}

# Alleen letters en cijfers, zodat het wachtwoord nergens geëscaped hoeft te worden.
gen_passwd() {
  local password=""
  while [ ${#password} -lt "$1" ]; do
    password+=$(head -c 256 /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9')
  done
  echo "${password:0:$1}"
}

# ------------------- Invoer ------------------- #

# Gebruik: ask_yes_no "vraag" [j|n]   (standaard n)
ask_yes_no() {
  local answer default="${2:-n}" hint="(j/N)"
  [ "$default" == "j" ] && hint="(J/n)"
  echo -n "* $1 $hint: "
  read -r answer || true
  is_yes "${answer:-$default}"
}

# Gebruik: required_input variabele "vraag" "foutmelding bij leeg" [standaard]
required_input() {
  local __resultvar=$1
  local result=''

  while [ -z "$result" ]; do
    echo -n "* ${2}"
    read -r result

    if [ -z "${3}" ]; then
      [ -z "$result" ] && result="${4}"
    else
      [ -z "$result" ] && error "${3}"
    fi
  done

  printf -v "$__resultvar" '%s' "$result"
}

# Gebruik: email_input variabele "vraag" "foutmelding" [standaard]
email_input() {
  local __resultvar=$1
  local result=''

  while ! valid_email "$result"; do
    echo -n "* ${2}"
    read -r result
    [ -z "$result" ] && result="${4}"

    valid_email "$result" || error "${3}"
  done

  printf -v "$__resultvar" '%s' "$result"
}

# Leest een wachtwoord zonder het te tonen (een * per teken).
# Gebruik: password_input variabele "vraag" "foutmelding bij leeg" [standaard]
password_input() {
  local __resultvar=$1
  local result=''
  local default="${4:-}"
  local char

  while [ -z "$result" ]; do
    echo -n "* ${2}"

    # Gebaseerd op https://stackoverflow.com/a/22940001
    while true; do
      IFS= read -r -s -n1 char || return 1
      if [[ -z $char ]]; then
        printf '\n'
        break
      fi
      if [[ $char == $'\x7f' || $char == $'\b' ]]; then
        if [ -n "$result" ]; then
          result=${result%?}
          printf '\b \b'
        fi
      else
        result+=$char
        printf '*'
      fi
    done
    [ -z "$result" ] && [ -n "$default" ] && result="$default"
    [ -z "$result" ] && error "${3}"
  done

  printf -v "$__resultvar" '%s' "$result"
}

# ------------------ Database ------------------ #

# MariaDB 10.3 op EL8 kent alleen de oude clientnaam 'mysql'.
mariadb() {
  if type -P mariadb >/dev/null 2>&1; then
    command mariadb "$@"
  else
    command mysql "$@"
  fi
}

check_database_connection() {
  mariadb -u root -e "SELECT 1;" >/dev/null || {
    error "Kan als root geen verbinding maken met MariaDB. Stel root-toegang in via $HOME/.my.cnf en probeer het opnieuw."
    return 1
  }
}

db_user_exists() {
  [ "$(mariadb -u root -N -e "SELECT COUNT(*) FROM mysql.user WHERE user = '$1' AND host = '$2';")" != "0" ]
}

# Gebruik: create_db_user naam wachtwoord [host]
create_db_user() {
  local db_user_name="$1"
  local db_user_password="${2//\'/\'\'}"
  local db_host="${3:-127.0.0.1}"

  output "Databasegebruiker '$db_user_name'@'$db_host' aanmaken..."
  if db_user_exists "$db_user_name" "$db_host"; then
    error "Databasegebruiker '$db_user_name'@'$db_host' bestaat al."
    return 1
  fi

  mariadb -u root -e "SET SESSION sql_mode = 'NO_BACKSLASH_ESCAPES'; CREATE USER '$db_user_name'@'$db_host' IDENTIFIED BY '$db_user_password';"
  mariadb -u root -e "FLUSH PRIVILEGES;"
}

# Gebruik: grant_all_privileges database|* gebruiker [host]
grant_all_privileges() {
  local db_name="$1"
  local db_user_name="$2"
  local db_host="${3:-127.0.0.1}"
  local db_identifier="\`$db_name\`"
  [ "$db_name" != "*" ] || db_identifier="*"

  output "Alle rechten op $db_name toekennen aan $db_user_name..."
  mariadb -u root -e "GRANT ALL PRIVILEGES ON $db_identifier.* TO '$db_user_name'@'$db_host' WITH GRANT OPTION;"
  mariadb -u root -e "FLUSH PRIVILEGES;"
}

# Gebruik: create_db database gebruiker [host]
create_db() {
  local db_name="$1"
  local db_user_name="$2"
  local db_host="${3:-127.0.0.1}"

  output "Database $db_name aanmaken..."
  if [ -n "$(mariadb -u root -N -e "SHOW DATABASES LIKE '$db_name';")" ]; then
    error "Database $db_name bestaat al."
    return 1
  fi
  mariadb -u root -e "CREATE DATABASE \`$db_name\`;"
  grant_all_privileges "$db_name" "$db_user_name" "$db_host"
}

# ------------------ Firewall ------------------ #

firewall_name() {
  case "$OS" in
  ubuntu | debian) echo "UFW" ;;
  *) echo "firewalld" ;;
  esac
}

# Poorten waarop sshd luistert, zodat de firewall SSH niet afsluit.
ssh_ports() {
  local ports
  ports=$(sshd -T 2>/dev/null | awk '$1 == "port" { print $2 }' | sort -un | tr '\n' ' ') || true
  echo "${ports:-22}"
}

# Zet de firewall aan met de opgegeven TCP-poorten open. De poorten worden eerst
# toegestaan en pas daarna wordt de firewall ingeschakeld, zodat een lopende
# SSH-sessie niet wordt afgesloten.
setup_firewall() {
  local port ports=("$@")
  output "Firewall ($(firewall_name)) instellen..."

  # Via de webinstaller moet de browser de wizard tijdens de installatie blijven
  # bereiken; de webinstaller haalt deze regel weg als hij stopt.
  if [ -n "${ETHERON_WEB_PORT:-}" ]; then
    ports+=("$ETHERON_WEB_PORT")
  fi

  case "$OS" in
  ubuntu | debian)
    ensure_command ufw ufw ufw
    for port in "${ports[@]}"; do
      ufw allow "$port/tcp" >/dev/null
      output "Poort $port/tcp toegestaan"
    done
    ufw --force enable >/dev/null
    ;;
  rocky | almalinux)
    ensure_command firewall-cmd firewalld firewalld
    systemctl enable --now firewalld >/dev/null 2>&1
    for port in "${ports[@]}"; do
      firewall-cmd --zone=public --permanent --add-port="$port/tcp" >/dev/null
      output "Poort $port/tcp toegestaan"
    done
    firewall-cmd --reload >/dev/null
    ;;
  esac

  success "Firewall ingeschakeld."
  return 0
}

# Staat één TCP-poort alleen toe vanaf één IP-adres.
# Gebruik: firewall_allow_from ip-adres poort
firewall_allow_from() {
  local source="${1#[}" family=ipv4
  source="${source%]}"

  case "$OS" in
  ubuntu | debian)
    ufw allow proto tcp from "$source" to any port "$2" >/dev/null
    ;;
  rocky | almalinux)
    [[ "$source" == *:* ]] && family=ipv6
    firewall-cmd --zone=public --permanent \
      --add-rich-rule="rule family=\"$family\" source address=\"$source\" port port=\"$2\" protocol=\"tcp\" accept" >/dev/null
    firewall-cmd --reload >/dev/null
    ;;
  esac
  output "Poort $2/tcp toegestaan vanaf $source"
}

# ------------- Instellingenbestand ------------- #

# Maakt een leeg instellingenbestand dat alleen root kan lezen.
new_config_file() {
  (umask 077 && mktemp /tmp/etheron-instellingen.XXXXXX)
}

# Een instellingenbestand bevat wachtwoorden: het moet van de huidige gebruiker
# zijn en mag niet door anderen gelezen of gewijzigd kunnen worden.
check_config_permissions() {
  local file="$1" mode

  if [ ! -f "$file" ] || [ -L "$file" ]; then
    error "Instellingenbestand '$file' bestaat niet of is geen gewoon bestand."
    return 1
  fi
  if [ ! -O "$file" ]; then
    error "Instellingenbestand '$file' moet eigendom zijn van $(id -un)."
    return 1
  fi
  mode=$(stat -c %a "$file")
  if ((8#$mode & 8#077)); then
    error "Instellingenbestand '$file' is toegankelijk voor anderen (rechten $mode). Los dit op met: chmod 600 '$file'"
    return 1
  fi
}

# Leest SLEUTEL=waarde-regels in de gelijknamige variabelen. Alleen sleutels uit
# CONFIG_KEYS zijn toegestaan; het bestand wordt nooit als script uitgevoerd.
load_config() {
  local file="$1" line key value lineno=0 seen=" "

  check_config_permissions "$file" || return 1

  # Alleen het bestand bepaalt de instellingen, niet de omgeving.
  for key in "${CONFIG_KEYS[@]}"; do
    printf -v "$key" '%s' ""
  done

  while IFS= read -r line || [ -n "$line" ]; do
    lineno=$((lineno + 1))
    line="${line%$'\r'}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" || "$line" == \#* ]] && continue

    if [[ ! "$line" =~ ^([A-Z_]+)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
      error "$file, regel $lineno: verwacht SLEUTEL=waarde."
      return 1
    fi
    key="${BASH_REMATCH[1]}"
    value="${BASH_REMATCH[2]}"
    if [[ "$value" =~ ^\"(.*)\"$ || "$value" =~ ^\'(.*)\'$ ]]; then
      value="${BASH_REMATCH[1]}"
    fi

    if ! array_contains_element "$key" "${CONFIG_KEYS[@]}"; then
      error "$file, regel $lineno: onbekende instelling '$key'."
      return 1
    fi
    if [[ "$seen" == *" $key "* ]]; then
      error "$file, regel $lineno: '$key' staat er meer dan één keer in."
      return 1
    fi
    if [[ "$value" =~ [[:cntrl:]] ]]; then
      error "$file, regel $lineno: '$key' bevat ongeldige tekens."
      return 1
    fi

    seen+="$key "
    printf -v "$key" '%s' "$value"
  done <"$file"

  return 0
}

# Zet SLEUTEL="waarde" in een instellingenbestand; een bestaande regel wordt vervangen.
config_set() {
  local file="$1" key="$2" value="$3" tmp
  tmp=$(new_config_file)
  grep -v "^$key=" "$file" >"$tmp" || true
  printf '%s="%s"\n' "$key" "$value" >>"$tmp"
  cat "$tmp" >"$file"
  rm -f "$tmp"
}

# Controleert één instelling en telt fouten op in CONFIG_ERRORS.
# Gebruik: check_setting SLEUTEL validator "uitleg"
check_setting() {
  if [ -z "${!1}" ]; then
    error "$1 ontbreekt ($3)."
    CONFIG_ERRORS=$((CONFIG_ERRORS + 1))
  elif ! "$2" "${!1}"; then
    error "Ongeldige waarde voor $1 ($3)."
    CONFIG_ERRORS=$((CONFIG_ERRORS + 1))
  fi
  return 0
}

describe_setting() {
  case "$1" in
  FQDN) echo "Domein (FQDN)" ;;
  EMAIL) echo "E-mailadres" ;;
  FIREWALL) echo "Firewall instellen" ;;
  LETSENCRYPT) echo "Let's Encrypt" ;;
  ASSUME_SSL) echo "Eigen SSL-certificaat" ;;
  VERIFY_DNS) echo "DNS controleren" ;;
  PANEL_VERSION) echo "Panel-versie" ;;
  PANEL_RELEASE) echo "Panel-release" ;;
  TIMEZONE) echo "Tijdzone" ;;
  TELEMETRY) echo "Telemetrie" ;;
  DB_NAME) echo "Database" ;;
  DB_USER) echo "Databasegebruiker" ;;
  DB_PASSWORD) echo "Databasewachtwoord" ;;
  ADMIN_EMAIL) echo "Beheerder: e-mail" ;;
  ADMIN_USERNAME) echo "Beheerder: gebruikersnaam" ;;
  ADMIN_FIRSTNAME) echo "Beheerder: voornaam" ;;
  ADMIN_LASTNAME) echo "Beheerder: achternaam" ;;
  ADMIN_PASSWORD) echo "Beheerder: wachtwoord" ;;
  WINGS_RELEASE) echo "Wings-release" ;;
  DBHOST) echo "Databasehost-gebruiker" ;;
  DBHOST_USER) echo "Databasehost: gebruiker" ;;
  DBHOST_PASSWORD) echo "Databasehost: wachtwoord" ;;
  DBHOST_ALLOW) echo "Databasehost: toegang vanaf" ;;
  DBHOST_FIREWALL) echo "Databasehost: poort 3306 open" ;;
  NODE_NAME) echo "Node: naam" ;;
  NODE_LOCATION) echo "Node: locatie" ;;
  NODE_PORTS) echo "Node: poorten voor gameservers" ;;
  NODE_FQDN) echo "Node: adres" ;;
  PANEL_URL) echo "Panel-adres" ;;
  PANEL_API_KEY) echo "API-sleutel van het panel" ;;
  *) echo "$1" ;;
  esac
}

# Toont de instellingen uit een bestand, met wachtwoorden verborgen.
print_config_summary() {
  local key value
  load_config "$1" || return 1

  print_brake 62
  for key in "${CONFIG_KEYS[@]}"; do
    value="${!key}"
    [ -n "$value" ] || continue
    case "$key" in *PASSWORD | *API_KEY) value="(verborgen)" ;; esac
    case "$value" in
    true) value="ja" ;;
    false) value="nee" ;;
    esac
    printf '* %-32s %s\n' "$(describe_setting "$key"):" "$value"
  done
  print_brake 62
}

# -------------------- DNS --------------------- #

# Adressen uit de A- en AAAA-records van een hostnaam, volgens een publieke resolver.
dns_addresses() {
  local type
  for type in A AAAA; do
    dig +short +time=5 +tries=2 "@$DNS_RESOLVER" "$1" "$type" 2>/dev/null | grep -E '^[0-9a-fA-F:.]+$' || true
  done | tr 'A-F' 'a-f' | LC_ALL=C sort -u
}

# Globale adressen op de netwerkkaarten van deze server.
local_addresses() {
  ip -o addr show scope global 2>/dev/null | awk '{ print $4 }' | cut -d/ -f1 | tr 'A-F' 'a-f' | LC_ALL=C sort -u
}

# Publieke adressen van deze server volgens een externe dienst (voor servers achter NAT).
public_addresses() {
  {
    curl -4 -fsS --max-time 5 "$CHECKIP_URL_V4" 2>/dev/null || true
    curl -6 -fsS --max-time 5 "$CHECKIP_URL_V6" 2>/dev/null || true
  } | tr -d ' \r' | tr 'A-F' 'a-f' | { grep -E '^[0-9a-f:.]+$' || true; } | LC_ALL=C sort -u
}

# Adres waarop deze server van buitenaf bereikbaar is: bij voorkeur het publieke IPv4-adres.
server_address() {
  local address=""
  address=$(public_addresses | grep -v ':' | head -n1) || true
  [ -n "$address" ] || address=$(local_addresses | grep -v ':' | head -n1) || true
  [ -n "$address" ] || address=$(public_addresses | head -n1) || true
  [ -n "$address" ] || address=$(local_addresses | head -n1) || true
  echo "$address"
}

# Gratis nip.io-adres voor een IPv4-adres, bijv. 192.0.2.10 -> 192-0-2-10.nip.io.
# Leeg voor IPv6 of ongeldige invoer (nip.io kent geen IPv6).
nip_name() {
  if is_ip_address "$1" && [[ "$1" != *:* ]]; then
    echo "${1//./-}.nip.io"
  fi
}

# nip.io-adres van deze server (leeg zonder publiek IPv4-adres).
server_nip_name() {
  # Uitvoer van een eventuele installatie van curl niet in het resultaat laten belanden.
  ensure_curl >&2
  nip_name "$(server_address)"
}

# Controleert of alle A- en AAAA-records van $1 naar deze server wijzen. Let's
# Encrypt kan elk van die adressen gebruiken, dus één fout record is genoeg om
# de aanvraag te laten mislukken.
verify_dns() {
  local fqdn="$1" records addresses unmatched

  ensure_curl
  ensure_command dig bind9-dnsutils bind-utils
  output "DNS controleren voor $fqdn..."

  records=$(dns_addresses "$fqdn")
  if [ -z "$records" ]; then
    error "Er is geen A- of AAAA-record gevonden voor $fqdn."
    return 1
  fi

  addresses=$(local_addresses)
  unmatched=$(LC_ALL=C comm -23 <(echo "$records") <(echo "$addresses"))
  if [ -n "$unmatched" ]; then
    output "Publiek IP-adres opvragen via $CHECKIP_URL_V4 en $CHECKIP_URL_V6..."
    addresses=$(printf '%s\n%s\n' "$addresses" "$(public_addresses)" | sed '/^$/d' | LC_ALL=C sort -u)
    unmatched=$(LC_ALL=C comm -23 <(echo "$records") <(echo "$addresses"))
  fi

  if [ -n "$unmatched" ]; then
    error "$fqdn wijst niet (alleen) naar deze server."
    output "DNS-records van $fqdn: $(join_lines "$records")"
    output "Adressen van deze server: $(join_lines "$addresses")"
    output "Hoort niet bij deze server: $(join_lines "$unmatched")"
    output "Gebruik je Cloudflare? Zet de proxy (oranje wolk) dan uit voor dit record."
    return 1
  fi

  success "DNS klopt: $fqdn wijst naar deze server."
}
