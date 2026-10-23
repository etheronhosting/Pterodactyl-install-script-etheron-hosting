# Etheron Pterodactyl-installer

Installatiescripts voor [Pterodactyl](https://pterodactyl.io/) Panel en Wings, zoals Etheron ze gebruikt. Gebaseerd op [pterodactyl-installer](https://github.com/pterodactyl-installer/pterodactyl-installer) v1.4.0 van Vilhelm Prytz en bijdragers, vertaald naar het Nederlands en uitgebreid met een onbegeleide modus. Niet verbonden aan het officiële Pterodactyl-project.

## Wat het doet

- **Panel**: PHP 8.3, MariaDB, Redis (Valkey op EL10), nginx, Composer, cronjob en de queue-worker (`pteroq`). Optioneel Let's Encrypt of een eigen certificaat.
- **Wings**: Docker en de Wings-binary met een systemd-service (wel ingeschakeld, nog niet gestart). Optioneel Let's Encrypt en een databasehost-gebruiker voor gameserverdatabases.
- **Beide**: panel en Wings op één server, met hetzelfde domein en certificaat.
- **Verwijderen**: panel en/of Wings, met per database, gebruiker en certificaat een bevestiging.
- **Firewall**: UFW (Debian/Ubuntu) of firewalld (Rocky/AlmaLinux), met de SSH-poort die sshd echt gebruikt.
- **Webinstaller**: dezelfde installatie via een wizard in de browser, bedoeld voor klanten.

Etheron-standaarden: tijdzone `Europe/Amsterdam`, telemetrie standaard uit.

## Ondersteunde systemen

| Besturingssysteem | Versies    | PHP |
| ----------------- | ---------- | --- |
| Ubuntu            | 22.04, 24.04, 26.04 | 8.3 |
| Debian            | 12, 13     | 8.3 |
| Rocky Linux       | 8, 9, 10   | 8.3 |
| AlmaLinux         | 8, 9, 10   | 8.3 |

Architectuur: x86_64 of arm64. Panel v2 is experimenteel (pre-release).

## Gebruik

Draai alles als root.

### Via de browser (webinstaller)

De makkelijkste route voor klanten: één commando op de server, daarna gaat alles in de browser.

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/etheronhosting/Pterodactyl-install-script-etheron-hosting/main/install.sh) web
```

Wat er gebeurt:

1. De installer zet Python 3 en OpenSSL klaar, vraagt een gratis certificaat van Let's Encrypt aan voor `installer-<ip>.sslip.io` en start een webpagina op poort 8443. Die draait als systemd-service (`etheron-webinstaller`), dus het SSH-venster mag daarna dicht.
2. In de terminal verschijnt een link met een eenmalige toegangscode, bijvoorbeeld `https://installer-203-0-113-10.sslip.io:8443/?token=…`. De browser geeft geen certificaatwaarschuwing.

   Voor het certificaat moet poort 80 kort bereikbaar zijn. Lukt de aanvraag niet (poort 80 dicht of bezet, of alleen IPv6), dan gebruikt de installer een tijdelijk eigen certificaat en een link met het IP-adres. De browser waarschuwt dan wel; de vingerafdruk van het certificaat staat in de terminal. Met `ETHERON_WEB_SELFSIGNED=1` voor het commando sla je de aanvraag over. Het certificaat staat in `/var/lib/etheron-webinstaller` (los van `/etc/letsencrypt`, zonder automatische verlenging) en wordt bij een volgende start hergebruikt zolang het nog minstens een week geldig is.
3. De wizard vraagt wat je wilt installeren (panel, Wings of beide), hoe de server bereikbaar moet zijn (eigen domein, gratis nip.io-adres of alleen het IP-adres), het beheerdersaccount en de Wings-opties. Het domein wordt meteen gecontroleerd, en alle instellingen worden op de server gecontroleerd voordat er iets gebeurt.
4. Tijdens de installatie zie je de voortgang live. Je kunt de pagina sluiten en later opnieuw openen met dezelfde link.
5. Na een Wings-installatie koppelt de wizard de node met één klik aan het panel. Hij maakt een locatie, een node en poorten voor gameservers aan, zet die poorten open in de firewall en start Wings. Staat het panel op dezelfde server (Panel en Wings), dan is daar niets extra's voor nodig. Staat het panel elders, dan vul je het adres van het panel en een Application API-sleutel in (Admin → Application API, Read & Write op Locations, Nodes en Allocations). Liever handmatig? Plak dan de configuratie van de node uit het panel.

