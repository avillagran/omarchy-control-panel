const fs = require('node:fs');
const assert = require('node:assert/strict');
const path = require('node:path');

const core = fs.readFileSync(path.join(__dirname, '../desktop/Core.qml'), 'utf8');
const i18n = JSON.parse(fs.readFileSync(path.join(__dirname, '../desktop/i18n.json'), 'utf8'));
const installer = fs.readFileSync(path.join(__dirname, '../bin/install-hyprland-scroll-patch.sh'), 'utf8');

const pinnedCommit = installer.match(/^HYPRLAND_PIN="([0-9a-f]{40})"$/m)?.[1];
assert.ok(pinnedCommit, 'scroll-patch installer must declare a full 40-character Hyprland commit');
assert.match(installer, new RegExp(`git -C "\\$SRC_DIR" checkout -q --detach ${pinnedCommit}`),
  'scroll-patch installer must detached-checkout the literal pinned commit before building');

assert.match(core, /import "ScrollFeelModel\.js" as ScrollFeelModel/);
for (const property of ['scrollAccelProfile', 'scrollAccelSpeed', 'scrollAccelMax',
  'scrollDecel', 'scrollFeelConfigured', 'scrollPatchSupported'])
  assert.match(core, new RegExp(`property (?:int|real|bool) ${property}:`), `${property} state missing`);

