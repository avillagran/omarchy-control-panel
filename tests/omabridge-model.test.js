const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const cp = require('node:child_process');
const vm = require('node:vm');

const repo = path.join(__dirname, '..');
const model = {};
vm.createContext(model);
vm.runInContext(fs.readFileSync(path.join(repo, 'desktop/OmaBridgeModel.js'), 'utf8').replace(/^\.pragma library\s*/, ''), model);
const plain = value => JSON.parse(JSON.stringify(value));

// Responses and page state.
const snapshot = {
  revision: 'r', available: true, version: '1', identity: true, stateDir: '/x', default: 'auto', routes: {}, active: {},
  device: { id: 'dev-1', name: 'laptop' },
  peers: [{ id: 'p1', name: 'desk', services: ['ssh'], remoteServices: ['t3'] }],
  pending: [{ id: 'p2', name: 'tablet', services: ['t3'], expires: 100 }],
  awaiting: [{ id: 'p3', name: 'server', expires: 200 }],
  published: { enabled: true, active: true, stale: false, sshAvailable: true, services: ['t3', 'ssh'] },
  error: ''
};
const ready = model.parseResponse(JSON.stringify(snapshot), 0);
assert.equal(ready.ok, true);
assert.equal(model.stateFor(ready), 'ready');
assert.equal(ready.snapshot.device.name, 'laptop');
assert.equal(ready.snapshot.published.active, true);
assert.equal(ready.created, null);
assert.equal(model.stateFor(model.parseResponse(JSON.stringify({ ...snapshot, available: false }), 0)), 'unavailable');
assert.equal(model.stateFor(model.parseResponse('{"error":"omabridge_outdated"}', 1)), 'outdated', 'no omabridge knows manage');
assert.equal(model.stateFor(model.parseResponse('{"error":"omabridge_missing"}', 1)), 'missing');
assert.equal(model.stateFor(model.parseResponse('{"error":"omabridge_command_failed"}', 1)), 'failed');
assert.equal(model.stateFor(null), 'loading');
assert.equal(model.parseResponse('', 124).error, 'timeout');
assert.equal(model.parseResponse('not json', 0).error, 'invalid_response');
assert.equal(model.parseResponse('[]', 0).error, 'invalid_response');
assert.equal(model.normalize({}).published.enabled, false, 'publishing is off unless OmaBridge says otherwise');

// The created invitation is kept apart from the snapshot; only SVG data URIs are shown.
const invited = model.parseResponse(JSON.stringify({ ...snapshot, created: { path: '/tmp/omabridge-invite-1.json', expires: 5, services: ['t3'], qrImage: 'data:image/svg+xml;base64,AAA' } }), 0);
assert.equal(invited.created.path, '/tmp/omabridge-invite-1.json');
assert.equal(invited.created.qrImage, 'data:image/svg+xml;base64,AAA');
assert.equal(JSON.stringify(invited.snapshot).includes('omabridge-invite'), false, 'the secret never enters the snapshot');
assert.equal(model.parseResponse(JSON.stringify({ ...snapshot, created: { path: '/p', qrImage: 'file:///etc/passwd' } }), 0).created.qrImage, '');
const paired = model.parseResponse(JSON.stringify({ ...snapshot, paired: { status: 'pending', name: 'desk', id: 'p9' } }), 0);
assert.deepEqual(plain(paired.paired), { status: 'pending', name: 'desk', id: 'p9', admin: false });

// Requests: confirmation is added in exactly one place, for known actions only.
assert.deepEqual(plain(model.readRequest()), { action: 'read' });
assert.deepEqual(plain(model.confirmedRequest('revoke', { peer: 'p1', confirmed: false, action: 'publish' })), { action: 'revoke', peer: 'p1', confirmed: true });
assert.equal(model.confirmedRequest('read', {}), null);
assert.equal(model.confirmedRequest('set', {}), null, 'route changes are not offered here');
assert.deepEqual(plain(model.inviteValues(snapshot.published, true, true, true)), { services: ['t3', 'ssh'], qr: true });
assert.deepEqual(plain(model.inviteValues({ services: ['t3'] }, true, true, false)), { services: ['t3'], qr: false }, 'only published services');
assert.deepEqual(plain(model.inviteValues({ services: [] }, true, true, false).services), []);

