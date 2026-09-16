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
assert.equal(context.normalizeNumeralStyle('roman'), 'arabic');
assert.equal(context.normalizeNumeralStyle('bogus'), 'arabic');
assert.equal(context.workspaceNumber({ name: '6' }), 6,
  'Hyprland 0.56 workspace objects identify numbered workspaces by name');
assert.equal(context.workspaceNumber({ id: 7, name: 'ignored' }), 7);
assert.equal(context.workspaceNumber({ id: 0, name: '8' }), 8,
  'an empty IPC id must fall back to the numbered workspace name');
assert.equal(context.workspaceNumber({ name: 'special:sidepanelX' }), 0,
  'special workspaces must not consume a numbered workspace button');
assert.equal(context.formatWorkspaceNumber(4, 'kanji'), '四');
assert.equal(context.formatWorkspaceNumber(4, 'runes'), 'ᚨ');
assert.equal(context.normalizeNumeralStyle('circled'), 'arabic');
assert.equal(context.normalizeNumeralStyle('yupana'), 'arabic');
assert.doesNotMatch(context.numeralStyles.join(','), /yupana/);
assert.doesNotMatch(context.numeralStyles.join(','), /circled/);
assert.doesNotMatch(context.numeralStyles.join(','), /roman/);
assert.equal(context.numeralPreview('greek'), 'α β γ');

const core = fs.readFileSync(path.join(__dirname, '../desktop/Core.qml'), 'utf8');
const widget = fs.readFileSync(path.join(__dirname, '../workspace-colors.qml'), 'utf8');
const shell = fs.readFileSync(path.join(__dirname, '../desktop/shell.qml'), 'utf8');
const quickView = fs.readFileSync(path.join(__dirname, '../desktop/MissionControl.qml'), 'utf8');
const quickViewLauncher = fs.readFileSync(path.join(__dirname, '../bin/quickview-toggle.sh'), 'utf8');
const thirdPartyNotices = fs.readFileSync(path.join(__dirname, '../THIRD_PARTY_NOTICES.md'), 'utf8');
const hyprviewIntegrationPatch = fs.readFileSync(path.join(__dirname, '../patches/qs-hyprview/0001-integration-refresh-toplevel-model.patch'), 'utf8');
const appTheme = fs.readFileSync(path.join(__dirname, '../desktop/AppTheme.qml'), 'utf8');
const rootPalette = fs.readFileSync(path.join(__dirname, '../ThemePalette.js'), 'utf8');
const desktopPalette = fs.readFileSync(path.join(__dirname, '../desktop/ThemePalette.js'), 'utf8');
const catalog = JSON.parse(fs.readFileSync(path.join(__dirname, '../desktop/i18n.json'), 'utf8'));

assert.equal(catalog.en.missionControl, 'QuickView');
assert.equal(catalog.es.missionControl, 'QuickView');
assert.doesNotMatch(shell, /id:\s*sectionTitle/,
  'the standalone content must not duplicate the icon/title/action section header');

