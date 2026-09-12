const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const core = fs.readFileSync(path.join(__dirname, '../desktop/Core.qml'), 'utf8');
const shell = fs.readFileSync(path.join(__dirname, '../desktop/shell.qml'), 'utf8');

assert.match(core, /property bool devMode:\s*false/,
  'developer-only features must default to hidden');
assert.match(core, /\{ title: t\(uiLang, "networkDevices"\), page: 5, devOnly: true \}/);
assert.match(core, /\{ title: t\(uiLang, "backup"\), page: 6, devOnly: true \}/);
assert.match(core, /label:\s*"Dev mode"[\s\S]*checked:\s*root\.devMode/,
  'Profiles title must expose the Dev mode toggle');
assert.match(core, /label: root\.t\(root\.uiLang, "browserCloseTab"\)[\s\S]*visible:\s*root\.devMode/,
  'SUPER+W must stay hidden outside Dev mode');
assert.match(core, /label: root\.quickViewBusy[^\n]*\n\s*visible:\s*root\.devMode/,
  'unfinished QuickView must stay hidden outside Dev mode');
assert.match(core, /label:\s*"Dev mode"[\s\S]*foreground:\s*Color\.urgent/,
  'Dev mode control must be highlighted in red');
assert.match(shell, /navButton\.modelData\.devOnly \? theme\.urgent/,
  'developer-only navigation entries must be highlighted in red');
assert.match(core, /devMode = d\.devMode === true/);
assert.match(core, /devMode:\s*devMode/,
  'Dev mode must persist locally');
assert.match(shell, /property var navigationTabs:[\s\S]*!tab\.devOnly \|\| core\.devMode/,
  'navigation must remove developer-only pages instead of leaving blank rows');

console.log('Dev mode visibility tests passed');