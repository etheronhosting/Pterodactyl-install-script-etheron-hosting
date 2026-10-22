#!/usr/bin/env python3
#
# Etheron Pterodactyl-installer
#
# Copyright (C) 2026 Etheron Hosting
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

"""Webinstaller: een tijdelijke HTTPS-server met de installatiewizard.

De server toont de wizard, controleert de instellingen met de bestaande
installers (--controleren) en voert daarna install.sh onbegeleid uit. Alleen
de standaardbibliotheek wordt gebruikt en de code werkt vanaf Python 3.6
(Rocky/AlmaLinux 8). Wordt gestart door webui/webinstaller.sh.
"""

import argparse
import hashlib
import hmac
import json
import os
import re
import signal
import socket
import socketserver
import ssl
import subprocess
import sys
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs, urlsplit

COOKIE_NAME = "etheron_installer"
MAX_BODY = 64 * 1024
MAX_VALUE = 512
MAX_WINGS_CONFIG = 64 * 1024
MAX_LOG_LINES = 20000

# Wanneer de webinstaller zichzelf afsluit.
IDLE_TIMEOUT = 60 * 60
DONE_GRACE = 30 * 60
MAX_LIFETIME = 24 * 60 * 60

DEFAULT_TIMEZONE = "Europe/Amsterdam"
PANEL_DIR = "/var/www/pterodactyl"
WINGS_DIR = "/etc/pterodactyl"

COMMON_KEYS = ["FQDN", "EMAIL", "FIREWALL", "LETSENCRYPT", "VERIFY_DNS"]
PANEL_KEYS = [
    "ASSUME_SSL", "PANEL_VERSION", "TIMEZONE", "TELEMETRY",
    "DB_NAME", "DB_USER", "DB_PASSWORD",
    "ADMIN_EMAIL", "ADMIN_USERNAME", "ADMIN_FIRSTNAME", "ADMIN_LASTNAME", "ADMIN_PASSWORD",
]
WINGS_KEYS = ["DBHOST", "DBHOST_USER", "DBHOST_PASSWORD", "DBHOST_ALLOW", "DBHOST_FIREWALL"]
NODE_KEYS = ["NODE_NAME", "NODE_LOCATION", "NODE_PORTS", "NODE_FQDN", "PANEL_URL", "PANEL_API_KEY"]
INSTALLERS = {"panel": ["panel"], "wings": ["wings"], "beide": ["panel", "wings"], "node": ["node"]}
INSTALL_ACTIONS = ("panel", "wings", "beide")
LOG_PATH = "/var/log/etheron-installer.log"

STATIC_FILES = {
    "/": ("index.html", "text/html; charset=utf-8"),
    "/app.js": ("app.js", "application/javascript; charset=utf-8"),
    "/style.css": ("style.css", "text/css; charset=utf-8"),
}
PUBLIC_PATHS = ("/app.js", "/style.css")

SECURITY_HEADERS = {
    "Content-Security-Policy": (
        "default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self' data:; "
        "connect-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'"
    ),
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
    "Referrer-Policy": "no-referrer",
    "Cache-Control": "no-store",
}

FORBIDDEN_PAGE = """<!doctype html>
<html lang="nl"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Link ongeldig · Etheron</title><link rel="stylesheet" href="/style.css"></head>
<body><main class="container"><div class="card">
<h1>Deze link werkt niet (meer)</h1>
<p class="lead">De link is ongeldig of de webinstaller is inmiddels gestopt.</p>
<p>Start de webinstaller opnieuw op je server en open de nieuwe link die daar verschijnt.</p>
</div></main></body></html>
"""

ANSI_RE = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]|\x1b\][^\x07]*\x07")
CONTROL_RE = re.compile(r"[\x00-\x1f\x7f]")
MISSING_RE = re.compile(r"^([A-Z_]+) ontbreekt \((.*)\)\.$")
INVALID_RE = re.compile(r"^Ongeldige waarde voor ([A-Z_]+) \((.*)\)\.$")
HOSTNAME_RE = re.compile(r"^[A-Za-z0-9.-]{1,253}$")


def strip_ansi(text):
    return ANSI_RE.sub("", text).replace("\r", "")


