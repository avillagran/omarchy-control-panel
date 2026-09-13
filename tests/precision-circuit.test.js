const fs = require('node:fs');
const assert = require('node:assert/strict');
const path = require('node:path');

const qml = fs.readFileSync(path.join(__dirname, '../desktop/PrecisionCircuit.qml'), 'utf8');
assert.match(qml, /Canvas\s*\{/);
assert.match(qml, /quadraticCurveTo/,
  'the circuit should be a curved multi-direction route, not a straight lane');
assert.match(qml, /Repeater\s*\{[\s\S]*model:\s*PointerFeelModel\.practicePointCount\(\)/);
assert.match(qml, /rotation:\s*45/,
  'route checkpoints should use an original diamond motif');
assert.match(qml, /signal hit\(\)/);
assert.match(qml, /onClicked:\s*circuit\.hit\(\)/);
assert.doesNotMatch(qml, /Target practice|A steady precision range|Slow and precise|macOS/i);

console.log('PrecisionCircuit tests passed');