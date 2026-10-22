#!/bin/bash

# Tests voor de functies in lib/lib.sh die geen root, netwerk of
# pakketbeheerder nodig hebben. Draai ze op Linux (of WSL):
#   bash tests/lib_test.sh

# shellcheck source=../lib/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/lib.sh"

PASSED=0
FAILED=0

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# Gebruik: pass_if "beschrijving" commando [argumenten...]
pass_if() {
  local description="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    PASSED=$((PASSED + 1))
  else
    FAILED=$((FAILED + 1))
    echo "MISLUKT (verwacht gelukt): $description"
  fi
}

# Gebruik: fail_if "beschrijving" commando [argumenten...]
fail_if() {
  local description="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    FAILED=$((FAILED + 1))
    echo "MISLUKT (verwacht fout): $description"
  else
    PASSED=$((PASSED + 1))
  fi
}

# Schrijft een instellingenbestand met rechten 600 en geeft het pad terug.
write_config() {
  printf '%s' "$2" >"$TMP_DIR/$1"
  chmod 600 "$TMP_DIR/$1"
  echo "$TMP_DIR/$1"
}

is_alphanumeric() {
  [[ "$1" =~ ^[A-Za-z0-9]+$ ]]
}

# ------------------- is_yes ------------------- #

for answer in j J ja Ja JA y Y yes YES; do
  pass_if "is_yes '$answer'" is_yes "$answer"
done
for answer in n N nee no "" jaa x; do
  fail_if "is_yes '$answer'" is_yes "$answer"
done

# ----------------- validatie ------------------ #

pass_if "geldig e-mailadres" valid_email beheer@etheron.nl
pass_if "e-mailadres met plus" valid_email beheer+test@etheron.nl
fail_if "e-mailadres zonder domein" valid_email beheer@
fail_if "geen e-mailadres" valid_email geen-email
fail_if "leeg e-mailadres" valid_email ""

pass_if "IPv4" is_ip_address 192.0.2.1
pass_if "IPv6" is_ip_address 2001:db8::1
pass_if "IPv6 tussen haken" is_ip_address "[2001:db8::1]"
fail_if "IPv4 buiten bereik" is_ip_address 256.1.1.1
fail_if "IPv4 met voorloopnul" is_ip_address 01.2.3.4
fail_if "hostnaam is geen IP" is_ip_address panel.etheron.nl

pass_if "hostnaam" valid_hostname panel.etheron.nl
pass_if "hostnaam met punt aan het eind" valid_hostname panel.etheron.nl.
pass_if "localhost" valid_hostname localhost
pass_if "IP als hostnaam" valid_hostname 192.0.2.1
fail_if "hostnaam begint met streepje" valid_hostname -panel.etheron.nl
fail_if "hostnaam met underscore" valid_hostname panel_etheron.nl
fail_if "hostnaam met spatie" valid_hostname "panel etheron.nl"

pass_if "domein" valid_domain panel.etheron.nl
fail_if "IP is geen domein" valid_domain 192.0.2.1
fail_if "IPv6 is geen domein" valid_domain "[2001:db8::1]"
fail_if "localhost is geen domein" valid_domain localhost

pass_if "databasewachtwoord met leestekens" valid_db_password 'Abc123!@%^&*()-_=+'
# shellcheck disable=SC2016
for bad in "met spatie" "a'b" 'a"b' 'a\b' 'a$b' 'a#b' 'a`b' ""; do
  fail_if "databasewachtwoord '$bad'" valid_db_password "$bad"
done
fail_if "databasewachtwoord te lang" valid_db_password "$(printf 'a%.0s' {1..129})"

password=$(gen_passwd 48)
pass_if "gen_passwd geeft 48 tekens" test "${#password}" -eq 48
pass_if "gen_passwd is alfanumeriek" is_alphanumeric "$password"
pass_if "gen_passwd is geldig databasewachtwoord" valid_db_password "$password"

pass_if "tijdzone Europe/Amsterdam" valid_timezone Europe/Amsterdam
fail_if "onbekende tijdzone" valid_timezone Mars/Olympus
fail_if "lege tijdzone" valid_timezone ""

pass_if "gebruikersnaam" valid_admin_username beheerder
pass_if "gebruikersnaam met punt" valid_admin_username etheron.beheer
fail_if "gebruikersnaam te kort" valid_admin_username ab
fail_if "gebruikersnaam begint met punt" valid_admin_username .beheer
pass_if "naam met accent" valid_admin_name "Jörg"
fail_if "lege naam" valid_admin_name " "
pass_if "beheerderswachtwoord" valid_admin_password "lang genoeg"
fail_if "beheerderswachtwoord te kort" valid_admin_password kort

