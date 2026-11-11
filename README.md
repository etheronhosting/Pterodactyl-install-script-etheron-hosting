# Etheron Pterodactyl-installer

[![Controles](https://github.com/etheronhosting/Pterodactyl-install-script-etheron-hosting/actions/workflows/controles.yml/badge.svg)](https://github.com/etheronhosting/Pterodactyl-install-script-etheron-hosting/actions/workflows/controles.yml)
![Versie](https://img.shields.io/badge/versie-1.0.1-0c94ab)
[![Licentie: GPL-3.0](https://img.shields.io/badge/licentie-GPL--3.0-blue)](LICENSE)

Installeer [Pterodactyl](https://pterodactyl.io/) Panel en Wings met één commando, via de browser of in de terminal.

> Niet verbonden aan het officiële Pterodactyl-project. Pterodactyl® is een geregistreerd handelsmerk van zijn eigenaren.

## Inhoud

- [Snel aan de slag](#snel-aan-de-slag)
- [Wat de installer doet](#wat-de-installer-doet)
- [Vereisten](#vereisten)
- [Installeren via de browser](#installeren-via-de-browser)
- [Installeren in de terminal](#installeren-in-de-terminal)
- [Adres en HTTPS](#adres-en-https)
- [Wings koppelen aan het panel](#wings-koppelen-aan-het-panel)
- [Databases voor gameservers](#databases-voor-gameservers)
- [Poorten](#poorten)
- [Verwijderen](#verwijderen)
- [Credits](#credits)
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
3. **Wizard invullen.** Kies wat je wilt installeren (Panel, Wings of beide) en hoe de server bereikbaar moet zijn (eigen domein, gratis nip.io-adres of alleen IP). Vul daarna het beheerdersaccount en de Wings-opties in.
4. **Installatie volgen.** De voortgang is live te zien. De pagina mag dicht en later opnieuw open met dezelfde link.
5. **Laatste stap.** Bovenaan de eindpagina staat de knop **Node aanmaken en Wings starten**, die Wings aan het panel koppelt.

**De webinstaller stopt vanzelf** 30 minuten na de installatie, na een uur zonder gebruik, na 24 uur, of als je op **Webinstaller afsluiten** klikt. Zelf stoppen kan met `systemctl stop etheron-webinstaller`.

## Installeren in de terminal

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/etheronhosting/Pterodactyl-install-script-etheron-hosting/main/install.sh) [actie]
```

Zonder actie verschijnt een menu.

| Actie | Wat het doet |
| ----- | ------------ |
| `web` | Webinstaller starten (installeren via de browser) |
| `panel` | Pterodactyl Panel installeren |
| `wings` | Wings installeren |
| `beide` | Panel en Wings op dezelfde server installeren |
| `verwijderen` | Panel en/of Wings verwijderen |

**Logbestand.** Alle uitvoer van de installatie staat ook in `/var/log/etheron-installer.log` (alleen leesbaar voor root).

## Adres en HTTPS

Het panel (en Wings) kan op drie manieren bereikbaar zijn:

| Keuze | Adres | HTTPS |
| ----- | ----- | ----- |
| **Eigen domein** | bijv. `panel.jouwdomein.nl`, met een A-record naar de server | Let's Encrypt (aanbevolen), een eigen certificaat of geen |
| **Gratis nip.io-adres** | bijv. `203-0-113-10.nip.io` of `mijnpanel-203-0-113-10.nip.io` | Let's Encrypt |
| **Alleen IP-adres** | bijv. `203.0.113.10` | Geen; alleen geschikt om te testen |

**Geen eigen domein?** [nip.io](https://nip.io/) haalt het IP-adres uit de naam, dus het adres wijst automatisch naar je server. Je hoeft geen DNS-records in te stellen.

**Controle vooraf.** Voor een certificaat controleert de installer of alle A- en AAAA-records naar de server wijzen. Gebruik je Cloudflare, zet dan de proxy (oranje wolk) uit voor dat record.

**Eigen certificaat.** Zet het certificaat in `/etc/ssl/<domein>.pem` en de sleutel in `/etc/ssl/<domein>.key`, en herstart daarna nginx: `nginx -t && systemctl restart nginx`.

## Wings koppelen aan het panel

Na een Wings-installatie koppelt de installer de node met één klik (webinstaller) of automatisch (terminal). Dat doet hij zo:

1. Een **locatie** aanmaken (standaard `nl`); bestaat die al, dan gebruikt hij die.
2. Een **node** aanmaken, met het geheugen en de vrije schijfruimte van de server.
3. **Poorten voor gameservers** toevoegen (standaard `25565-25600`) en die in de firewall openzetten, voor TCP en UDP.
4. De **configuratie van Wings** neerzetten, **Wings starten** en controleren of het draait.

**Staat het panel op een andere server?** Dan heb je een API-sleutel nodig. Die maak je in het panel via **Admin → Application API → Create New**. Zet **Locations**, **Nodes** en **Allocations** op Read & Write.

**Liever zelf koppelen?** In de webinstaller kun je ook de configuratie van de node uit het panel plakken (tabblad *Configuration* van de node). De wizard zet die dan neer en start Wings.

## Databases voor gameservers

Bij Wings kies je tussen drie opties:

| Optie | Wat er gebeurt |
| ----- | -------------- |
| **Automatisch instellen** | De installer maakt een databasegebruiker aan en zet de databasehost in het panel. Alleen als Panel en Wings op dezelfde server staan. |
| **Zelf instellen** | Je kiest zelf gebruikersnaam en wachtwoord. Daarna voeg je de databasehost zelf toe onder **Admin → Databases**. |
| **Niet nodig** | Er wordt niets ingesteld. |

Bij "Automatisch" draaien gameservers in Docker en bereiken MariaDB via de Docker-gateway (standaard `172.18.0.1`). De firewall laat poort 3306 alleen toe vanuit het Docker-netwerk, dus van buiten blijft die dicht.

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
| Webinstaller | 8443 (TCP), tijdelijk | zolang de webinstaller draait |
| Webinstaller | 80 (TCP), kort | tijdens de certificaataanvraag |

## Verwijderen

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/etheronhosting/Pterodactyl-install-script-etheron-hosting/main/install.sh) verwijderen
```

**Panel:** panelbestanden, nginx-configuratie, queue-worker en cronjob. Na een vraag ook de database en de databasegebruiker van het panel.

**Wings:** containers van gameservers (gedeelde images en volumes blijven staan), de bestanden, de service en de MariaDB-instelling voor databases van buitenaf.

**Wat blijft staan:** Composer, Docker, MariaDB, nginx, PHP en de gebruikers van databasehosts.

## Credits

Deze installer bestaat dankzij [pterodactyl-installer](https://github.com/pterodactyl-installer/pterodactyl-installer):

- gemaakt door [Vilhelm Prytz](https://github.com/vilhelmprytz);
- onderhouden door [Linux123123](https://github.com/Linux123123);
- met hulp van [veel bijdragers](https://github.com/pterodactyl-installer/pterodactyl-installer/graphs/contributors).

Meer over de herkomst en over onderdelen van derden staat in [CREDITS.md](CREDITS.md).

## Licentie

GPL-3.0, net als het origineel; zie [LICENSE](LICENSE). Verspreid je een aangepaste versie, dan moet die ook onder GPL-3.0 vallen, moet de broncode beschikbaar zijn en moeten de copyrightvermeldingen blijven staan.

- Copyright © 2018–2026 Vilhelm Prytz en bijdragers (oorspronkelijk project)
- Copyright © 2026 Etheron Hosting (aanpassingen en uitbreidingen)

Uitzonderingen in `webui/static/`:

- Het Etheron-logo en het favicon zijn handelsmerken van Etheron Hosting. Volgens artikel 7(e) van de GPL-3.0 vallen ze niet onder de licentie; vervang ze in een eigen versie.
- Het lettertype Rubik valt onder de SIL Open Font License 1.1 (zie [OFL.txt](webui/static/fonts/OFL.txt)).
