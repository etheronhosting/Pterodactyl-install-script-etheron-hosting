# Herkomst en credits

## Oorspronkelijk project

De Etheron Pterodactyl-installer is een aangepaste versie (fork) van **pterodactyl-installer**:

- **Project:** <https://github.com/pterodactyl-installer/pterodactyl-installer>
- **Basis:** versie v1.4.0 (commit `19e7e12`, 10 oktober 2026)
- **Copyright:** © 2018 – 2026 Vilhelm Prytz <vilhelm@prytznet.se> en bijdragers
- **Licentie:** GNU General Public License v3.0 of later

Met dank aan:

- [Vilhelm Prytz](https://github.com/vilhelmprytz), maker van pterodactyl-installer;
- [Linux123123](https://github.com/Linux123123), maintainer;
- [alle bijdragers](https://github.com/pterodactyl-installer/pterodactyl-installer/graphs/contributors) aan het oorspronkelijke project.

De opzet van de installatie van het panel en Wings, de configuratiesjablonen in `configs/`, de verwijderroutine en een groot deel van de hulpfuncties in `lib/lib.sh` komen uit dat project. De copyrightvermeldingen van het origineel staan in de headers van de overgenomen bestanden.

## Wijzigingen door Etheron Hosting

In oktober 2026 heeft Etheron Hosting het project aangepast en uitgebreid. Op hoofdlijnen:

- alle teksten in het Nederlands, met Etheron-standaarden;
- installatie volledig lokaal, met een onbegeleide modus;
- nieuw: de webinstaller (`webui/`), het automatisch koppelen van nodes (`installers/node.sh`), databases voor gameservers en nip.io-adressen;
- diverse fouten opgelost en de beveiliging verbeterd.

Alle wijzigingen staan per onderdeel in [CHANGELOG.md](CHANGELOG.md). De volledige geschiedenis staat in de git-log van deze repository.

## Onderdelen van derden

| Onderdeel | Eigenaar | Licentie of gebruik |
| --------- | -------- | ------------------- |
| Lettertype Rubik (`webui/static/fonts/`) | The Rubik Project Authors | SIL Open Font License 1.1, zie [OFL.txt](webui/static/fonts/OFL.txt) |
| Etheron-logo en favicon (`webui/static/`) | Etheron Hosting | Handelsmerk; valt niet onder de GPL (zie hieronder) |
| Invoer van wachtwoorden in `lib/lib.sh` | Stack Overflow-antwoord [22940001](https://stackoverflow.com/a/22940001) | CC BY-SA 4.0; overgenomen via het oorspronkelijke project |

## Handelsmerken

- **Pterodactyl®** is een geregistreerd handelsmerk. Pterodactyl is © Dane Everitt en bijdragers en valt onder de MIT-licentie ([github.com/pterodactyl](https://github.com/pterodactyl)). Deze installer is **niet** verbonden aan het officiële Pterodactyl-project; de naam wordt alleen gebruikt om aan te geven waarvoor de installer dient.
- **Etheron** en het Etheron-logo zijn handelsmerken van Etheron Hosting. Volgens artikel 7(e) van de GPL-3.0 geeft deze licentie geen recht om de naam of het logo van Etheron te gebruiken. Verspreid je een aangepaste versie, vervang dan het logo en de naam Etheron in de webinstaller.