def allowed_keys(action):
    if action == "node":
        return list(NODE_KEYS)
    keys = list(COMMON_KEYS)
    if "panel" in INSTALLERS[action]:
        keys += PANEL_KEYS
    if "wings" in INSTALLERS[action]:
        keys += WINGS_KEYS
    return keys


def build_config(action, settings):
    """Zet de instellingen uit de wizard om naar een instellingenbestand voor install.sh."""
    if action not in INSTALLERS:
        raise ValueError("Kies wat je wilt installeren.")
    if not isinstance(settings, dict):
        raise ValueError("Ongeldige instellingen.")

    allowed = allowed_keys(action)
    lines = ["# Gemaakt door de Etheron-webinstaller"]
    for key, value in settings.items():
        if key not in allowed:
            raise ValueError("Onbekende instelling: %s" % key)
        if isinstance(value, bool):
            value = "true" if value else "false"
        elif isinstance(value, int):
            value = str(value)
        elif value is None:
            value = ""
        elif not isinstance(value, str):
            raise ValueError("Ongeldige waarde voor %s." % key)
        if len(value) > MAX_VALUE or CONTROL_RE.search(value):
            raise ValueError("Ongeldige tekens in %s." % key)
        lines.append('%s="%s"' % (key, value))
    return "\n".join(lines) + "\n"


def parse_errors(output):
    """Haalt de foutmeldingen uit de uitvoer van 'installers/*.sh --controleren'."""
    errors = []
    for line in strip_ansi(output).splitlines():
        line = line.strip()
        if not line.startswith("* FOUT: "):
            continue
        message = line[len("* FOUT: "):]
        if message.startswith("Het instellingenbestand bevat"):
            continue
        match = MISSING_RE.match(message)
        if match:
            errors.append({"key": match.group(1), "message": "Dit veld is verplicht."})
            continue
        match = INVALID_RE.match(message)
        if match:
            hint = match.group(2)
            errors.append({"key": match.group(1), "message": "Ongeldige waarde: " + hint + ("" if hint.endswith(".") else ".")})
            continue
        errors.append({"key": None, "message": message})
    return errors


def nip_name(address):
    """Gratis nip.io-adres voor een IPv4-adres (nip.io kent geen IPv6)."""
    if not address or ":" in address:
        return ""
    return address.replace(".", "-") + ".nip.io"


def write_private(directory, text, suffix=".conf"):
    """Schrijft tekst naar een nieuw bestand dat alleen de eigenaar kan lezen."""
    fd, path = tempfile.mkstemp(dir=directory, suffix=suffix)
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        handle.write(text)
    return path


def os_name():
    try:
        with open("/etc/os-release", encoding="utf-8") as handle:
            for line in handle:
                if line.startswith("PRETTY_NAME="):
                    return line.split("=", 1)[1].strip().strip('"')
    except OSError:
        pass
    return "Linux"


class Job:
    """De installatie die vanuit de wizard is gestart (er kan er maar één tegelijk lopen)."""

    def __init__(self):
        self.lock = threading.Lock()
        self.state = "idle"
        self.action = None
        self.flags = {}
        self.lines = []
        self.exit_code = None
        self.finished_at = None

    def summary(self):
        with self.lock:
            return {
                "state": self.state,
                "action": self.action,
                "flags": dict(self.flags),
                "exitCode": self.exit_code,
            }


