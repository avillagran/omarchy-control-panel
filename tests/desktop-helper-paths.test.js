const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
for (const name of ['BackupPage.qml', 'Core.qml']) {
    const source = fs.readFileSync(path.join(__dirname, '../desktop', name), 'utf8');
    assert.equal(/Qt\.resolvedUrl\("\.\.\//.test(source), false, `${name}: parent helpers must use physical shellDir, not intercepted QML URLs`);
}
const core = fs.readFileSync(path.join(__dirname, '../desktop/Core.qml'), 'utf8');
assert.equal(/Qt\.resolvedUrl\("bin\//.test(core), false,
  'Core helpers must not depend on the marketplace-forbidden desktop/bin symlink');
assert.equal(/root\.pluginDir \+ "\/bin\//.test(core), false,
  'Core helper paths must resolve from the physical parent bin directory');
assert.equal(fs.existsSync(path.join(__dirname, '../desktop/bin')), false,
  'plugin package must not contain symlinks');
for (const entry of fs.readdirSync(path.join(__dirname, '../desktop'))) {
  assert.equal(fs.lstatSync(path.join(__dirname, '../desktop', entry)).isSymbolicLink(), false,
    `desktop/${entry} must not be a symlink`);
}
console.log('Desktop helper path regression checks passed');
