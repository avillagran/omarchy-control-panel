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
assert.equal(model.stateFor(model.parseResponse('{"error":"invalid_command"}', 1)), 'outdated', 'an ot3 without omabridge-action');
assert.equal(model.stateFor(model.parseResponse('{"error":"invalid_command"}', 0)), 'outdated', 'old omabridge-read exits 0');
assert.equal(model.stateFor(model.parseResponse('{"error":"ot3_missing"}', 1)), 'missing');
assert.equal(model.stateFor(model.parseResponse('{"error":"omabridge_command_failed"}', 1)), 'failed');
assert.equal(model.stateFor(null), 'loading');
assert.equal(model.parseResponse('', 124).error, 'timeout');
assert.equal(model.parseResponse('not json', 0).error, 'invalid_response');
assert.equal(model.parseResponse('[]', 0).error, 'invalid_response');
assert.equal(model.normalize({}).published.enabled, false, 'publishing is off unless ot3 says otherwise');

// The created invitation is kept apart from the snapshot; only SVG data URIs are shown.
const invited = model.parseResponse(JSON.stringify({ ...snapshot, created: { path: '/tmp/omabridge-invite-1.json', expires: 5, services: ['t3'], qrImage: 'data:image/svg+xml;base64,AAA' } }), 0);
assert.equal(invited.created.path, '/tmp/omabridge-invite-1.json');
assert.equal(invited.created.qrImage, 'data:image/svg+xml;base64,AAA');
assert.equal(JSON.stringify(invited.snapshot).includes('omabridge-invite'), false, 'the secret never enters the snapshot');
assert.equal(model.parseResponse(JSON.stringify({ ...snapshot, created: { path: '/p', qrImage: 'file:///etc/passwd' } }), 0).created.qrImage, '');
const paired = model.parseResponse(JSON.stringify({ ...snapshot, paired: { status: 'pending', name: 'desk', id: 'p9' } }), 0);
assert.deepEqual(plain(paired.paired), { status: 'pending', name: 'desk', id: 'p9' });

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
assert.equal(model.localPath('file:///home/u/My%20Invites/omabridge-invite-1.json'), '/home/u/My Invites/omabridge-invite-1.json');

// Every documented error code has a readable message.
const contractCodes = ['confirmation_required', 'invalid_command', 'omabridge_unavailable', 'omabridge_identity_missing',
  'omabridge_not_published', 'omabridge_service_not_published', 'omabridge_ssh_unavailable', 'omabridge_invite_expired',
  'omabridge_invite_invalid', 'omabridge_invite_unreadable', 'omabridge_peer_not_found', 'omabridge_unit_foreign',
  'omabridge_publish_failed', 'omabridge_command_failed'];
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
  'omabridgePublishOff', 'omabridgePublishStale', 'omabridgePublishInactive', 'omabridgePublishOn', 'cancel'
]);
for (const lang of ['en', 'es']) for (const key of keys) assert.ok(catalog[lang][key], `${lang} translation missing: ${key}`);
assert.equal(catalog.es.omabridgeInstallOt3, 'Instala o actualiza Omarchy T3 Code para gestionar OmaBridge');
for (const key of keys) if (/%1/.test(catalog.en[key])) assert.match(catalog.es[key], /%1/, key);

// The helper finds ot3 under either plugin id and reports when it is missing.
const fixture = fs.mkdtempSync(path.join(os.tmpdir(), 'omabridge-client-'));
const run = (home, input) => cp.spawnSync(path.join(repo, 'bin/omabridge-client'), [], {
  input, encoding: 'utf8', env: { PATH: process.env.PATH, HOME: home, FAKE_OT3_STATE: path.join(home, 'state.json'), FAKE_OT3_LOG: path.join(home, 'log') }
});
const missingHome = path.join(fixture, 'missing');
fs.mkdirSync(missingHome);
const missing = run(missingHome, '{"action":"read"}');
assert.equal(missing.status, 1);
assert.deepEqual(JSON.parse(missing.stdout), { error: 'ot3_missing' });
for (const id of ['omarchy-t3-code', 'io.github.avillagran.omarchy-t3-code']) {
  const home = path.join(fixture, id);
  const bin = path.join(home, '.config/omarchy/plugins', id, 'bin');
  fs.mkdirSync(bin, { recursive: true });
  fs.copyFileSync(path.join(repo, 'tests/fixtures/fake-omarchy-t3-client'), path.join(bin, 'omarchy-t3-client'));
  fs.chmodSync(path.join(bin, 'omarchy-t3-client'), 0o755);
  const read = run(home, '{"action":"read"}');
  assert.equal(read.status, 0, read.stdout + read.stderr);
  assert.equal(JSON.parse(read.stdout).available, true);
  const refused = run(home, '{"action":"identity-create"}');
  assert.equal(refused.status, 1);
  assert.deepEqual(JSON.parse(refused.stdout), { error: 'confirmation_required' });
  const log = fs.readFileSync(path.join(home, 'log'), 'utf8').trim().split('\n').map(line => JSON.parse(line));
  assert.deepEqual(log.map(entry => entry.argv), [['omabridge-action'], ['omabridge-action']]);
  assert.equal(log[1].stdin, '{"action":"identity-create"}', 'stdin passes through unchanged');
}
fs.rmSync(fixture, { recursive: true, force: true });

console.log('OmaBridgeModel tests passed');
