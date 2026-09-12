const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const cp = require('node:child_process');
const vm = require('node:vm');

const sourcePath = path.join(__dirname, '../desktop/NetworkDevicesModel.js');
assert.ok(fs.existsSync(sourcePath), 'NetworkDevicesModel.js must exist');
const model = {};
vm.createContext(model);
vm.runInContext(fs.readFileSync(sourcePath, 'utf8').replace(/^\.pragma library\s*/, ''), model);

const scan = model.parseScan(JSON.stringify({
  ok: true,
  devices: [
    { name: 'Family Capsule', hostname: 'capsule.local', ip: '192.168.1.20', kind: 'time-capsule', services: [{ protocol: 'smb', advertised: true }] },
    { host: 'capsule.local', addresses: ['192.168.1.20'], services: [{ protocol: 'afp', probed: true }], mounts: [{ protocol: 'smb', path: '/run/user/1000/gvfs/smb-share:server=capsule.local,share=Data', verified: true }] },
    { ip: '192.168.1.44', services: ['sftp'] },
    { ip: '192.168.1.55', services: [] }
  ]
}), 0);
assert.equal(scan.ok, true);
assert.equal(scan.devices.length, 3, 'duplicate observations must be grouped without hiding unnamed neighbors');
assert.equal(scan.devices[0].name, 'Family Capsule');
assert.equal(scan.devices[0].ip, '192.168.1.20');
assert.deepEqual(Array.from(scan.devices[0].protocols), ['smb', 'afp']);
assert.equal(scan.devices[0].timeCapsule, true);
assert.equal(scan.devices[0].connected, true, 'only a verified mount marks the device connected');
const legacy = model.normalizeDevices([{ displayName: 'VQ TimeCapsule', ip: '192.168.1.15', services: [{ protocol: 'smb', advertised: true }], legacySmb: true }])[0];
assert.equal(legacy.name, 'VQ TimeCapsule');
assert.equal(legacy.ip, '192.168.1.15');
assert.equal(legacy.legacySmb, true);
const mounted = model.mergeMounts([legacy], [{ host: '192.168.1.15', protocol: 'smb', verified: true, path: '/run/user/1000/gvfs/capsule' }]);
assert.equal(mounted[0].connected, true);
assert.equal(mounted[0].mounts[0].path, '/run/user/1000/gvfs/capsule');
const backendShape = model.normalizeDevices([{
  id: 'net-vq', name: 'VQ TimeCapsule', host: 'vq.local', addresses: ['192.168.1.15'], kind: 'timeCapsule',
  services: [{ protocol: 'smb', port: 445, name: 'Microsoft Windows Network' }, { protocol: 'timemachine', port: 9, name: 'Apple TimeMachine' }],
  connection: { preferredAddress: '192.168.1.15', protocols: { smb: { port: 445, open: true } }, legacySmb: true, adapter: { status: 'required' } }
}])[0];
assert.equal(backendShape.name, 'VQ TimeCapsule');
assert.deepEqual(Array.from(backendShape.protocols), ['smb']);
assert.equal(backendShape.timeCapsule, true);
assert.equal(backendShape.legacySmb, true);
assert.equal(backendShape.backendDevice.id, 'net-vq');
assert.equal(scan.devices[1].name, '192.168.1.44', 'unnamed devices use their IP as the prominent label');
assert.deepEqual(Array.from(scan.devices[1].protocols), ['sftp']);
assert.equal(scan.devices[2].name, '192.168.1.55');

const opened = model.parseScan(JSON.stringify({ ok: true, devices: [{ ip: '192.168.1.9', services: ['smb'], opened: true, connected: true }] }), 0);
assert.equal(opened.devices[0].connected, false, 'opening native authentication is not verified mount evidence');
assert.deepEqual(Array.from(model.protocolsFor({ services: [{ protocol: 'smb', advertised: false }, { protocol: 'sftp', probed: true }, 'afp'] })), ['sftp', 'afp'], 'buttons require actually advertised or probed services');

