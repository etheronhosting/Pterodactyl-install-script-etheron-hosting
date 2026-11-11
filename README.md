# Etheron Pterodactyl-installer

[![Controles](https://github.com/etheronhosting/Pterodactyl-install-script-etheron-hosting/actions/workflows/controles.yml/badge.svg)](https://github.com/etheronhosting/Pterodactyl-install-script-etheron-hosting/actions/workflows/controles.yml)
![Versie](https://img.shields.io/badge/versie-1.0.1-0c94ab)
[![Licentie: GPL-3.0](https://img.shields.io/badge/licentie-GPL--3.0-blue)](LICENSE)

Installeer [Pterodactyl](https://pterodactyl.io/) Panel en Wings met één commando. Je doet alles gewoon via je browser, geen technische kennis nodig.

> Niet verbonden aan het officiële Pterodactyl-project. Pterodactyl® is een geregistreerd handelsmerk van zijn eigenaren.

## Inhoud

- [Snel aan de slag](#snel-aan-de-slag)
- [Wat de installer doet](#wat-de-installer-doet)
- [Vereisten](#vereisten)
- [Installeren via de browser](#installeren-via-de-browser)
- [Adres en HTTPS](#adres-en-https)
- [Wings koppelen aan het panel](#wings-koppelen-aan-het-panel)
- [Databases voor gameservers](#databases-voor-gameservers)
- [Poorten](#poorten)
- [Credits](#credits)
- [Licentie](#licentie)

## Snel aan de slag

Volg deze stappen op een **verse server** (dus zonder andere software erop). Je logt in als **root** via SSH (bijvoorbeeld met PuTTY of de terminal van je computer).

**Stap 1 — Installeer eerst `curl`.** Dit heb je nodig om de installer binnen te halen. Kopieer en plak dit commando:

Voor Ubuntu of Debian:

```bash
apt update && apt install -y curl
```

Voor Rocky Linux of AlmaLinux:

```bash
dnf install -y curl
```

**Stap 2 — Start de installer.** Kopieer en plak dit commando:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/etheronhosting/Pterodactyl-install-script-etheron-hosting/main/install.sh) web
```

**Stap 3 — Open de link.** Er verschijnt een link in de terminal, bijvoorbeeld `https://installer-203-0-113-10.sslip.io:8443/?token=…`. Klik erop of kopieer hem naar je browser. De rest wijst zich vanzelf: je kiest wat je wilt installeren en de installer doet de rest. Je mag het SSH-venster daarna rustig sluiten.

Klaar! De installatie gaat volledig via je browser verder.

## Wat de installer doet

De installer regelt alles voor je, zodat jij je geen zorgen hoeft te maken over technische zaken:

| Onderdeel | Wat er gebeurt |
| --------- | -------------- |
| **Panel** | De bediening van Pterodactyl (waar jij en je klanten gameservers beheren), plus je eerste beheerdersaccount. |
| **Wings** | Het programma dat de gameservers zelf draait. |
| **Panel en Wings** | Beide samen op één server, kant-en-klaar. |
| **Node koppelen** | De server automatisch aan het panel koppelen, inclusief poorten voor gameservers. |
| **Databases** | Een databasehost voor gameservers instellen en direct in het panel zetten. |
| **HTTPS** | Gratis beveiligd verbinding (Let's Encrypt), of een eigen certificaat. Geen eigen domein? Dan krijg je een gratis adres. |
| **Firewall** | Alleen de poorten die echt nodig zijn, gaan open. De rest blijft dicht. |

Standaard: tijdzone `Europe/Amsterdam` en telemetrie uit. Alles wordt gecontroleerd voordat er iets wordt geïnstalleerd.

## Vereisten

Je server moet een van deze besturingssystemen hebben:

| Besturingssysteem | Versies |
| ----------------- | ------- |
| Ubuntu | 22.04, 24.04, 26.04 |
| Debian | 12, 13 |
| Rocky Linux | 8, 9, 10 |
| AlmaLinux | 8, 9, 10 |

Verder heb je nodig:

- **Een verse server** (x86_64 of arm64). De installer werkt alleen op een lege server. Heb je al een panel draaien? Gebruik dan de [officiële handleiding om te upgraden](https://pterodactyl.io/panel/1.0/updating.html).
- **Root-toegang.** Log in als `root`, of word root met `sudo -i`.
- **Poorten open bij je hostingprovider.** Heeft je provider een eigen firewall? Zet daar de poorten open die bij [Poorten](#poorten) staan.

## Installeren via de browser

Als je op stap 2 uit [Snel aan de slag](#snel-aan-de-slag) het commando uitvoert, gebeurt dit:

1. **De installer start.** Hij zet Python en OpenSSL klaar en vraagt een gratis certificaat aan. Daarna start hij de wizard op poort 8443.
2. **Je krijgt een link.** In de terminal verschijnt een link met een eenmalige toegangscode. Alleen met die link kom je op de wizard.
3. **Open de link in je browser.** Je kiest wat je wilt installeren (Panel, Wings of beide) en hoe de server bereikbaar moet zijn:
   - **Je eigen domein** (bijv. `panel.jouwdomein.nl`);
   - **Een gratis adres**, als je geen domein hebt;
   - **Alleen het IP-adres** (alleen om te testen).
4. **Vul je gegevens in.** Je maakt een beheerdersaccount en vult de Wings-opties in. De installer controleert alles voordat er iets wordt geïnstalleerd.
5. **De installatie loopt.** Je ziet live wat er gebeurt. Je mag de pagina sluiten en later weer openen met dezelfde link.
6. **Laatste stap.** Klik op **Node aanmaken en Wings starten**. Klaar!

**De webinstaller sluit zichzelf af** 30 minuten na de installatie, of na een uur zonder gebruik, of na 24 uur, of als je op **Webinstaller afsluiten** klikt. Zo blijft hij niet onnodig open staan.

**Krijg je een waarschuwing over het certificaat?** Dat kan gebeuren als poort 80 niet open stond. Je mag dan rustig doorklikken; de vingerafdruk van het certificaat staat in de terminal, zodat je kunt controleren of het klopt.

## Adres en HTTPS

De installer kan je panel op drie manieren bereikbaar maken:

| Keuze | Adres | HTTPS |
| ----- | ----- | ----- |
| **Eigen domein** | bijv. `panel.jouwdomein.nl` (zet een A-record naar de server) | Gratis via Let's Encrypt (aanbevolen) |
| **Gratis adres (nip.io)** | bijv. `203-0-113-10.nip.io` | Gratis via Let's Encrypt |
| **Alleen IP-adres** | bijv. `203.0.113.10` | Geen; alleen om te testen |

**Geen eigen domein?** Geen probleem. [nip.io](https://nip.io/) geeft je gratis een adres dat automatisch naar je server wijst. Je hoeft helemaal niets in te stellen.

**Gebruik je Cloudflare?** Zet de proxy (het oranje wolkje) uit voor het record, anders lukt het certificaat niet.

**Eigen certificaat gebruiken?** Zet het certificaat in `/etc/ssl/<domein>.pem` en de sleutel in `/etc/ssl/<domein>.key`, en herstart nginx: `nginx -t && systemctl restart nginx`.

## Wings koppelen aan het panel

Na de installatie koppelt de installer Wings met één klik aan het panel. Wat er dan gebeurt:

1. Er wordt een **locatie** aangemaakt (standaard `nl`).
2. Er wordt een **node** aangemaakt, met het geheugen en de vrije schijfruimte van je server.
3. **Poorten voor gameservers** worden toegevoegd (standaard `25565-25600`) en in de firewall opengezet.
4. De **configuratie van Wings** wordt neergezet en Wings wordt gestart.

**Staat je panel op een andere server?** Dan heb je een API-sleutel nodig uit het panel (**Admin → Application API → Create New**). Zet **Locations**, **Nodes** en **Allocations** op Read & Write.

## Databases voor gameservers

Bij Wings kies je uit drie opties:

| Optie | Wat er gebeurt |
| ----- | -------------- |
| **Automatisch** | De installer maakt alles zelf aan en zet de databasehost in het panel. (Alleen als Panel en Wings op dezelfde server staan.) |
| **Zelf instellen** | Jij kiest zelf gebruikersnaam en wachtwoord. Daarna voeg je de databasehost toe via **Admin → Databases**. |
| **Niet nodig** | Er wordt niets ingesteld. |

Kies je "Automatisch", dan is de database alleen bereikbaar vanuit de gameservers zelf. Van buitenaf blijft poort 3306 dicht.

## Poorten

De installer zet deze poorten open. Heeft je hostingprovider een eigen firewall? Zet ze daar ook open, anders werkt het niet.

| Onderdeel | Poorten | Wanneer |
| --------- | ------- | ------- |
| SSH | meestal 22 | altijd |
| Panel | 80, 443 (TCP) | panel |
| Wings | 8080, 2022 (TCP) | Wings |
| Wings met HTTPS | 80, 443 (TCP) | certificaat voor Wings |
| Gameservers | standaard 25565-25600 (TCP en UDP) | bij het koppelen |
| Webinstaller | 8443 (TCP), tijdelijk | zolang de webinstaller draait |

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