De webinstaller stopt vanzelf 30 minuten na de installatie, na een uur zonder gebruik, of als je op "Webinstaller afsluiten" klikt. Zelf stoppen kan met `systemctl stop etheron-webinstaller`. Poort 8443 gaat alleen open zolang de webinstaller draait. Een andere poort kies je met `ETHERON_WEB_PORT=9443` voor het commando. Achter een firewall van de hostingprovider moet die poort ook daar open staan.

Beveiliging: zonder de code uit de link is de wizard niet bereikbaar. Het verkeer loopt via HTTPS, en de code staat niet in het logbestand. Instellingenbestanden met wachtwoorden worden meteen na gebruik verwijderd.

### Geen domein? nip.io

Wie geen eigen domein heeft, kan een gratis adres van [nip.io](https://nip.io/) gebruiken. Voor een server met IP-adres `203.0.113.10` is dat `203-0-113-10.nip.io`; dat adres wijst automatisch naar de server en werkt met Let's Encrypt, dus met HTTPS. Een eigen naam ervoor kan ook, bijvoorbeeld `mijnpanel-203-0-113-10.nip.io`. Het IP-adres blijft altijd in de naam staan, want nip.io haalt het adres daaruit.

- De webinstaller biedt dit als keuze aan, naast een eigen domein en alleen het IP-adres.
- De installer in de terminal stelt het voor als standaardantwoord bij de vraag naar het adres.
- Onbegeleid vul je het zelf in, bijvoorbeeld `FQDN=203-0-113-10.nip.io`.

nip.io werkt alleen met IPv4. Let's Encrypt geeft voor alle nip.io-adressen samen een ruime, maar gedeelde limiet. Lukt het aanvragen daardoor een keer niet, dan draait het panel eerst op HTTP en meldt de installer dat. Je kunt dan later opnieuw een certificaat aanvragen, of `203-0-113-10.sslip.io` gebruiken: een vergelijkbare dienst van dezelfde makers.

### Met de one-liner

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/etheronhosting/Pterodactyl-install-script-etheron-hosting/main/install.sh)
```

Gebruik `bash <(curl ...)` en niet `curl ... | bash`: de installer stelt vragen en heeft daarvoor de terminal nodig. Het script downloadt de installer en draait die lokaal vanuit een tijdelijke map. De repository moet daarvoor publiek zijn.

Welke versie je krijgt:

- Staat de release uit `ETHERON_VERSION` als tag op GitHub, dan krijg je die vaste release.
- Is die tag er nog niet, dan gebruikt de one-liner de nieuwste code van `main` en meldt hij dat.
- Een andere versie of branch kies je met `ETHERON_REF`, bijvoorbeeld `ETHERON_REF=main` om na een release nieuwe code te testen, of `ETHERON_REF=v1.0.0` voor een vaste versie.

### Vanuit een clone

```bash
git clone https://github.com/etheronhosting/Pterodactyl-install-script-etheron-hosting.git
cd Pterodactyl-install-script-etheron-hosting
./install.sh
```

Zonder argument verschijnt een menu. Je kunt de actie ook meegeven: `./install.sh panel`, `wings`, `beide` of `verwijderen`. Alle uitvoer gaat ook naar `/var/log/etheron-installer.log`.

### Onbegeleid

Voor het automatisch uitrollen van servers en nodes: zet alle antwoorden in een instellingenbestand en geef dat mee met `--config`. De installer stelt dan geen vragen.

```bash
cp voorbeelden/panel.conf /root/panel.conf
nano /root/panel.conf
chmod 600 /root/panel.conf
./install.sh panel --config /root/panel.conf
```

Kant-en-klare voorbeelden met uitleg per instelling staan in [voorbeelden/](voorbeelden/): [panel.conf](voorbeelden/panel.conf), [wings.conf](voorbeelden/wings.conf) en [beide.conf](voorbeelden/beide.conf).

Hoe het werkt:

- Het bestand moet van root zijn en rechten `600` of `400` hebben; het bevat wachtwoorden.
- Het wordt niet als script uitgevoerd, maar regel voor regel gelezen. Alleen bekende sleutels zijn toegestaan; een typefout geeft een foutmelding.
- Alle instellingen worden gecontroleerd voordat er iets wordt geïnstalleerd, bij `beide` voor panel en Wings samen.
- Met `LETSENCRYPT=true` ga je akkoord met de [voorwaarden van Let's Encrypt](https://letsencrypt.org/repository/).
- Wijst het domein niet naar de server, dan stopt de installatie. Zet `VERIFY_DNS=false` om die controle over te slaan.
- Lukt Let's Encrypt toch niet, dan valt het panel terug op HTTP en meldt de installer dat.
- Verwijderen kan alleen interactief.

| Sleutel | Voor | Standaard | Betekenis |
| ------- | ---- | --------- | --------- |
| `FQDN` | beide | verplicht (panel) | Domeinnaam of IP-adres |
| `EMAIL` | beide | verplicht (panel) | E-mailadres voor Let's Encrypt en het panel |
| `FIREWALL` | beide | `false` | UFW/firewalld instellen |
| `LETSENCRYPT` | beide | `false` | HTTPS met Let's Encrypt |
| `VERIFY_DNS` | beide | `true` | Controleren of het domein naar de server wijst |
| `ASSUME_SSL` | panel | `false` | Nginx voor een eigen certificaat in `/etc/ssl/` |
| `PANEL_VERSION` | panel | `1` | `1` (stabiel) of `2` (experimenteel) |
| `PANEL_RELEASE` | panel | nieuwste | Vaste tag (v1) of commit-hash (v2) |
| `TIMEZONE` | panel | `Europe/Amsterdam` | Tijdzone |
| `TELEMETRY` | panel | `false` | Anonieme telemetrie |
| `DB_NAME`, `DB_USER` | panel | `panel`, `pterodactyl` | Database van het panel |
| `DB_PASSWORD` | panel | willekeurig | Databasewachtwoord |
| `ADMIN_EMAIL` | panel | `EMAIL` | E-mail van de eerste beheerder |
| `ADMIN_USERNAME`, `ADMIN_FIRSTNAME`, `ADMIN_LASTNAME`, `ADMIN_PASSWORD` | panel | verplicht | Eerste beheerder |
| `WINGS_RELEASE` | wings | nieuwste | Vaste Wings-tag |
| `DBHOST` | wings | `false` | Databasehost-gebruiker aanmaken |
| `DBHOST_USER`, `DBHOST_PASSWORD` | wings | `pterodactyluser`, verplicht | Databasehost-gebruiker |
| `DBHOST_ALLOW` | wings | `127.0.0.1` | Toegang vanaf: `127.0.0.1`, `%` of IP/hostnaam van het panel |
| `DBHOST_FIREWALL` | wings | `false` | Poort 3306 openen (alleen voor `DBHOST_ALLOW` als dat een IP is) |
| `NODE_NAME` | node | hostnaam | Naam van de node in het panel |
| `NODE_LOCATION` | node | `nl` | Korte naam van de locatie; bestaat hij al, dan wordt hij gebruikt |
| `NODE_PORTS` | node | `25565-25600` | Poorten voor gameservers (max. 1000), gaan ook open in de firewall |
| `NODE_FQDN` | node | domein met certificaat, anders IP | Adres waarop het panel Wings bereikt |
| `PANEL_URL`, `PANEL_API_KEY` | node | leeg | Alleen als het panel op een andere server staat |
| `NODE_DBHOST` | node | `false` | Databases voor gameservers automatisch instellen en in het panel zetten (alleen met het panel op dezelfde server) |

### Databases voor gameservers

In de webinstaller kiest de klant bij Wings tussen drie opties:

- **Automatisch** (alleen als het panel op dezelfde server staat): bij het koppelen van de node maakt de installer een databasegebruiker aan met een willekeurig wachtwoord en zet hij de databasehost meteen in het panel, gekoppeld aan de node. Gameservers draaien in Docker en bereiken MariaDB via de gateway van het Docker-netwerk van Wings (standaard `172.18.0.1`). MariaDB luistert daarvoor op alle adressen; de firewall laat poort 3306 alleen toe vanuit het Docker-netwerk. Pterodactyl heeft hier geen API voor, daarom kan dit niet als het panel op een andere server staat.
- **Zelf instellen:** de klant kiest gebruikersnaam en wachtwoord (en eventueel toegang vanaf een panel elders) en voegt de databasehost zelf toe onder Admin → Databases.
- **Niet nodig.**

Staat er een `NODE_*`- of `PANEL_*`-instelling in het bestand, dan koppelt `wings` of `beide` Wings na de installatie meteen aan het panel. Alleen koppelen kan met `./install.sh node --config bestand.conf`.

## Poorten

| Onderdeel | Poorten (TCP) |
| --------- | ------------- |
| Panel | SSH, 80, 443 |
| Wings | SSH, 8080, 2022, plus 80 en 443 met Let's Encrypt, plus 3306 als `DBHOST_FIREWALL=true` |

## Verschillen met pterodactyl-installer

- Nederlandstalig, met Etheron-standaarden (`Europe/Amsterdam`, telemetrie uit).
- Draait volledig lokaal: deelscripts en configs komen niet meer los van GitHub tijdens de installatie. De one-liner downloadt één vaste release.
- Onbegeleide modus met een gecontroleerd instellingenbestand.
- Opgeloste fouten en verbeteringen:
  - De DNS-controle kijkt naar alle A- en AAAA-records (ook IPv6) en vergelijkt eerst met de adressen van de server zelf. Alleen als het nodig is, vraagt hij het publieke IP op bij icanhazip.com (Cloudflare).
  - De firewall zet eerst de poorten open en wordt pas daarna ingeschakeld. De echte SSH-poort wordt meegenomen.
  - De nep-kernelcontrole (`grep "xxxx"`) en de losse `+` in de firewalld-melding zijn weg.
  - De installer van Composer wordt gecontroleerd met de officiële SHA-384-controlesom.
  - `.env` is niet meer leesbaar voor iedereen; ook verborgen bestanden in het panel krijgen de juiste eigenaar.
  - Wings wordt na elke certificaatverlenging herstart. Draait er nginx op de server, dan stopt certbot nginx tijdens het aanvragen en verlengen.
  - MariaDB-toegang van buitenaf gaat via een eigen configbestand in plaats van een `sed` op de standaardconfig. Poort 3306 kan beperkt worden tot het IP-adres van het panel.
  - Gegenereerde wachtwoorden bevatten alleen letters en cijfers, zodat ze nergens geëscaped hoeven te worden.
  - Op een kale server worden voor de Wings-installatie eerst de pakketbronnen bijgewerkt.

## Een release maken

1. Werk `ETHERON_VERSION` in [install.sh](install.sh) bij en zet de wijzigingen in [CHANGELOG.md](CHANGELOG.md).
2. Commit, tag en push:

   ```bash
   git tag v1.0.0
   ```

   ```bash
   git push origin main v1.0.0
   ```

De one-liner installeert daarna de release uit `ETHERON_VERSION`. Wil je een niet-uitgebrachte versie testen, zet dan `ETHERON_REF` op een branch: `ETHERON_REF=main bash <(curl ...)`.

## Testen

- Unittests van de hulpfuncties (Linux of WSL): `bash tests/lib_test.sh`
- ShellCheck: `shellcheck -x install.sh lib/*.sh ui/*.sh installers/*.sh tests/*.sh`
- Beide draaien ook in GitHub Actions bij elke push.
- Een echte installatie test je op een verse VM. Met [Vagrant](https://www.vagrantup.com) start `vagrant up debian_bookworm` een testmachine; daarin staat het project in `/vagrant`, dus `sudo /vagrant/install.sh`. Zie de [Vagrantfile](Vagrantfile) voor alle machines.

## Licentie

GPL-3.0, net als het origineel; zie [LICENSE](LICENSE). Verspreid je een aangepaste versie, dan moet die ook onder GPL-3.0 vallen en moet de broncode beschikbaar zijn.

Copyright (C) 2026 Etheron Hosting. Gebaseerd op werk dat Copyright (C) 2018 - 2026 Vilhelm Prytz en bijdragers is.
