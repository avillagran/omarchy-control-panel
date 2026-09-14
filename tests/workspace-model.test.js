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

// Moving a display in the layout must NOT renumber its workspaces: with a
// previous map, each monitor keeps its range regardless of position.
const swapped = [
  { name: "HDMI-A-1", x: 0, y: 0 },     // HDMI moved to the LEFT
  { name: "eDP-1", x: 2560, y: 0 }
]
const pinned = context.workspaceVisualMap(swapped, 10, 5, {}, visual)
assert.strictEqual(pinned["1"].monitor, "eDP-1", "eDP-1 must keep workspaces 1-5 after being moved right")
assert.strictEqual(pinned["5"].monitor, "eDP-1")
assert.strictEqual(pinned["6"].monitor, "HDMI-A-1", "HDMI-A-1 must keep workspaces 6-10 after being moved left")
assert.strictEqual(pinned["10"].monitor, "HDMI-A-1")

// Without a previous map the ranges follow position (first run behavior).
const fresh = context.workspaceVisualMap(swapped, 10, 5, {})
assert.strictEqual(fresh["1"].monitor, "HDMI-A-1")
assert.strictEqual(fresh["6"].monitor, "eDP-1")

// A newly connected display appends after the claimed ranges.
const three = swapped.concat([{ name: "DP-1", x: 5120, y: 0 }])
const grown = context.workspaceVisualMap(three, 10, 5, {}, pinned)
assert.strictEqual(grown["1"].monitor, "eDP-1")
assert.strictEqual(grown["6"].monitor, "HDMI-A-1")
assert.strictEqual(grown["11"].monitor, "DP-1", "new monitor takes the next free range")
assert.strictEqual(grown["15"].monitor, "DP-1")
console.log("WorkspaceModel tests passed")