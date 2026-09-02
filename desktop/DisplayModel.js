.pragma library

// Pure display-layout helpers shared by the Displays tab. Kept side-effect
// free and framework-agnostic so it can be unit-tested outside Quickshell.

function clone(value) { return JSON.parse(JSON.stringify(value)) }

function modeParts(mode) {
  var match = String(mode || "").match(/^(\d+)x(\d+)@(\d+(?:\.\d+)?)/)
  return match ? { width: Number(match[1]), height: Number(match[2]), refresh: Number(match[3]) } : null
}

function resolution(mode) {
  var p = modeParts(mode)
  return p ? p.width + "x" + p.height : ""
}

function refresh(mode) {
  var p = modeParts(mode)
  return p ? String(Math.round(p.refresh * 100) / 100) : ""
}

function canonicalMode(mode) {
  var p = modeParts(mode)
  return p ? p.width + "x" + p.height + "@" + (Math.round(p.refresh * 100) / 100) : String(mode || "preferred")
}

function modesForResolution(modes, wanted) {
  return (modes || []).filter(function(mode) { return resolution(mode) === wanted })
}

function refreshOptions(modes, wanted) {
  var seen = {}, result = []
  modesForResolution(modes, wanted).forEach(function(mode) {
    var value = refresh(mode)
    if (value && !seen[value]) {
      seen[value] = true
      result.push({ value: value, label: value + " Hz" })
    }
  })
  return result
}

function resolutions(modes) {
  var seen = {}, result = []
  ;(modes || []).forEach(function(mode) {
    var value = resolution(mode)
    if (value && !seen[value]) { seen[value] = true; result.push(value) }
  })
  return result
}

function resolutionOptions(modes) {
  var values = resolutions(modes)
  return values.map(function(value) {
    return {
      value: value,
      label: values.length === 1 ? value + " (native)" : value
    }
  })
}

function validScales(mode) {
  var p = modeParts(mode)
  if (!p) return [1]
  // Common integer, Windows-style, and fractional Wayland scales, spanning
  // 50%–400%. Filter out values that would create fractional logical pixels
  // for the chosen mode — Hyprland silently quantizes anything else.
  var candidates = [0.5, 0.6, 2 / 3, 0.75, 0.8, 0.9, 1, 1.1, 1.2, 1.25, 4 / 3, 1.5, 1.6, 1.75, 1.8, 2, 2.25, 2.5, 3, 3.5, 4]
  return candidates.filter(function(scale) {
    return Math.abs(p.width / scale - Math.round(p.width / scale)) < 0.0001
      && Math.abs(p.height / scale - Math.round(p.height / scale)) < 0.0001
  })
}

// Nearest Hyprland-accepted scale to an arbitrary slider value. Hyprland
// quantizes scale to modes that yield integer logical sizes, so a free slider
// must snap to the closest valid value or the apply step gets a mismatch.
function nearestScale(mode, wantedScale) {
  var scales = validScales(mode)
  var target = Number(wantedScale), best = scales[0], distance = Infinity
  scales.forEach(function(scale) {
    var delta = Math.abs(scale - target)
    if (delta < distance) { best = scale; distance = delta }
  })
  return best
}

// Close horizontal gaps between active displays. After a scale change the
// logical size of a display changes but its x does not, which leaves a gap
// (or overlap) the user then has to fix by hand. For every pair of adjacent
// displays (left-to-right) whose horizontal gap is within `maxGap`, pull the
// right-hand display flush against the left one. Mirrors and disabled outputs
// are left alone. Positions of displays that are far apart are preserved.
function closeGaps(displays, maxGap) {
  var copy = clone(displays)
  var limit = (maxGap === undefined) ? 400 : maxGap
  var active = copy.filter(function(d) { return !d.disabled && !d.mirror })
  active.sort(function(a, b) { return a.x - b.x })
  for (var i = 1; i < active.length; i++) {
    var prev = active[i - 1], d = active[i]
    var prevW = logicalSize(prev).width
    var gap = d.x - (prev.x + prevW)
    if (gap > 0 && gap <= limit) d.x = prev.x + prevW
  }
  return copy
}

function nearestValue(candidates, value) {
  var best = candidates[0], dist = Infinity
  for (var i = 0; i < candidates.length; i++) {
    var d = Math.abs(candidates[i] - value)
    if (d < dist) { best = candidates[i]; dist = d }
  }
  return best
}

