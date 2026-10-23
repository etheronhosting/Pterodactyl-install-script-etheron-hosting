#!/bin/bash

set -e -o pipefail

# Etheron Pterodactyl-installer
#
# Copyright (C) 2018 - 2026, Vilhelm Prytz, <vilhelm@prytznet.se> en bijdragers
#   Oorspronkelijk project: pterodactyl-installer,
#   https://github.com/pterodactyl-installer/pterodactyl-installer
# Copyright (C) 2026 Etheron Hosting (aanpassingen en uitbreidingen)
#
# Dit bestand is een aangepaste versie van pterodactyl-installer v1.4.0, in
# oktober 2026 gewijzigd door Etheron Hosting. Zie CHANGELOG.md en CREDITS.md.
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

export ETHERON_VERSION="v1.0.0"

# GitHub-repository met de releases van dit script, als "eigenaar/naam".
ETHERON_REPO="${ETHERON_REPO:-etheronhosting/Pterodactyl-install-script-etheron-hosting}"

# Release-tag (of branch) die de one-liner downloadt. Zonder ETHERON_REF is dat de
# release uit ETHERON_VERSION, en zolang die nog niet bestaat de nieuwste code van main.
ETHERON_REF_GIVEN="${ETHERON_REF:-}"
ETHERON_REF="${ETHERON_REF:-$ETHERON_VERSION}"

usage() {
  cat <<EOF
Gebruik: install.sh [actie] [opties]

Acties (zonder actie verschijnt een menu):
  web            Installeren via de webbrowser (webinstaller)
  panel          Pterodactyl Panel installeren
  wings          Pterodactyl Wings installeren
  beide          Panel en Wings op dezelfde server installeren
  verwijderen    Panel en/of Wings verwijderen
  node           Wings koppelen aan een panel (alleen met --config)

Opties:
  -c, --config BESTAND   Onbegeleid installeren met de instellingen uit BESTAND
  -h, --help             Deze hulp tonen
  -v, --version          Versie tonen

Voorbeeld: install.sh beide --config /root/etheron.conf
EOF
}

# Downloadt de broncode van een release of branch; geeft de HTTP-status terug.
download_ref() {
  # Bij een netwerkfout schrijft curl zelf 000 als status.
  curl -sSL -o "$BOOTSTRAP_DIR/installer.tar.gz" -w '%{http_code}' \
    "https://github.com/$ETHERON_REPO/archive/$1.tar.gz" || true
}

# Bij 'bash <(curl ...)' staat de rest van het project niet naast dit script.
# Download dan de volledige release en start die.
bootstrap() {
  local status=0 http_code

  if [ -z "$ETHERON_REPO" ]; then
    echo "* FOUT: ETHERON_REPO is niet ingesteld, dus de installer kan zichzelf niet downloaden." >&2
    echo "* Clone de repository en start ./install.sh vanuit die map." >&2
    exit 1
  fi
  if [[ ! "$ETHERON_REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ || ! "$ETHERON_REF" =~ ^[A-Za-z0-9_./-]+$ ]]; then
    echo "* FOUT: ongeldige ETHERON_REPO of ETHERON_REF." >&2
    exit 1
  fi
  if ! command -v curl >/dev/null 2>&1 || ! command -v tar >/dev/null 2>&1; then
    echo "* FOUT: curl en tar zijn nodig. Installeer ze met apt of dnf." >&2
    exit 1
  fi

  BOOTSTRAP_DIR=$(mktemp -d /tmp/etheron-installer.XXXXXX)
  trap 'rm -rf "$BOOTSTRAP_DIR"' EXIT

  echo "* Etheron-installer $ETHERON_REF downloaden van github.com/$ETHERON_REPO..."
  http_code=$(download_ref "$ETHERON_REF")
  # Nog geen release getagd en geen versie opgegeven: gebruik de nieuwste code.
  if [ "$http_code" == "404" ] && [ -z "$ETHERON_REF_GIVEN" ]; then
    echo "* Release $ETHERON_REF staat nog niet op GitHub; de nieuwste versie (main) wordt gebruikt."
    ETHERON_REF="main"
    http_code=$(download_ref "$ETHERON_REF")
  fi
  if [ "$http_code" == "404" ]; then
    echo "* FOUT: versie $ETHERON_REF van de installer staat (nog) niet op GitHub." >&2
    echo "* Wil je de nieuwste code van main gebruiken? Zet dan ETHERON_REF=main voor het commando:" >&2
    echo "*   ETHERON_REF=main bash <(curl -fsSL https://raw.githubusercontent.com/$ETHERON_REPO/main/install.sh) $*" >&2
    exit 1
  elif [ "$http_code" != "200" ]; then
    echo "* FOUT: downloaden van de installer is mislukt (HTTP $http_code). Controleer de internetverbinding van de server." >&2
    exit 1
  fi
  mkdir "$BOOTSTRAP_DIR/installer"
  tar -xzf "$BOOTSTRAP_DIR/installer.tar.gz" -C "$BOOTSTRAP_DIR/installer" --strip-components=1

  bash "$BOOTSTRAP_DIR/installer/install.sh" "$@" || status=$?
  exit "$status"
}

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd) || SCRIPT_DIR=""
if [ -z "$SCRIPT_DIR" ] || [ ! -f "$SCRIPT_DIR/lib/lib.sh" ]; then
  bootstrap "$@"
fi

# shellcheck source=lib/lib.sh
source "$SCRIPT_DIR/lib/lib.sh"

ACTION=""
CONFIG_FILE=""
CLEANUP_FILE=""

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
    web | webui | browser) ACTION="web" ;;
    panel | wings | node) ACTION="$1" ;;
    beide | both) ACTION="beide" ;;
    verwijderen | uninstall) ACTION="verwijderen" ;;
    -c | --config)
      if [ -z "${2:-}" ]; then
        error "--config verwacht een bestandsnaam."
        exit 1
      fi
      CONFIG_FILE="$2"
      shift
      ;;
    --config=*) CONFIG_FILE="${1#*=}" ;;
    -h | --help)
      usage
      exit 0
      ;;
    -v | --version)
      echo "$ETHERON_VERSION"
      exit 0
      ;;
    *)
      error "Onbekend argument: $1"
      usage >&2
      exit 1
      ;;
    esac
    shift
  done
}

