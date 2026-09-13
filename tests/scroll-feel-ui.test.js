const fs = require('node:fs');
const assert = require('node:assert/strict');
const path = require('node:path');

const core = fs.readFileSync(path.join(__dirname, '../desktop/Core.qml'), 'utf8');
const i18n = JSON.parse(fs.readFileSync(path.join(__dirname, '../desktop/i18n.json'), 'utf8'));

assert.match(core, /import "ScrollFeelModel\.js" as ScrollFeelModel/);
for (const property of ['scrollAccelProfile', 'scrollAccelSpeed', 'scrollAccelMax',
  'scrollDecel', 'scrollFeelConfigured', 'scrollPatchSupported'])
  assert.match(core, new RegExp(`property (?:int|real|bool) ${property}:`), `${property} state missing`);

// Setters must refuse to run on an unpatched compositor.
assert.match(core, /function updateScrollFeel\(profile, speed, max, decel, quiet\) \{\s*if \(!root\.scrollPatchSupported\) return/,
  'scroll setters must be gated on the capability probe');
assert.match(core, /function selectScrollPreset\(id\) \{\s*if \(!root\.scrollPatchSupported\) return/,
  'preset selection must be gated on the capability probe');

// writeLua may only emit the patch keys when the probe succeeded AND the user
// configured values through the panel (double gate).
assert.match(core, /if \(root\.scrollPatchSupported && saved\.scrollFeelConfigured\) \{\s*var scrollStatement = ScrollFeelModel\.luaConfigStatement/,
  'writeLua must double-gate the scroll emission');
assert.ok(core.includes('case \\"$l\\" in *scroll_accel*|*scroll_decel*) continue;; esac;'),
  'reapplySaved must skip scroll-patch lines during replay');

// The UI card is developer-only and styled with the urgent token.
assert.match(core, /id: scrollFeelCard[\s\S]*?visible: root\.devMode/,
  'scroll card must be hidden unless dev mode is on');
assert.match(core, /id: scrollFeelCard[\s\S]*?border\.color: Color\.urgent/,
  'scroll card must use the urgent theme token');
assert.match(core, /model: ScrollFeelModel\.presetIds\(\)/, 'preset selector missing');
assert.match(core, /onMoved: root\.updateScrollFeel\(root\.scrollAccelProfile, value,\s*root\.scrollAccelMax, root\.scrollDecel, true\)/,
  'coast slider must apply live');
assert.match(core, /scrollProbeProc/, 'capability probe process missing');
assert.match(core, /onExited: function\(exitCode\) \{\s*root\.scrollPatchProbed = true/,
  'probe must record support from the getoption exit code');

// Persistence: prefs load/save, profiles and the saved defaults must all
// carry the scroll fields so nothing silently drops them.
assert.match(core, /scrollFeelConfigured = d\.scrollFeelConfigured === true/,
  'prefs load must restore the configured flag');
assert.match(core, /scrollFeelConfigured: scrollFeelConfigured,\s*scrollAccelProfile: scrollAccelProfile/,
  'savePrefs must persist the scroll fields');
assert.match(core, /scrollDecel: saved\.scrollDecel,/, 'currentSettings must include scroll values for profiles');

const keys = [
  'scrollFeelTitle', 'scrollFeelSupported', 'scrollFeelUnsupported',
  'scrollFeelNative', 'scrollFeelLinear', 'scrollFeelAdaptive', 'scrollFeelGlide', 'scrollFeelCustom',
  'scrollFeelDescriptionNative', 'scrollFeelDescriptionLinear', 'scrollFeelDescriptionAdaptive',
  'scrollFeelDescriptionGlide', 'scrollFeelDescriptionCustom',
  'scrollFeelSpeed', 'scrollFeelSpeedGentle', 'scrollFeelSpeedBalanced', 'scrollFeelSpeedResponsive',
  'scrollFeelSpeedAggressive', 'scrollFeelMax', 'scrollFeelMaxMild', 'scrollFeelMaxModerate',
  'scrollFeelMaxStrong', 'scrollFeelMaxExtreme', 'scrollFeelCoast', 'scrollFeelCoastOff', 'scrollFeelApplied'
];
for (const lang of ['en', 'es'])
  for (const key of keys) assert.ok(i18n[lang][key], `${lang}.${key} missing`);

console.log('Scroll feel UI contract tests passed');
