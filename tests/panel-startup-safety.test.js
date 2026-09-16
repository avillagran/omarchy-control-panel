const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const core = fs.readFileSync(path.join(__dirname, '../desktop/Core.qml'), 'utf8');
const loadProfiles = core.match(/function loadProfilesFromText\(raw\) \{([\s\S]*?)\n  \}\n\n  function saveProfiles/);
assert.ok(loadProfiles, 'profile loader must exist');
assert.match(core, /var list = root\.displays && root\.displays\.length \? root\.displays : root\.saved\.displays/,
  'profile capture must use the current display layout');
assert.match(core, /function saveActiveProfileDisplayMap\(\)[\s\S]*?ProfileModel\.saveDisplayLayout\(root\.profiles, root\.activeProfileId,[\s\S]*?root\.currentDisplayTopology\(\), map\)/,
  'a manual display apply must update the active profile map used by hotplug recovery');
assert.match(core, /id:\s*displayInstantProc[\s\S]*?root\.saveActiveProfileDisplayMap\(\)/,
  'the profile map must update only after an instant display apply succeeds');
assert.match(core, /function displaySave\(\) \{[\s\S]*?displayApplyChanges\(\)/,
  'Save must route through the existing safe preview/direct-apply decision');
assert.match(core, /text:\s*root\.t\(root\.uiLang, "saveDisplayLayout"\)[\s\S]*?onClicked:\s*root\.displaySave\(\)/,
  'the Displays header must expose an explicit Save action beside Identify');
assert.match(core, /function displayKeep\(\)[\s\S]*?root\.saveActiveProfileDisplayMap\(\)/,
  'keeping a previewed mode or orientation must also update the hotplug profile map');
assert.match(core, /function currentDisplayTopology\(\)[\s\S]*?fingerprint/,
  'the current display combination must derive from stable monitor fingerprints');
assert.match(core, /function saveActiveProfileDisplayMap\(\)[\s\S]*?ProfileModel\.saveDisplayLayout/,
  'display persistence must scope the map to the detected monitor combination');
assert.match(core, /activeP\.settings\.displayLayouts[\s\S]*?physicalTopology[\s\S]*?byIdentity\[ki\]/,
  'the in-panel hotplug path must restore the exact fingerprint-keyed monitor combination');
assert.match(core, /id:\s*displayInstantProc[\s\S]*?root\.applyWorkspaceLayout\(true\)/,
  'reordering physical displays must immediately recompute numbered workspace ranges');
assert.match(core, /function saveCurrentToActiveProfile\(\)[\s\S]*?saveCurrentToProfile\(root\.activeProfileId\)/,
  'section headers need a shared active-profile save path');
assert.match(core, /text:\s*root\.t\(root\.uiLang, "profileSave"\)[\s\S]*?root\.saveCurrentToActiveProfile\(\)/,
  'Trackpad must expose a header Save action for the current profile');
assert.match(core, /saved\.mirror !== undefined/,
  'profile display restore must include mirror state');
assert.match(core, /L\.push\(["']-- Display layout["']\)[\s\S]*?hl\.monitor/,
  'rewriting control-panel.lua must retain the applied monitor layout');
assert.match(core, /win\.tags[\s\S]*?chromium-based-browser[\s\S]*?firefox-based-browser/,
  'SUPER+W must use Omarchy browser tags instead of depending only on a class field');
assert.match(core, /hl\.dsp\.send_key_state\(\{ mods = "CTRL", key = "W", state = "down" \}\)[\s\S]*?state = "up"/,
  'browser SUPER+W must deliver native Ctrl+W key states instead of closing the window');
assert.match(core, /hl\.dsp\.window\.close\(\)\) end end, \{ release = true \}/,
  'SUPER+W Lua must close both the branch and callback before bind options');
assert.match(core, /hl\.unbind\("SUPER \+ W"\); hl\.bind\("SUPER \+ W", function\(\) end\); hl\.bind\("SUPER \+ W"/,
  'SUPER+W must consume press/repeat events before handling the release');

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

const catalog = JSON.parse(fs.readFileSync(path.join(__dirname, '../desktop/i18n.json'), 'utf8'));
for (const [lang, strings] of Object.entries(catalog)) {
  assert.ok(strings.saveDisplayLayout, `${lang} requires the display Save translation`);
}

console.log('Panel startup and local backup device safety tests passed');