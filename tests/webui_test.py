#!/usr/bin/env python3
"""Tests voor webui/server.py die geen root of netwerk nodig hebben.

Draai ze op Linux (of WSL):  python3 tests/webui_test.py
"""

import os
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, os.path.join(ROOT, "webui"))

import server  # noqa: E402


class BuildConfigTest(unittest.TestCase):
    def test_booleans_and_strings(self):
        text = server.build_config("panel", {"FIREWALL": True, "TELEMETRY": False, "FQDN": "panel.etheron.nl"})
        self.assertIn('FIREWALL="true"', text)
        self.assertIn('TELEMETRY="false"', text)
        self.assertIn('FQDN="panel.etheron.nl"', text)

    def test_unknown_action(self):
        with self.assertRaises(ValueError):
            server.build_config("alles", {})

    def test_unknown_key(self):
        with self.assertRaises(ValueError):
            server.build_config("panel", {"FOO": "bar"})

    def test_wings_keys_not_allowed_for_panel(self):
        with self.assertRaises(ValueError):
            server.build_config("panel", {"DBHOST": True})

    def test_panel_keys_not_allowed_for_wings(self):
        with self.assertRaises(ValueError):
            server.build_config("wings", {"ADMIN_PASSWORD": "geheim123"})

    def test_beide_allows_both(self):
        text = server.build_config("beide", {"DBHOST": True, "ADMIN_USERNAME": "beheerder"})
        self.assertIn('DBHOST="true"', text)
        self.assertIn('ADMIN_USERNAME="beheerder"', text)

    def test_node_allows_only_node_keys(self):
        text = server.build_config("node", {"NODE_NAME": "node1", "PANEL_API_KEY": "ptla_abc", "NODE_DBHOST": True})
        self.assertIn('NODE_NAME="node1"', text)
        self.assertIn('NODE_DBHOST="true"', text)
        self.assertIn('PANEL_API_KEY="ptla_abc"', text)
        with self.assertRaises(ValueError):
            server.build_config("node", {"ADMIN_PASSWORD": "geheim123"})
        with self.assertRaises(ValueError):
            server.build_config("wings", {"NODE_NAME": "node1"})

    def test_control_characters_rejected(self):
        for value in ("a\nFIREWALL=true", "a\rb", "a\x00b", "a\tb"):
            with self.assertRaises(ValueError):
                server.build_config("panel", {"FQDN": value})

    def test_too_long_value_rejected(self):
        with self.assertRaises(ValueError):
            server.build_config("panel", {"FQDN": "a" * 513})

    def test_non_string_rejected(self):
        with self.assertRaises(ValueError):
            server.build_config("panel", {"FQDN": ["panel.etheron.nl"]})

    def test_settings_must_be_object(self):
        with self.assertRaises(ValueError):
            server.build_config("panel", ["FQDN"])


class NipNameTest(unittest.TestCase):
    def test_ipv4(self):
        self.assertEqual(server.nip_name("185.114.156.248"), "185-114-156-248.nip.io")

    def test_ipv6_and_empty(self):
        self.assertEqual(server.nip_name("2001:db8::1"), "")
        self.assertEqual(server.nip_name(""), "")


class ParseErrorsTest(unittest.TestCase):
    OUTPUT = (
        "\n* \x1b[0;31mFOUT\x1b[0m: ADMIN_PASSWORD ontbreekt (minimaal 8 tekens).\n\n"
        "* \x1b[0;31mFOUT\x1b[0m: Ongeldige waarde voor TIMEZONE (zie configs/valid_timezones.txt).\n"
        "* \x1b[0;31mFOUT\x1b[0m: Let's Encrypt vraagt een domeinnaam, geen IP-adres of localhost (FQDN=192.0.2.1).\n"
        "* \x1b[0;31mFOUT\x1b[0m: Het instellingenbestand bevat 3 fout(en). Er is niets geïnstalleerd.\n"
        "* Gewone uitvoer\n"
    )

    def test_parse(self):
        errors = server.parse_errors(self.OUTPUT)
        self.assertEqual(errors, [
            {"key": "ADMIN_PASSWORD", "message": "Dit veld is verplicht."},
            {"key": "TIMEZONE", "message": "Ongeldige waarde: zie configs/valid_timezones.txt."},
            {"key": None, "message": "Let's Encrypt vraagt een domeinnaam, geen IP-adres of localhost (FQDN=192.0.2.1)."},
        ])

    def test_strip_ansi(self):
        self.assertEqual(server.strip_ansi("\x1b[1;33mLET OP\x1b[0m\r"), "LET OP")


@unittest.skipUnless(shutil.which("bash") and os.name == "posix", "bash op Linux nodig")
class RoundTripTest(unittest.TestCase):
    """Een bestand van de webinstaller moet in Bash exact dezelfde waarden opleveren."""

    def test_values_survive_load_config(self):
        settings = {
            "FQDN": "panel.etheron.nl",
            "ADMIN_PASSWORD": ' spaties "quotes" $dollar `backtick` \\slash # hekje ',
            "ADMIN_FIRSTNAME": "Jörg",
            "FIREWALL": True,
        }
        directory = tempfile.mkdtemp()
        try:
            path = server.write_private(directory, server.build_config("panel", settings))
            self.assertEqual(os.stat(path).st_mode & 0o777, 0o600)
            script = (
                'source "$1/lib/lib.sh" && load_config "$2" && '
                'printf "%s\\n" "$FQDN" "$ADMIN_PASSWORD" "$ADMIN_FIRSTNAME" "$FIREWALL"'
            )
            result = subprocess.run(["bash", "-c", script, "test", ROOT, path], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            self.assertEqual(result.returncode, 0, result.stderr.decode())
            values = result.stdout.decode("utf-8").split("\n")[:4]
            self.assertEqual(values, [settings["FQDN"], settings["ADMIN_PASSWORD"], "Jörg", "true"])
        finally:
            shutil.rmtree(directory)


if __name__ == "__main__":
    unittest.main(verbosity=1)
