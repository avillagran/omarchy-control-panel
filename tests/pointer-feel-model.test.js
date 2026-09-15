const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const path = require('node:path');

const source = fs.readFileSync(path.join(__dirname, '../desktop/PointerFeelModel.js'), 'utf8')
  .replace(/^\.pragma library\s*/m, '');
const context = { Math, Number, String, Array, Object, JSON, isFinite };
vm.createContext(context);
vm.runInContext(source, context);
const plain = value => JSON.parse(JSON.stringify(value));

assert.deepEqual(plain(context.presetIds()), ['system', 'flat', 'mac', 'custom']);
assert.deepEqual(plain(context.preset('system')), { sensitivity: 0, scrollFactor: 1, accelProfile: 'adaptive' });
assert.deepEqual(plain(context.preset('flat')), { sensitivity: 0, scrollFactor: 1, accelProfile: 'flat' });
assert.deepEqual(plain(context.preset('mac')), { sensitivity: 0.3, scrollFactor: 0.2, accelProfile: 'adaptive' });
assert.equal(context.preset('custom'), null);
assert.equal(context.clampSensitivity(-3), -1);
assert.equal(context.clampSensitivity(3), 1);
assert.equal(context.clampSensitivity(0.123), 0.1);
assert.equal(context.clampScrollFactor(0), 0.01);
assert.equal(context.clampScrollFactor(5), 1);
assert.equal(context.clampScrollFactor(0.873), 0.87);
assert.equal(context.detectPreset(0, 1, 'adaptive'), 'system');
assert.equal(context.detectPreset(-0.15, 0.65, 'adaptive'), 'custom');
assert.equal(context.detectPreset(0, 1, 'flat'), 'flat');
assert.equal(context.pointerLabel(-0.7), 'pointerFeelVeryControlled');
assert.equal(context.pointerLabel(0), 'pointerFeelNeutral');
assert.equal(context.pointerLabel(0.8), 'pointerFeelVeryFast');
assert.equal(context.scrollLabel(0.3), 'pointerFeelScrollSoft');
assert.equal(context.scrollLabel(1.6), 'pointerFeelScrollNatural');
assert.equal(context.luaDeviceStatement('apple "pad"', 0.15, 0.9, 'adaptive'),
  'hl.device({ name = "apple \\"pad\\"", sensitivity = 0.15, scroll_factor = 0.90, accel_profile = "adaptive" })');
assert.equal(context.luaDeviceStatement('bad\nname', 0, 1, 'adaptive'), '');
assert.equal(context.luaDeviceStatement('pad', 0, 1, 'custom evil'), '');
assert.equal(context.practicePointCount(), 8);
assert.deepEqual(plain(context.practicePoint(0)), { x: 0.1, y: 0.5 });
assert.deepEqual(plain(context.practicePoint(1)), { x: 0.76, y: 0.14 });
assert.deepEqual(plain(context.practicePoint(7)), { x: 0.5, y: 0.08 });
assert.deepEqual(plain(context.practicePoint(8)), { x: 0.1, y: 0.5 });
assert.deepEqual(plain(context.practicePoint(-1)), { x: 0.5, y: 0.08 });

console.log('PointerFeelModel tests passed');
