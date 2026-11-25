// Scroll feel in plugin mode (stock Hyprland + omarchy-hyprland-inertia).
const fs = require('node:fs');
const vm = require('node:vm');
const os = require('node:os');
const path = require('node:path');
const assert = require('node:assert/strict');
const { spawnSync } = require('node:child_process');

const source = fs.readFileSync(path.join(__dirname, '../desktop/ScrollFeelModel.js'), 'utf8')
  .replace(/^\.pragma library\s*/m, '');
const m = { Math, Number, String, Array, Object, JSON, isFinite };
vm.createContext(m);
vm.runInContext(source, m);

// Presets set only the coast length; Adaptive is the plugin default.
assert.equal(m.pluginDefaultCoast, 800);
assert.equal(m.detectPluginPreset(800), 'adaptive');
assert.equal(m.detectPluginPreset(1000), 'glide');
assert.equal(m.detectPluginPreset(0), 'native');
assert.equal(m.detectPluginPreset(650), 'custom');
assert.equal(m.pluginCoast('native', 1000), 0);
assert.equal(m.pluginCoast('browsers', 1000), 1000);
assert.equal(m.pluginCoast('off', 99999), 3000);
assert.equal(m.pluginAllApps('off'), true);
assert.equal(m.pluginAllApps('browsers'), false);
assert.equal(m.pluginAllApps('native'), false);
assert.equal(m.pluginFeelStatement(1000, true),
  'hl.config({ plugin = { inertia = { coast = 1000, all_apps = true } } })');
assert.equal(m.supportsPluginFeelFromProbe('no such option', 0), false);
assert.equal(m.supportsPluginFeelFromProbe('{"option":"plugin:inertia:coast","int":800,"set":false}', 0), true);
assert.equal(m.supportsPluginFeelFromProbe('{"option":"x"}', 1), false);

// The generated Lua: touchpad/mouse always, coast/all_apps only on 0.1.2+.
const lines = m.pluginLuaLines(true, false, 1000, false).join('\n');
const lua = ['lua5.4', 'lua', 'luajit'].find(bin => spawnSync(bin, ['-v']).status === 0);
if (lua) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'cp-lua-'));
  const run = version => {
    const script = path.join(dir, `t-${version}.lua`);
    fs.writeFileSync(script, `
local calls = {}
hl = { get_loaded_plugins = function() return {{ name = "omarchy-inertia", version = "${version}" }} end,
       config = function(t) local i = t.plugin.inertia
         calls[#calls + 1] = (i.coast and ("coast=" .. i.coast .. ",all_apps=" .. tostring(i.all_apps)))
           or ("touchpad=" .. tostring(i.touchpad) .. ",mouse=" .. tostring(i.mouse)) end }
${lines}
print(table.concat(calls, ";"))
`);
    const out = spawnSync(lua, [script], { encoding: 'utf8' });
    fs.unlinkSync(script);
    assert.equal(out.status, 0, out.stderr);
    return out.stdout.trim();
  };
  assert.equal(run('0.1.1'), 'touchpad=true,mouse=false');
  assert.equal(run('0.1.2'), 'touchpad=true,mouse=false;coast=1000,all_apps=false');
  assert.equal(run('0.2.0'), 'touchpad=true,mouse=false;coast=1000,all_apps=false');
  assert.equal(run('dev'), 'touchpad=true,mouse=false');
  fs.rmdirSync(dir);
}

// Core wiring: the card goes live in plugin mode, acceleration stays patch-only.
const core = fs.readFileSync(path.join(__dirname, '../desktop/Core.qml'), 'utf8');
assert.match(core, /readonly property bool scrollPluginMode: !scrollPatchSupported && inertiaPluginFeel/);
assert.match(core, /enabled: root\.scrollFeelLive/);
assert.match(core, /command: \["hyprctl", "getoption", "plugin:inertia:coast", "-j"\]/);
assert.match(core, /ScrollFeelModel\.pluginLuaLines\(saved\.inertia, saved\.inertiaMouse,/);
assert.equal((core.match(/visible: root\.scrollAccelProfile > 0 && !root\.scrollPluginMode/g) || []).length, 2);
assert.match(core, /if \(root\.scrollPluginMode\) \{ root\.setInertiaMouse\(!root\.inertiaMouseOn\); return \}/);

const i18n = JSON.parse(fs.readFileSync(path.join(__dirname, '../desktop/i18n.json'), 'utf8'));
for (const lang of Object.keys(i18n))
  for (const key of ['scrollFeelPluginSupported', 'scrollIgnorePluginHint', 'scrollIgnorePluginLabel', 'scrollIgnorePluginNative'])
    assert.ok(i18n[lang][key], `${lang}.${key} missing`);

console.log('Scroll feel plugin-mode tests passed');
