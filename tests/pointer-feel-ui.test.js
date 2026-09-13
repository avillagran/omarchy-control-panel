const fs = require('node:fs');
const assert = require('node:assert/strict');
const path = require('node:path');

const core = fs.readFileSync(path.join(__dirname, '../desktop/Core.qml'), 'utf8');
const i18n = JSON.parse(fs.readFileSync(path.join(__dirname, '../desktop/i18n.json'), 'utf8'));

assert.match(core, /import "PointerFeelModel\.js" as PointerFeelModel/);
for (const property of ['trackpadSensitivity', 'trackpadScrollFactor', 'trackpadAccelProfile', 'disableWhileTyping', 'clickfingerBehavior'])
  assert.match(core, new RegExp(`property (?:real|bool|string) ${property}:`), `${property} state missing`);
assert.match(core, /function stagePointerFeel\(/);
assert.match(core, /function applyPointerFeel\(/);
assert.match(core, /function restorePointerFeel\(/);
assert.match(core, /function resetPointerFeel\(/);
assert.match(core, /property bool pointerFeelReady:\s*root\.prefsLoaded\s*&&\s*root\.readProcDone\s*&&\s*root\.luaStateProcDone/,
  'trackpad controls must remain inert until all startup state is loaded');
assert.match(core, /if \(!root\.pointerFeelReady\) return/,
  'trackpad setters must reject first-load interaction races');
assert.match(core, /configured:\s*root\.saved\.trackpadFeelConfigured/,
  'restore snapshot must preserve whether per-device overrides existed');
assert.match(core, /previous\.configured\s*\?\s*root\.applyPointerFeel\(\)\s*:\s*root\.resetPointerFeel\(/,
  'restore must be able to remove a newly-created per-device override');
assert.match(core, /s\.trackpadFeelConfigured\s*===\s*true[\s\S]*else if \(s\.trackpadFeelConfigured\s*===\s*false\) root\.resetPointerFeel/,
  'Default profile must reset, not enable, trackpad overrides');
assert.match(core, /label:\s*root\.t\(root\.uiLang,\s*"globalFlatAccel"\)/,
  'legacy global acceleration control must not claim to describe the per-device trackpad preset');
assert.match(core, /PointerFeelModel\.luaDeviceStatement/,
  'touchpad feel must be persisted as safe per-device literals');
assert.match(core, /model: PointerFeelModel\.presetIds\(\)/,
  'preset selector missing');
assert.match(core, /property int practiceHits:/,
  'in-panel pointer practice missing');
assert.match(core, /PrecisionCircuit\s*\{/,
  'the original multi-direction precision circuit must be embedded');
assert.match(core, /practiceTargetIndex\s*=\s*\(root\.practiceTargetIndex\s*\+\s*1\)\s*%\s*PointerFeelModel\.practicePointCount\(\)/,
  'practice target must traverse the complete non-linear circuit');
assert.doesNotMatch(core, /property var positions:\s*\[0\.12,\s*0\.72/,
  'the previous straight accuracy lane must be removed');
assert.match(core, /disable_while_typing/);
assert.match(core, /clickfinger_behavior/);
assert.doesNotMatch(core, /Mac-inspired|A steady precision range|Target practice/,
  'reference wording/design must not be copied');

const keys = [
  'pointerFeelTitle', 'pointerFeelDevice', 'pointerFeelFine', 'pointerFeelBalanced',
  'pointerFeelSwift', 'pointerFeelLinear', 'pointerFeelCustom', 'pointerFeelDescriptionFine',
  'pointerFeelDescriptionBalanced', 'pointerFeelDescriptionSwift', 'pointerFeelDescriptionLinear',
  'pointerFeelDescriptionCustom', 'pointerFeelPointer', 'pointerFeelScroll', 'pointerFeelApply',
  'pointerFeelRestore', 'pointerFeelPractice', 'pointerFeelPracticeHint', 'pointerFeelHit', 'pointerFeelHits', 'disableWhileTyping',
  'twoFingerRightClick'
];
for (const lang of ['en', 'es'])
  for (const key of keys) assert.ok(i18n[lang][key], `${lang}.${key} missing`);

console.log('Pointer feel UI contract tests passed');