// Display helpers.
assert.equal(model.servicesText(['t3', 'ssh']), 'T3, SSH');
assert.equal(model.servicesText({ length: 1, 0: 't3' }), 'T3', 'QML sequences are lists too');
assert.equal(model.shortId('0123456789abcdef'), '01234567');
assert.equal(model.publishStatusKey({ enabled: false }), 'omabridgePublishOff');
assert.equal(model.publishStatusKey({ enabled: true, stale: true, active: true }), 'omabridgePublishStale');
assert.equal(model.publishStatusKey({ enabled: true, active: false }), 'omabridgePublishInactive');
assert.equal(model.publishStatusKey({ enabled: true, active: true }), 'omabridgePublishOn');
assert.equal(model.publishStatusKey({ enabled: false, active: true, external: true }), 'omabridgePublishExternal');

// Relay: public by default, an own relay keeps its URL, unknown modes fall back to public.
assert.deepEqual(plain(model.normalize({}).relay), { mode: 'public', url: '' });
assert.deepEqual(plain(model.normalize({ relay: { mode: 'custom', url: 'https://relay.example.net/' } }).relay),
  { mode: 'custom', url: 'https://relay.example.net/' });
assert.deepEqual(plain(model.normalize({ relay: { mode: 'none', url: 'https://ignored' } }).relay), { mode: 'none', url: '' });
assert.deepEqual(plain(model.normalize({ relay: { mode: 'bogus' } }).relay), { mode: 'public', url: '' });
assert.deepEqual(plain(model.relayValues('public', 'https://x')), { relay: 'public' });
assert.deepEqual(plain(model.relayValues('none', '')), { relay: 'none' });
assert.deepEqual(plain(model.relayValues('custom', '  https://relay.example.net  ')), { relay: 'https://relay.example.net' });
assert.equal(model.relayValid('custom', 'https://relay.example.net'), true);
assert.equal(model.relayValid('custom', 'http://relay.example.net'), false);
assert.equal(model.relayValid('custom', 'https://'), false);
assert.equal(model.relayValid('public', ''), true);
assert.equal(model.relayStatusKey({ mode: 'public' }), 'omabridgeRelayPublic');
assert.equal(model.relayStatusKey({ mode: 'custom' }), 'omabridgeRelayCustom');
assert.equal(model.relayStatusKey({ mode: 'none' }), 'omabridgeRelayNone');
assert.equal(model.confirmedRequest('relay-set', { relay: 'none' }).confirmed, true);
assert.equal(model.errorKey('omabridge_relay_invalid', true), 'omabridgeErrorRelayInvalid');

// Rename and sync.
assert.equal(model.nameValid('Desk'), true);
assert.equal(model.nameValid('  '), false);
assert.equal(model.nameValid('a\nb'), false);
assert.equal(model.nameValid('x'.repeat(81)), false);
assert.deepEqual(plain(model.renameValues('  Desk  ')), { name: 'Desk' });
assert.equal(model.confirmedRequest('rename', { name: 'Desk' }).confirmed, true);
assert.deepEqual(plain(model.syncRequest()), { action: 'sync' });
assert.equal(model.confirmedRequest('sync', {}), null, 'sync is never sent as a confirmed change');
assert.deepEqual(plain(model.renamedStatus({ via: 'direct', reached: 1, total: 2 })), { key: 'omabridgeRenamedDirect', reached: 1, total: 2 });
assert.equal(model.renamedStatus({ via: 'service' }).key, 'omabridgeRenamedService');
assert.equal(model.errorKey('omabridge_name_invalid', true), 'omabridgeErrorNameInvalid');

