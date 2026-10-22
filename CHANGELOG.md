# Changelog

Dit project volgt [semantic versioning](https://semver.org). Wijzigingen staan onder Opgelost, Gewijzigd of Toegevoegd.

## v1.0.0 (nog niet uitgebracht)

Eerste versie, gebaseerd op [pterodactyl-installer v1.4.0](https://github.com/pterodactyl-installer/pterodactyl-installer/releases/tag/v1.4.0).

### Toegevoegd

- Webinstaller (`install.sh web`): een tijdelijke HTTPS-wizard op de server voor klanten, met domeincontrole, live voortgang en Wings koppelen via de browser.
- Onbegeleide installatie met `--config <bestand>` en voorbeeldbestanden in `voorbeelden/`.
- Alle instellingen worden gecontroleerd voordat er iets wordt geïnstalleerd, ook bij panel en Wings samen.
- Het beheerderswachtwoord moet twee keer ingevoerd worden.
- Wings wordt na een certificaatverlenging automatisch herstart.
- Poort 3306 kan beperkt worden tot het IP-adres van het panel.
- Unittests (`tests/lib_test.sh`) en GitHub Actions voor ShellCheck en tests.

### Gewijzigd

- Alle teksten in het Nederlands.
- Standaardtijdzone `Europe/Amsterdam`, telemetrie standaard uit.
- Het script draait volledig lokaal; de one-liner downloadt één vaste release in plaats van losse bestanden.
- MariaDB-toegang van buitenaf via `99-etheron-dbhost.cnf` in plaats van een `sed` op de standaardconfig.
- Gegenereerde wachtwoorden bevatten alleen letters en cijfers.
- Geen "canary"-opties meer in het menu; gebruik `ETHERON_REF=<branch>`.

### Opgelost

- DNS-controle: kijkt naar alle A- en AAAA-records en eerst naar de eigen adressen van de server.
- Firewall: poorten worden geopend voordat de firewall aangaat, en de echte SSH-poort wordt meegenomen.
- Nep-kernelcontrole (`grep "xxxx"`) verwijderd.
- Losse `+` in de melding bij het installeren van firewalld.
- Composer-installer wordt gecontroleerd met de officiële controlesom.
- `.env` van het panel is niet meer leesbaar voor iedereen; ook verborgen bestanden krijgen de juiste eigenaar.
- Wings-installatie op een kale Debian/Ubuntu-server: de pakketbronnen worden nu eerst bijgewerkt.
- Op minimale installaties zonder curl installeert de installer eerst curl en CA-certificaten.
- Certbot voor Wings stopt nginx (indien actief) bij aanvragen en verlengen, zodat poort 80 vrij is.