// Auto-correct "weird" states so the user always ends up with a working picture
// instead of a blank or confusing one (never asks first):
//  - a mirror whose target is missing / disabled / itself mirroring / itself is
//    cleared back to "extend".
//  - an output that is BOTH disabled AND carrying a corrupt mirror is a broken
//    state, so it is re-enabled (extend) to guarantee a picture.
//  - if every output is disabled, the first one is re-enabled.
function sanitizeDisplays(displays) {
  var copy = clone(displays)
  var byName = {}
  copy.forEach(function(d) { byName[d.name] = d })
  var anyEnabled = false
  copy.forEach(function(d) {
    var t = d.mirror ? byName[d.mirror] : null
    var invalidMirror = !!d.mirror && (!t || t.disabled || !!t.mirror || t.name === d.name)
    if (invalidMirror) {
      d.mirror = ""
      if (d.disabled) d.disabled = false
    }
    if (!d.disabled) anyEnabled = true
  })
  if (!anyEnabled && copy.length > 0) copy[0].disabled = false
  return copy
}

// Fully automatic arrangement around a reference display (the one just dragged
// or rescaled). Every other active output is pulled flush against the reference
// on the side it already occupies (left/right when mostly horizontal, above/
// below when mostly vertical), and its cross-axis is snapped to the nearest
// aligned edge. The result never overlaps and never leaves a gap, while keeping
// the user's intended relative layout (including stacked monitors).
// Reflow the layout around the display that just changed. Every other active
// display is snapped flush against it on the side it already occupies (left/
// right when mostly horizontal, above/below when mostly vertical) so the layout
// stays CONNECTED (the mouse can cross between screens). The cross-axis offset
// the user chose is preserved (e.g. a monitor shifted down so only 10% of its
// edge touches), only clamped enough that the two still touch. The result never
// overlaps and never leaves a gap, while keeping stacked/offset layouts.
function reflowAroundSelected(displays, selectedIndex) {
  var copy = clone(displays)
  var sel = copy[selectedIndex]
  if (!sel || sel.disabled || sel.mirror) return copy
  var ss = logicalSize(sel)
  for (var i = 0; i < copy.length; i++) {
    if (i === selectedIndex) continue
    var d = copy[i]
    if (d.disabled || d.mirror) continue
    var ds = logicalSize(d)
    // Decide the side from the displays' TOP-LEFT positions, not their centres.
    // A scale/mode change grows the reference display and shifts its centre,
    // which would flip a right-hand neighbour to "above"; top-left positions do
    // not move on resize, so the side stays correct.
    var dx = d.x - sel.x
    var dy = d.y - sel.y
    if (Math.abs(dx) >= Math.abs(dy)) {
      // Horizontal neighbour: flush left/right, keep the user's vertical offset.
      d.x = dx >= 0 ? sel.x + ss.width : sel.x - ds.width
      d.y = clampTouch(d.y, ds.height, sel.y, ss.height)
    } else {
      // Vertical neighbour: flush above/below, keep the user's horizontal offset.
      d.y = dy >= 0 ? sel.y + ss.height : sel.y - ds.height
      d.x = clampTouch(d.x, ds.width, sel.x, ss.width)
    }
  }
  return copy
}

// Keep the interval [pos, pos+len] overlapping the reference interval
// [refPos, refPos+refLen] by at least one logical pixel (so the monitors share
// an edge boundary and the mouse can cross), while staying as close to the
// requested pos as possible. This is what makes the layout "flexible touching":
// any offset is allowed as long as the displays still touch.
function clampTouch(pos, len, refPos, refLen) {
  var minPos = refPos - len + 1      // pos+len must stay > refPos
  var maxPos = refPos + refLen - 1   // pos must stay < refPos+refLen
  if (pos < minPos) return minPos
  if (pos > maxPos) return maxPos
  return pos
}

// Snap the DRAGGED display flush against the nearest other display, choosing
// the flush side (left/right/above/below) closest to where it was dropped, and
// preserving its cross-axis offset (clamped so they still touch). Unlike
// reflowAroundSelected, the OTHER displays do not move -- only the dragged one
// snaps into place. Use this for drag: pulling a neighbour along would move the
// panel-hosting monitor and force a shell restart.
function snapDraggedFlush(displays, draggedIndex) {
  var copy = clone(displays)
  var d = copy[draggedIndex]
  if (!d || d.disabled || d.mirror) return copy
  var ds = logicalSize(d)
  var best = null, bd = Infinity
  for (var i = 0; i < copy.length; i++) {
    if (i === draggedIndex) continue
    var o = copy[i]
    if (o.disabled || o.mirror) continue
    var os = logicalSize(o)
    var cands = [
      { x: o.x + os.width, y: clampTouch(d.y, ds.height, o.y, os.height) },
      { x: o.x - ds.width, y: clampTouch(d.y, ds.height, o.y, os.height) },
      { x: clampTouch(d.x, ds.width, o.x, os.width), y: o.y + os.height },
      { x: clampTouch(d.x, ds.width, o.x, os.width), y: o.y - ds.height }
    ]
    for (var c = 0; c < cands.length; c++) {
      var dist = Math.abs(cands[c].x - d.x) + Math.abs(cands[c].y - d.y)
      if (dist < bd) { bd = dist; best = cands[c] }
    }
  }
  if (best) { d.x = best.x; d.y = best.y }
  return copy
}

