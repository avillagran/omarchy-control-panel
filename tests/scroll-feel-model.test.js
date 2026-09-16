const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const path = require('node:path');

const source = fs.readFileSync(path.join(__dirname, '../desktop/ScrollFeelModel.js'), 'utf8')
  .replace(/^\.pragma library\s*/m, '');
const context = { Math, Number, String, Array, Object, JSON, isFinite };
vm.createContext(context);
vm.runInContext(source, context);
const plain = value => JSON.parse(JSON.stringify(value));

assert.deepEqual(plain(context.presetIds()), ['native', 'linear', 'adaptive', 'glide']);
assert.deepEqual(plain(context.preset('native')), { profile: 0, speed: 1.0, max: 3.0, decel: 0 });
assert.deepEqual(plain(context.preset('adaptive')), { profile: 2, speed: 1.0, max: 3.0, decel: 600 });
assert.equal(context.preset('missing'), null);

assert.equal(context.clampProfile(-1), 0);
assert.equal(context.clampProfile(2), 2);
assert.equal(context.clampProfile(9), 2);
assert.equal(context.clampProfile('x'), 2);
assert.equal(context.clampSpeed(0), 0.2);
assert.equal(context.clampSpeed(5), 3.0);
assert.equal(context.clampSpeed(0.873), 0.85);
assert.equal(context.clampMax(0), 1.0);
assert.equal(context.clampMax(99), 10.0);
assert.equal(context.clampMax(2.33), 2.25);
assert.equal(context.clampDecel(-10), 0);
assert.equal(context.clampDecel(9999), 3000);
assert.equal(context.clampDecel(623), 600);

assert.equal(context.detectPreset(0, 1.0, 3.0, 0), 'native');
assert.equal(context.detectPreset(1, 1.0, 3.0, 300), 'linear');
assert.equal(context.detectPreset(2, 1.0, 3.0, 600), 'adaptive');
assert.equal(context.detectPreset(2, 1.3, 4.0, 1000), 'glide');
assert.equal(context.detectPreset(2, 1.0, 3.0, 500), 'custom');

assert.equal(context.speedLabel(0.4), 'scrollFeelSpeedGentle');
assert.equal(context.speedLabel(1.0), 'scrollFeelSpeedBalanced');
assert.equal(context.speedLabel(1.5), 'scrollFeelSpeedResponsive');
assert.equal(context.speedLabel(2.5), 'scrollFeelSpeedAggressive');
assert.equal(context.maxLabel(1.5), 'scrollFeelMaxMild');
assert.equal(context.maxLabel(3.0), 'scrollFeelMaxModerate');
assert.equal(context.maxLabel(5.0), 'scrollFeelMaxStrong');
assert.equal(context.maxLabel(8.0), 'scrollFeelMaxExtreme');

assert.equal(context.luaConfigStatement(2, 1.0, 3.0, 600),
  'hl.config({ input = { touchpad = { scroll_accel_profile = 2, scroll_accel_speed = 1.00, scroll_accel_max = 3.00, scroll_decel = 600, scroll_ignore_classes = "" } } })');
assert.equal(context.luaConfigStatement(0, 1.0, 3.0, 0),
  'hl.config({ input = { touchpad = { scroll_accel_profile = 0, scroll_accel_speed = 1.00, scroll_accel_max = 3.00, scroll_decel = 0, scroll_ignore_classes = "" } } })');
// out-of-range profile must never produce a broken literal
assert.equal(context.luaConfigStatement(7, 1.0, 3.0, 600), '');
assert.match(context.luaConfigStatement(2, 1.234, 3.0, 600), /scroll_accel_speed = 1\.25/);
// ignore-class list is emitted verbatim (composer-managed, no user input)
assert.match(context.luaConfigStatement(2, 1.0, 3.0, 600, 'kitty,chromium'),
  /scroll_ignore_classes = "kitty,chromium"/);

