.pragma library

function clampCount(value, fallback) {
  var n = Math.round(Number(value))
  return isFinite(n) ? Math.max(1, Math.min(10, n)) : fallback
}

function activeMonitors(displays) {
  return (displays || []).filter(function(d) {
    return d && d.name && !d.disabled && !d.mirror
  }).sort(function(a, b) {
    var ax = Number(a.x) || 0
    var bx = Number(b.x) || 0
    if (ax !== bx) return ax - bx
    var ay = Number(a.y) || 0
    var by = Number(b.y) || 0
    if (ay !== by) return ay - by
    return String(a.name).localeCompare(String(b.name))
  })
}

// Order monitors for workspace range assignment. Monitors that already own
// workspaces keep their range order (pinned by identity), so moving a display
// in the layout never swaps its workspaces with another display. New
// monitors (no claims) append after the claimed ones, in position order.
function pinOrder(monitors, previous) {
  function lowestClaim(name) {
    var best = Infinity
    for (var k in previous) {
      var v = previous[k]
      if (v && v.monitor === name) {
        var n = Number(k)
        if (isFinite(n) && n < best) best = n
      }
    }
    return best
  }
  return monitors.slice().sort(function(a, b) {
    var ca = lowestClaim(a.name)
    var cb = lowestClaim(b.name)
    if (ca !== Infinity || cb !== Infinity) return ca - cb
    return 0 // both unclaimed: keep position order (stable sort)
  })
}

function assignments(displays, singleCount, perMonitorCount, previous) {
  var monitors = pinOrder(activeMonitors(displays), previous || {})
  if (!monitors.length) return []
  var count = monitors.length === 1
    ? clampCount(singleCount, 10)
    : clampCount(perMonitorCount, 5)
  var result = []
  var workspace = 1
  for (var i = 0; i < monitors.length; i++) {
    for (var j = 0; j < count; j++) {
      result.push({
        workspace: workspace++,
        monitor: monitors[i].name,
        default: j === 0,
        persistent: true
      })
    }
  }
  return result
}

function summary(displays, singleCount, perMonitorCount) {
  var monitors = activeMonitors(displays)
  if (!monitors.length) return "No active displays"
  var count = monitors.length === 1
    ? clampCount(singleCount, 10)
    : clampCount(perMonitorCount, 5)
  return monitors.length === 1
    ? count + " workspaces on " + monitors[0].name
    : monitors.length + " displays · " + count + " workspaces each · " + (monitors.length * count) + " total"
}

var monitorPalette = [
  "accent", "green", "yellow", "magenta", "red",
  "cyan", "orange", "blue", "bright_green", "bright_blue"
]

var legacyColorRoles = {
  "#7aa2f7": "accent", "#9ece6a": "green", "#e0af68": "yellow",
  "#bb9af7": "magenta", "#f7768e": "red", "#7dcfff": "cyan",
  "#ff9e64": "orange", "#73daca": "cyan", "#c0caf5": "foreground",
  "#b4f9f8": "bright_cyan"
}

function normalizeIndicatorMode(value) {
  return ["square", "rounded", "circle", "none"].indexOf(value) >= 0 ? value : "none"
}

function normalizeColorRole(value) {
  if (monitorPalette.indexOf(value) >= 0 || ["bright_red", "bright_yellow", "bright_magenta", "bright_cyan", "foreground", "muted"].indexOf(value) >= 0)
    return value
  return legacyColorRoles[String(value || "").toLowerCase()] || ""
}

function explicitColorRoleForMonitor(name, colors) {
  return normalizeColorRole(colors && colors[name])
}

function colorRoleForMonitor(name, displays, colors) {
  var selectedRole = explicitColorRoleForMonitor(name, colors)
  if (selectedRole) return selectedRole
  var monitors = activeMonitors(displays)
  for (var i = 0; i < monitors.length; i++) {
    if (monitors[i].name === name) return monitorPalette[i % monitorPalette.length]
  }
  return monitorPalette[0]
}

function workspaceVisualMap(displays, singleCount, perMonitorCount, colors, previous) {
  var plan = assignments(displays, singleCount, perMonitorCount, previous)
  var result = {}
  for (var i = 0; i < plan.length; i++) {
    var rule = plan[i]
    result[String(rule.workspace)] = {
      monitor: rule.monitor,
      colorRole: colorRoleForMonitor(rule.monitor, displays, colors)
    }
  }
  return result
}