pass_if "databasehost overal" valid_dbhost_allow "%"
pass_if "databasehost lokaal" valid_dbhost_allow 127.0.0.1
pass_if "databasehost hostnaam" valid_dbhost_allow panel.etheron.nl
fail_if "databasehost ongeldig" valid_dbhost_allow "pan el"

pass_if "release-tag" valid_release_tag v1.11.13
fail_if "release-tag zonder v" valid_release_tag 1.11.13
pass_if "panel-versie 2" valid_panel_version 2
fail_if "panel-versie 3" valid_panel_version 3
pass_if "bool true" valid_bool true
fail_if "bool ja" valid_bool ja

# ---------------- load_config ----------------- #

file=$(write_config basis.conf $'# commentaar\n\n  FQDN=panel.etheron.nl\nEMAIL = "beheer@etheron.nl"\r\nADMIN_PASSWORD=\'met # hekje\'\nDB_PASSWORD=\nTIMEZONE=Europe/Amsterdam')
TELEMETRY=true
pass_if "basisbestand laden" load_config "$file"
load_config "$file" >/dev/null 2>&1
pass_if "FQDN gelezen" test "$FQDN" = panel.etheron.nl
pass_if "spaties, aanhalingstekens en CRLF verwijderd" test "$EMAIL" = beheer@etheron.nl
pass_if "# binnen waarde blijft staan" test "$ADMIN_PASSWORD" = "met # hekje"
pass_if "lege waarde" test -z "$DB_PASSWORD"
pass_if "laatste regel zonder newline" test "$TIMEZONE" = Europe/Amsterdam
pass_if "omgeving telt niet mee" test -z "$TELEMETRY"

fail_if "onbekende sleutel" load_config "$(write_config onbekend.conf $'FOO=bar\n')"
fail_if "dubbele sleutel" load_config "$(write_config dubbel.conf $'FQDN=a.nl\nFQDN=b.nl\n')"
fail_if "regel zonder =" load_config "$(write_config zonder-is.conf $'FQDN\n')"
fail_if "sleutel in kleine letters" load_config "$(write_config klein.conf $'fqdn=a.nl\n')"
fail_if "stuurteken in waarde" load_config "$(write_config stuurteken.conf $'FQDN=a\tb\n')"
fail_if "bestand bestaat niet" load_config "$TMP_DIR/bestaat-niet.conf"

file=$(write_config leesbaar.conf $'FQDN=a.nl\n')
chmod 644 "$file"
fail_if "leesbaar voor anderen" load_config "$file"

ln -s "$(write_config doel.conf $'FQDN=a.nl\n')" "$TMP_DIR/link.conf"
fail_if "symlink" load_config "$TMP_DIR/link.conf"

# ----------------- config_set ----------------- #

file=$(write_config rondje.conf "")
config_set "$file" ADMIN_PASSWORD ' spaties "en" quotes '
config_set "$file" FQDN eerste.nl
config_set "$file" FQDN tweede.nl
load_config "$file" >/dev/null 2>&1
pass_if "waarde komt ongewijzigd terug" test "$ADMIN_PASSWORD" = ' spaties "en" quotes '
pass_if "config_set vervangt bestaande regel" test "$FQDN" = tweede.nl
pass_if "config_set houdt rechten 600" test "$(stat -c %a "$file")" = 600

# ---------------- check_setting --------------- #

CONFIG_ERRORS=0
FQDN=""
check_setting FQDN valid_hostname "test" 2>/dev/null >/dev/null
pass_if "lege verplichte waarde telt als fout" test "$CONFIG_ERRORS" -eq 1
FQDN="ongeldig_host"
check_setting FQDN valid_hostname "test" 2>/dev/null >/dev/null
pass_if "ongeldige waarde telt als fout" test "$CONFIG_ERRORS" -eq 2
FQDN="panel.etheron.nl"
check_setting FQDN valid_hostname "test" 2>/dev/null >/dev/null
pass_if "geldige waarde telt niet" test "$CONFIG_ERRORS" -eq 2

# ------------- regeleinden (CRLF) ------------- #

# Een checkout op Windows kan CRLF opleveren; dat breekt scripts en configs op Linux.
for project_file in "$ETHERON_DIR"/install.sh "$ETHERON_DIR"/{lib,ui,installers,configs,voorbeelden,webui,webui/static}/*.*; do
  fail_if "CRLF in ${project_file#"$ETHERON_DIR"/}" grep -q $'\r' "$project_file"
done

# ---------------- voorbeelden ----------------- #

for example in "$ETHERON_DIR"/voorbeelden/*.conf; do
  file=$(write_config "$(basename "$example")" "$(cat "$example")")
  pass_if "voorbeeld $(basename "$example") is leesbaar" load_config "$file"
done

echo "$PASSED geslaagd, $FAILED mislukt"
[ "$FAILED" -eq 0 ]
