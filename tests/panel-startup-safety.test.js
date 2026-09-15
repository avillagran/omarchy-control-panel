const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const core = fs.readFileSync(path.join(__dirname, '../desktop/Core.qml'), 'utf8');
const loadProfiles = core.match(/function loadProfilesFromText\(raw\) \{([\s\S]*?)\n  \}\n\n  function saveProfiles/);
assert.ok(loadProfiles, 'profile loader must exist');
assert.match(core, /var list = root\.displays && root\.displays\.length \? root\.displays : root\.saved\.displays/,
  'profile capture must use the current display layout');
assert.match(core, /saved\.mirror !== undefined/,
  'profile display restore must include mirror state');

assert.doesNotMatch(loadProfiles[1], /queueApplyActiveProfile|applyProfile\(/,
  'opening the panel must not apply the active profile or touch display modes');

const reapplySaved = core.match(/function reapplySaved\(\) \{([\s\S]*?)\n  \}\n\n  function close/);
assert.ok(reapplySaved, 'persisted-settings replay must exist');
assert.doesNotMatch(reapplySaved[1], /execDetached/,
  'settings replay must be awaitable so refresh cannot read defaults first');
assert.match(core, /id:\s*reapplyProc[\s\S]*onExited:[\s\S]*root\.refresh\(\)/,
  'live state may refresh only after persisted settings finish replaying');
const loadPrefs = core.match(/function loadPrefs\(raw\) \{([\s\S]*?)\n  \}\n\n  function savePrefs/);
assert.ok(loadPrefs, 'preferences loader must exist');
assert.doesNotMatch(loadPrefs[1], /root\.refresh\(\)/,
  'loading preferences must not race the persisted-settings replay');
assert.match(core, /if \(root\.workspaceTopology !== ""\)\s*workspaceTopologyTimer\.restart\(\)/,
  'the first display read must not persist a synthetic topology with default input settings');

const backupPage = fs.readFileSync(path.join(__dirname, '../desktop/BackupPage.qml'), 'utf8');
assert.match(backupPage, /connectJob\("local-devices"\)/,
  'local backup flow must discover removable storage');
assert.match(backupPage, /connectJob\("mount",\s*modelData\.device\)/,
  'choosing an unmounted device must mount it before verification');

assert.match(core, /delete copy\[name\]/,
  'clicking the selected monitor color again must clear it');
assert.match(core, /property string assignedColorRole:/,
  'display outlines must distinguish an explicit color from no selection');

console.log('Panel startup and local backup device safety tests passed');