// Management.
const managed = model.normalize({ peers: [{ id: 'a', name: 'A', admin: true, managed: 'yes' }] }).peers[0];
assert.equal(managed.admin, true);
assert.equal(managed.managed, false, 'only a real boolean counts');
assert.deepEqual(plain(model.pairValues('/x.json', null, true)), { path: '/x.json' }, 'no consent field unless asked');
assert.deepEqual(plain(model.pairValues('/x.json', { manage: true }, undefined)), { path: '/x.json', allowManage: false });
assert.deepEqual(plain(model.pairValues('/x.json', { manage: true }, true)), { path: '/x.json', allowManage: true });
assert.deepEqual(plain(model.inspectRequest('/x.json')), { action: 'invite-inspect', path: '/x.json' });
assert.equal(model.confirmedRequest('invite-inspect', {}), null, 'inspecting is never a confirmed change');
assert.deepEqual(plain(model.remoteReadRequest('p')), { action: 'remote', peer: 'p', command: { action: 'read' } });
assert.equal(model.remoteValues('p', { action: 'invite' }), null, 'only remote actions OmaBridge allows');
assert.equal(model.remoteValues('p', { action: 'admin-set' }), null);
assert.deepEqual(plain(model.remoteValues('p', { action: 'rename', name: 'X' })), { peer: 'p', command: { action: 'rename', name: 'X' } });
assert.equal(model.remoteRevocable({ admin: true }), false);
assert.equal(model.remoteRevocable({ admin: false }), true);
assert.deepEqual(plain(model.inviteManageValues({ services: ['t3'], qr: false }, true)), { services: ['t3'], qr: false, manage: true });
assert.deepEqual(plain(model.inviteManageValues({ services: ['t3'], qr: false }, false)), { services: ['t3'], qr: false });
assert.equal(model.manageText({ admin: true, managed: true }, k => k), 'omabridgeManagesThis · omabridgeYouManage');
const parsed = model.parseResponse(JSON.stringify({ available: true, renamed: { via: 'direct', reached: 1, total: 2 },
  invitation: { name: 'A', expires: 5, manage: true, token: 'secret' }, remote: { available: true, device: { id: 'r', name: 'R' } } }), 0);
assert.deepEqual(plain(parsed.renamed), { via: 'direct', reached: 1, total: 2 });
assert.deepEqual(plain(parsed.invitation), { name: 'A', expires: 5, manage: true }, 'never the token');
assert.equal(parsed.remote.device.name, 'R');
assert.equal(model.errorKey('omabridge_manage_consent_required', true), 'omabridgeErrorConsentRequired');

// Hosted relay.
assert.deepEqual(plain(model.normalize({}).relayHost), { enabled: false, url: '', running: false, error: '', suggested: '' });
assert.equal(model.normalize({ relayHost: { suggested: 'https://r.example.net:3341/' } }).relayHost.suggested, 'https://r.example.net:3341/');
assert.equal(model.relayHostStatusKey({ enabled: false }), 'omabridgeHostOff');
assert.equal(model.relayHostStatusKey({ enabled: true, running: true }), 'omabridgeHostRunning');
assert.equal(model.relayHostStatusKey({ enabled: true, error: 'port' }), 'omabridgeHostPort');
assert.equal(model.relayHostStatusKey({ enabled: true, error: 'certificate' }), 'omabridgeHostCertificate');
assert.equal(model.relayHostStatusKey({ enabled: true }), 'omabridgeHostStarting');
const moves = plain(model.relayEverywhereRequests('https://r/', [{ id: 'a', managed: true }, { id: 'b', managed: false }, { id: 'c', managed: true }]));
assert.deepEqual(moves.map(r => r.action === 'remote' ? r.peer : 'self'), ['a', 'c', 'self'], 'managed devices first, this one last');
assert.deepEqual(moves[0], { action: 'remote', peer: 'a', command: { action: 'relay-set', relay: 'https://r/' }, confirmed: true });
assert.deepEqual(moves[2], { action: 'relay-set', relay: 'https://r/', confirmed: true });
assert.notEqual(model.remoteValues('p', { action: 'relay-host', enabled: true }), null);
assert.deepEqual(plain(model.publishValues({ t3Available: true, sshAvailable: false }, true, true)), { t3: true, ssh: false }, 'only what can be served');
assert.deepEqual(plain(model.publishValues({ t3Available: false, sshAvailable: true }, true, true)), { t3: false, ssh: true });
assert.equal(model.normalize({ published: { external: true, t3Available: true } }).published.external, true);
assert.equal(model.localPath('file:///home/u/My%20Invites/omabridge-invite-1.json'), '/home/u/My Invites/omabridge-invite-1.json');

