'use strict';

// Etheron-webinstaller: de wizard in de browser. Praat met webui/server.py.
// Alle tekst van de server wordt als tekst getoond (textContent), nooit als HTML.

const STEP_LABELS = {
  keuze: 'Keuze',
  domein: 'Domein',
  panel: 'Panel',
  node: 'Wings',
  controle: 'Controle',
  installatie: 'Installatie',
};

const STEPS = {
  panel: ['keuze', 'domein', 'panel', 'controle', 'installatie'],
  wings: ['keuze', 'domein', 'node', 'controle', 'installatie'],
  beide: ['keuze', 'domein', 'panel', 'node', 'controle', 'installatie'],
};

const ACTION_LABELS = { panel: 'Panel', wings: 'Wings (node)', beide: 'Panel en Wings' };
const HTTPS_LABELS = { letsencrypt: "Let's Encrypt", eigen: 'Eigen certificaat', geen: 'Geen' };
const ACCESS_LABELS = { lokaal: 'Alleen deze server', panel: 'Alleen mijn panel', overal: 'Iedereen' };

// Bij welke stap en onder welk label een instelling hoort, voor foutmeldingen van de server.
const FIELDS = {
  FQDN: ['domein', 'Domeinnaam'],
  EMAIL: ['domein', 'E-mailadres'],
  FIREWALL: ['domein', 'Firewall'],
  LETSENCRYPT: ['domein', 'HTTPS'],
  ASSUME_SSL: ['domein', 'HTTPS'],
  VERIFY_DNS: ['domein', 'Domeincontrole'],
  PANEL_VERSION: ['panel', 'Panel-versie'],
  TIMEZONE: ['panel', 'Tijdzone'],
  TELEMETRY: ['panel', 'Gebruiksstatistieken'],
  DB_NAME: ['panel', 'Databasenaam'],
  DB_USER: ['panel', 'Databasegebruiker'],
  DB_PASSWORD: ['panel', 'Databasewachtwoord'],
  ADMIN_EMAIL: ['panel', 'E-mailadres beheerder'],
  ADMIN_USERNAME: ['panel', 'Gebruikersnaam'],
  ADMIN_FIRSTNAME: ['panel', 'Voornaam'],
  ADMIN_LASTNAME: ['panel', 'Achternaam'],
  ADMIN_PASSWORD: ['panel', 'Wachtwoord'],
  DBHOST: ['node', 'Databases voor gameservers'],
  DBHOST_USER: ['node', 'Gebruikersnaam databasehost'],
  DBHOST_PASSWORD: ['node', 'Wachtwoord databasehost'],
  DBHOST_ALLOW: ['node', 'IP-adres van je panel'],
  DBHOST_FIREWALL: ['node', 'Poort 3306'],
};

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
const HOST_RE = /^(?=.{1,253}$)([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)*[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$/;
const IPV4_RE = /^\d{1,3}(\.\d{1,3}){3}$/;
const USERNAME_RE = /^[a-zA-Z0-9][a-zA-Z0-9_.-]+[a-zA-Z0-9]$/;
const IDENTIFIER_RE = /^[a-zA-Z0-9_]{1,64}$/;
const DB_PASSWORD_BAD = /[\s'"\\$`#]/;
const DB_PASSWORD_MESSAGE = 'Geen spaties, aanhalingstekens, \\, $, # of ` (maximaal 128 tekens).';

// Velden van 'Node koppelen' (na de installatie).
const NODE_LABELS = {
  NODE_NAME: 'Naam van de node',
  NODE_LOCATION: 'Locatie',
  NODE_PORTS: 'Poorten',
  NODE_FQDN: 'Adres van de node',
  PANEL_URL: 'Adres van je panel',
  PANEL_API_KEY: 'API-sleutel',
};
const NODE_NAME_RE = /^[A-Za-z0-9_ .-]{1,100}$/;
const LOCATION_RE = /^[A-Za-z0-9_.-]{1,60}$/;
const PANEL_URL_RE = /^https?:\/\/[A-Za-z0-9.-]+(:\d{1,5})?\/?$/;
const API_KEY_RE = /^ptla_[A-Za-z0-9]{20,}$/;

const state = {
  info: null,
  action: null,
  index: 0,
  dns: { fqdn: null, ok: false },
  logNext: 0,
  logLines: [],
  progress: [],
  progressIndex: 0,
  flags: {},
  pollTimer: null,
  failures: 0,
  stopped: false,
};

// ---------------- Hulpjes ---------------- //

const $ = (selector) => document.querySelector(selector);
const $$ = (selector) => Array.from(document.querySelectorAll(selector));

function el(tag, attrs, ...children) {
  const node = document.createElement(tag);
  for (const [name, value] of Object.entries(attrs || {})) {
    if (name === 'class') node.className = value;
    else if (name === 'text') node.textContent = value;
    else node.setAttribute(name, value);
  }
  node.append(...children);
  return node;
}

const val = (id) => $('#' + id).value.trim();
const raw = (id) => $('#' + id).value;
const checked = (id) => $('#' + id).checked;
const radio = (name) => {
  const input = $(`input[name="${name}"]:checked`);
  return input ? input.value : null;
};
const hasPanel = () => state.action === 'panel' || state.action === 'beide';
const hasWings = () => state.action === 'wings' || state.action === 'beide';
const isIp = (value) => IPV4_RE.test(value) || value.includes(':');
const fqdnValue = () => val('fqdn').replace(/\.$/, '');
const steps = () => STEPS[state.action || 'beide'];
const addressChoice = () => radio('address');
// Eigen naam voor een nip.io-adres: kleine letters, cijfers en losse streepjes.
const NIP_LABEL_RE = /^(?=.{1,40}$)[a-z0-9]+(-[a-z0-9]+)*$/;
const nipLabel = () => val('nip-label').toLowerCase();

// nip.io-adres van deze server, met de eigen naam ervoor als die is ingevuld.
function nipName() {
  const base = (state.info && state.info.nipName) || '';
  const label = nipLabel();
  return base && label && NIP_LABEL_RE.test(label) ? `${label}-${base}` : base;
}

// Databases automatisch instellen kan alleen als het panel op deze server staat.
const panelHere = () => hasPanel() || Boolean(state.info && state.info.panelInstalled);
const dbhostMode = () => radio('dbhost-mode');

// Het adres van het panel of de node volgens de gekozen manier van bereikbaar zijn.
function currentFqdn() {
  const choice = addressChoice();
  if (choice === 'nipio') return nipName();
  if (choice === 'ip') return state.info ? state.info.address : '';
  return fqdnValue();
}

// nip.io: altijd Let's Encrypt. Alleen IP: geen HTTPS. Eigen domein: zelf kiezen
// voor het panel; voor Wings betekent een domein Let's Encrypt.
function httpsChoice() {
  const choice = addressChoice();
  if (choice === 'nipio') return 'letsencrypt';
  if (choice === 'ip') return 'geen';
  return hasPanel() ? radio('https') : 'letsencrypt';
}

class Forbidden extends Error {}

async function api(path, body) {
  const options = { credentials: 'same-origin', cache: 'no-store', headers: {} };
  if (body !== undefined) {
    options.method = 'POST';
    options.headers['Content-Type'] = 'application/json';
    options.body = JSON.stringify(body);
  }
  const response = await fetch(path, options);
  if (response.status === 403) {
    showMessage('Deze link werkt niet (meer)', 'De webinstaller is gestopt of de link is ongeldig. Start de webinstaller opnieuw op je server en open de nieuwe link.');
    throw new Forbidden();
  }
  let data = {};
  try {
    data = await response.json();
  } catch (e) {
    // Geen JSON: behandel als lege reactie.
  }
  data.httpStatus = response.status;
  return data;
}

function showMessage(title, text) {
  state.stopped = true;
  clearTimeout(state.pollTimer);
  $('#wizard').hidden = true;
  $('#stepper').hidden = true;
  $('#loading').hidden = true;
  $('#message-title').textContent = title;
  $('#message-text').textContent = text;
  $('#message').hidden = false;
}

// ---------------- Foutmeldingen ---------------- //

function clearErrors(scope) {
  scope.querySelectorAll('.field-error').forEach((node) => { node.textContent = ''; });
  scope.querySelectorAll('[aria-invalid]').forEach((node) => node.removeAttribute('aria-invalid'));
}

function setError(key, message) {
  const target = $(`[data-error-for="${key}"]`);
  if (target) target.textContent = message;
  const input = $(`[data-key="${key}"]`) || document.getElementById(key);
  if (input) {
    input.setAttribute('aria-invalid', 'true');
    const details = input.closest('details');
    if (details) details.open = true;
  }
  return false;
}

function focusFirstError(scope) {
  const input = scope.querySelector('[aria-invalid="true"]');
  if (input) input.focus();
}

function showServerErrors(errors) {
  const list = $('#check-errors');
  list.replaceChildren();
  for (const error of errors) {
    const field = error.key ? FIELDS[error.key] : null;
    const item = el('li');
    if (field) {
      setError(error.key, error.message);
      item.append(el('strong', { text: field[1] + ': ' }), error.message + ' ');
      const target = steps().indexOf(field[0]);
      if (target >= 0) {
        const button = el('button', { type: 'button', text: 'Aanpassen' });
        button.addEventListener('click', () => showStep(target));
        item.append(button);
      }
    } else {
      item.append(error.message);
    }
    list.append(item);
  }
  list.hidden = false;
}

// ---------------- Formulier ---------------- //

function updateForm() {
  const panel = hasPanel();
  const wings = hasWings();

  // nip.io kent alleen IPv4: zonder IPv4-adres is die keuze er niet.
  $('#address-nip').hidden = !nipName();
  if (!nipName() && addressChoice() === 'nipio') {
    $('input[name="address"][value="domein"]').checked = true;
  }
  const choice = addressChoice();
  const address = state.info ? state.info.address : 'deze server';
  $('#nip-field').hidden = choice !== 'nipio';
  $('#nip-name').textContent = nipName();
  $('#ip-name').textContent = address;
  $('#address-legend').textContent = panel ? 'Hoe moet je panel bereikbaar zijn?' : 'Hoe moet deze node bereikbaar zijn?';
  const addressHints = {
    domein: `Maak bij je domeinbeheer een A-record aan dat naar ${address} wijst.`,
    nipio: `Dit adres van nip.io wijst automatisch naar ${address}. Je krijgt er gratis een HTTPS-certificaat bij en hoeft zelf niets in te stellen.`,
    ip: panel
      ? `Je panel wordt bereikbaar via http://${address}. Wachtwoorden gaan dan onversleuteld over het internet; alleen geschikt om te testen.`
      : `Wings wordt bereikbaar via http://${address}:8080. Dat werkt alleen als je panel ook zonder HTTPS draait.`,
  };
  $('#address-hint').textContent = addressHints[choice];

  // De HTTPS-keuze is er alleen voor een eigen domein van het panel.
  $('#https-field').hidden = choice !== 'domein' || !panel;
  const https = httpsChoice();

  $('#fqdn-field').hidden = choice !== 'domein';
  $('#email-field').hidden = !panel && https !== 'letsencrypt';
  $('#le-terms-field').hidden = https !== 'letsencrypt';
  $('#dns-field').hidden = https === 'geen';

  $('#fqdn-hint').textContent = panel ? 'Bijvoorbeeld panel.jouwdomein.nl.' : 'Bijvoorbeeld node1.jouwdomein.nl.';
  $('#fqdn').placeholder = panel ? 'panel.jouwdomein.nl' : 'node1.jouwdomein.nl';
  if (https !== 'letsencrypt') {
    $('#email-hint').textContent = 'Het panel gebruikt dit adres als afzender van e-mails.';
  } else {
    $('#email-hint').textContent = panel
      ? 'Voor meldingen over je certificaat. Het panel gebruikt dit adres ook als afzender.'
      : 'Voor meldingen over je certificaat.';
  }

  const httpsHints = {
    letsencrypt: 'Je krijgt gratis een certificaat dat automatisch wordt verlengd. Je domein moet daarvoor al naar deze server wijzen.',
    eigen: 'Na de installatie zet je je certificaat in /etc/ssl/<domein>.pem en de sleutel in /etc/ssl/<domein>.key. Tot die tijd is het panel niet bereikbaar.',
    geen: panel
      ? 'Wachtwoorden gaan dan onversleuteld over het internet. Alleen geschikt om te testen.'
      : 'Werkt alleen als je panel ook zonder HTTPS draait.',
  };
  $('#https-hint').textContent = httpsHints[https];

  const ports = ['SSH'];
  if (panel || https === 'letsencrypt') ports.push('80', '443');
  if (wings) ports.push('8080', '2022');
  const firewall = state.info ? state.info.firewall : 'firewall';
  $('#firewall-hint').textContent = `Alleen de poorten die nodig zijn gaan open in ${firewall}: ${ports.join(', ')}.`;

  $('#panel-v2-warning').hidden = $('#panel-version').value !== '2';
  $('#admin-email').placeholder = val('email');

  const local = panelHere();
  $('#dbhost-mode-auto').hidden = !local;
  if (!local && dbhostMode() === 'auto') {
    $('input[name="dbhost-mode"][value="none"]').checked = true;
  }
  const mode = dbhostMode();
  const modeHints = {
    auto: 'We maken een databasegebruiker aan en zetten hem bij het koppelen van de node meteen in je panel. Je hoeft niets in te vullen.',
    manual: 'Je kiest zelf een gebruikersnaam en wachtwoord en voegt de databasehost daarna zelf toe in het panel (Admin → Databases).',
    none: '',
  };
  $('#dbhost-mode-hint').textContent = [modeHints[mode], local ? '' : 'Automatisch instellen kan alleen als het panel op deze server staat.']
    .filter(Boolean).join(' ');

  const access = radio('dbhost-access');
  $('#dbhost-fields').hidden = mode !== 'manual';
  $('#dbhost-allow-field').hidden = access !== 'panel';
  $('#dbhost-firewall-field').hidden = access === 'lokaal' || !checked('firewall');
}

function resetDns() {
  state.dns = { fqdn: null, ok: false };
  $('#dns-result').hidden = true;
  $('#dns-override-field').hidden = true;
  $('#dns-override').checked = false;
  $('#btn-dns').textContent = 'Domein controleren';
}

async function runDns() {
  const fqdn = currentFqdn();
  const button = $('#btn-dns');
  const result = $('#dns-result');
  $('[data-error-for="dns"]').textContent = '';
  if (!fqdn || isIp(fqdn)) {
    return setError('FQDN', 'Vul eerst een domeinnaam in (geen IP-adres).');
  }

  button.disabled = true;
  button.textContent = 'Bezig met controleren…';
  try {
    const data = await api('/api/dns', { fqdn });
    state.dns = { fqdn, ok: Boolean(data.ok) };
    const lines = (data.lines && data.lines.length) ? data.lines : [data.message || 'De controle gaf geen resultaat.'];
    result.replaceChildren(...lines.map((line) => el('p', { text: line.replace(/^(GELUKT|FOUT|LET OP): /, '') })));
    result.className = 'dns-result ' + (data.ok ? 'ok' : 'err');
    result.hidden = false;
    $('#dns-override-field').hidden = Boolean(data.ok);
  } catch (error) {
    if (error instanceof Forbidden) return false;
    state.dns = { fqdn, ok: false };
    result.replaceChildren(el('p', { text: 'De controle is niet gelukt. Probeer het opnieuw.' }));
    result.className = 'dns-result err';
    result.hidden = false;
  } finally {
    button.disabled = false;
    button.textContent = 'Opnieuw controleren';
  }
  return state.dns.ok;
}

// ---------------- Controle per stap ---------------- //

async function validateDomain() {
  const panel = hasPanel();
  const https = httpsChoice();
  const fqdn = currentFqdn();
  let ok = true;

  if (!$('#fqdn-field').hidden) {
    if (!fqdn) ok = setError('FQDN', 'Vul een domeinnaam in.');
    else if (!HOST_RE.test(fqdn) && !isIp(fqdn)) ok = setError('FQDN', 'Dit is geen geldige domeinnaam.');
    else if (https !== 'geen' && isIp(fqdn)) {
      ok = setError('FQDN', "Voor HTTPS heb je een domeinnaam nodig. Geen domein? Kies hierboven het gratis nip.io-adres of 'Alleen het IP-adres'.");
    }
  }
  if (addressChoice() === 'nipio' && nipLabel() && !NIP_LABEL_RE.test(nipLabel())) {
    ok = setError('nip-label', 'Alleen kleine letters, cijfers en losse streepjes (maximaal 40 tekens).');
  }
  if (!$('#email-field').hidden && !EMAIL_RE.test(val('email'))) {
    ok = setError('EMAIL', 'Vul een geldig e-mailadres in.');
  }
  if (https === 'letsencrypt' && !checked('le-terms')) {
    ok = setError('le-terms', "Ga akkoord met de voorwaarden om Let's Encrypt te gebruiken.");
  }
  if (!ok) return false;

  if (https !== 'geen') {
    if (state.dns.fqdn !== fqdn) await runDns();
    if (!state.dns.ok && !checked('dns-override')) {
      const what = panel ? 'Je domein' : 'Het domein van deze node';
      return setError('dns', `${what} wijst (nog) niet naar deze server. Pas het A-record aan en controleer opnieuw, of vink aan dat je toch wilt doorgaan.`);
    }
  }
  return true;
}

function validatePanel() {
  let ok = true;
  if (!val('admin-firstname')) ok = setError('ADMIN_FIRSTNAME', 'Vul je voornaam in.');
  if (!val('admin-lastname')) ok = setError('ADMIN_LASTNAME', 'Vul je achternaam in.');
  if (!USERNAME_RE.test(val('admin-username'))) {
    ok = setError('ADMIN_USERNAME', 'Minimaal 3 tekens: letters, cijfers, punt, streepje of underscore. Begin en eindig met een letter of cijfer.');
  }
  if (val('admin-email') && !EMAIL_RE.test(val('admin-email'))) {
    ok = setError('ADMIN_EMAIL', 'Vul een geldig e-mailadres in, of laat het veld leeg.');
  }
  if (raw('admin-password').length < 8) {
    ok = setError('ADMIN_PASSWORD', 'Kies een wachtwoord van minimaal 8 tekens.');
  } else if (raw('admin-password') !== raw('admin-password2')) {
    ok = setError('admin-password2', 'De wachtwoorden komen niet overeen.');
  }
  if (!IDENTIFIER_RE.test(val('db-name'))) ok = setError('DB_NAME', 'Alleen letters, cijfers en _ (maximaal 64 tekens).');
  if (!IDENTIFIER_RE.test(val('db-user'))) ok = setError('DB_USER', 'Alleen letters, cijfers en _ (maximaal 64 tekens).');
  if (raw('db-password') && (DB_PASSWORD_BAD.test(raw('db-password')) || raw('db-password').length > 128)) {
    ok = setError('DB_PASSWORD', DB_PASSWORD_MESSAGE);
  }
  return ok;
}

function validateNode() {
  if (dbhostMode() !== 'manual') return true;
  let ok = true;
  if (!/^[a-zA-Z0-9_]{1,32}$/.test(val('dbhost-user'))) ok = setError('DBHOST_USER', 'Alleen letters, cijfers en _ (maximaal 32 tekens).');
  const password = raw('dbhost-password');
  if (!password) ok = setError('DBHOST_PASSWORD', 'Kies een wachtwoord.');
  else if (DB_PASSWORD_BAD.test(password) || password.length > 128) ok = setError('DBHOST_PASSWORD', DB_PASSWORD_MESSAGE);
  else if (password !== raw('dbhost-password2')) ok = setError('dbhost-password2', 'De wachtwoorden komen niet overeen.');
  if (radio('dbhost-access') === 'panel') {
    const allow = val('dbhost-allow');
    if (!isIp(allow) && !HOST_RE.test(allow)) ok = setError('DBHOST_ALLOW', 'Vul het IP-adres van je panel in.');
  }
  return ok;
}

async function validateStep(name) {
  const section = $(`section[data-step="${name}"]`);
  clearErrors(section);
  let ok = true;
  if (name === 'keuze' && !state.action) ok = setError('action', 'Kies wat je wilt installeren.');
  if (name === 'domein') ok = await validateDomain();
  if (name === 'panel') ok = validatePanel();
  if (name === 'node') ok = validateNode();
  if (!ok) focusFirstError(section);
  return ok;
}

// ---------------- Instellingen ---------------- //

function collectSettings() {
  const https = httpsChoice();
  const fqdn = currentFqdn();
  const settings = {
    FIREWALL: checked('firewall'),
    LETSENCRYPT: https === 'letsencrypt',
    // Alleen uitzetten als de klant bewust doorgaat na een mislukte controle.
    VERIFY_DNS: !(state.dns.fqdn === fqdn && !state.dns.ok && checked('dns-override')),
  };
  // Het panel heeft altijd een adres nodig; Wings alleen voor HTTPS.
  if (hasPanel() || https === 'letsencrypt') settings.FQDN = fqdn;
  if (!$('#email-field').hidden) settings.EMAIL = val('email');

  if (hasPanel()) {
    Object.assign(settings, {
      ASSUME_SSL: https === 'eigen',
      PANEL_VERSION: $('#panel-version').value,
      TIMEZONE: $('#timezone').value,
      TELEMETRY: checked('telemetry'),
      DB_NAME: val('db-name'),
      DB_USER: val('db-user'),
      DB_PASSWORD: raw('db-password'),
      ADMIN_EMAIL: val('admin-email') || val('email'),
      ADMIN_USERNAME: val('admin-username'),
      ADMIN_FIRSTNAME: val('admin-firstname'),
      ADMIN_LASTNAME: val('admin-lastname'),
      ADMIN_PASSWORD: raw('admin-password'),
    });
  }

  if (hasWings()) {
    // 'Automatisch' gebeurt bij het koppelen van de node (installers/node.sh).
    settings.DBHOST = dbhostMode() === 'manual';
    if (settings.DBHOST) {
      const access = radio('dbhost-access');
      settings.DBHOST_USER = val('dbhost-user');
      settings.DBHOST_PASSWORD = raw('dbhost-password');
      settings.DBHOST_ALLOW = { lokaal: '127.0.0.1', overal: '%', panel: val('dbhost-allow') }[access];
      settings.DBHOST_FIREWALL = access !== 'lokaal' && settings.FIREWALL && checked('dbhost-firewall');
    }
  }
  return settings;
}

function renderSummary() {
  const settings = collectSettings();
  const list = $('#summary');
  const group = (title) => list.append(el('dt', { class: 'group', text: title }));
  const row = (label, value) => list.append(el('dt', { text: label }), el('dd', { text: value }));

  list.replaceChildren();
  group('Algemeen');
  row('Installatie', ACTION_LABELS[state.action]);
  if (settings.FQDN) row('Adres', addressChoice() === 'nipio' ? `${settings.FQDN} (gratis nip.io-adres)` : settings.FQDN);
  row('HTTPS', HTTPS_LABELS[httpsChoice()]);
  if (settings.EMAIL) row('E-mailadres', settings.EMAIL);
  row('Firewall instellen', settings.FIREWALL ? 'Ja' : 'Nee');

  if (hasPanel()) {
    group('Panel');
    row('Beheerder', `${settings.ADMIN_FIRSTNAME} ${settings.ADMIN_LASTNAME} (${settings.ADMIN_USERNAME})`);
    row('E-mailadres beheerder', settings.ADMIN_EMAIL);
    row('Tijdzone', settings.TIMEZONE);
    row('Versie', settings.PANEL_VERSION === '2' ? '2 (experimenteel)' : '1 (stabiel)');
    row('Gebruiksstatistieken', settings.TELEMETRY ? 'Delen' : 'Niet delen');
  }
  if (hasWings()) {
    group('Wings');
    row('Databases voor gameservers', { auto: 'Automatisch instellen', manual: 'Zelf instellen', none: 'Niet nodig' }[dbhostMode()]);
    if (settings.DBHOST) {
      const access = radio('dbhost-access');
      row('Toegang tot databases', access === 'panel' ? `${ACCESS_LABELS.panel} (${settings.DBHOST_ALLOW})` : ACCESS_LABELS[access]);
    }
  }
}

async function runCheck() {
  const status = $('#check-status');
  const next = $('#btn-next');
  $('#check-errors').hidden = true;
  status.className = 'notice';
  status.textContent = 'Instellingen controleren…';
  status.hidden = false;
  next.disabled = true;

  try {
    const data = await api('/api/check', { action: state.action, settings: collectSettings() });
    if (data.ok) {
      status.className = 'notice ok';
      status.textContent = 'Alles is in orde. Je kunt de installatie starten.';
    } else {
      status.hidden = true;
      showServerErrors(data.errors || [{ key: null, message: data.message || 'De controle is mislukt.' }]);
      return;
    }
  } catch (error) {
    if (error instanceof Forbidden) return;
    status.className = 'notice err';
    status.textContent = 'De controle is niet gelukt. Je kunt het opnieuw proberen met de knop hieronder.';
  }
  next.disabled = false;
}

// ---------------- Navigatie ---------------- //

function renderStepper() {
  const list = $('#stepper');
  list.replaceChildren();
  steps().forEach((name, i) => {
    const item = el('li', {},
      el('span', { class: 'num', text: i < state.index ? '✓' : String(i + 1) }),
      el('span', { class: 'label', text: STEP_LABELS[name] }));
    if (i < state.index) item.classList.add('done');
    if (i === state.index) {
      item.classList.add('current');
      item.setAttribute('aria-current', 'step');
    }
    list.append(item);
  });
}

function showStep(index) {
  state.index = index;
  const name = steps()[index];
  $$('section[data-step]').forEach((section) => { section.hidden = section.dataset.step !== name; });
  renderStepper();
  updateForm();

  const back = $('#btn-back');
  const next = $('#btn-next');
  back.style.visibility = index === 0 ? 'hidden' : 'visible';
  $('#nav').hidden = name === 'installatie';
  next.disabled = false;
  next.textContent = name === 'controle' ? 'Installatie starten' : 'Volgende';

  if (name === 'controle') {
    renderSummary();
    runCheck();
  }

  const heading = $(`section[data-step="${name}"] h1, section[data-step="${name}"] h2`);
  if (heading) {
    heading.setAttribute('tabindex', '-1');
    heading.focus({ preventScroll: true });
  }
  window.scrollTo(0, 0);
}

async function onNext() {
  const name = steps()[state.index];
  if (name === 'controle') return startInstall();

  const next = $('#btn-next');
  next.disabled = true;
  try {
    if (await validateStep(name)) showStep(state.index + 1);
  } finally {
    next.disabled = false;
  }
}

// ---------------- Installatie ---------------- //

function progressSteps(action, flags) {
  const list = [{ label: 'Voorbereiden' }];
  if (action !== 'wings') {
    list.push(
      { label: 'Pakketten installeren', re: /^\* Afhankelijkheden installeren/ },
      { label: 'Composer installeren', re: /^\* Composer installeren/ },
      { label: 'Panel downloaden', re: /^\* Panel .* downloaden/ },
      { label: 'Onderdelen van het panel installeren', re: /^\* Composer-afhankelijkheden installeren/ },
      { label: 'Database en beheerder aanmaken', re: /^\* Databasegebruiker .* aanmaken/ },
      { label: 'Panel instellen', re: /^\* Omgeving van het panel instellen/ },
      { label: 'Webserver instellen', re: /^\* Nginx instellen/ },
    );
    if (flags.LETSENCRYPT) list.push({ label: 'HTTPS-certificaat aanvragen', re: /^\* Let's Encrypt-certificaat aanvragen/ });
  }
  if (action !== 'panel') {
    list.push(
      { label: 'Docker installeren', re: /^\* Afhankelijkheden installeren/ },
      { label: 'Wings downloaden', re: /^\* Wings .* downloaden/ },
      { label: 'Wings-service instellen', re: /^\* Systemd-service installeren/ },
    );
    if (flags.DBHOST) list.push({ label: 'Databasehost instellen', re: /^\* Databasehost-gebruiker instellen/ });
    if (flags.LETSENCRYPT) list.push({ label: 'HTTPS-certificaat instellen', re: /^\* Let's Encrypt-certificaat instellen/ });
  }
  return list;
}

function renderProgress(finalState) {
  const list = $('#progress');
  list.replaceChildren();
  state.progress.forEach((step, i) => {
    let status = '';
    let icon = '';
    if (finalState === 'done' || i < state.progressIndex) {
      status = 'done';
      icon = '✓';
    } else if (i === state.progressIndex) {
      status = finalState === 'failed' ? 'failed' : 'active';
      icon = finalState === 'failed' ? '!' : '';
    }
    const item = el('li', {}, el('span', { class: 'icon', 'aria-hidden': 'true', text: icon }), el('span', { text: step.label }));
    if (status) item.classList.add(status);
    if (status === 'active') item.setAttribute('aria-current', 'step');
    list.append(item);
  });
}

// Schuift de voortgang door als een logregel bij een volgende stap hoort.
function advanceProgress(line) {
  for (let i = state.progressIndex + 1; i < state.progress.length; i++) {
    if (state.progress[i].re && state.progress[i].re.test(line)) {
      state.progressIndex = i;
      return true;
    }
  }
  return false;
}

function appendLog(lines) {
  if (!lines.length) return;
  const log = $('#log');
  const atBottom = log.scrollHeight - log.scrollTop - log.clientHeight < 40;
  state.logLines.push(...lines);
  log.append(document.createTextNode(lines.join('\n') + '\n'));
  if (atBottom) log.scrollTop = log.scrollHeight;
}

function enterInstall(action, flags) {
  state.action = action;
  state.flags = flags || {};
  state.progress = progressSteps(action, state.flags);
  state.progressIndex = 0;
  state.logNext = 0;
  state.logLines = [];
  $('#log').textContent = '';
  showStep(steps().length - 1);
  renderProgress('running');
  poll();
}

async function startInstall() {
  const next = $('#btn-next');
  const status = $('#check-status');
  next.disabled = true;
  next.textContent = 'Bezig met starten…';
  $('#check-errors').hidden = true;

  try {
    const settings = collectSettings();
    // Extra keuzes die de server alleen onthoudt (bijv. na herladen), geen installatie-instellingen.
    const flags = { DBHOST_AUTO: hasWings() && dbhostMode() === 'auto' };
    const data = await api('/api/install', { action: state.action, settings, flags });
    if (data.ok) {
      enterInstall(state.action, {
        LETSENCRYPT: settings.LETSENCRYPT,
        ASSUME_SSL: settings.ASSUME_SSL,
        DBHOST: settings.DBHOST,
        DBHOST_AUTO: flags.DBHOST_AUTO,
      });
      return;
    }
    if (data.httpStatus === 409) {
      status.className = 'notice warn';
      status.textContent = data.message || 'Er loopt al een installatie.';
      status.hidden = false;
    } else {
      status.hidden = true;
      showServerErrors(data.errors || [{ key: null, message: data.message || 'Starten is mislukt.' }]);
    }
  } catch (error) {
    if (error instanceof Forbidden) return;
    status.className = 'notice err';
    status.textContent = 'Starten is niet gelukt. Controleer je verbinding en probeer het opnieuw.';
    status.hidden = false;
  }
  next.disabled = false;
  next.textContent = 'Installatie starten';
}

async function poll() {
  clearTimeout(state.pollTimer);
  if (state.stopped) return;

  let data;
  try {
    data = await api('/api/status?since=' + state.logNext);
  } catch (error) {
    if (error instanceof Forbidden) return;
    state.failures += 1;
    $('#install-lead').textContent = 'De verbinding met je server is even weg. We proberen het opnieuw…';
    state.pollTimer = setTimeout(poll, Math.min(10000, 2000 * state.failures));
    return;
  }
  state.failures = 0;

  const lines = data.lines || [];
  appendLog(lines);
  lines.forEach(advanceProgress);
  state.logNext = data.next || state.logNext;

  if (data.state === 'done' || data.state === 'failed') {
    finish(data);
    return;
  }
  $('#install-lead').textContent = 'Je kunt deze pagina sluiten en later opnieuw openen met dezelfde link; de installatie gaat gewoon door.';
  renderProgress('running');
  state.pollTimer = setTimeout(poll, lines.length >= 2000 ? 0 : 1500);
}

function findLine(re) {
  for (let i = state.logLines.length - 1; i >= 0; i--) {
    const match = state.logLines[i].match(re);
    if (match) return match;
  }
  return null;
}

function finish(data) {
  const ok = data.state === 'done';
  const panel = state.action !== 'wings';
  const wings = state.action !== 'panel';
  renderProgress(data.state);

  $('#install-title').textContent = ok ? 'Installatie voltooid' : 'Installatie mislukt';
  $('#install-lead').textContent = ok
    ? 'Alles staat klaar. Hieronder lees je wat je nu kunt doen.'
    : 'Er ging iets mis. Hieronder zie je waar de installatie is gestopt.';

  const result = $('#result');
  result.replaceChildren();
  if (ok) {
    result.className = 'result ok';
    if (panel) {
      const address = findLine(/^\* Adres:\s+(\S+)/);
      const admin = findLine(/^\* Beheerder:\s+(\S+)/);
      result.append(el('h3', { text: 'Je panel is klaar' }));
      if (address) {
        result.append(el('p', { text: 'Open je panel:' }),
          el('p', {}, el('a', { class: 'big-link', href: address[1], target: '_blank', rel: 'noopener noreferrer', text: address[1] })));
      }
      if (admin) result.append(el('p', { text: `Log in met gebruikersnaam ${admin[1]} en het wachtwoord dat je hebt gekozen.` }));
      if (findLine(/Let's Encrypt-certificaat is mislukt/)) {
        result.append(el('p', { class: 'notice warn', text: "Het HTTPS-certificaat kon niet worden aangevraagd. Je panel werkt voorlopig via HTTP. Controleer je domein en vraag het certificaat later opnieuw aan." }));
      }
      if (state.flags.ASSUME_SSL) {
        result.append(el('p', { class: 'notice warn', text: 'Je hebt gekozen voor een eigen certificaat. Zet het in /etc/ssl/ op je server; daarna is het panel bereikbaar.' }));
      }
    }
    if (wings) {
      result.append(el('h3', { text: panel ? 'Wings is ook geïnstalleerd' : 'Wings is geïnstalleerd' }),
        el('p', { id: 'wings-next', text: 'Koppel deze node nog aan je panel met de knop hierboven.' }));
      const fqdn = findLine(/^\*\s+\/etc\/letsencrypt\/live\/([^/]+)\//);
      const host = fqdn ? fqdn[1] : (state.info ? state.info.address : 'het IP-adres van deze server');
      $('#wings-config-fqdn').textContent = '';
      $('#wings-config-fqdn').append('Vul bij ', el('strong', { text: 'FQDN' }), ` ${host} in en kies bij SSL voor ` +
        (fqdn ? '"Use SSL Connection".' : '"Use HTTP Connection".'));
      setupNodeForm(host, Boolean(fqdn));
      $('#wings-config').hidden = false;
    }
  } else {
    result.className = 'result err';
    const reason = findLine(/^\* FOUT: (.+)$/);
    result.append(el('h3', { text: 'De installatie is gestopt' }));
    if (reason) result.append(el('p', { text: reason[1] }));
    result.append(el('p', { text: 'Bekijk de technische details hieronder. Kom je er niet uit? Neem contact op met Etheron en stuur de technische details mee. Het volledige logbestand staat op je server in /var/log/etheron-installer.log.' }));
    $('#log-details').open = true;
  }
  result.hidden = false;

  if (typeof data.closesIn === 'number') {
    $('#close-hint').textContent = `De webinstaller sluit automatisch over ${Math.max(1, Math.round(data.closesIn / 60))} minuten. Ben je klaar? Sluit hem dan nu af.`;
  }
  $('#close-row').hidden = false;
}

// ---------------- Node koppelen ---------------- //

function setupNodeForm(host, https) {
  state.nodeFqdn = host;
  // Staat het panel niet op deze server, dan is er een API-sleutel van het panel nodig.
  const remote = state.action === 'wings' && !(state.info && state.info.panelInstalled);
  $('#node-remote').hidden = !remote;
  const name = $('#node-name');
  if (!name.value) {
    const hostname = (state.info && state.info.hostname) || '';
    name.value = hostname.replace(/[^A-Za-z0-9_ .-]/g, '').slice(0, 100) || 'node1';
  }
  $('#node-address').textContent = `Wings wordt bereikbaar op ${https ? 'https' : 'http'}://${host}:8080.`;
  $('#node-dbhost-note').hidden = !state.flags.DBHOST_AUTO;
  $('#manual-dbhost-note').hidden = !state.flags.DBHOST_AUTO;
}

function validPortRange(value) {
  const match = value.match(/^(\d{4,5})(?:-(\d{4,5}))?$/);
  if (!match) return false;
  const start = Number(match[1]);
  const end = Number(match[2] || match[1]);
  return start >= 1025 && end <= 65535 && start <= end && end - start < 1000;
}

function validateNodeForm() {
  const form = $('#node-form');
  clearErrors(form);
  let ok = true;
  if (!NODE_NAME_RE.test(val('node-name'))) ok = setError('NODE_NAME', 'Letters, cijfers, spaties, -, _ en . (maximaal 100 tekens).');
  if (!LOCATION_RE.test(val('node-location'))) ok = setError('NODE_LOCATION', 'Een korte naam zoals nl: letters, cijfers, -, _ en .');
  if (!validPortRange(val('node-ports'))) {
    ok = setError('NODE_PORTS', 'Eén poort of een reeks zoals 25565-25600, tussen 1025 en 65535, maximaal 1000 poorten.');
  }
  if (!$('#node-remote').hidden) {
    if (!PANEL_URL_RE.test(val('panel-url'))) ok = setError('PANEL_URL', 'Vul het adres van je panel in, bijvoorbeeld https://panel.jouwdomein.nl.');
    if (!API_KEY_RE.test(val('panel-api-key'))) ok = setError('PANEL_API_KEY', 'Plak de volledige sleutel; die begint met ptla_.');
  }
  if (!ok) focusFirstError(form);
  return ok;
}

async function linkNode() {
  if (!validateNodeForm()) return;
  const button = $('#btn-node');
  const notice = $('#node-result');
  const list = $('#node-errors');
  const log = $('#node-log');
  const settings = {
    NODE_NAME: val('node-name'),
    NODE_LOCATION: val('node-location'),
    NODE_PORTS: val('node-ports'),
    NODE_FQDN: state.nodeFqdn,
  };
  if (!$('#node-remote').hidden) {
    settings.PANEL_URL = val('panel-url');
    settings.PANEL_API_KEY = val('panel-api-key');
  }
  if (state.flags.DBHOST_AUTO) settings.NODE_DBHOST = true;

  button.disabled = true;
  button.textContent = 'Bezig met koppelen… (ongeveer een halve minuut)';
  notice.hidden = true;
  list.hidden = true;
  log.hidden = true;
  try {
    const data = await api('/api/node', { settings });
    if (data.lines && data.lines.length) appendLog(['', '--- Node koppelen ---', ...data.lines]);
    if (data.ok) {
      notice.className = 'notice ok';
      notice.textContent = 'Je node is gekoppeld en Wings draait. In het panel staat hij onder Admin → Nodes; het hartje wordt binnen een minuut groen.';
      notice.hidden = false;
      $('#node-form').hidden = true;
      $('#manual-config').hidden = true;
      if ($('#wings-next')) $('#wings-next').textContent = 'Deze node is gekoppeld aan je panel.';
      return;
    }
    if (data.httpStatus === 409) {
      notice.className = 'notice warn';
      notice.textContent = data.message || 'Dit kan nu niet.';
      notice.hidden = false;
      return;
    }
    list.replaceChildren();
    for (const error of data.errors || []) {
      const label = error.key ? NODE_LABELS[error.key] : null;
      if (label) setError(error.key, error.message);
      list.append(el('li', {}, label ? el('strong', { text: label + ': ' }) : '', error.message));
    }
    list.hidden = false;
    if (data.lines && data.lines.length) {
      log.textContent = data.lines.slice(-25).join('\n');
      log.hidden = false;
    }
  } catch (error) {
    if (error instanceof Forbidden) return;
    notice.className = 'notice err';
    notice.textContent = 'Koppelen is niet gelukt door een verbindingsfout. Probeer het opnieuw.';
    notice.hidden = false;
  } finally {
    button.disabled = false;
    button.textContent = 'Node aanmaken en Wings starten';
  }
}

async function saveWingsConfig() {
  const button = $('#btn-wings-config');
  const notice = $('#wings-config-result');
  const log = $('#wings-config-log');
  button.disabled = true;
  button.textContent = 'Bezig met starten…';
  log.hidden = true;
  try {
    const data = await api('/api/wings-config', { config: $('#wings-config-text').value });
    notice.className = 'notice ' + (data.ok ? 'ok' : 'err');
    notice.textContent = data.message || (data.ok ? 'Wings draait.' : 'Er ging iets mis.');
    if (data.ok) $('#node-form').hidden = true;
    if (data.log) {
      log.textContent = data.log;
      log.hidden = false;
    }
  } catch (error) {
    if (error instanceof Forbidden) return;
    notice.className = 'notice err';
    notice.textContent = 'Opslaan is niet gelukt. Probeer het opnieuw.';
  } finally {
    notice.hidden = false;
    button.disabled = false;
    button.textContent = 'Wings starten';
  }
}

async function closeInstaller() {
  try {
    const data = await api('/api/close', {});
    if (data.ok) {
      showMessage('De webinstaller is afgesloten', 'Je kunt dit tabblad sluiten. De tijdelijke poort op je server gaat binnen een minuut dicht.');
    }
  } catch (error) {
    // Bij Forbidden toont api() al een melding.
  }
}

// ---------------- Start ---------------- //

function applyInstalled(info) {
  const notes = [];
  const disable = (value) => { $(`input[name="action"][value="${value}"]`).disabled = true; };
  if (info.panelInstalled) {
    disable('panel');
    disable('beide');
    notes.push('Er staat al een panel op deze server.');
  }
  if (info.wingsInstalled) {
    disable('wings');
    disable('beide');
    notes.push('Wings staat al op deze server.');
  }
  if (notes.length) {
    const notice = $('#installed-notice');
    notice.textContent = notes.join(' ') + ' Opnieuw installeren kan pas nadat het bestaande onderdeel is verwijderd.';
    notice.className = 'notice warn';
    notice.hidden = false;
  }
}

function bindEvents() {
  $$('input[name="action"]').forEach((input) => input.addEventListener('change', () => {
    state.action = input.value;
    $('[data-error-for="action"]').textContent = '';
    // Databases: automatisch als dat kan (panel op deze server), anders niet nodig.
    $(`input[name="dbhost-mode"][value="${panelHere() ? 'auto' : 'none'}"]`).checked = true;
    renderStepper();
    updateForm();
  }));
  $$('input[name="https"], input[name="dbhost-access"], input[name="dbhost-mode"]').forEach((input) => input.addEventListener('change', updateForm));
  $('#nip-label').addEventListener('input', () => {
    resetDns();
    updateForm();
  });
  $$('input[name="address"]').forEach((input) => input.addEventListener('change', () => {
    resetDns();
    updateForm();
  }));
  ['firewall', 'panel-version', 'email'].forEach((id) => $('#' + id).addEventListener('input', updateForm));
  ['firewall', 'panel-version'].forEach((id) => $('#' + id).addEventListener('change', updateForm));
  $('#fqdn').addEventListener('input', resetDns);
  $('#btn-dns').addEventListener('click', runDns);
  $('#btn-next').addEventListener('click', onNext);
  $('#btn-back').addEventListener('click', () => showStep(Math.max(0, state.index - 1)));
  $('#btn-wings-config').addEventListener('click', saveWingsConfig);
  $('#btn-node').addEventListener('click', linkNode);
  $('#btn-close').addEventListener('click', closeInstaller);

  // Enter in een invoerveld = Volgende.
  $('#wizard').addEventListener('keydown', (event) => {
    if (event.key !== 'Enter' || event.target.tagName !== 'INPUT' || event.target.type === 'checkbox' || event.target.type === 'radio') return;
    event.preventDefault();
    if (!$('#nav').hidden && !$('#btn-next').disabled) onNext();
  });
}

async function init() {
  bindEvents();

  let info;
  try {
    info = await api('/api/info');
  } catch (error) {
    if (!(error instanceof Forbidden)) {
      showMessage('Je server is niet bereikbaar', 'Controleer of de webinstaller nog draait en of je internetverbinding werkt, en laad de pagina opnieuw.');
    }
    return;
  }
  state.info = info;

  $('#server-info').textContent = `${info.os} · ${info.address}`;
  $('#version').textContent = info.version || '';
  const timezone = $('#timezone');
  timezone.replaceChildren(...info.timezones.map((zone) => el('option', { value: zone, text: zone.replace(/_/g, ' ') })));
  timezone.value = info.defaultTimezone;
  applyInstalled(info);

  $('#loading').hidden = true;
  $('#wizard').hidden = false;

  // Loopt er al een installatie (pagina opnieuw geopend)? Ga dan meteen naar de voortgang.
  if (info.job && info.job.state !== 'idle' && info.job.action) {
    enterInstall(info.job.action, info.job.flags);
    return;
  }
  showStep(0);
}

init();
