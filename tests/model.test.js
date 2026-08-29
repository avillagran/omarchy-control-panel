const fs = require("fs")
const vm = require("vm")
const assert = require("assert")

const path = require("path")
const source = fs.readFileSync(path.join(__dirname, "../DisplayModel.js"), "utf8")
  .replace(/^\.pragma library\s*/m, "")
const context = { JSON, Math, Number, String, Array, Object, isFinite }
vm.createContext(context)
vm.runInContext(source, context)

assert.deepStrictEqual(Array.from(context.resolutions(["1920x1080@60", "1920x1080@144", "2560x1440@60"])), ["1920x1080", "2560x1440"])
assert.strictEqual(context.resolutionOptions(["3840x2400@59.99Hz", "3840x2400@47.99Hz"])[0].label, "3840x2400 (native)")
assert.strictEqual(context.nearestMode(["1920x1080@60", "1920x1080@144"], "1920x1080", 120), "1920x1080@144")
assert.strictEqual(context.nearestMode(["3440x1440@59.97Hz"], "3440x1440", 60), "3440x1440@59.97")
assert.deepStrictEqual(JSON.parse(JSON.stringify(context.refreshOptions(["1920x1080@60.00Hz", "1920x1080@60.00Hz", "1920x1080@59.94Hz"], "1920x1080"))), [
  { value: "60", label: "60 Hz" },
  { value: "59.94", label: "59.94 Hz" }
])
assert.deepStrictEqual(Array.from(context.resolutions(["7680x4320@30.00Hz", "5120x1440@120.00Hz", "3440x1440@59.97Hz"])), ["7680x4320", "5120x1440", "3440x1440"])
assert.strictEqual(context.logicalSize({ mode: "3840x2160@60", scale: 2, transform: 0 }).width, 1920)
assert.strictEqual(context.logicalSize({ mode: "1920x1080@60", scale: 1, transform: 1 }).width, 1080)
assert.strictEqual(context.hasOverlap([
  { mode: "1920x1080@60", scale: 1, transform: 0, x: 0, y: 0 },
  { mode: "1920x1080@60", scale: 1, transform: 0, x: 1800, y: 0 }
]), true)
assert.strictEqual(context.hasOverlap([
  { mode: "1920x1080@60", scale: 1, transform: 0, x: 0, y: 0 },
  { mode: "1920x1080@60", scale: 1, transform: 0, x: 1920, y: 0 }
]), false)
assert.deepStrictEqual(Array.from(context.validScales("1920x1080@60")), [0.5, 0.6, 2 / 3, 0.75, 0.8, 1, 1.2, 1.25, 4 / 3, 1.5, 1.6, 2, 2.5, 3, 4])
assert.ok(context.validScales("3840x2160@60").indexOf(4 / 3) >= 0)
// nearestScale: arbitrary slider values snap to the closest Hyprland-valid one.
assert.strictEqual(context.nearestScale("1920x1080@60", 1.35), 4 / 3)
assert.strictEqual(context.nearestScale("1920x1080@60", 0.52), 0.5)
assert.strictEqual(context.nearestScale("1920x1080@60", 0.58), 0.6)
assert.strictEqual(context.nearestScale("1920x1080@60", 1.0), 1)
assert.strictEqual(context.nearestScale("1920x1080@60", 3.9), 4)
assert.strictEqual(context.nearestScale("3456x2234@120", 1.9), 2)
assert.deepStrictEqual(context.normalizePositions([
  { name: "A", x: 1920, y: 100, disabled: false },
  { name: "B", x: 0, y: 0, disabled: false }
]).map(function(d) { return d.x + ":" + d.y }), ["1920:100", "0:0"])
assert.deepStrictEqual(context.canonicalMode("1920x1080@60.00"), "1920x1080@60")