// Setters must refuse to run on an unpatched compositor.
assert.match(core, /function updateScrollFeel\(profile, speed, max, decel, quiet\) \{\s*if \(!root\.scrollPatchSupported\) return/,
  'scroll setters must be gated on the capability probe');
assert.match(core, /function selectScrollPreset\(id\) \{\s*if \(!root\.scrollPatchSupported\) return/,
  'preset selection must be gated on the capability probe');
assert.match(core, /function updateScrollIgnoreMode\(mode, quiet\) \{\s*if \(!root\.scrollPatchSupported \|\| !root\.scrollIgnoreSupported\) return/,
  'ignore-mode setter must be gated on both probes');
assert.match(core, /property string scrollIgnoreMode:/, 'ignore mode state missing');
assert.match(core, /property bool scrollIgnoreSupported:/, 'ignore support probe state missing');

// writeLua may only emit the patch keys when the probe succeeded AND the user
// configured values through the panel (double gate). The effective profile
// must come from the mode ("native" => 0) and the statement must carry the
// mode's ignore list.
assert.match(core, /if \(root\.scrollPatchSupported && saved\.scrollFeelConfigured\) \{[\s\S]*?var scrollStatement = ScrollFeelModel\.luaConfigStatement/,
  'writeLua must double-gate the scroll emission');
assert.match(core, /ScrollFeelModel\.profileForMode\(saved\.scrollIgnoreMode, saved\.scrollAccelProfile\)/,
  'writeLua must resolve the effective profile from the ignore mode');
assert.match(core, /ScrollFeelModel\.ignoreListForMode\(saved\.scrollIgnoreMode\)/,
  'writeLua must emit the mode ignore list');
assert.ok(core.includes('case \\"$l\\" in *scroll_accel*|*scroll_decel*|*scroll_ignore*) continue;; esac;'),
  'reapplySaved must skip scroll-patch lines during replay');

// Choosing an accel preset must leave "native" (patch off) mode, and the
// live slider updates must preserve the ignore list instead of clobbering it.
assert.match(core, /selectScrollPreset[\s\S]*?scrollIgnoreMode = "off"[\s\S]*?updateScrollFeel\(value\.profile/,
  'preset selection must exit native mode');
assert.match(core, /updateScrollFeel[\s\S]*?ScrollFeelModel\.ignoreListForMode\(root\.saved\.scrollIgnoreMode\)/,
  'slider updates must keep the mode ignore list');

// The state probe reads the ignore classes too and mirrors an unconfigured
// panel from the live compositor values.
assert.match(core, /scroll_ignore_classes -j"\]/, 'state probe must read scroll_ignore_classes');
assert.match(core, /modeFromLive\(\s*values\.profile, values\.ignoreClasses\)/,
  'probe must derive the ignore mode from live values');

// Outside developer mode, leave a translated pointer in the same Trackpad tab.
assert.match(core, /visible: !root\.devMode[\s\S]*?scrollFeelDevHint/,
  'non-DEV users must see the Scroll feel DEV-version hint');
assert.match(core, /scrollFeelDevRepo[\s\S]*?Qt\.openUrlExternally\("https:\/\/github\.com\/avillagran\/Hyprland\/tree\/feat\/touchpad-scroll-acceleration"\)/,
  'non-DEV users must be able to open the DEV implementation repository');

// The UI card is developer-only and styled with the urgent token.
assert.match(core, /id: scrollFeelCard[\s\S]*?visible: root\.devMode/,
  'scroll card must be hidden unless dev mode is on');
assert.match(core, /id: scrollFeelCard[\s\S]*?border\.color: Color\.urgent/,
  'scroll card must use the urgent theme token');
assert.match(core, /model: ScrollFeelModel\.presetIds\(\)/, 'preset selector missing');
assert.match(core, /model: ScrollFeelModel\.ignoreModes/, 'ignore-mode selector missing');
assert.match(core, /onClicked: root\.updateScrollIgnoreMode\(modelData\)/,
  'ignore-mode buttons must apply live');
assert.match(core, /onMoved: root\.updateScrollFeel\(root\.scrollAccelProfile, value,\s*root\.scrollAccelMax, root\.scrollDecel, true\)/,
  'coast slider must apply live');
assert.match(core, /scrollProbeProc/, 'capability probe process missing');
assert.match(core, /onExited: function\(exitCode\) \{\s*root\.scrollPatchProbed = true/,
  'probe must record support from the getoption exit code');

// Persistence: prefs load/save, profiles and the saved defaults must all
// carry the scroll fields so nothing silently drops them.
assert.match(core, /scrollFeelConfigured = d\.scrollFeelConfigured === true/,
  'prefs load must restore the configured flag');
assert.match(core, /scrollIgnoreMode = ScrollFeelModel\.clampIgnoreMode\(d\.scrollIgnoreMode\)/,
  'prefs load must restore the ignore mode');
assert.match(core, /root\.scrollIgnoreSupported\s*=\s*values\.ignoreSupported/,
  'state probe must record ignore support');
assert.match(core, /luaConfigStatement\([\s\S]*?root\.scrollIgnoreSupported\)/,
  'writeLua must omit scroll_ignore_classes on a 4-key build');
assert.match(core, /enabled: root\.scrollIgnoreSupported/,
  'mode buttons must disable when the compositor lacks the ignore key');
assert.match(core, /scrollFeelConfigured: scrollFeelConfigured,\s*scrollIgnoreMode: scrollIgnoreMode,\s*scrollAccelProfile: scrollAccelProfile/,
  'savePrefs must persist the scroll fields');
assert.match(core, /scrollDecel: saved\.scrollDecel,/, 'currentSettings must include scroll values for profiles');

// "Config like macOS" bundle: one click must flip every macOS-style toggle
// on, mark the trackpad feel configured (writeLua persistence gate), apply
// the Adaptive preset and the browsers ignore mode — all live.
assert.match(core, /function applyMacOSConfig\(\) \{\s*root\.setNaturalScroll\(true, true\)/,
  'macOS config must start with natural scroll (quiet)');
for (const fn of ['setTapToClick\\(true\\)', 'setDisableWhileTyping\\(true\\)',
  'setClickfingerBehavior\\(true\\)', 'setSwipe3\\(true\\)', 'setMiddleBtnOff\\(true\\)',
  'setInertia\\(true\\)', 'applyAnimations\\(true\\)', 'animSet\\(true\\)'])
  assert.match(core, new RegExp('applyMacOSConfig[\\s\\S]*?root\\.' + fn),
    'macOS config must call ' + fn);
assert.match(core, /applyMacOSConfig[\s\S]*?root\.trackpadFeelConfigured = true\s*root\.saved\.trackpadFeelConfigured = true/,
  'macOS config must mark the trackpad feel configured so writeLua persists it');
assert.match(core, /applyMacOSConfig[\s\S]*?root\.selectScrollPreset\("adaptive"\)/,
  'macOS config must apply the Adaptive scroll preset');
assert.match(core, /applyMacOSConfig[\s\S]*?root\.updateScrollIgnoreMode\("browsers", true\)/,
  'macOS config must keep browsers/terminals inertia excepted');
assert.match(core, /if \(root\.scrollPatchSupported\) \{\s*root\.selectScrollPreset\("adaptive"\)/,
  'scroll part of the macOS config must be gated on the patch probe');
assert.match(core, /onClicked: root\.applyMacOSConfig\(\)/,
  'macOS config button must call the bundle');

const keys = [
  'scrollFeelDevHint', 'scrollFeelTitle', 'scrollFeelSupported', 'scrollFeelUnsupported',
  'scrollFeelNative', 'scrollFeelLinear', 'scrollFeelAdaptive', 'scrollFeelGlide', 'scrollFeelCustom',
  'scrollFeelDescriptionNative', 'scrollFeelDescriptionLinear', 'scrollFeelDescriptionAdaptive',
  'scrollFeelDescriptionGlide', 'scrollFeelDescriptionCustom',
  'scrollFeelSpeed', 'scrollFeelSpeedGentle', 'scrollFeelSpeedBalanced', 'scrollFeelSpeedResponsive',
  'scrollFeelSpeedAggressive', 'scrollFeelMax', 'scrollFeelMaxMild', 'scrollFeelMaxModerate',
  'scrollFeelMaxStrong', 'scrollFeelMaxExtreme', 'scrollFeelCoast', 'scrollFeelCoastOff', 'scrollFeelApplied',
  'scrollIgnoreLabel', 'scrollIgnoreOff', 'scrollIgnoreBrowsers', 'scrollIgnoreNative',
  'scrollIgnoreHint', 'scrollIgnoreApplied', 'scrollIgnoreUnsupported',
  'macConfig', 'macConfigHint', 'macConfigApplied'
];
for (const lang of ['en', 'es'])
  for (const key of keys) assert.ok(i18n[lang][key], `${lang}.${key} missing`);
for (const lang of Object.keys(i18n))
  assert.ok(i18n[lang].scrollFeelDevHint, `${lang}.scrollFeelDevHint missing`);
for (const lang of Object.keys(i18n))
  assert.ok(i18n[lang].scrollFeelDevRepo, `${lang}.scrollFeelDevRepo missing`);

console.log('Scroll feel UI contract tests passed');
