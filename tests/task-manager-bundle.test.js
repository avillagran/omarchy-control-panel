const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const read = (p) => fs.readFileSync(path.join(__dirname, '..', p), 'utf8');
const core = read('desktop/Core.qml');
const page = read('desktop/TaskManagerPage.qml');
const shellQml = read('desktop/shell.qml');
const i18n = JSON.parse(read('desktop/i18n.json'));

// The Task Manager is its own plugin: the panel only switches it and reuses
// its components from the installed folder, never a vendored copy.
assert.match(core, /\{ title: t\(uiLang, "taskManager"\), page: 8, devOnly: false \}/);
assert.match(core, /TaskManagerPage \{[\s\S]*?currentTab === 8/);
assert.ok(!fs.existsSync(path.join(__dirname, '../desktop/OmiFace.qml')),
  'Omi must come from omarchy-task-manager, not a copy');
assert.match(shellQml, /core\.taskManagerDir \+ "\/OmiFace\.qml"/);
assert.match(page, /core\.taskManagerDir \+ "\/ActivityGraph\.qml"/);
// Switched through Omarchy's plugin manager, only from the toggle: no
// download-and-run, no install on first launch.
assert.match(page, /\["omarchy", "plugin", "add", repoUrl, "--enable", "--yes"\]/);
assert.match(page, /\["omarchy", "plugin", "enable", pluginId\]/);
assert.match(page, /\["omarchy", "plugin", "disable", pluginId\]/);
assert.doesNotMatch(page, /curl|install\.sh|maybeAutoInstall/);

// Tabs are addressed by page id: adding a tab must not move Profiles.
assert.match(core, /readonly property int profilesPage: 7/);
assert.doesNotMatch(core, /currentTab = root\.tabs\.length - 1/);

for (const [lang, table] of Object.entries(i18n)) {
  for (const key of ['taskManager', 'taskManagerSubtitle', 'taskManagerEnable', 'taskManagerOpen', 'tmMaxRam', 'tmBarMode',
                     'singleWindowSquare', 'noGaps']) {
    assert.ok(table[key], `${lang}.${key} missing`);
  }
  assert.match(table.taskManagerPaused, /%1/, `${lang}.taskManagerPaused needs %1`);
}

console.log('Task Manager bundle tests passed');