// Push a dragged display out of any overlap it was dropped into. It is moved
// along the dominant arrangement axis (the one on which its centre differs most
// from the display it overlaps), landing flush on that side — so a side-by-side
// drop resolves horizontally and a stacked drop resolves vertically. Unlike
// reflowAroundSelected this does NOT close intentional gaps; it only guarantees
// displays never sit on top of each other.
function resolveOverlap(displays, draggedIndex) {
  var copy = clone(displays)
  var d = copy[draggedIndex]
  if (!d || d.disabled || d.mirror) return copy
  var ds = logicalSize(d)
  for (var i = 0; i < copy.length; i++) {
    if (i === draggedIndex) continue
    var o = copy[i]
    if (o.disabled || o.mirror || !overlap(d, o)) continue
    var os = logicalSize(o)
    var dx = (d.x + ds.width / 2) - (o.x + os.width / 2)
    var dy = (d.y + ds.height / 2) - (o.y + os.height / 2)
    if (Math.abs(dx) >= Math.abs(dy))
      d.x = dx >= 0 ? o.x + os.width : o.x - ds.width   // push flush right / left
    else
      d.y = dy >= 0 ? o.y + os.height : o.y - ds.height // push flush below / above
  }
  return copy
}

function logicalSize(display) {
  var p = modeParts(display.mode) || { width: display.width || 0, height: display.height || 0 }
  var scale = Number(display.scale) || 1
  var rotated = Number(display.transform) % 2 === 1
  return {
    width: Math.round((rotated ? p.height : p.width) / scale),
    height: Math.round((rotated ? p.width : p.height) / scale)
  }
}

function overlap(a, b) {
  if (a.disabled || b.disabled || a.mirror || b.mirror) return false
  var as = logicalSize(a), bs = logicalSize(b)
  return a.x < b.x + bs.width && a.x + as.width > b.x
      && a.y < b.y + bs.height && a.y + as.height > b.y
}

function hasOverlap(displays) {
  for (var i = 0; i < displays.length; i++)
    for (var j = i + 1; j < displays.length; j++)
      if (overlap(displays[i], displays[j])) return true
  return false
}

function normalizePositions(displays) {
  var copy = clone(displays), minX = Infinity, minY = Infinity
  copy.forEach(function(d) {
    if (!d.disabled && !d.mirror) { minX = Math.min(minX, d.x); minY = Math.min(minY, d.y) }
  })
  if (!isFinite(minX)) return copy
  copy.forEach(function(d) {
    if (!d.disabled && !d.mirror) { d.x -= minX; d.y -= minY }
  })
  return copy
}

function nearestMode(modes, wantedResolution, wantedRefresh) {
  var choices = modesForResolution(modes, wantedResolution)
  if (!choices.length) return modes && modes.length ? modes[0] : "preferred"
  var target = Number(wantedRefresh), best = choices[0], distance = Infinity
  choices.forEach(function(mode) {
    var delta = Math.abs(Number(refresh(mode)) - target)
    if (delta < distance) { best = mode; distance = delta }
  })
  return canonicalMode(best)
}

// Snap a dragged display to the edges of its neighbours. Given the display
// being moved and the full layout, returns the position after snapping to the
// nearest candidate edge within `threshold` logical pixels (per axis). This is
// what makes arrangements "click" into place instead of leaving small gaps.
function snapEdges(display, displays, threshold) {
  var size = logicalSize(display)
  var result = { x: display.x, y: display.y }
  var bestX = null, bestY = null
  ;(displays || []).forEach(function(other) {
    if (other === display || other.disabled || other.mirror) return
    var os = logicalSize(other)
    var candidatesX = [
      { pos: other.x, dist: Math.abs(display.x - other.x) },                                  // left edges aligned
      { pos: other.x + os.width - size.width, dist: Math.abs((display.x + size.width) - (other.x + os.width)) }, // right edges aligned
      { pos: other.x + os.width, dist: Math.abs(display.x - (other.x + os.width)) },          // flush to other's right
      { pos: other.x - size.width, dist: Math.abs((display.x + size.width) - other.x) }       // flush to other's left
    ]
    var candidatesY = [
      { pos: other.y, dist: Math.abs(display.y - other.y) },
      { pos: other.y + os.height - size.height, dist: Math.abs((display.y + size.height) - (other.y + os.height)) },
      { pos: other.y + os.height, dist: Math.abs(display.y - (other.y + os.height)) },
      { pos: other.y - size.height, dist: Math.abs((display.y + size.height) - other.y) }
    ]
    candidatesX.forEach(function(c) { if (c.dist <= threshold && (!bestX || c.dist < bestX.dist)) bestX = c })
    candidatesY.forEach(function(c) { if (c.dist <= threshold && (!bestY || c.dist < bestY.dist)) bestY = c })
  })
  if (bestX) result.x = bestX.pos
  if (bestY) result.y = bestY.pos
  return result
}