class Installer:
    """Alles wat de wizard op deze server kan doen."""

    def __init__(self, args):
        self.etheron_dir = os.path.abspath(args.etheron_dir)
        self.work_dir = os.path.abspath(args.work_dir)
        self.port = args.port
        self.address = args.address
        self.firewall_name = args.firewall_name
        self.tls = not args.no_tls
        with open(os.path.join(self.work_dir, "token"), encoding="utf-8") as handle:
            self.token = handle.read().strip()
        if len(self.token) < 24:
            raise SystemExit("Token ontbreekt of is te kort.")
        self.session = hmac.new(self.token.encode(), b"sessie", hashlib.sha256).hexdigest()
        self.job = Job()
        self.busy = threading.Lock()
        self.started = time.monotonic()
        self.last_request = time.monotonic()
        self.close_requested = False

        env = dict(os.environ)
        env.setdefault("HOME", "/root")
        env["ETHERON_WEB_PORT"] = str(self.port)
        env.pop("UNATTENDED", None)
        self.env = env

    # ---------------- Toegang ---------------- #

    def valid_token(self, token):
        return hmac.compare_digest(token.encode(), self.token.encode())

    def authorized(self, headers):
        cookie_header = headers.get("Cookie", "")
        for part in cookie_header.split(";"):
            name, _, value = part.strip().partition("=")
            if name == COOKIE_NAME and hmac.compare_digest(value.encode(), self.session.encode()):
                return True
        return False

    def cookie_header(self):
        attributes = "Path=/; HttpOnly; SameSite=Strict"
        if self.tls:
            attributes += "; Secure"
        return "%s=%s; %s" % (COOKIE_NAME, self.session, attributes)

    # ---------------- Gegevens ---------------- #

    def timezones(self):
        path = os.path.join(self.etheron_dir, "configs", "valid_timezones.txt")
        with open(path, encoding="utf-8") as handle:
            return [line.strip() for line in handle if line.strip()]

    def info(self):
        return {
            "version": os.environ.get("ETHERON_VERSION", ""),
            "os": os_name(),
            "address": self.address,
            "nipName": nip_name(self.address),
            "hostname": socket.gethostname().split(".")[0],
            "firewall": self.firewall_name,
            "webPort": self.port,
            "panelInstalled": os.path.isdir(PANEL_DIR),
            "wingsInstalled": os.path.isdir(WINGS_DIR),
            "timezones": self.timezones(),
            "defaultTimezone": DEFAULT_TIMEZONE,
            "job": self.job.summary(),
        }

    def status(self, since):
        with self.job.lock:
            since = max(0, min(since, len(self.job.lines)))
            lines = self.job.lines[since:since + 2000]
            closes_in = None
            if self.job.finished_at is not None:
                closes_in = max(0, int(DONE_GRACE - (time.monotonic() - self.job.finished_at)))
            return {
                "state": self.job.state,
                "action": self.job.action,
                "flags": dict(self.job.flags),
                "exitCode": self.job.exit_code,
                "lines": lines,
                "next": since + len(lines),
                "closesIn": closes_in,
            }

    # ---------------- Acties ---------------- #

    def script(self, *parts):
        return os.path.join(self.etheron_dir, *parts)

    def run(self, command, timeout):
        result = subprocess.run(
            command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            stdin=subprocess.DEVNULL, env=self.env, timeout=timeout,
        )
        return result.returncode, result.stdout.decode("utf-8", "replace")

    def check_dns(self, fqdn):
        if not HOSTNAME_RE.match(fqdn or ""):
            return {"ok": False, "lines": ["Vul een geldige domeinnaam in."]}
        if not self.busy.acquire(blocking=False):
            return {"ok": False, "lines": ["Er loopt al een controle of installatie. Probeer het zo opnieuw."]}
        try:
            code, output = self.run(["bash", self.script("webui", "webinstaller.sh"), "dns", fqdn], 300)
        finally:
            self.busy.release()
        lines = []
        for line in strip_ansi(output).splitlines():
            line = line.strip()
            # Alleen de uitslag; voortgangsregels ("...controleren...") weglaten.
            if line.startswith("* ") and len(line) > 2 and not line.endswith("..."):
                lines.append(line[2:])
        return {"ok": code == 0, "lines": lines}

    def check_settings(self, action, settings):
        """Controleert de instellingen met de installers. Geeft een lijst fouten terug."""
        path = write_private(self.work_dir, build_config(action, settings))
        try:
            errors = []
            for name in INSTALLERS[action]:
                code, output = self.run(
                    ["bash", self.script("installers", name + ".sh"), path, "--controleren"], 300)
                if code != 0:
                    errors += parse_errors(output) or [
                        {"key": None, "message": "De controle is mislukt: " + strip_ansi(output).strip()[-300:]}]
            return errors
        finally:
            os.unlink(path)

    def check(self, action, settings):
        if action not in INSTALL_ACTIONS:
            raise ValueError("Kies wat je wilt installeren.")
        if self.job.summary()["state"] != "idle":
            return 409, {"ok": False, "message": "Er loopt al een installatie."}
        if not self.busy.acquire(blocking=False):
            return 409, {"ok": False, "message": "Er loopt al een controle. Probeer het zo opnieuw."}
        try:
            errors = self.check_settings(action, settings)
        finally:
            self.busy.release()
        return 200, {"ok": not errors, "errors": errors}

    def install(self, action, settings):
        if action not in INSTALL_ACTIONS:
            raise ValueError("Kies wat je wilt installeren.")
        if not self.busy.acquire(blocking=False):
            return 409, {"ok": False, "message": "Er loopt al een controle of installatie."}
        started = False
        try:
            with self.job.lock:
                if self.job.state != "idle":
                    return 409, {"ok": False, "message": "Er loopt al een installatie."}
            errors = self.check_settings(action, settings)
            if errors:
                return 200, {"ok": False, "errors": errors}

            config = write_private(self.work_dir, build_config(action, settings))
            process = subprocess.Popen(
                ["bash", self.script("install.sh"), action, "--config", config],
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL, env=self.env,
            )
            with self.job.lock:
                self.job.state = "running"
                self.job.action = action
                self.job.flags = {key: bool(settings.get(key)) for key in ("LETSENCRYPT", "ASSUME_SSL", "DBHOST")}
                self.job.lines = []
            threading.Thread(target=self.follow, args=(process, config), daemon=True).start()
            started = True
            return 200, {"ok": True}
        finally:
            # Tijdens de installatie blijft 'busy' bezet, zodat er geen DNS-controle tussendoor komt.
            if not started:
                self.busy.release()

    def follow(self, process, config):
        try:
            for raw in iter(process.stdout.readline, b""):
                line = strip_ansi(raw.decode("utf-8", "replace")).rstrip()
                with self.job.lock:
                    self.job.lines.append(line)
                    if len(self.job.lines) > MAX_LOG_LINES:
                        del self.job.lines[:1000]
            process.wait()
        finally:
            # Het instellingenbestand bevat wachtwoorden: direct weg na de installatie.
            try:
                os.unlink(config)
            except OSError:
                pass
            with self.job.lock:
                self.job.exit_code = process.returncode
                self.job.state = "done" if process.returncode == 0 else "failed"
                self.job.finished_at = time.monotonic()
            self.busy.release()

    def log_to_file(self, title, output):
        """Voegt uitvoer toe aan het logbestand van de installer (voor support)."""
        try:
            fd = os.open(LOG_PATH, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
            with os.fdopen(fd, "a", encoding="utf-8") as handle:
                handle.write("\n* %s: %s\n%s\n" % (time.strftime("%Y-%m-%d %H:%M:%S"), title, strip_ansi(output)))
        except OSError:
            pass

    def link_node(self, settings):
        """Maakt locatie, node en poorten aan in het panel en start Wings (installers/node.sh)."""
        if self.job.summary()["state"] == "running":
            return 409, {"ok": False, "message": "Wacht tot de installatie klaar is."}
        if not os.path.exists("/usr/local/bin/wings"):
            return 409, {"ok": False, "message": "Wings is nog niet geïnstalleerd op deze server."}
        if not self.busy.acquire(blocking=False):
            return 409, {"ok": False, "message": "Er loopt al een andere actie. Probeer het zo opnieuw."}
        try:
            path = write_private(self.work_dir, build_config("node", settings))
            try:
                code, output = self.run(["bash", self.script("installers", "node.sh"), path], 300)
            finally:
                os.unlink(path)
        finally:
            self.busy.release()

        self.log_to_file("Node koppelen via de webinstaller", output)
        lines = [line for line in strip_ansi(output).splitlines() if line.strip()]
        if code == 0:
            return 200, {"ok": True, "lines": lines}
        errors = parse_errors(output) or [{"key": None, "message": "Koppelen is mislukt. Bekijk de details hieronder."}]
        return 200, {"ok": False, "errors": errors, "lines": lines}

    def save_wings_config(self, text):
        """Zet de configuratie uit het panel op de node en start Wings."""
        if not os.path.exists("/usr/local/bin/wings") or not os.path.isdir(WINGS_DIR):
            return 409, {"ok": False, "message": "Wings is nog niet geïnstalleerd op deze server."}
        if self.job.summary()["state"] == "running":
            return 409, {"ok": False, "message": "Wacht tot de installatie klaar is."}
        if not isinstance(text, str) or not text.strip() or len(text) > MAX_WINGS_CONFIG:
            return 200, {"ok": False, "message": "Plak de volledige configuratie uit het panel."}
        if not re.search(r"^uuid:", text, re.M) or not re.search(r"^token:", text, re.M):
            return 200, {"ok": False, "message": "Dit lijkt geen Wings-configuratie. Kopieer de tekst van het tabblad Configuration van je node."}

        path = os.path.join(WINGS_DIR, "config.yml")
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(text.replace("\r\n", "\n"))
        os.chmod(path, 0o600)

        self.run(["systemctl", "enable", "wings"], 60)
        self.run(["systemctl", "restart", "wings"], 60)
        time.sleep(5)
        code, _ = self.run(["systemctl", "is-active", "--quiet", "wings"], 30)
        if code == 0:
            return 200, {"ok": True, "message": "Wings draait. In het panel wordt je node binnen een minuut groen."}
        _, log = self.run(["journalctl", "-u", "wings", "-n", "15", "--no-pager", "-o", "cat"], 30)
        return 200, {"ok": False, "message": "Wings start niet met deze configuratie.", "log": strip_ansi(log)}

    def request_close(self):
        if self.job.summary()["state"] == "running":
            return 409, {"ok": False, "message": "De installatie loopt nog."}
        self.close_requested = True
        return 200, {"ok": True}

    def should_stop(self):
        now = time.monotonic()
        summary = self.job.summary()
        if summary["state"] == "running":
            return False
        if self.close_requested or now - self.started > MAX_LIFETIME:
            return True
        if summary["state"] in ("done", "failed"):
            return now - self.job.finished_at > DONE_GRACE
        return now - self.last_request > IDLE_TIMEOUT


class Handler(BaseHTTPRequestHandler):
    server_version = "Etheron-webinstaller"
    sys_version = ""
    timeout = 60

    @property
    def app(self):
        return self.server.app

    def log_message(self, fmt, *args):
        # Nooit de query loggen: daar staat bij het eerste bezoek het token in.
        path = urlsplit(getattr(self, "path", "") or "").path
        sys.stderr.write("%s %s %s\n" % (self.address_string(), getattr(self, "command", "-"), path))

    # ---------------- Antwoorden ---------------- #

    def send_body(self, code, body, content_type, extra_headers=None):
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        for name, value in SECURITY_HEADERS.items():
            self.send_header(name, value)
        for name, value in (extra_headers or {}).items():
            self.send_header(name, value)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def send_json(self, code, data):
        self.send_body(code, json.dumps(data).encode("utf-8"), "application/json; charset=utf-8")

    def send_static(self, path):
        name, content_type = STATIC_FILES[path]
        with open(os.path.join(self.app.etheron_dir, "webui", "static", name), "rb") as handle:
            self.send_body(200, handle.read(), content_type)

    def forbidden(self):
        self.send_body(403, FORBIDDEN_PAGE.encode("utf-8"), "text/html; charset=utf-8")

    # ---------------- Routes ---------------- #

    def do_GET(self):
        url = urlsplit(self.path)
        query = parse_qs(url.query)

        if url.path in PUBLIC_PATHS:
            return self.send_static(url.path)

        if url.path == "/" and "token" in query:
            if self.app.valid_token(query["token"][0]):
                self.app.last_request = time.monotonic()
                # Token uit de adresbalk halen; verder gaat het via een cookie.
                return self.send_body(303, b"", "text/plain", {"Location": "/", "Set-Cookie": self.app.cookie_header()})
            return self.forbidden()

        if not self.app.authorized(self.headers):
            if url.path.startswith("/api/"):
                return self.send_json(403, {"ok": False, "message": "Geen toegang."})
            return self.forbidden()
        self.app.last_request = time.monotonic()

        if url.path == "/":
            return self.send_static("/")
        if url.path == "/api/info":
            return self.send_json(200, self.app.info())
        if url.path == "/api/status":
            try:
                since = int(query.get("since", ["0"])[0])
            except ValueError:
                since = 0
            return self.send_json(200, self.app.status(since))
        return self.send_json(404, {"ok": False, "message": "Niet gevonden."})

    def do_HEAD(self):
        self.do_GET()

    def read_json(self):
        """Leest een JSON-verzoek van dezelfde site. Geeft None bij een ongeldig verzoek."""
        origin = self.headers.get("Origin")
        if not origin or urlsplit(origin).netloc != self.headers.get("Host"):
            return None
        if not self.headers.get("Content-Type", "").startswith("application/json"):
            return None
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            return None
        if length <= 0 or length > MAX_BODY:
            return None
        try:
            data = json.loads(self.rfile.read(length).decode("utf-8"))
        except (ValueError, UnicodeDecodeError):
            return None
        return data if isinstance(data, dict) else None

    def do_POST(self):
        path = urlsplit(self.path).path
        if not self.app.authorized(self.headers):
            return self.send_json(403, {"ok": False, "message": "Geen toegang."})
        data = self.read_json()
        if data is None:
            return self.send_json(400, {"ok": False, "message": "Ongeldig verzoek."})
        self.app.last_request = time.monotonic()

        try:
            if path == "/api/dns":
                return self.send_json(200, self.app.check_dns(str(data.get("fqdn", ""))))
            if path == "/api/check":
                return self.send_json(*self.app.check(data.get("action"), data.get("settings")))
            if path == "/api/install":
                return self.send_json(*self.app.install(data.get("action"), data.get("settings")))
            if path == "/api/node":
                return self.send_json(*self.app.link_node(data.get("settings")))
            if path == "/api/wings-config":
                return self.send_json(*self.app.save_wings_config(data.get("config")))
            if path == "/api/close":
                return self.send_json(*self.app.request_close())
        except ValueError as exc:
            return self.send_json(200, {"ok": False, "errors": [{"key": None, "message": str(exc)}]})
        except subprocess.TimeoutExpired:
            return self.send_json(200, {"ok": False, "errors": [{"key": None, "message": "De controle duurde te lang. Probeer het opnieuw."}]})
        return self.send_json(404, {"ok": False, "message": "Niet gevonden."})


class Server(socketserver.ThreadingMixIn, HTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    def handle_error(self, request, client_address):
        # Browsers breken de verbinding vaak af bij de waarschuwing over het certificaat.
        sys.stderr.write("Verbinding met %s mislukt: %s\n" % (client_address[0], sys.exc_info()[1]))


class DualStackServer(Server):
    """Luistert op IPv6 en IPv4 tegelijk."""

    address_family = socket.AF_INET6

    def server_bind(self):
        self.socket.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
        super().server_bind()


def make_server(bind, port):
    if bind:
        server_class = DualStackServer if ":" in bind else Server
        return server_class((bind, port), Handler)
    try:
        return DualStackServer(("::", port), Handler)
    except OSError:
        # IPv6 staat uit op deze server.
        return Server(("", port), Handler)


def watchdog(server):
    while True:
        time.sleep(15)
        if server.app.should_stop():
            server.shutdown()
            return


def main():
    parser = argparse.ArgumentParser(description="Etheron-webinstaller")
    parser.add_argument("--work-dir", required=True)
    parser.add_argument("--etheron-dir", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
    parser.add_argument("--port", type=int, default=8443)
    parser.add_argument("--bind", default="")
    parser.add_argument("--address", default="")
    parser.add_argument("--firewall-name", default="firewall")
    parser.add_argument("--no-tls", action="store_true", help="alleen voor ontwikkeling")
    args = parser.parse_args()

    app = Installer(args)
    server = make_server(args.bind, args.port)
    server.app = app

    if app.tls:
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        if hasattr(context, "minimum_version"):
            context.minimum_version = ssl.TLSVersion.TLSv1_2
        else:
            # Python 3.6 (EL8) kent minimum_version nog niet.
            context.options |= ssl.OP_NO_TLSv1 | ssl.OP_NO_TLSv1_1
        context.load_cert_chain(os.path.join(app.work_dir, "cert.pem"), os.path.join(app.work_dir, "key.pem"))
        # De handshake gebeurt in de thread van het verzoek, niet in de accept-lus.
        server.socket = context.wrap_socket(server.socket, server_side=True, do_handshake_on_connect=False)

    # systemctl stop: netjes afsluiten zodat het opruimen hieronder nog gebeurt.
    signal.signal(signal.SIGTERM, lambda *_: threading.Thread(target=server.shutdown, daemon=True).start())
    threading.Thread(target=watchdog, args=(server,), daemon=True).start()

    print("Webinstaller luistert op poort %d" % args.port, flush=True)
    try:
        server.serve_forever()
    finally:
        server.server_close()
        cleanup = os.path.join(app.etheron_dir, "webui", "webinstaller.sh")
        subprocess.call(["bash", cleanup, "cleanup", app.work_dir], env=app.env)


if __name__ == "__main__":
    main()
