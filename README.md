# Etheron Pterodactyl-installer

[![Controles](https://github.com/etheronhosting/Pterodactyl-install-script-etheron-hosting/actions/workflows/controles.yml/badge.svg)](https://github.com/etheronhosting/Pterodactyl-install-script-etheron-hosting/actions/workflows/controles.yml)
![Versie](https://img.shields.io/badge/versie-1.0.0-0c94ab)
[![Licentie: GPL-3.0](https://img.shields.io/badge/licentie-GPL--3.0-blue)](LICENSE)

Installeer [Pterodactyl](https://pterodactyl.io/) Panel en Wings met één commando, via de browser of in de terminal. Gemaakt door [Etheron Hosting](https://etheron.nl), in het Nederlands, en gebaseerd op [pterodactyl-installer](https://github.com/pterodactyl-installer/pterodactyl-installer) v1.4.0 van Vilhelm Prytz en bijdragers.

> Dit project is niet verbonden aan het officiële Pterodactyl-project.

## Inhoud

- [Snel aan de slag](#snel-aan-de-slag)
- [Wat de installer doet](#wat-de-installer-doet)
- [Vereisten](#vereisten)
- [Installeren via de browser](#installeren-via-de-browser)
- [Installeren in de terminal](#installeren-in-de-terminal)
- [Adres en HTTPS](#adres-en-https)
- [Wings koppelen aan het panel](#wings-koppelen-aan-het-panel)
- [Databases voor gameservers](#databases-voor-gameservers)
- [Onbegeleid installeren](#onbegeleid-installeren)
- [Poorten](#poorten)
- [Verwijderen](#verwijderen)
- [Problemen oplossen](#problemen-oplossen)
- [Opbouw van het project](#opbouw-van-het-project)
- [Ontwikkelen en testen](#ontwikkelen-en-testen)
- [Een nieuwe versie uitbrengen](#een-nieuwe-versie-uitbrengen)
- [Licentie](#licentie)

## Snel aan de slag

Log als **root** in op een verse server en kies een van de twee manieren.

**Via de browser (aanbevolen):** de installer start een wizard en geeft je een link.

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/etheronhosting/Pterodactyl-install-script-etheron-hosting/main/install.sh) web
```

**In de terminal:** je krijgt een menu met vragen.

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/etheronhosting/Pterodactyl-install-script-etheron-hosting/main/install.sh)
```

Gebruik altijd `bash <(curl ...)` en niet `curl ... | bash`; de installer heeft de terminal nodig. Op een minimale server zonder curl installeer je dat eerst met `apt install -y curl` of `dnf install -y curl`.

## Wat de installer doet

| Onderdeel | Wat er gebeurt |
| --------- | -------------- |
| **Panel** | PHP 8.3, MariaDB, Redis (Valkey op EL10), nginx, Composer, cronjob en queue-worker (`pteroq`), plus het eerste beheerdersaccount. |
| **Wings** | Docker en Wings met een systemd-service. |
| **Panel en Wings** | Beide op één server, met hetzelfde adres en certificaat. |
| **Node koppelen** | Locatie, node en poorten voor gameservers aanmaken in het panel, de configuratie van Wings neerzetten en Wings starten. |
| **Databases** | Een databasehost voor gameservers instellen en in het panel zetten. |
| **HTTPS** | Let's Encrypt, een eigen certificaat of geen HTTPS; zonder eigen domein een gratis nip.io-adres. |
| **Firewall** | UFW (Debian/Ubuntu) of firewalld (Rocky/AlmaLinux), met alleen de poorten die nodig zijn en de SSH-poort die sshd echt gebruikt. |
| **Verwijderen** | Panel en/of Wings weer van de server halen. |

Etheron-standaarden: tijdzone `Europe/Amsterdam` en telemetrie standaard uit. Alle instellingen worden gecontroleerd voordat er iets wordt geïnstalleerd.

## Vereisten

| Besturingssysteem | Versies |
| ----------------- | ------- |
| Ubuntu | 22.04, 24.04, 26.04 |
| Debian | 12, 13 |
| Rocky Linux | 8, 9, 10 |
| AlmaLinux | 8, 9, 10 |

- **Architectuur:** x86_64 of arm64.
- **Een verse server:** de installer doet alleen nieuwe installaties. Upgraden van een bestaand panel doe je met de [officiële handleiding](https://pterodactyl.io/panel/1.0/updating.html).
- **Root-toegang:** log in als root, of word root met `sudo -i`.
- **Poorten bij je hostingprovider:** heeft je provider een eigen firewall, zet daar dezelfde poorten open als in [Poorten](#poorten).
- **Panel-versie:** standaard versie 1 (stabiel). Versie 2 is te kiezen, maar nog experimenteel (pre-release).

## Installeren via de browser

De webinstaller is bedoeld voor klanten: één commando op de server, de rest gaat in de browser.

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/etheronhosting/Pterodactyl-install-script-etheron-hosting/main/install.sh) web
```

1. **Starten.** De installer zet Python 3 en OpenSSL klaar en vraagt een gratis certificaat van Let's Encrypt aan voor `installer-<ip>.sslip.io`. Daarna start hij de wizard op poort 8443 als systemd-service (`etheron-webinstaller`). Het SSH-venster mag daarna dicht.
2. **Link openen.** In de terminal verschijnt een link met een eenmalige toegangscode, bijvoorbeeld `https://installer-203-0-113-10.sslip.io:8443/?token=…`.
3. **Wizard invullen.** De klant kiest wat hij wil installeren (Panel, Wings of beide) en hoe de server bereikbaar moet zijn (eigen domein, gratis nip.io-adres of alleen IP). Daarna vult hij het beheerdersaccount en de Wings-opties in. Het domein wordt meteen gecontroleerd, en alle instellingen worden op de server gecontroleerd voordat de installatie begint.
4. **Installatie volgen.** De voortgang is live te zien. De pagina mag dicht en later opnieuw open met dezelfde link.
5. **Laatste stap.** Bovenaan de eindpagina staat de knop **Node aanmaken en Wings starten**, die Wings aan het panel koppelt (zie [Wings koppelen](#wings-koppelen-aan-het-panel)).

**Certificaat van de webinstaller.** Voor het certificaat moet poort 80 kort bereikbaar zijn. Lukt dat niet, dan gebruikt de installer een tijdelijk eigen certificaat en een link met het IP-adres; de browser waarschuwt dan, en de vingerafdruk staat in de terminal. Het certificaat staat in `/var/lib/etheron-webinstaller`, los van `/etc/letsencrypt` en zonder automatische verlenging. Bij een volgende start wordt het hergebruikt zolang het nog minstens een week geldig is.

**Stoppen.** De webinstaller stopt vanzelf in deze gevallen:

- 30 minuten na de installatie;
- na een uur zonder gebruik;
- na 24 uur;
- als je op **Webinstaller afsluiten** klikt.

Zelf stoppen kan met `systemctl stop etheron-webinstaller`. Poort 8443 gaat alleen open zolang de webinstaller draait.

**Beveiliging:**

- Zonder de code uit de link is de wizard niet bereikbaar.
- Al het verkeer loopt via HTTPS, en verzoeken van andere websites worden geweigerd.
- De code komt niet in de logbestanden.
- Instellingenbestanden met wachtwoorden worden direct na gebruik verwijderd.

## Installeren in de terminal

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/etheronhosting/Pterodactyl-install-script-etheron-hosting/main/install.sh) [actie] [opties]
```

Zonder actie verschijnt een menu. Vanuit een clone werkt hetzelfde met `./install.sh`:

```bash
git clone https://github.com/etheronhosting/Pterodactyl-install-script-etheron-hosting.git
```

```bash
cd Pterodactyl-install-script-etheron-hosting && ./install.sh
```

| Actie | Wat het doet |
| ----- | ------------ |
| `web` | Webinstaller starten (installeren via de browser) |
| `panel` | Pterodactyl Panel installeren |
| `wings` | Wings installeren |
| `beide` | Panel en Wings op dezelfde server installeren |
| `verwijderen` | Panel en/of Wings verwijderen |
| `node` | Wings koppelen aan een panel (alleen met `--config`) |

| Optie | Betekenis |
| ----- | --------- |
| `-c`, `--config BESTAND` | Onbegeleid installeren met de instellingen uit een bestand |
| `-h`, `--help` | Hulp tonen |
| `-v`, `--version` | Versie tonen |

| Omgevingsvariabele | Betekenis |
| ------------------ | --------- |
| `ETHERON_REF` | Welke versie de one-liner downloadt, bijvoorbeeld `main` of `v1.0.0` |
| `ETHERON_WEB_PORT` | Poort van de webinstaller (standaard `8443`) |
| `ETHERON_WEB_SELFSIGNED=1` | Geen certificaat aanvragen voor de webinstaller; een eigen certificaat gebruiken |

Zet een omgevingsvariabele vóór het commando, bijvoorbeeld `ETHERON_WEB_PORT=9443 bash <(curl ...) web`.

**Welke versie je krijgt.** Staat de release uit `ETHERON_VERSION` (nu `v1.0.0`) als tag op GitHub, dan download je die vaste versie. Zolang die tag er nog niet is, gebruikt de one-liner de nieuwste code van `main` en meldt hij dat. De repository moet publiek zijn.

**Logbestand.** Alle uitvoer van de installatie staat ook in `/var/log/etheron-installer.log` (alleen leesbaar voor root).

## Adres en HTTPS

Het panel (en Wings) kan op drie manieren bereikbaar zijn:

| Keuze | Adres | HTTPS |
| ----- | ----- | ----- |
| **Eigen domein** | bijv. `panel.jouwdomein.nl`, met een A-record naar de server | Let's Encrypt (aanbevolen), een eigen certificaat of geen |
| **Gratis nip.io-adres** | bijv. `203-0-113-10.nip.io` of `mijnpanel-203-0-113-10.nip.io` | Let's Encrypt |
| **Alleen IP-adres** | bijv. `203.0.113.10` | Geen; alleen geschikt om te testen |

**nip.io voor wie geen domein heeft.** [nip.io](https://nip.io/) haalt het IP-adres uit de naam. Het adres wijst daardoor automatisch naar de server, zonder DNS-records. De klant kan er een eigen naam voor zetten; het IP-adres blijft altijd in de naam staan.

- De webinstaller biedt nip.io als keuze aan.
- De terminal stelt het voor als standaardantwoord.
- Onbegeleid vul je het zelf in, bijvoorbeeld `FQDN=mijnpanel-203-0-113-10.nip.io`.

nip.io werkt alleen met IPv4. Let's Encrypt hanteert voor alle nip.io-adressen samen één ruime, maar gedeelde limiet. Lukt een aanvraag daardoor niet, dan draait het panel eerst op HTTP en meldt de installer dat. Een vergelijkbaar alternatief is `…sslip.io`.

**Controle vooraf.** Voor een certificaat controleert de installer of alle A- en AAAA-records naar de server wijzen. Het voorkomt zo een mislukte aanvraag door een verkeerd of nog niet bijgewerkt DNS-record. Gebruik je Cloudflare, zet dan de proxy (oranje wolk) uit voor dat record.

**Eigen certificaat.** Zet het certificaat in `/etc/ssl/<domein>.pem` en de sleutel in `/etc/ssl/<domein>.key`, en herstart daarna nginx: `nginx -t && systemctl restart nginx`.

## Wings koppelen aan het panel

Na een Wings-installatie koppelt de installer de node met één klik (webinstaller) of met `NODE_*`-instellingen (onbegeleid). Dat doet hij zo:

1. Een **locatie** aanmaken (standaard `nl`); bestaat die al, dan gebruikt hij die.
2. Een **node** aanmaken, met het geheugen en de vrije schijfruimte van de server.
3. **Poorten voor gameservers** toevoegen (standaard `25565-25600`) en die in de firewall openzetten, voor TCP en UDP.
4. De **configuratie van Wings** neerzetten, **Wings starten** en controleren of het draait.

| Waar staat het panel? | Hoe | Wat je invult |
| --------------------- | --- | ------------- |
| Op dezelfde server | Via de beheeropdrachten van het panel (`p:location:make`, `p:node:make`, `p:node:configuration`) | Niets extra |
| Op een andere server | Via de Application API van het panel | Adres van het panel en een API-sleutel |

**De API-sleutel** maak je in het panel via **Admin → Application API → Create New**. Zet daarbij **Locations**, **Nodes** en **Allocations** op Read & Write.

**Adres van de node.** Het adres wordt automatisch gekozen. Heeft Wings een certificaat, dan is dat het domein via HTTPS; anders het IP-adres via HTTP. Gebruikt het panel HTTPS en Wings niet, dan blokkeren browsers de console van gameservers; de installer waarschuwt daarvoor.

**Liever zelf koppelen?** In de webinstaller kun je ook de configuratie van de node uit het panel plakken (tabblad *Configuration* van de node). De wizard zet die dan neer en start Wings.

## Databases voor gameservers

Bij Wings kies je tussen drie opties:

| Optie | Wat er gebeurt |
| ----- | -------------- |
| **Automatisch instellen** | Bij het koppelen van de node maakt de installer een databasegebruiker aan met een willekeurig wachtwoord. Daarna zet hij de databasehost in het panel, gekoppeld aan de node. Alleen mogelijk als het panel op dezelfde server staat; Pterodactyl heeft geen API voor databasehosts. |
| **Zelf instellen** | Je kiest zelf gebruikersnaam en wachtwoord, eventueel met toegang vanaf een panel elders. Daarna voeg je de databasehost zelf toe onder **Admin → Databases**. |
| **Niet nodig** | Er wordt niets ingesteld. |

**Hoe "Automatisch" werkt:**

- Gameservers draaien in Docker en bereiken MariaDB via de gateway van het Docker-netwerk van Wings (standaard `172.18.0.1`). Dat adres wordt de databasehost in het panel.
- MariaDB luistert daarvoor op alle adressen. De firewall laat poort 3306 alleen toe vanuit het Docker-netwerk, dus van buiten blijft die dicht. Is er geen firewall actief, dan waarschuwt de installer.
- Docker zet verkeer van de server naar zichzelf vaak om naar het publieke IP-adres (NAT). De installer herkent dat aan de melding van MariaDB en geeft de databasegebruiker ook vanaf dat adres toegang. Toegang blijft beperkt tot de server zelf.
- Mislukt het instellen van de databases, dan blijft de koppeling van de node staan. Opnieuw proberen stelt alleen de databases in, zonder nieuwe node.

## Onbegeleid installeren

Voor het automatisch uitrollen van servers en nodes zet je alle antwoorden in een instellingenbestand. Met `--config` stelt de installer dan geen vragen.

```bash
cp voorbeelden/panel.conf /root/panel.conf
nano /root/panel.conf
chmod 600 /root/panel.conf
./install.sh panel --config /root/panel.conf
```

Voorbeelden met uitleg per instelling: [panel.conf](voorbeelden/panel.conf), [wings.conf](voorbeelden/wings.conf) en [beide.conf](voorbeelden/beide.conf).

- Het bestand moet van root zijn en rechten `600` of `400` hebben; het bevat wachtwoorden.
- Het wordt regel voor regel gelezen (`SLEUTEL=waarde`) en nooit als script uitgevoerd. Een onbekende sleutel of een typefout geeft een foutmelding.
- Alle instellingen worden vooraf gecontroleerd, bij `beide` voor panel en Wings samen.
- Wijst het domein niet naar de server, dan stopt de installatie. Met `VERIFY_DNS=false` sla je die controle over.
- Met `LETSENCRYPT=true` ga je akkoord met de [voorwaarden van Let's Encrypt](https://letsencrypt.org/repository/).
- Staan er `NODE_*`- of `PANEL_*`-instellingen in het bestand, dan koppelt `wings` of `beide` Wings meteen daarna aan het panel. Alleen koppelen kan met `./install.sh node --config bestand.conf`.
- Verwijderen kan alleen interactief.

### Alle instellingen

**Algemeen** (panel en Wings)

| Sleutel | Standaard | Betekenis |
| ------- | --------- | --------- |
| `FQDN` | verplicht voor het panel | Domeinnaam, nip.io-adres of IP-adres |
| `EMAIL` | verplicht voor het panel | E-mailadres voor Let's Encrypt en het panel |
| `FIREWALL` | `false` | UFW/firewalld instellen |
| `LETSENCRYPT` | `false` | HTTPS met Let's Encrypt |
| `VERIFY_DNS` | `true` | Controleren of het adres naar de server wijst |

**Panel**

| Sleutel | Standaard | Betekenis |
| ------- | --------- | --------- |
| `ASSUME_SSL` | `false` | Nginx instellen voor een eigen certificaat in `/etc/ssl/` |
| `PANEL_VERSION` | `1` | `1` (stabiel) of `2` (experimenteel) |
| `PANEL_RELEASE` | nieuwste | Vaste release-tag (v1) of commit-hash (v2) |
| `TIMEZONE` | `Europe/Amsterdam` | Tijdzone |
| `TELEMETRY` | `false` | Anonieme gebruiksstatistieken naar Pterodactyl |
| `DB_NAME`, `DB_USER` | `panel`, `pterodactyl` | Database van het panel |
| `DB_PASSWORD` | willekeurig | Wachtwoord van die database |
| `ADMIN_EMAIL` | gelijk aan `EMAIL` | E-mailadres van de eerste beheerder |
| `ADMIN_USERNAME`, `ADMIN_FIRSTNAME`, `ADMIN_LASTNAME`, `ADMIN_PASSWORD` | verplicht | Eerste beheerder |

**Wings**

| Sleutel | Standaard | Betekenis |
| ------- | --------- | --------- |
| `WINGS_RELEASE` | nieuwste | Vaste release-tag van Wings |
| `DBHOST` | `false` | Databasehost zelf instellen (de optie "Zelf instellen") |
| `DBHOST_USER`, `DBHOST_PASSWORD` | `pterodactyluser`, verplicht | Gebruiker van de databasehost (maximaal 32 tekens) |
| `DBHOST_ALLOW` | `127.0.0.1` | Toegang vanaf `127.0.0.1`, `%` (overal) of het IP/de hostnaam van het panel |
| `DBHOST_FIREWALL` | `false` | Poort 3306 openzetten; is `DBHOST_ALLOW` een IP-adres, dan alleen daarvoor |

**Node koppelen**

| Sleutel | Standaard | Betekenis |
| ------- | --------- | --------- |
| `NODE_NAME` | hostnaam | Naam van de node in het panel |
| `NODE_LOCATION` | `nl` | Korte naam van de locatie |
| `NODE_PORTS` | `25565-25600` | Poorten voor gameservers (maximaal 1000) |
| `NODE_FQDN` | domein met certificaat, anders IP | Adres waarop het panel Wings bereikt |
| `NODE_DBHOST` | `false` | Databases automatisch instellen (de optie "Automatisch") |
| `PANEL_URL`, `PANEL_API_KEY` | leeg | Alleen als het panel op een andere server staat |

## Poorten

De installer zet deze poorten open als de firewall wordt ingesteld. Heeft je hostingprovider een eigen firewall, zet ze daar ook open.

| Onderdeel | Poorten | Wanneer |
| --------- | ------- | ------- |
| SSH | de poort van sshd (meestal 22) | altijd |
| Panel | 80, 443 (TCP) | panel |
| Wings | 8080, 2022 (TCP) | Wings |
| Wings met Let's Encrypt | 80, 443 (TCP) | certificaat voor Wings |
| Gameservers | standaard 25565-25600 (TCP en UDP) | bij het koppelen van de node |
| Databases | 3306 (TCP), alleen vanuit het Docker-netwerk | databases automatisch |
| Databases | 3306 (TCP), alleen vanaf het panel | databases zelf instellen met `DBHOST_FIREWALL=true` |
| Webinstaller | 8443 (TCP), tijdelijk | zolang de webinstaller draait |
| Webinstaller | 80 (TCP), kort | tijdens de certificaataanvraag |

## Verwijderen

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/etheronhosting/Pterodactyl-install-script-etheron-hosting/main/install.sh) verwijderen
```

**Panel.** De installer verwijdert:

- de panelbestanden, de nginx-configuratie, de queue-worker en de cronjob;
- na een vraag ook de database en de databasegebruiker van het panel.

**Wings.** De installer verwijdert:

- de containers van gameservers (gedeelde images en volumes blijven staan);
- de bestanden, de service en de MariaDB-instelling voor databases van buitenaf.

**Beide.** Bij Let's Encrypt-certificaten die niet meer in gebruik zijn, vraagt hij of ze weg mogen. Het certificaat van de webinstaller verdwijnt altijd.

**Wat blijft staan:** Composer, Docker, MariaDB, nginx, PHP en de gebruikers van databasehosts.

## Problemen oplossen

| Probleem | Oplossing |
| -------- | --------- |
| `curl: command not found` | Installeer curl eerst: `apt install -y curl` of `dnf install -y curl`. |
| De link van de webinstaller laadt niet | Zet poort 8443 open bij je hostingprovider, of kies een andere poort met `ETHERON_WEB_PORT`. |
| De browser waarschuwt voor het certificaat van de webinstaller | Poort 80 was dicht of bezet. Zet poort 80 open en start de webinstaller opnieuw, of ga door met de waarschuwing (de vingerafdruk staat in de terminal). |
| Let's Encrypt mislukt | Controleer of het adres naar de server wijst (zonder Cloudflare-proxy) en of poort 80 en 443 open staan. Het panel draait dan eerst op HTTP; vraag later opnieuw aan met `certbot --nginx -d <domein>`. |
| "Wings is al gekoppeld" | De node bestaat al. Wil je alleen de databases (opnieuw) instellen, gebruik dan een instellingenbestand met `NODE_DBHOST=true` en `./install.sh node --config <bestand>`. Wil je helemaal opnieuw koppelen, verwijder dan eerst `/etc/pterodactyl/config.yml` en de node in het panel. |
| "Databases voor gameservers zijn nog niet ingesteld" | De melding noemt de oorzaak. Los die op en klik op **Databases opnieuw instellen**, of gebruik `NODE_DBHOST=true` zoals hierboven. |
| De console van een gameserver werkt niet in de browser | Het panel gebruikt HTTPS en Wings niet. Installeer Wings met Let's Encrypt, of gebruik voor beide hetzelfde nip.io-adres of domein. |
| Meer details nodig | Bekijk `/var/log/etheron-installer.log`, `journalctl -u etheron-webinstaller` of `journalctl -u wings`. |

## Opbouw van het project

```text
install.sh               Startpunt: menu, acties, onbegeleide modus en de one-liner
lib/lib.sh               Gedeelde functies: systeem, pakketten, firewall, DNS, instellingen
ui/                      Vragen in de terminal (panel.sh, wings.sh)
installers/              De installatie zelf: panel.sh, wings.sh, node.sh, uninstall.sh
webui/webinstaller.sh    Webinstaller starten, certificaat, firewallpoort en opruimen
webui/server.py          Webserver van de wizard (alleen Python-standaardbibliotheek, 3.6+)
webui/static/            Wizard: HTML, CSS, JavaScript, logo en lettertype
configs/                 Sjablonen voor nginx, systemd en PHP-FPM, en geldige tijdzones
voorbeelden/             Voorbeelden van instellingenbestanden voor onbegeleid installeren
tests/                   Unittests (Bash en Python)
```

## Ontwikkelen en testen

| Controle | Commando |
| -------- | -------- |
| Unittests Bash (Linux of WSL) | `bash tests/lib_test.sh` |
| Unittests webinstaller | `python3 tests/webui_test.py` |
| ShellCheck | `shellcheck -x install.sh lib/*.sh ui/*.sh installers/*.sh webui/*.sh tests/*.sh` |
| JavaScript-syntax | `node --check webui/static/app.js` |

Deze controles draaien ook in GitHub Actions bij elke push.

Een echte installatie test je op een verse VM, bijvoorbeeld met [Vagrant](https://www.vagrantup.com):

```bash
vagrant up debian_trixie
```

```bash
vagrant ssh debian_trixie
```

Start daarna in de VM `sudo /vagrant/install.sh`; het project staat daar in `/vagrant`.

Beschikbare machines:

- Ubuntu: `ubuntu_jammy`, `ubuntu_noble`, `ubuntu_resolute`
- Debian: `debian_bookworm`, `debian_trixie`
- AlmaLinux: `almalinux_8`, `almalinux_9`, `almalinux_10`
- Rocky Linux: `rockylinux_8`, `rockylinux_9`, `rockylinux_10`

Nieuwe code testen na een release kan met `ETHERON_REF=main` voor de one-liner.

## Een nieuwe versie uitbrengen

1. Zet het nieuwe versienummer in `ETHERON_VERSION` in [install.sh](install.sh), bijvoorbeeld `v1.0.1`.
2. Zet de wijzigingen en de datum in [CHANGELOG.md](CHANGELOG.md).
3. Commit en push naar `main`.
4. Maak de tag aan en push die:

   ```bash
   git tag v1.0.1
   ```

   ```bash
   git push origin v1.0.1
   ```

Vanaf dat moment downloadt de one-liner die release. Wijzigingen op `main` komen pas bij klanten met de volgende tag.

## Verschillen met pterodactyl-installer

- Nederlandstalig, met Etheron-standaarden en de huisstijl van etheron.nl.
- Webinstaller, automatisch koppelen van nodes, databases voor gameservers en nip.io-adressen.
- Onbegeleide modus met een gecontroleerd instellingenbestand.
- Draait volledig lokaal: tijdens de installatie worden geen losse scripts van GitHub opgehaald.
- Verbeteringen:
  - DNS-controle op alle A- en AAAA-records;
  - de firewall gaat pas aan als de poorten open staan, met de echte SSH-poort;
  - de installer van Composer wordt met de officiële controlesom gecontroleerd;
  - `.env` is niet leesbaar voor andere gebruikers;
  - Wings wordt herstart na een verlenging van het certificaat;
  - gegenereerde wachtwoorden hoeven nergens geëscaped te worden.

Alle wijzigingen staan in [CHANGELOG.md](CHANGELOG.md).

## Licentie

GPL-3.0, net als het origineel; zie [LICENSE](LICENSE). Verspreid je een aangepaste versie, dan moet die ook onder GPL-3.0 vallen en moet de broncode beschikbaar zijn.

Uitzonderingen in `webui/static/`:

- Het Etheron-logo en het favicon zijn eigendom van Etheron Hosting en vallen niet onder de GPL.
- Het lettertype Rubik valt onder de SIL Open Font License 1.1 (zie [OFL.txt](webui/static/fonts/OFL.txt)).

Copyright © 2026 Etheron Hosting. Gebaseerd op werk dat copyright © 2018–2026 Vilhelm Prytz en bijdragers is.
