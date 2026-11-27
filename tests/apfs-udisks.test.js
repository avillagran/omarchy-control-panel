// APFS disks mount through udisks with a fixed argv: no privileged shell
// strings, no package manager, external disk labels shown as plain text.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const core = fs.readFileSync(path.join(__dirname, '../desktop/Core.qml'), 'utf8');

assert.match(core, /\["udisksctl", "mount", "--block-device", device\]/);
assert.match(core, /\["udisksctl", "unmount", "--block-device", device\]/);
assert.match(core, /function apfsDevice\(dev\)[\s\S]*?root\.apfsList\[i\]\.path === dev/,
  'only devices the probe listed can be mounted');
assert.doesNotMatch(core, /pkexec bash|\/etc\/fstab|yay -S|sudo (depmod|modprobe)/);
assert.match(core, /Qt\.openUrlExternally\("https:\/\/aur\.archlinux\.org\/packages\/linux-apfs-rw-dkms"\)/);
assert.match(core, /modelData\.label[\s\S]{0,200}textFormat: Text\.PlainText/);
console.log('APFS udisks tests passed');