// Every documented error code has a readable message.
// The codes `omabridge manage` documents, plus the helper's own two.
const contractCodes = ['invalid_command', 'invalid_action', 'confirmation_required', 'local_error',
  'omabridge_identity_missing', 'omabridge_not_published', 'omabridge_service_not_published', 'omabridge_ssh_unavailable',
  'omabridge_t3_unavailable', 'omabridge_nothing_to_publish', 'omabridge_already_running', 'omabridge_unit_foreign',
  'omabridge_path_unsupported', 'omabridge_publish_failed', 'omabridge_invite_directory', 'omabridge_invite_unreadable',
  'omabridge_invite_invalid', 'omabridge_invite_expired', 'omabridge_pair_denied', 'omabridge_peer_unreachable',
  'omabridge_peer_not_found', 'omabridge_request_changed', 'omabridge_command_failed', 'omabridge_missing', 'omabridge_outdated'];
for (const code of contractCodes) assert.notEqual(model.errorKey(code, true), 'omabridgeErrorGeneric', code);
assert.equal(model.errorKey('invalid_command', false), 'omabridgeErrorOutdated');
assert.equal(model.errorKey('invalid_command', true), 'omabridgeErrorInvalidRequest');
assert.equal(model.errorKey('something_new', true), 'omabridgeErrorGeneric');

