const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');
const { spawnSync } = require('node:child_process');
const { test } = require('node:test');
const project = path.resolve(__dirname, '..');

function model(name) {
  const context = vm.createContext({});
  const source = fs.readFileSync(path.join(project, 'desktop', name + '.js'), 'utf8');
  vm.runInContext(source.replace(/^\.pragma library\s*/m, ''), context);
  return context;
}

// Run actual QML JavaScript methods; stub only the compositor/file-I/O boundary.
function panel(file) {
  const source = fs.readFileSync(path.join(project, file), 'utf8');
  const context = vm.createContext({
    Qt: { resolvedUrl: value => ({ toString: () => 'file:///fixture/' + value }), callLater() {} },
    Quickshell: { execDetached: args => context.calls.push(args) },
    calls: [],
    WorkspaceModel: model('WorkspaceModel'),
    ScrollFeelModel: model('ScrollFeelModel'),
    PointerFeelModel: model('PointerFeelModel'),
    luaWriter: {}, prefsWriter: {},
    prefsFile: { setText: value => { context.writtenPrefs = value; } },
  });
  context.root = context;
  for (const match of source.matchAll(/property (?:bool|real|int|string|var) (\w+): ([^\n]+)/g)) {
    context[match[1]] = undefined;
    try { context[match[1]] = vm.runInContext('(' + match[2] + ')', context); } catch {}
  }
  context.saved = vm.runInContext(source.match(/property var saved: (\(\{[\s\S]*?\}\))/)[1], context);
  Object.assign(context, { prefsLoaded: true, opened: false, allMiceNames: [], displays: [],
    prefsPath: '/fixture/prefs.json', luaPath: '/fixture/settings.lua', binDir: '/fixture/bin' });
  for (const name of ['loadPrefs', 'savePrefs', 'writeLua', 'applySuperWBind']) {
    const method = source.match(new RegExp('  function ' + name + '\\([^)]*\\) \\{[\\s\\S]*?\\n  \\}'));
    if (method) vm.runInContext(method[0], context);
  }
  return context;
}

for (const file of ['Panel.qml', 'desktop/Core.qml']) {
  test(file + ': settings save preserves SUPER+W opt-out', () => {
    const context = panel(file);
    context.loadPrefs(JSON.stringify({ manageSuperW: false, browserCloseTab: true,
      singleMonitorWorkspaces: 10, multiMonitorWorkspaces: 5 }));
    context.savePrefs();
    const output = context.writtenPrefs || context.prefsWriter.command[3];
    assert.equal(JSON.parse(output).manageSuperW, false);
    assert.equal(context.calls.length, 0, 'opening disabled settings must not apply the shortcut');
  });
}

test('legacy settings writer preserves mouse controls without taking SUPER+W', () => {
  const context = panel('Panel.qml');
  context.manageSuperW = false;
  context.saved.sensitivity = 0.7;
  context.writeLua();
  const lua = context.luaWriter.command[3];
  assert.match(lua, /sensitivity = 0\.70/);
  assert.doesNotMatch(lua, /hl\.(?:un)?bind\("SUPER \+ W"/);
  context.manageSuperW = true;
  context.writeLua();
  assert.match(context.luaWriter.command[3], /hl\.bind\("SUPER \+ W"/);
});

test('startup and forced helper calls respect persisted ownership', () => {
  const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'ocp-superw-'));
  try {
    const state = path.join(scratch, '.local/state/omarchy');
    fs.mkdirSync(state, { recursive: true });
    const bin = path.join(scratch, 'bin');
    fs.mkdirSync(bin);
    const capture = path.join(scratch, 'calls');
    fs.writeFileSync(path.join(bin, 'hyprctl'), '#!/bin/sh\nprintf "%s\\n" "$*" >> "$CAPTURE"\ncase "$1" in binds) echo "[]";; eval) echo ok;; esac\n', { mode: 0o755 });
    const prefs = path.join(state, 'control-panel-prefs.json');
    for (const ownership of [false, true, undefined]) {
      fs.writeFileSync(prefs, JSON.stringify({ manageSuperW: ownership, browserCloseTab: true }));
      for (const argument of [[], ['true'], ['false']]) {
        fs.rmSync(capture, { force: true });
        const result = spawnSync('bash', [path.join(project, 'bin/apply-superw-bind'), ...argument], {
          env: { ...process.env, HOME: scratch, XDG_CONFIG_HOME: path.join(scratch, '.config'), PATH: bin + ':' + process.env.PATH, CAPTURE: capture }, encoding: 'utf8'
        });
        assert.equal(result.status, 0, result.stderr);
        assert.equal(fs.existsSync(capture), ownership !== false,
          `manageSuperW=${ownership}, args=${argument}: unexpected compositor access`);
      }
    }
  } finally { fs.rmSync(scratch, { recursive: true, force: true }); }
});

test('an installed Reprieve binding takes precedence over default ownership', () => {
  const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'ocp-reprieve-'));
  try {
    const config = path.join(scratch, '.config/hypr');
    fs.mkdirSync(config, { recursive: true });
    fs.writeFileSync(path.join(config, 'bindings.lua'), '-- BEGIN tech.greyforge.reprieve\no.bind("SUPER + W", "Park window (Reprieve)", "reprieve park")\n-- END tech.greyforge.reprieve\n');
    const bin = path.join(scratch, 'bin'); fs.mkdirSync(bin);
    const capture = path.join(scratch, 'calls');
    fs.writeFileSync(path.join(bin, 'hyprctl'), '#!/bin/sh\necho "$*" >> "$CAPTURE"\necho ok\n', { mode: 0o755 });
    for (const argument of [[], ['true'], ['false']]) {
      const result = spawnSync('bash', [path.join(project, 'bin/apply-superw-bind'), ...argument], {
        env: { ...process.env, HOME: scratch, XDG_CONFIG_HOME: path.join(scratch, '.config'), PATH: bin + ':' + process.env.PATH, CAPTURE: capture }, encoding: 'utf8'
      });
      assert.equal(result.status, 0, result.stderr);
      assert.equal(fs.existsSync(capture), false, 'control panel displaced Reprieve');
    }
  } finally { fs.rmSync(scratch, { recursive: true, force: true }); }
});
