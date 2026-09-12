const fs = require("fs")
const vm = require("vm")
const assert = require("assert")
const path = require("path")

const source = fs.readFileSync(path.join(__dirname, "../desktop/ProfileModel.js"), "utf8")
  .replace(/^\.pragma library\s*/m, "")
const context = { JSON, String, Array, Object }
vm.createContext(context)
vm.runInContext(source, context)
const plain = value => JSON.parse(JSON.stringify(value))

const builtins = [
  { id: "default", name: "Default", builtin: true, settings: { cursorSize: 24 } },
  { id: "retina", name: "Retina", builtin: true, settings: { cursorSize: 42 } }
]
const old = [
  { id: "default", name: "stale", builtin: true, settings: {} },
  { id: "personal-1", name: "Mac", builtin: false, settings: { cursorSize: 30 } }
]
const merged = context.mergeBuiltins(builtins, old)
assert.deepStrictEqual(plain(merged.map(p => p.id)), ["default", "retina", "personal-1"])
assert.strictEqual(merged[0].settings.cursorSize, 24)

const allSettings = {
  displays: { "eDP-1": { scale: 2 } }, sensitivity: 0.7, cursorSize: 42,
  naturalScroll: true, tapToClick: true, swipe3: true, inertia: true,
  animations: true, wsAnimation: true, gapsIn: 6, gapsOut: 10,
  kbLayout: "latam", singleMonitorWorkspaces: 10, multiMonitorWorkspaces: 5
}
const created = context.create(merged, "", "Personal", allSettings, 100)
assert.strictEqual(created.id, "personal-100")
assert.strictEqual(created.profiles.length, 4)
assert.deepStrictEqual(plain(created.profiles[3].settings), allSettings)
allSettings.cursorSize = 12
assert.strictEqual(created.profiles[3].settings.cursorSize, 42, "settings must be deep-cloned")

const duplicated = context.duplicate(created.profiles, "retina", " (copy)", 101)
assert.strictEqual(duplicated.id, "personal-101")
assert.strictEqual(duplicated.profiles[4].name, "Retina (copy)")
assert.deepStrictEqual(plain(duplicated.profiles[4].settings), { cursorSize: 42 })

const saved = context.saveSettings(duplicated.profiles, "personal-101", { cursorSize: 55, gapsIn: 8 })
assert.strictEqual(saved.found, true)
assert.deepStrictEqual(plain(saved.profiles[4].settings), { cursorSize: 55, gapsIn: 8 })

const renamedBuiltin = context.rename(saved.profiles, "default", "Broken")
assert.strictEqual(renamedBuiltin.found, false)
const renamed = context.rename(saved.profiles, "personal-101", "Windows-like")
assert.strictEqual(renamed.found, true)
assert.strictEqual(renamed.profiles[4].name, "Windows-like")

assert.strictEqual(context.remove(renamed.profiles, "default").length, renamed.profiles.length)
assert.strictEqual(context.remove(renamed.profiles, "personal-101").length, renamed.profiles.length - 1)

console.log("ProfileModel tests passed")
