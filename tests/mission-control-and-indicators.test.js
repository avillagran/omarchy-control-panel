const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');

const modelPath = path.join(__dirname, '../desktop/WorkspaceModel.js');
const source = fs.readFileSync(modelPath, 'utf8').replace(/^\.pragma library\s*/, '');
const context = {};
vm.createContext(context);
vm.runInContext(source, context);

assert.equal(context.normalizeIndicatorMode('square'), 'square');
assert.equal(context.normalizeIndicatorMode('rounded'), 'rounded');
assert.equal(context.normalizeIndicatorMode('circle'), 'circle');
assert.equal(context.normalizeIndicatorMode('none'), 'none');
assert.equal(context.normalizeIndicatorMode('bogus'), 'none');
assert.equal(context.normalizeIndicatorMode(undefined), 'none');

const core = fs.readFileSync(path.join(__dirname, '../desktop/Core.qml'), 'utf8');
const widget = fs.readFileSync(path.join(__dirname, '../workspace-colors.qml'), 'utf8');
const shell = fs.readFileSync(path.join(__dirname, '../desktop/shell.qml'), 'utf8');
const appTheme = fs.readFileSync(path.join(__dirname, '../desktop/AppTheme.qml'), 'utf8');
const rootPalette = fs.readFileSync(path.join(__dirname, '../ThemePalette.js'), 'utf8');
const desktopPalette = fs.readFileSync(path.join(__dirname, '../desktop/ThemePalette.js'), 'utf8');
const catalog = JSON.parse(fs.readFileSync(path.join(__dirname, '../desktop/i18n.json'), 'utf8'));

assert.match(core, /import "ThemePalette\.js" as ThemePalette/);
assert.equal(desktopPalette, rootPalette);
assert.match(core, /property string workspaceIndicatorMode:\s*"none"/);
assert.match(core, /property int workspaceIndicatorPadding:\s*4/);
assert.match(core, /workspaceIndicatorPadding:\s*workspaceIndicatorPadding/);
assert.match(core, /workspaceIndicatorMode:\s*workspaceIndicatorMode/);
assert.match(core, /missionControlEnabled/);
assert.match(core, /function loadSavedState\(\) \{[\s\S]*?luaStateProc\.running = true/,
  'opening the standalone panel must load saved state without applying it');
assert.match(core, /id: applyOnLoadTimer[\s\S]*?onTriggered: \{[\s\S]*?root\.loadSavedState\(\)[\s\S]*?root\.applySuperWBind\(\)/,
  'the standalone window must read state on load rather than replay control-panel.lua');
assert.doesNotMatch(core, /id: applyOnLoadTimer[\s\S]*?onTriggered: \{[\s\S]*?reapplySaved\(\)/,
  'opening the standalone panel must not reissue Hyprland configuration');

assert.match(catalog.es.missionControlHint, /SUPER\+SHIFT\+↑/);
assert.match(widget, /bar\.targetWindow \? bar\.targetWindow\(root\)/,
  'workspace widget must resolve the monitor from its owning bar window');
assert.match(widget, /readonly property string screenTopology:[\s\S]*?Quickshell\.screens/,
  'hotplug detection must compare the actual output topology');
assert.match(widget, /property string knownScreenTopology:\s*""/,
  'hotplug detection must retain a topology baseline');
assert.match(widget, /function onScreensChanged\(\) \{[\s\S]*?if \(root\.screenTopology === root\.knownScreenTopology\) return[\s\S]*?root\.scheduleHotplugSync\(\)/,
  'persistent bar widget must ignore non-topology screen notifications');
assert.match(widget, /display-hotplug-sync/,
  'workspace widget must invoke the display hotplug synchronizer');
assert.match(widget, /if \(root\.prefsLoaded\) return/,
  'stale nested shell settings must not overwrite authoritative prefs');
assert.match(widget, /workspaceIndicatorMode/);
assert.match(widget, /indicatorMode === "square"/);
assert.match(widget, /indicatorMode === "rounded"/);
assert.match(widget, /indicatorMode === "circle"/);
assert.match(widget, /workspaceIndicatorPadding/);
assert.match(widget, /Math\.max\(4,/);
assert.match(widget, /onTriggered:\s*prefsFile\.reload\(\)/);
assert.match(shell, /win\.startSystemMove\(\)/);
for (const role of ['lighter_background', 'selection', 'darker_background', 'muted', 'light_foreground']) {
  assert.ok(appTheme.includes(`"${role}"`), `AppTheme missing role: ${role}`);
}
for (const lang of ['en', 'es']) {
  for (const key of ['workspaceIndicatorMode', 'workspaceIndicatorPadding', 'indicatorSquare', 'indicatorRounded', 'indicatorCircle', 'indicatorNone', 'missionControl', 'missionControlHint']) {
    assert.ok(catalog[lang][key], `${lang} translation missing: ${key}`);
  }
}
console.log('Mission Control and workspace indicator tests passed');