// snapEdges: a display dropped near a neighbour snaps flush; a distant one
// stays put. Layout: A at 0,0 (1920x1080 logical), B dragged near A.
var snapA = { name: "A", mode: "1920x1080@60", scale: 1, transform: 0, x: 0, y: 0 }
var snapB = { name: "B", mode: "1920x1080@60", scale: 1, transform: 0, x: 1940, y: 12 }
var snapped = context.snapEdges(snapB, [snapA, snapB], 50)
assert.strictEqual(snapped.x, 1920, "should snap flush to A's right edge")
assert.strictEqual(snapped.y, 0, "should snap top edges aligned")
// Right-edge alignment: drag B so its right edge is close to A's right edge.
var snapC = { name: "C", mode: "1920x1080@60", scale: 1, transform: 0, x: 30, y: 500 }
var snappedC = context.snapEdges(snapC, [snapA, snapC], 50)
assert.strictEqual(snappedC.x, 0, "should align left edges when close")
// Below: B dropped under A snaps flush vertically.
var snapD = { name: "D", mode: "1920x1080@60", scale: 1, transform: 0, x: 100, y: 1090 }
var snappedD = context.snapEdges(snapD, [snapA, snapD], 50)
assert.strictEqual(snappedD.y, 1080, "should snap flush below A")
// Far away: no snap.
var snapFar = { name: "F", mode: "1920x1080@60", scale: 1, transform: 0, x: 5000, y: 4000 }
var snappedFar = context.snapEdges(snapFar, [snapA, snapFar], 50)
assert.strictEqual(snappedFar.x, 5000)
assert.strictEqual(snappedFar.y, 4000)
// Mirror and disabled displays are ignored as snap targets: B dragged next to
// a mirrored output must not snap to it (only to real targets).
var snapMirrorTarget = { name: "M", mode: "1920x1080@60", scale: 1, transform: 0, x: 0, y: 2000, mirror: "A" }
var snapMoving = { name: "B", mode: "1920x1080@60", scale: 1, transform: 0, x: 10, y: 2010 }
var snappedMoving = context.snapEdges(snapMoving, [snapMirrorTarget, snapMoving], 50)
assert.strictEqual(snappedMoving.x, 10, "mirror targets are skipped")
assert.strictEqual(snappedMoving.y, 2010, "mirror targets are skipped")

// closeGaps: after a scale change, a neighbour left with a small horizontal
// gap is pulled flush; far-apart displays are left where they are.
var gapA = { name: "A", mode: "1920x1080@60", scale: 1, transform: 0, x: 0, y: 0 }
var gapB = { name: "B", mode: "1920x1080@60", scale: 1, transform: 0, x: 2000, y: 0 }
var packed = context.closeGaps([gapA, gapB])
assert.strictEqual(packed[1].x, 1920, "small gap closes flush")
var farB = { name: "B", mode: "1920x1080@60", scale: 1, transform: 0, x: 5000, y: 0 }
var packedFar = context.closeGaps([gapA, farB])
assert.strictEqual(packedFar[1].x, 5000, "far apart displays stay put")
// Mirrors are never moved by closeGaps.
var gapM = { name: "M", mode: "1920x1080@60", scale: 1, transform: 0, x: 2000, y: 0, mirror: "A" }
var packedM = context.closeGaps([gapA, gapM])
assert.strictEqual(packedM[1].x, 2000, "mirror is not moved")

// reflowAroundSelected: neighbours snap flush to the reference on the side they
// occupy, never overlapping, preserving the relative arrangement.
// Side-by-side: B to the right of A ends flush at A's right edge.
var rfA = { name: "A", mode: "1920x1080@60", scale: 1, transform: 0, x: 0, y: 0 }
var rfB = { name: "B", mode: "1920x1080@60", scale: 1, transform: 0, x: 2100, y: 40 }
var rf1 = context.reflowAroundSelected([rfA, rfB], 0)
assert.strictEqual(rf1[1].x, 1920, "B snaps flush to A's right edge")
assert.strictEqual(rf1[1].y, 40, "B's vertical offset is preserved (flexible touching)")
// A display offset so far it would disconnect is clamped back to just-touching.
var rfFar = { name: "B", mode: "1920x1080@60", scale: 1, transform: 0, x: 2100, y: 1100 }
var rf1b = context.reflowAroundSelected([rfA, rfFar], 0)
assert.strictEqual(rf1b[1].x, 1920, "still flush right when far")
assert.ok(rf1b[1].y < 1080 && rf1b[1].y + 1080 > 0, "clamped so it still touches A")
// Overlap resolves: B dropped overlapping A gets pushed flush, not left overlapping.
var rfC = { name: "C", mode: "1920x1080@60", scale: 1, transform: 0, x: 100, y: 10 }
var rf2 = context.reflowAroundSelected([rfA, rfC], 0)
assert.strictEqual(context.hasOverlap(rf2), false, "no overlap after reflow")
// Stacked (vertical) arrangement is preserved: B below A stays below, flush.
var rfD = { name: "D", mode: "1920x1080@60", scale: 1, transform: 0, x: 50, y: 1200 }
var rf3 = context.reflowAroundSelected([rfA, rfD], 0)
assert.strictEqual(rf3[1].y, 1080, "B stays below A, flush")
assert.strictEqual(rf3[1].x, 50, "B's horizontal offset is preserved")
// B to the left of A snaps flush to A's left edge.
var rfE = { name: "E", mode: "1920x1080@60", scale: 1, transform: 0, x: -2100, y: 0 }
var rf4 = context.reflowAroundSelected([rfA, rfE], 0)
assert.strictEqual(rf4[1].x, -1920, "B snaps flush to A's left edge")