const verifiedMounts = model.parseMounts(JSON.stringify({ ok: true, mounts: [{ host: 'capsule.local', protocol: 'smb', path: '/run/user/1000/gvfs/share' }] }), 0).mounts;
assert.deepEqual(Array.from(verifiedMounts).map(m => m.host), ['capsule.local']);
assert.equal(verifiedMounts[0].verified, true, 'mounts action is verified evidence and is normalized explicitly');
assert.equal(model.parseScan('{bad json', 0).ok, false);
assert.equal(model.parseScan('{"ok":false,"error":"scan failed"}', 1).error, 'scan failed');
assert.equal(model.protocolLabel('timecapsule'), 'Time Capsule');
assert.equal(model.protocolLabel('sftp'), 'SFTP');

const capsuleDevice = model.normalizeDevices([{
  id: 'net-vq', name: 'VQ TimeCapsule', host: 'vq-timecapsule.local', mac: '5C:96:9D:6D:B2:4A',
  addresses: ['169.254.194.141', '192.168.1.15'], services: [{ protocol: 'smb' }],
  connection: { preferredAddress: '192.168.1.15', legacySmb: true }
}])[0];
const sharesRequest = model.timeCapsuleRequest(capsuleDevice, 'alice', '', false);
assert.deepEqual(JSON.parse(JSON.stringify(sharesRequest)), {
  host: 'vq-timecapsule.local', address: '192.168.1.15', mac: '5C:96:9D:6D:B2:4A', user: 'alice'
});
assert.deepEqual(Array.from(model.timeCapsuleCommand('/plugin/bin/timecapsule-smb', 'shares')), ['/plugin/bin/timecapsule-smb', 'shares']);
assert.doesNotMatch(JSON.stringify(model.timeCapsuleCommand('/plugin/bin/timecapsule-smb', 'shares')), /vault-secret/);
assert.equal(model.timeCapsuleRequest(capsuleDevice, 'alice', 'Data', true).savedCredential, true);
assert.equal(model.timeCapsuleRequest(capsuleDevice, 'alice', 'Data', true).share, 'Data');
assert.deepEqual(JSON.parse(JSON.stringify(model.parseTimeCapsuleCapabilities('{"ok":true,"smbclient":true,"secretService":true}', 0))), {
  ok: true, smbclient: true, secretService: true
});
assert.deepEqual(Array.from(model.parseTimeCapsuleShares('{"ok":true,"shares":[{"name":"Data","comment":"Backups"},{"name":"IPC$","type":"IPC"}],"connected":true,"mounted":false}', 0).shares).map(s => s.name), ['Data', 'IPC$']);
assert.equal(model.parseTimeCapsuleVerify('{"ok":true,"connected":true,"mounted":false,"share":"Data"}', 0).accessible, true);
assert.equal(model.parseTimeCapsuleVerify('{"ok":true,"connected":true,"mounted":true,"share":"Data"}', 0).ok, false, 'legacy authentication must never be represented as a mount');
const authenticated = model.withTimeCapsuleDestination(capsuleDevice, 'alice', 'Data');
assert.equal(authenticated.connected, false);
assert.equal(authenticated.protocolAccessible, true);
assert.deepEqual(JSON.parse(JSON.stringify(authenticated.selectedDestination)), {
  kind: 'timecapsule', protocol: 'smb1', host: 'vq-timecapsule.local', address: '192.168.1.15',
  mac: '5C:96:9D:6D:B2:4A', user: 'alice', share: 'Data', authenticated: true,
  available: true, mounted: false
});
const authenticatedAfterMountCheck = model.mergeMounts([authenticated], [])[0];
assert.equal(authenticatedAfterMountCheck.protocolAccessible, true, 'mount refresh must preserve independently verified protocol access');
assert.equal(authenticatedAfterMountCheck.selectedDestination.share, 'Data');

