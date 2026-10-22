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

export ETHERON_VERSION="v1.0.0"

# GitHub-repository met de releases van dit script, als "eigenaar/naam".
ETHERON_REPO="${ETHERON_REPO:-etheronhosting/Pterodactyl-install-script-etheron-hosting}"

# Release-tag (of branch) die de one-liner downloadt.
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

Opties:
  -c, --config BESTAND   Onbegeleid installeren met de instellingen uit BESTAND
  -h, --help             Deze hulp tonen
  -v, --version          Versie tonen

Voorbeeld: install.sh beide --config /root/etheron.conf
EOF
}

# Bij 'bash <(curl ...)' staat de rest van het project niet naast dit script.
# Download dan de volledige release en start die.
bootstrap() {
  local status=0

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
  curl -fsSL "https://github.com/$ETHERON_REPO/archive/$ETHERON_REF.tar.gz" | tar -xz -C "$BOOTSTRAP_DIR" --strip-components=1

  bash "$BOOTSTRAP_DIR/install.sh" "$@" || status=$?
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
    panel | wings) ACTION="$1" ;;
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
  esac

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
  panel | wings | beide) ;;
  verwijderen | web)
    error "--config werkt alleen met panel, wings of beide."
    exit 1
    ;;
  *)
    error "Geef bij --config ook aan wat je wilt installeren: panel, wings of beide."
    exit 1
    ;;
  esac
  [[ "$CONFIG_FILE" == /* ]] || CONFIG_FILE="$PWD/$CONFIG_FILE"
  load_config "$CONFIG_FILE" || exit 1
  export UNATTENDED=true
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