choose_action() {
  local choice i
  local options=(
    "Panel installeren"
    "Wings installeren"
    "Panel en Wings installeren op deze server"
    "Panel en/of Wings verwijderen"
    "Installeren via de webbrowser"
  )
  local actions=(panel wings beide verwijderen web)

  while true; do
    output "Wat wil je doen?"
    for i in "${!options[@]}"; do
      output "[$i] ${options[$i]}"
    done
    echo -n "* Keuze 0-$((${#options[@]} - 1)): "
    read -r choice

    if [[ "$choice" =~ ^[0-9]$ ]] && ((choice < ${#actions[@]})); then
      ACTION="${actions[$choice]}"
      return 0
    fi
    error "Ongeldige keuze."
  done
}

run_installers() {
  local installer installers=()
  case "$ACTION" in
  panel) installers=(panel) ;;
  wings) installers=(wings) ;;
  beide) installers=(panel wings) ;;
  node) installers=(node) ;;
  esac
  # Staan er NODE_*- of PANEL_*-instellingen in het bestand, koppel Wings dan meteen aan het panel.
  if [[ "$ACTION" == wings || "$ACTION" == beide ]] &&
    { [ -n "${NODE_NAME:-}${NODE_LOCATION:-}${NODE_PORTS:-}${PANEL_URL:-}" ] || [ "${NODE_DBHOST:-}" == true ]; }; then
    installers+=(node)
  fi

  # Eerst alle instellingen controleren, zodat 'beide' niet halverwege stopt.
  for installer in "${installers[@]}"; do
    bash "$ETHERON_DIR/installers/$installer.sh" "$1" --controleren
  done
  for installer in "${installers[@]}"; do
    bash "$ETHERON_DIR/installers/$installer.sh" "$1"
  done
}

# Stelt de vragen, toont een overzicht en installeert na bevestiging.
run_interactive() {
  local config
  config=$(new_config_file)
  CLEANUP_FILE="$config"
  trap 'rm -f "$CLEANUP_FILE"' EXIT

  case "$ACTION" in
  panel) bash "$ETHERON_DIR/ui/panel.sh" "$config" ;;
  wings) bash "$ETHERON_DIR/ui/wings.sh" "$config" ;;
  beide)
    bash "$ETHERON_DIR/ui/panel.sh" "$config"
    bash "$ETHERON_DIR/ui/wings.sh" "$config"
    ;;
  esac

  output "Overzicht van je keuzes:"
  print_config_summary "$config"
  if ! ask_yes_no "Installatie starten?"; then
    error "Installatie afgebroken."
    exit 1
  fi
  run_installers "$config"
}

main() {
  echo ""
  output "$(date): etheron-installer $ETHERON_VERSION gestart"
  welcome

  if [ "$UNATTENDED" == true ]; then
    output "Onbegeleide installatie ($ACTION) met $CONFIG_FILE"
    run_installers "$CONFIG_FILE"
    return 0
  fi

  [ -n "$ACTION" ] || choose_action
  case "$ACTION" in
  verwijderen) bash "$ETHERON_DIR/installers/uninstall.sh" ;;
  web) bash "$ETHERON_DIR/webui/webinstaller.sh" start ;;
  *) run_interactive ;;
  esac
}

parse_args "$@"
require_root
detect_os

if [ -n "$CONFIG_FILE" ]; then
  case "$ACTION" in
  panel | wings | beide | node) ;;
  verwijderen | web)
    error "--config werkt alleen met panel, wings, beide of node."
    exit 1
    ;;
  *)
    error "Geef bij --config ook aan wat je wilt doen: panel, wings, beide of node."
    exit 1
    ;;
  esac
  [[ "$CONFIG_FILE" == /* ]] || CONFIG_FILE="$PWD/$CONFIG_FILE"
  load_config "$CONFIG_FILE" || exit 1
  export UNATTENDED=true
elif [ "$ACTION" == "node" ]; then
  error "Koppelen kan via de webinstaller (install.sh web) of onbegeleid met --config."
  exit 1
elif [ "$ACTION" == "web" ]; then
  # De webinstaller stelt geen vragen in de terminal en logt de installatie zelf;
  # buiten het logbestand houden, want de link bevat een toegangstoken.
  welcome
  bash "$ETHERON_DIR/webui/webinstaller.sh" start
  exit 0
elif [ ! -t 0 ]; then
  error "Geen terminal gevonden. Start de installer met 'bash <(curl -fsSL ...)' in plaats van 'curl ... | bash', of gebruik --config."
  exit 1
fi

(umask 077 && touch "$LOG_PATH")
main 2>&1 | tee -a "$LOG_PATH"
