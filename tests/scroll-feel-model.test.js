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
  'hl.config({ input = { touchpad = { scroll_accel_profile = 2, scroll_accel_speed = 1.00, scroll_accel_max = 3.00, scroll_decel = 600 } } })');
assert.equal(context.luaConfigStatement(0, 1.0, 3.0, 0),
  'hl.config({ input = { touchpad = { scroll_accel_profile = 0, scroll_accel_speed = 1.00, scroll_accel_max = 3.00, scroll_decel = 0 } } })');
// out-of-range profile must never produce a broken literal
assert.equal(context.luaConfigStatement(7, 1.0, 3.0, 600), '');
assert.match(context.luaConfigStatement(2, 1.234, 3.0, 600), /scroll_accel_speed = 1\.25/);

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
  '{"option":"input:touchpad:scroll_decel","set":true,"int":900}'
].join('\n');
assert.deepEqual(plain(context.parseLiveValues(lines)),
  { profile: 1, speed: 1.4, max: 4.5, decel: 900 });
// unknown keys / garbage lines fall back to the patch defaults
assert.deepEqual(plain(context.parseLiveValues('Invalid option\n')),
  { profile: 2, speed: 1.0, max: 3.0, decel: 600 });

console.log('ScrollFeelModel tests passed');