const page = fs.readFileSync(path.join(__dirname, '../desktop/NetworkDevicesPage.qml'), 'utf8');
const core = fs.readFileSync(path.join(__dirname, '../desktop/Core.qml'), 'utf8');
const backup = fs.readFileSync(path.join(__dirname, '../desktop/BackupPage.qml'), 'utf8');
const catalog = JSON.parse(fs.readFileSync(path.join(__dirname, '../desktop/i18n.json'), 'utf8'));
assert.match(page, /Quickshell\.shellDir\s*\+\s*"\/\.\.\/bin\/network-devices"/);
assert.match(page, /function scan\(\)\s*\{[\s\S]*?run\("scan",\s*\{[\s\S]*?deep:\s*true/);
assert.doesNotMatch(page, /Component\.onCompleted\s*:\s*(?:root\.)?scan\(/, 'network scans must be user invoked');
assert.match(page, /device:\s*device\.backendDevice/);
assert.match(page, /Quickshell\.shellDir\s*\+\s*"\/\.\.\/bin\/timecapsule-smb"/);
assert.match(page, /echoMode:\s*TextInput\.Password/);
assert.match(page, /timeCapsuleBackend\.write\(root\.timeCapsuleJson\s*\+\s*"\\n"\)/);
assert.match(page, /timeCapsuleBackend\.write\(root\.timeCapsulePassword\s*\+\s*"\\n"\)/);
assert.doesNotMatch(page, /timeCapsuleCommand\([^\n]*password|command\s*=\s*\[[^\]]*timeCapsulePassword/, 'password must never enter argv');
assert.match(page, /timeCapsulePassword\s*=\s*""/);
assert.match(page, /selectedNetworkDevice\s*=\s*NetworkDevicesModel\.withTimeCapsuleDestination/);
assert.match(page, /networkAuthenticatedAvailable/);
assert.match(core, /networkDevices[\s\S]*backup[\s\S]*profiles/);
assert.match(core, /NetworkDevicesPage\s*\{[\s\S]*?currentTab === 5/);
assert.match(core, /BackupPage\s*\{[\s\S]*?currentTab === 6/);
assert.match(core, /\/\/ ---------- Profiles ----------[\s\S]*?currentTab === 7/);
assert.match(backup, /backupChooseFromNetworkDevices/);
assert.doesNotMatch(backup, /placeholderText:\s*root\.t\("backupHost"\)/, 'Backup must not ask users to remember or type hosts');
const networkKeys = [...page.matchAll(/["'](network[A-Z][A-Za-z]+)["']/g)].map(match => match[1]);
for (const lang of ['en', 'es']) for (const key of networkKeys) assert.ok(catalog[lang][key], `${lang} translation missing: ${key}`);

// Render the actual page with a fake Core and inert Process implementation.
// This is deliberately isolated from Core.qml, the LAN, credentials and helpers.
const fixtureRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'network-devices-ui-'));
const fixtureDesktop = path.join(fixtureRoot, 'desktop');
fs.mkdirSync(fixtureDesktop);
for (const name of ['NetworkDevicesPage.qml', 'NetworkDevicesModel.js', 'AppTheme.qml', 'ThemePalette.js'])
  fs.copyFileSync(path.join(__dirname, '../desktop', name), path.join(fixtureDesktop, name));
fs.mkdirSync(path.join(fixtureRoot, 'qs/Commons'), { recursive: true });
fs.writeFileSync(path.join(fixtureRoot, 'qs/Commons/qmldir'), 'module qs.Commons\nsingleton Color 1.0 Color.qml\nsingleton Style 1.0 Style.qml\n');
fs.writeFileSync(path.join(fixtureRoot, 'qs/Commons/Color.qml'), 'pragma Singleton\nimport QtQuick\nQtObject { property color background: "#1a1b26"; property color foreground: "#c0caf5"; property color accent: "#7aa2f7" }\n');
fs.writeFileSync(path.join(fixtureRoot, 'qs/Commons/Style.qml'), 'pragma Singleton\nimport QtQuick\nQtObject { property var font: ({family: "Sans Serif", body: 14, caption: 12}) }\n');
fs.mkdirSync(path.join(fixtureRoot, 'Quickshell/Io'), { recursive: true });
fs.writeFileSync(path.join(fixtureRoot, 'Quickshell/qmldir'), 'module Quickshell\nsingleton Quickshell 1.0 Quickshell.qml\n');
fs.writeFileSync(path.join(fixtureRoot, 'Quickshell/Quickshell.qml'), 'pragma Singleton\nimport QtQuick\nQtObject { readonly property string shellDir: "/forbidden"; function env(name) { return "" } }\n');
fs.writeFileSync(path.join(fixtureRoot, 'Quickshell/Io/qmldir'), 'module Quickshell.Io\nProcess 1.0 Process.qml\nStdioCollector 1.0 StdioCollector.qml\nFileView 1.0 FileView.qml\n');
fs.writeFileSync(path.join(fixtureRoot, 'Quickshell/Io/Process.qml'), 'import QtQuick\nQtObject { property bool running: false; property bool stdinEnabled: false; property var command: []; property QtObject stdout; property QtObject stderr; signal started(); signal exited(int exitCode, int exitStatus); function write(value) { throw new Error("forbidden helper invocation") } }\n');
fs.writeFileSync(path.join(fixtureRoot, 'Quickshell/Io/StdioCollector.qml'), 'import QtQuick\nQtObject { property bool waitForEnd: true; property string text: "" }\n');
fs.writeFileSync(path.join(fixtureRoot, 'Quickshell/Io/FileView.qml'), 'import QtQuick\nQtObject { property string path: ""; property bool blockLoading: false; property bool watchChanges: false; property bool printErrors: false; signal loaded(); signal fileChanged(); function text() { return "" } function reload() {} }\n');
const screenshot = path.join(os.tmpdir(), 'network-devices-timecapsule.png');
fs.rmSync(screenshot, { force: true });
fs.writeFileSync(path.join(fixtureRoot, 'capture.qml'), `import QtQuick
import QtQuick.Window
import QtQuick.Controls
import "desktop"
Window {
  width: 960; height: 1100; visible: true; color: "#1a1b26"
  property var translations: (${JSON.stringify(catalog)})
  QtObject { id: mockCore; property string uiLang: "en"; property var networkDevices: [device]; property var selectedNetworkDevice: device; property var device: ({ id: "net-vq", name: "VQ TimeCapsule", ip: "192.168.1.15", hostname: "vq-timecapsule.local", protocols: ["smb"], legacySmb: true, timeCapsule: true, connected: false, protocolAccessible: true, backendDevice: ({ host: "vq-timecapsule.local", mac: "5C:96:9D:6D:B2:4A", addresses: ["192.168.1.15"], connection: ({preferredAddress: "192.168.1.15"}) }) }); function t(lang, key) { return translations[lang][key] || translations.en[key] || key } }
  Rectangle { id: shot; anchors.fill: parent; color: parent.color
    ScrollView { anchors.fill: parent; anchors.margins: 24; contentWidth: availableWidth
      NetworkDevicesPage { id: page; width: parent.width; height: implicitHeight; core: mockCore; helperPath: "/forbidden"; timeCapsuleHelperPath: "/forbidden"; timeCapsuleOpen: true; timeCapsuleSmbclient: true; timeCapsuleSecretService: true; timeCapsuleShares: [({name: "Data", comment: "Backup disk"})]; timeCapsuleShare: "Data"; timeCapsuleVerified: true; timeCapsuleStatus: t("networkAuthenticatedAvailable") }
    }
  }
  Timer { interval: 500; running: true; onTriggered: shot.grabToImage(function(result) { if (!result.saveToFile(${JSON.stringify(screenshot)})) Qt.exit(2); else Qt.quit() }) }
}`);
const qmlRun = cp.spawnSync('/usr/lib/qt6/bin/qml', ['-I', fixtureRoot, path.join(fixtureRoot, 'capture.qml')], {
  encoding: 'utf8', timeout: 20000,
  env: { HOME: path.join(fixtureRoot, 'home'), XDG_CONFIG_HOME: path.join(fixtureRoot, 'config'), XDG_DATA_HOME: path.join(fixtureRoot, 'data'), XDG_CACHE_HOME: path.join(fixtureRoot, 'cache'), XDG_RUNTIME_DIR: path.join(fixtureRoot, 'runtime'), QT_QPA_PLATFORM: 'offscreen', QT_QPA_PLATFORMTHEME: 'basic', QT_QUICK_CONTROLS_STYLE: 'Basic', QT_QUICK_BACKEND: 'software', QML_IMPORT_PATH: fixtureRoot }
});
assert.equal(qmlRun.status, 0, `offscreen fixture failed:\n${qmlRun.stdout}\n${qmlRun.stderr}`);
assert.deepEqual(fs.readFileSync(screenshot).subarray(0, 8), Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]));
fs.rmSync(fixtureRoot, { recursive: true, force: true });

console.log('NetworkDevicesModel tests passed');
