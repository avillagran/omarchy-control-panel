const fs = require("fs")
const vm = require("vm")
const assert = require("assert")
const path = require("path")

const source = fs.readFileSync(path.join(__dirname, "../desktop/WorkspaceModel.js"), "utf8")
  .replace(/^\.pragma library\s*/m, "")
const context = { Math, Number, String, Array, Object, isFinite }
vm.createContext(context)
vm.runInContext(source, context)

const displays = [
  { name: "HDMI-A-1", x: 1920, y: 0 },
  { name: "eDP-1", x: 0, y: 0 }
]
assert.strictEqual(context.colorRoleForMonitor("eDP-1", displays, {}), "accent")
assert.strictEqual(context.colorRoleForMonitor("HDMI-A-1", displays, {}), "green")
assert.strictEqual(context.colorRoleForMonitor("eDP-1", displays, { "eDP-1": "red" }), "red")
assert.strictEqual(context.colorRoleForMonitor("eDP-1", displays, { "eDP-1": "#f7768e" }), "red")
assert.strictEqual(context.colorRoleForMonitor("eDP-1", displays, { "eDP-1": "not-a-color" }), "accent")
assert.strictEqual(context.explicitColorRoleForMonitor("eDP-1", {}), "")
assert.strictEqual(context.explicitColorRoleForMonitor("eDP-1", { "eDP-1": "bright_magenta" }), "bright_magenta")
assert.strictEqual(context.explicitColorRoleForMonitor("eDP-1", { "eDP-1": "not-a-color" }), "")

const visual = context.workspaceVisualMap(displays, 10, 5, { "HDMI-A-1": "#e0af68" })
assert.deepStrictEqual(JSON.parse(JSON.stringify(visual["1"])), { monitor: "eDP-1", colorRole: "accent" })
assert.deepStrictEqual(JSON.parse(JSON.stringify(visual["5"])), { monitor: "eDP-1", colorRole: "accent" })
assert.deepStrictEqual(JSON.parse(JSON.stringify(visual["6"])), { monitor: "HDMI-A-1", colorRole: "yellow" })
assert.deepStrictEqual(JSON.parse(JSON.stringify(visual["10"])), { monitor: "HDMI-A-1", colorRole: "yellow" })
console.log("WorkspaceModel tests passed")