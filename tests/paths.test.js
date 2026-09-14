// Regression test: every helper referenced through `root.binDir + "/..."`
// in desktop/Core.qml must exist under bin/. A wrong path fails silently at
// runtime (empty picker models, dead buttons) — this is how the system
// language selector shipped empty in 0.2.
const fs = require('node:fs');
const assert = require('node:assert/strict');
const path = require('node:path');

const root = path.join(__dirname, '..');
const core = fs.readFileSync(path.join(root, 'desktop/Core.qml'), 'utf8');

const refs = new Set();
for (const m of core.matchAll(/binDir\s*\+\s*"\/([^"]+)"/g)) {
  const name = m[1].match(/^[A-Za-z0-9._-]+/);
  if (name) refs.add(name[0]);
}
assert.ok(refs.size >= 5, `expected several binDir references, found ${refs.size}`);

const missing = [...refs].filter(f => !fs.existsSync(path.join(root, 'bin', f)));
assert.deepEqual(missing, [], `binDir-referenced files missing from bin/: ${missing.join(', ')}`);

// The locale picker source script must exist AND emit the "value\tinstalled"
// rows the Core.qml parser expects; guard against shipping an empty model.
const { execSync } = require('node:child_process');
const out = execSync(`bash ${path.join(root, 'bin/locale-list.sh')}`).toString();
const rows = out.split('\n').filter(l => l.split('\t').length >= 2);
assert.ok(rows.length > 100, `locale-list.sh returned only ${rows.length} rows`);

console.log(`paths.test.js OK (${refs.size} binDir refs, ${rows.length} locales)`);