assert.match(core, /import "ThemePalette\.js" as ThemePalette/);
assert.equal(desktopPalette, rootPalette);
assert.match(core, /property string workspaceIndicatorMode:\s*"none"/);
assert.match(core, /property int workspaceIndicatorPadding:\s*4/);
assert.match(core, /property string workspaceNumeralStyle:\s*"arabic"/);
assert.doesNotMatch(core, /Yupana/);
assert.match(core, /workspaceIndicatorPadding:\s*workspaceIndicatorPadding/);
assert.match(core, /workspaceIndicatorMode:\s*workspaceIndicatorMode/);
assert.match(core, /missionControlEnabled/);
assert.match(core, /function loadSavedState\(\) \{[\s\S]*?luaStateProc\.running = true/,
  'opening the standalone panel must load saved state without applying it');
assert.match(core, /id: applyOnLoadTimer[\s\S]*?onTriggered: \{[\s\S]*?root\.loadSavedState\(\)[\s\S]*?root\.applySuperWBind\(\)/,
  'the standalone window must read state on load rather than replay control-panel.lua');
assert.doesNotMatch(core, /id: applyOnLoadTimer[\s\S]*?onTriggered: \{[\s\S]*?reapplySaved\(\)/,
  'opening the standalone panel must not reissue Hyprland configuration');
assert.match(core, /id:\s*displayInstantProc[\s\S]*?root\.applyWorkspaceLayout\(true\)/,
  'display reorders must immediately recalculate virtual-workspace output positions');

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
assert.match(widget, /WorkspaceModel\.workspaceNumber\(values\[i\]\)/,
  'workspace widget must use the numeric workspace name when IPC has no id field');
assert.match(widget, /Every bar shows the complete workspace strip/,
  'every monitor bar must expose the complete numbered workspace strip');
assert.doesNotMatch(widget, /liveMonitorOf\(values\[i\]\) === screenName/,
  'workspace visibility must not be restricted to the bar monitor');
assert.match(widget, /Hyprland\.focusedWorkspace[\s\S]*?WorkspaceModel\.workspaceNumber/,
  'workspace widget must mark focus from the current Hyprland workspace name');
assert.match(widget, /formatWorkspaceNumber\(delegate\.modelData, root\.workspaceNumeralStyle\)/,
  'workspace labels must honor the selected numeral style');
assert.match(widget, /color: delegate\.focused \? delegate\.workspaceColor/,
  'the focused workspace must remain visibly marked in every numeral style');
assert.match(widget, /function uniformIndicatorExtent\(\)/,
  'shaped indicators must use one shared extent across the active numeral style');
assert.match(widget, /numberLabel\.implicitWidth \+ 2 \* root\.workspaceIndicatorPadding/,
  'none mode spacing must honor number padding');
assert.match(widget, /onTriggered:\s*prefsFile\.reload\(\)/);
assert.match(shell, /win\.startSystemMove\(\)/);
assert.match(quickView, /target: "omarchy-control-panel-quickview"/,
  'QuickView must expose an IPC target for the compositor gesture and global shortcut');
assert.match(quickView, /hyprctl", "dispatch", "hl\.dsp\.window\.move/,
  'dropping a window card must move that explicit window to the destination workspace');
assert.match(quickView, /DropArea[\s\S]*?onDropped/,
  'each workspace needs a drop target');
assert.match(quickView, /DragHandler/,
  'window cards need drag interaction');
assert.match(quickView, /workspaceForScreen\(modelData\.name\)/,
  'each output must only render workspaces assigned to its live screen name');
assert.match(quickView, /ListView[\s\S]*orientation:\s*ListView\.Horizontal/,
  'workspaces must be a horizontal row instead of a square grid');
assert.match(quickView, /ScreencopyView[\s\S]*live:\s*root\.open/,
  'window previews must use the compositor live toplevel stream while QuickView is open');
assert.match(quickView, /displaced:\s*Transition[\s\S]*NumberAnimation/,
  'inserting a workspace must animate neighboring cards out of the way');
assert.match(quickView, /returnToOrigin\(/,
  'an undropped window preview must animate back to its original workspace');
assert.match(quickView, /workspaceTint\(/,
  'workspace cards must derive their tint from the selected monitor color role');
assert.match(quickViewLauncher, /github\.com\/dom0\/qs-hyprview/,
  'the QuickView launcher must reference the upstream qs-hyprview project');
assert.match(quickViewLauncher, /TARGET="expose"/,
  'the launcher must use qs-hyprview’s documented IPC target');
assert.match(quickViewLauncher, /LAYOUT="bands"/,
  'the initial integration must preserve workspace grouping through qs-hyprview bands');
assert.match(quickViewLauncher, /INTEGRATION_PATCH=.*0001-integration-refresh-toplevel-model\.patch/,
  'the launcher must apply Omarchy integration without claiming upstream source as local code');
assert.match(hyprviewIntegrationPatch, /refreshGeneration[\s\S]*property Timer refreshTimer[\s\S]*interval: 200/,
  'the integration patch must refresh the initially-empty standalone Hyprland toplevel model');
assert.match(hyprviewIntegrationPatch, /Number\(workspace\.id\) \|\| Number\(workspace\.name\)/,
  'the integration patch must support Hyprland 0.56 workspace name identity');
assert.match(thirdPartyNotices, /Domenico Martella/,
  'upstream authorship must be explicit');
assert.match(thirdPartyNotices, /GPL-3\.0/,
  'upstream licensing must be explicit');
assert.match(thirdPartyNotices, /1fdea0ac9faea585771d4da3680397e449285706/,
  'the upstream revision must be pinned explicitly');
assert.match(quickView, /workspaces\.width - workspaces\.spacing \* Math\.max\(0, workspaces\.count - 1\)/,
  'each workspace row must fit every defined slot into its available monitor width');
assert.match(quickView, /invalid release leaves the card at[\s\S]*?target:\s*null/,
  'a workspace drag must not move a card freely outside its defined slots');
assert.match(quickView, /previewWorkspaceInsert[\s\S]*?commitWorkspaceInsert[\s\S]*?cancelWorkspaceInsert/,
  'hover insertion must preview neighbor movement, commit on a slot, and cancel on an invalid release');
assert.match(shell, /MissionControl \{ id: missionControl \}/,
  'desktop shell must retain the QuickView renderer');
for (const role of ['lighter_background', 'selection', 'darker_background', 'muted', 'light_foreground']) {
  assert.ok(appTheme.includes(`"${role}"`), `AppTheme missing role: ${role}`);
}
for (const lang of ['en', 'es']) {
  for (const key of ['workspaceIndicatorMode', 'workspaceIndicatorPadding', 'workspaceNumerals', 'indicatorSquare', 'indicatorRounded', 'indicatorCircle', 'indicatorNone', 'missionControl', 'missionControlHint']) {
    assert.ok(catalog[lang][key], `${lang} translation missing: ${key}`);
  }
}
console.log('QuickView and workspace indicator tests passed');