// resolveOverlap: a display dropped onto another is pushed out to the nearest
// flush edge; a separated (gapped) layout is left untouched.
var ovA = { name: "A", mode: "1920x1080@60", scale: 1, transform: 0, x: 0, y: 0 }
var ovB = { name: "B", mode: "1920x1080@60", scale: 1, transform: 0, x: 500, y: 0 } // overlaps A
var resolved = context.resolveOverlap([ovA, ovB], 1)
assert.ok(!context.overlap(resolved[0], resolved[1]), "overlap resolved")
assert.strictEqual(resolved[0].x, 0, "non-dragged display stays put")
// B was dropped overlapping A's right portion -> nearest flush is right of A.
assert.strictEqual(resolved[1].x, 1920, "pushed flush right of A")
assert.strictEqual(resolved[1].y, 0)

// A separated layout (intentional gap) is preserved, not closed.
var sepA = { name: "A", mode: "1920x1080@60", scale: 1, transform: 0, x: 0, y: 0 }
var sepB = { name: "B", mode: "1920x1080@60", scale: 1, transform: 0, x: 2600, y: 400 }
var kept = context.resolveOverlap([sepA, sepB], 1)
assert.strictEqual(kept[1].x, 2600, "gap preserved")
assert.strictEqual(kept[1].y, 400)

// snapDraggedFlush: only the dragged display moves; it snaps flush to the nearest
// neighbour, others stay fixed (so the panel-hosting monitor isn't reconfigured).
var sdA = { name: "A", mode: "1920x1080@60", scale: 1, transform: 0, x: 0, y: 0 }
var sdB = { name: "B", mode: "1920x1080@60", scale: 1, transform: 0, x: 5000, y: 30 }
var sd1 = context.snapDraggedFlush([sdA, sdB], 1)
assert.strictEqual(sd1[0].x, 0, "A (not dragged) does not move")
assert.strictEqual(sd1[1].x, 1920, "dragged B snaps flush to A's right edge")
assert.strictEqual(sd1[1].y, 30, "B's vertical offset preserved")
// Dropped overlapping -> snapped out to the nearest flush edge.
var sdC = { name: "C", mode: "1920x1080@60", scale: 1, transform: 0, x: 100, y: 0 }
var sd2 = context.snapDraggedFlush([sdA, sdC], 1)
assert.strictEqual(context.hasOverlap(sd2), false, "no overlap after snap")
// Dropped above -> snapped flush above.
var sdD = { name: "D", mode: "1920x1080@60", scale: 1, transform: 0, x: 40, y: -3000 }
var sd3 = context.snapDraggedFlush([sdA, sdD], 1)
assert.strictEqual(sd3[1].y, -1080, "dragged D snaps flush above A")
assert.strictEqual(sd3[0].y, 0, "A still does not move")

// sanitizeDisplays: corrupt/weird states are auto-corrected so there is always
// a working picture (extend, never blank), without asking.
var sA = { name: "A", mode: "1920x1080@60", scale: 1, transform: 0, x: 0, y: 0, disabled: false }
var sB = { name: "B", mode: "1920x1080@60", scale: 1, transform: 0, x: 1920, y: 0, disabled: false, mirror: "GHOST" }
var sz1 = context.sanitizeDisplays([sA, sB])
assert.strictEqual(sz1[1].mirror, "", "mirror to a missing target is cleared to extend")
var sC = { name: "A", mode: "1920x1080@60", scale: 1, transform: 0, x: 0, y: 0, disabled: true, mirror: "2" }
var sD = { name: "B", mode: "1920x1080@60", scale: 1, transform: 0, x: 1920, y: 0, disabled: false }
var sz2 = context.sanitizeDisplays([sC, sD])
assert.strictEqual(sz2[0].disabled, false, "disabled output with a corrupt mirror is re-enabled")
assert.strictEqual(sz2[0].mirror, "", "and its mirror is cleared (extend)")
var sE = { name: "A", mode: "1920x1080@60", scale: 1, transform: 0, x: 0, y: 0, disabled: true }
var sF = { name: "B", mode: "1920x1080@60", scale: 1, transform: 0, x: 1920, y: 0, disabled: true }
var sz3 = context.sanitizeDisplays([sE, sF])
assert.strictEqual(sz3[0].disabled, false, "all-disabled -> first output re-enabled")
var sG = { name: "A", mode: "1920x1080@60", scale: 1, transform: 0, x: 0, y: 0, disabled: false }
var sH = { name: "B", mode: "1920x1080@60", scale: 1, transform: 0, x: 1920, y: 0, disabled: false }
var sz4 = context.sanitizeDisplays([sG, sH])
assert.strictEqual(JSON.stringify(sz4), JSON.stringify([sG, sH]), "a clean extended layout is untouched")
console.log("DisplayModel tests passed")