// ignore modes: off = patch everywhere, browsers = keep native inertia in
// apps that have their own (browsers + terminals like kitty), native = off.
assert.deepEqual(plain(context.ignoreModes), ['off', 'browsers', 'native']);
assert.equal(context.clampIgnoreMode('off'), 'off');
assert.equal(context.clampIgnoreMode('native'), 'native');
assert.equal(context.clampIgnoreMode('garbage'), 'browsers');
assert.match(context.ignoreClassesBrowsers, /chromium/);
assert.match(context.ignoreClassesBrowsers, /firefox/);
assert.match(context.ignoreClassesBrowsers, /kitty/);
assert.equal(context.ignoreModeLabelKey('off'), 'scrollIgnoreOff');
assert.equal(context.ignoreModeLabelKey('browsers'), 'scrollIgnoreBrowsers');
assert.equal(context.ignoreModeLabelKey('native'), 'scrollIgnoreNative');
assert.equal(context.ignoreModeLabelKey('?'), 'scrollIgnoreBrowsers');
assert.equal(context.ignoreListForMode('off'), '');
assert.match(context.ignoreListForMode('browsers'), /kitty/);
assert.equal(context.ignoreListForMode('native'), '');
assert.equal(context.profileForMode('native', 2), 0);
assert.equal(context.profileForMode('browsers', 2), 2);
assert.equal(context.profileForMode('off', 1), 1);
assert.equal(context.modeFromLive(0, ''), 'native');
assert.equal(context.modeFromLive(2, ''), 'off');
assert.equal(context.modeFromLive(2, 'google-chrome,chromium,kitty'), 'browsers');
assert.equal(context.modeFromLive(2, 'something-custom'), 'browsers');

// capability probe: only a JSON success for the patch key counts
assert.equal(context.supportsPatchFromProbe('{"option":"input:touchpad:scroll_decel","set":true,"int":600}', 0), true);
assert.equal(context.supportsPatchFromProbe('', 1), false);
assert.equal(context.supportsPatchFromProbe('Invalid option', 0), false);
assert.equal(context.supportsPatchFromProbe('{"option":"input:touchpad:scroll_factor"}', 0), false);
assert.equal(context.supportsPatchFromProbe('not json scroll_decel', 0), false);

const lines = [
  '{"option":"input:touchpad:scroll_accel_profile","set":true,"int":1}',
  '{"option":"input:touchpad:scroll_accel_speed","set":true,"float":1.4}',
  '{"option":"input:touchpad:scroll_accel_max","set":true,"float":4.5}',
  '{"option":"input:touchpad:scroll_decel","set":true,"int":900}',
  '{"option":"input:touchpad:scroll_ignore_classes","set":true,"str":"google-chrome,kitty"}'
].join('\n');
assert.deepEqual(plain(context.parseLiveValues(lines)),
  { profile: 1, speed: 1.4, max: 4.5, decel: 900, ignoreClasses: 'google-chrome,kitty', ignoreSupported: true });
// unknown keys / garbage lines fall back to the patch defaults
assert.deepEqual(plain(context.parseLiveValues('Invalid option\n')),
  { profile: 2, speed: 1.0, max: 3.0, decel: 600, ignoreClasses: '', ignoreSupported: false });
// a 4-key build (no scroll_ignore_classes line) must parse as ignore-unsupported
assert.deepEqual(plain(context.parseLiveValues(
  '{"option":"input:touchpad:scroll_decel","set":true,"int":600}').ignoreSupported), false);
// legacy statement (includeIgnore=false) omits scroll_ignore_classes entirely
assert.equal(context.luaConfigStatement(2, 1.0, 3.0, 600, 'kitty', false),
  'hl.config({ input = { touchpad = { scroll_accel_profile = 2, scroll_accel_speed = 1.00, scroll_accel_max = 3.00, scroll_decel = 600 } } })');
assert.doesNotMatch(context.luaConfigStatement(2, 1.0, 3.0, 600, 'kitty', false), /scroll_ignore_classes/);

// Physical mouse wheels are always opt-in. The generated statement is a
// separate input:mouse block and fully disables acceleration/coasting at off.
assert.equal(context.mouseLuaConfigStatement(false, 2, 1.0, 3.0, 600),
  'hl.config({ input = { mouse = { scroll_accel_profile = 0, scroll_accel_speed = 1.00, scroll_accel_max = 3.00, scroll_decel = 0 } } })');
assert.equal(context.mouseLuaConfigStatement(true, 2, 1.0, 3.0, 600),
  'hl.config({ input = { mouse = { scroll_accel_profile = 2, scroll_accel_speed = 1.00, scroll_accel_max = 3.00, scroll_decel = 600 } } })');
assert.equal(context.mouseLuaConfigStatement(true, 7, 1.0, 3.0, 600), '');

console.log('ScrollFeelModel tests passed');
