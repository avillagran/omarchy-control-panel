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

assert.deepEqual(plain(context.presetIds()), ['fine', 'balanced', 'swift', 'linear']);
assert.deepEqual(plain(context.preset('fine')), { sensitivity: -0.2, scrollFactor: 0.65, accelProfile: 'adaptive' });
assert.deepEqual(plain(context.preset('balanced')), { sensitivity: 0.15, scrollFactor: 0.9, accelProfile: 'adaptive' });
assert.deepEqual(plain(context.preset('swift')), { sensitivity: 0.5, scrollFactor: 1.2, accelProfile: 'adaptive' });
assert.deepEqual(plain(context.preset('linear')), { sensitivity: 0.1, scrollFactor: 0.85, accelProfile: 'flat' });
assert.equal(context.clampSensitivity(-3), -1);
assert.equal(context.clampSensitivity(3), 1);
assert.equal(context.clampSensitivity(0.123), 0.1);
assert.equal(context.clampScrollFactor(0), 0.1);
assert.equal(context.clampScrollFactor(5), 2);
assert.equal(context.clampScrollFactor(0.873), 0.85);
assert.equal(context.detectPreset(-0.2, 0.65, 'adaptive'), 'fine');
assert.equal(context.detectPreset(-0.15, 0.65, 'adaptive'), 'custom');
assert.equal(context.detectPreset(0.1, 0.85, 'flat'), 'linear');
assert.equal(context.pointerLabel(-0.7), 'pointerFeelVeryControlled');
assert.equal(context.pointerLabel(0), 'pointerFeelNeutral');
assert.equal(context.pointerLabel(0.8), 'pointerFeelVeryFast');
assert.equal(context.scrollLabel(0.3), 'pointerFeelScrollSoft');
assert.equal(context.scrollLabel(1.6), 'pointerFeelScrollFast');
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
