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

// Workspace ranges follow physical display order. Moving HDMI to the left
// makes it own the first range; stacking uses y when x is equal.
const swapped = [
  { name: "HDMI-A-1", x: 0, y: 0 },     // HDMI moved to the LEFT
  { name: "eDP-1", x: 2560, y: 0 }
]
const reordered = context.workspaceVisualMap(swapped, 10, 5, {}, visual)
assert.strictEqual(reordered["1"].monitor, "HDMI-A-1", "the left display owns workspaces 1-5")
assert.strictEqual(reordered["5"].monitor, "HDMI-A-1")
assert.strictEqual(reordered["6"].monitor, "eDP-1", "the right display owns workspaces 6-10")
assert.strictEqual(reordered["10"].monitor, "eDP-1")

// This must also hold when no prior map exists.
const fresh = context.workspaceVisualMap(swapped, 10, 5, {})
assert.strictEqual(fresh["1"].monitor, "HDMI-A-1")
assert.strictEqual(fresh["6"].monitor, "eDP-1")

// A newly connected display at the right receives the final range.
const three = swapped.concat([{ name: "DP-1", x: 5120, y: 0 }])
const grown = context.workspaceVisualMap(three, 10, 5, {}, reordered)
assert.strictEqual(grown["1"].monitor, "HDMI-A-1")
assert.strictEqual(grown["6"].monitor, "eDP-1")
assert.strictEqual(grown["11"].monitor, "DP-1", "new monitor takes the next free range")
assert.strictEqual(grown["15"].monitor, "DP-1")

const stacked = [
  { name: "eDP-1", x: 180, y: 1440 },
  { name: "HDMI-A-1", x: 0, y: 0 }
]
const vertical = context.workspaceVisualMap(stacked, 10, 5, {})
assert.strictEqual(vertical["1"].monitor, "HDMI-A-1", "the top display owns the first range")
assert.strictEqual(vertical["6"].monitor, "eDP-1", "the bottom display owns the final range")
console.log("WorkspaceModel tests passed")
// An output without EDID identity (a remote or headless screen another
// program owns) gets no workspaces; rows without identity fields at all, such
// as saved profile entries, still count.
const withRemote = [
  { name: "eDP-1", make: "Apple", model: "Retina", serial: "", x: 0, y: 0 },
  { name: "gliff-4242", make: "", model: "", serial: "", x: 1728, y: 0 }
]
assert.strictEqual(context.isVirtualDisplay(withRemote[0]), false)
assert.strictEqual(context.isVirtualDisplay(withRemote[1]), true)
assert.strictEqual(context.isVirtualDisplay({ name: "HDMI-A-1", x: 0, y: 0 }), false)
// A built-in panel without EDID identity (Apple eDP-1 under Asahi) is still
// physical: the connector name decides, or display-manager's `virtual` flag.
assert.strictEqual(context.isVirtualDisplay({ name: "eDP-1", make: "", model: "", serial: "" }), false)
assert.strictEqual(context.isVirtualDisplay({ name: "HEADLESS-1", make: "", model: "", serial: "" }), true)
assert.strictEqual(context.isVirtualDisplay({ name: "eDP-1", make: "", model: "", serial: "", virtual: true }), true)
assert.strictEqual(context.isVirtualDisplay({ name: "gliff-7", make: "", model: "", serial: "", virtual: false }), false)
assert.deepStrictEqual(Array.from(context.activeMonitors(withRemote), function(d) { return d.name }), ["eDP-1"])
