const assert = require("assert");
const fs = require("fs");
const path = require("path");

const desktop = path.join(__dirname, "..", "desktop");
const core = fs.readFileSync(path.join(desktop, "Core.qml"), "utf8");
const shell = fs.readFileSync(path.join(desktop, "shell.qml"), "utf8");
const i18n = JSON.parse(fs.readFileSync(path.join(desktop, "i18n.json"), "utf8"));

// The Displays border must follow the window: a hidden window is not "opened".
assert.match(shell, /Core \{[\s\S]*?opened: win\.visible/);
assert.match(core, /selectedName: root\.opened && root\.currentTab === 2/);

// Brightness slider: 0..100 through Omarchy's helper, no OSD, per monitor.
assert.match(core, /label: root\.t\(root\.uiLang, "displayBrightness"\)[\s\S]*?from: 0\s*\n\s*to: 100/);
assert.match(core, /\["omarchy-brightness-display", "--no-osd",\s*"--monitor", root\.displayBrightnessFor, pct \+ "%"\]/);
assert.match(core, /\["omarchy-brightness-display", "--monitor", name\]/);
// Writes are serialized so the last slider position always lands.
assert.match(core, /if \(!displayBrightnessWrite\.running\) root\.flushDisplayBrightness\(\)/);
assert.match(core, /id: displayBrightnessWrite\s*\n\s*onExited: root\.flushDisplayBrightness\(\)/);

for (const lang of Object.keys(i18n)) {
  assert.ok(i18n[lang].displayBrightness, `missing displayBrightness in ${lang}`);
}

console.log("Display brightness and overlay lifecycle tests passed");