// Page wiring and translations.
const page = fs.readFileSync(path.join(repo, 'desktop/OmaBridgePage.qml'), 'utf8');
const core = fs.readFileSync(path.join(repo, 'desktop/Core.qml'), 'utf8');
const shell = fs.readFileSync(path.join(repo, 'desktop/shell.qml'), 'utf8');
const catalog = JSON.parse(fs.readFileSync(path.join(repo, 'desktop/i18n.json'), 'utf8'));
assert.match(page, /Quickshell\.shellDir\s*\+\s*"\/\.\.\/bin\/omabridge-client"/);
assert.match(page, /backend\.command = \[helperPath\]/, 'requests never travel on argv');
assert.match(page, /write\(root\.pendingJson \+ "\\n"\)/);
assert.doesNotMatch(page, /confirmed\s*:\s*true/, 'only OmaBridgeModel.confirmedRequest adds confirmation');
assert.doesNotMatch(page, /console\.|savePrefs|resultText/, 'responses are never logged or saved');
assert.match(page, /onClosed: \{\s*root\.created = null;/, 'closing the invitation dialog forgets it');
assert.match(core, /\{ title: t\(uiLang, "omabridge"\), page: 9, devOnly: false \}/);
assert.match(core, /OmaBridgePage \{[\s\S]*?visible: root\.currentTab === 9/);
assert.match(core, /devices"\), page: 4[^\n]*\n[^\n]*"omabridge"/, 'OmaBridge follows Devices in the navigation');
assert.doesNotMatch(core, /tabs\.length - 1/, 'Profiles is addressed by page, not by position');
assert.match(shell, /core\.currentTab = navigationTabs\[index\]\.page/);
const keys = new Set([
  'omabridge',
  ...[...page.matchAll(/root\.tr?\("(omabridge[A-Za-z0-9]+)"/g)].map(match => match[1]),
  ...Object.values(model.ERROR_KEYS), 'omabridgeErrorInvalidRequest', 'omabridgeErrorGeneric',
  'omabridgePublishOff', 'omabridgePublishStale', 'omabridgePublishInactive', 'omabridgePublishOn', 'omabridgePublishExternal', 'cancel'
]);
for (const lang of ['en', 'es']) for (const key of keys) assert.ok(catalog[lang][key], `${lang} translation missing: ${key}`);
assert.equal(catalog.es.omabridgeInstall, 'Instala o actualiza OmaBridge para gestionarlo aquí');
assert.doesNotMatch(page + fs.readFileSync(path.join(repo, 'desktop/OmaBridgeModel.js'), 'utf8'), /omarchy-t3-client|ot3_missing/, 'the panel does not depend on T3 Code');
for (const key of keys) if (/%1/.test(catalog.en[key])) assert.match(catalog.es[key], /%1/, key);

// The helper finds `omabridge` on PATH, in ~/.local/bin or bundled with T3 Code,
// skips a release without `manage`, and reports when none is usable.
const fixture = fs.mkdtempSync(path.join(os.tmpdir(), 'omabridge-client-'));
const fake = path.join(repo, 'tests/fixtures/fake-omabridge');
const install = (file, source) => {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  if (source) fs.copyFileSync(source, file);
  else fs.writeFileSync(file, '#!/bin/sh\necho "error: unrecognized subcommand" >&2\nexit 2\n');
  fs.chmodSync(file, 0o755);
};
const run = (home, input, extraPath = '') => cp.spawnSync(path.join(repo, 'bin/omabridge-client'), [], {
  input, encoding: 'utf8',
  env: { PATH: `${extraPath}/usr/bin:/bin`, HOME: home, FAKE_OMABRIDGE_STATE: path.join(home, 'state.json'), FAKE_OMABRIDGE_LOG: path.join(home, 'log') }
});
const logOf = home => fs.readFileSync(path.join(home, 'log'), 'utf8').trim().split('\n').map(line => JSON.parse(line));
const missingHome = path.join(fixture, 'missing');
fs.mkdirSync(missingHome);
const missing = run(missingHome, '{"action":"read"}');
assert.equal(missing.status, 1);
assert.deepEqual(JSON.parse(missing.stdout), { error: 'omabridge_missing' });
const oldHome = path.join(fixture, 'old');
install(path.join(oldHome, '.local/bin/omabridge'));
assert.deepEqual(JSON.parse(run(oldHome, '{"action":"read"}').stdout), { error: 'omabridge_outdated' });
const layouts = {
  path: home => { install(path.join(home, 'tools/omabridge'), fake); return `${home}/tools:`; },
  local: home => { install(path.join(home, '.local/bin/omabridge'), fake); return ''; },
  bundled: home => {
    install(path.join(home, '.local/bin/omabridge'));
    install(path.join(home, '.config/omarchy/plugins/omarchy-t3-code/bin/omabridge'), fake);
    return '';
  },
  'bundled-id': home => { install(path.join(home, '.config/omarchy/plugins/io.github.avillagran.omarchy-t3-code/bin/omabridge'), fake); return ''; }
};
for (const [name, layout] of Object.entries(layouts)) {
  const home = path.join(fixture, name);
  const extraPath = layout(home);
  const read = run(home, '{"action":"read"}', extraPath);
  assert.equal(read.status, 0, name + read.stdout + read.stderr);
  assert.equal(JSON.parse(read.stdout).available, true);
  const refused = run(home, '{"action":"identity-create"}', extraPath);
  assert.equal(refused.status, 1);
  assert.deepEqual(JSON.parse(refused.stdout), { error: 'confirmation_required' });
  const log = logOf(home);
  assert.deepEqual(log.map(entry => entry.argv), [['manage'], ['manage']], name);
  assert.equal(log[1].stdin, '{"action":"identity-create"}', 'stdin passes through unchanged');
}
const large = run(path.join(fixture, 'local'), ' '.repeat(70 * 1024));
assert.deepEqual(JSON.parse(large.stdout), { error: 'invalid_command' });
fs.rmSync(fixture, { recursive: true, force: true });

console.log('OmaBridgeModel tests passed');
