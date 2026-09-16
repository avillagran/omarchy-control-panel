.pragma library

function clampCount(value, fallback) {
  var n = Math.round(Number(value))
  return isFinite(n) ? Math.max(1, Math.min(10, n)) : fallback
}

function activeMonitors(displays) {
  var monitors = (displays || []).filter(function(d) {
    return d && d.name && !d.disabled && !d.mirror
  })
  if (monitors.length < 2) return monitors

  // Use geometry, not connector names or a fixed display count. Choose the
  // dominant layout axis so a vertically stacked pair remains top→bottom even
  // when its x offsets differ, while side-by-side displays remain left→right.
  var minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity
  for (var i = 0; i < monitors.length; i++) {
    var x = Number(monitors[i].x) || 0
    var y = Number(monitors[i].y) || 0
    minX = Math.min(minX, x); maxX = Math.max(maxX, x)
    minY = Math.min(minY, y); maxY = Math.max(maxY, y)
  }
  var horizontal = (maxX - minX) >= (maxY - minY)
  return monitors.sort(function(a, b) {
    var primaryA = horizontal ? Number(a.x) || 0 : Number(a.y) || 0
    var primaryB = horizontal ? Number(b.x) || 0 : Number(b.y) || 0
    if (primaryA !== primaryB) return primaryA - primaryB
    var secondaryA = horizontal ? Number(a.y) || 0 : Number(a.x) || 0
    var secondaryB = horizontal ? Number(b.y) || 0 : Number(b.x) || 0
    if (secondaryA !== secondaryB) return secondaryA - secondaryB
    return String(a.name).localeCompare(String(b.name))
  })
}

function assignments(displays, singleCount, perMonitorCount, previous) {
  // Workspace ranges deliberately follow physical monitor order: first
  // workspaces on the left/top display, final ones on the right/bottom.
  var monitors = activeMonitors(displays)
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

var numeralStyles = ["arabic", "kanji", "runes", "greek"]

function normalizeNumeralStyle(value) {
  return numeralStyles.indexOf(value) >= 0 ? value : "arabic"
}

// Hyprland 0.56 represents workspace identity with `name`/`address`; older
// Quickshell objects exposed a numeric `id`. Accept both without accidentally
// treating special workspaces such as `special:sidepanelX` as numbered ones.
function workspaceNumber(workspace) {
  if (!workspace) return 0
  var id = Number(workspace.id)
  if (isFinite(id) && id > 0 && Math.floor(id) === id) return id
  var name = Number(workspace.name)
  return isFinite(name) && name > 0 && Math.floor(name) === name ? name : 0
}

function formatWorkspaceNumber(value, style) {
  var number = Math.floor(Number(value))
  if (!isFinite(number) || number < 1) return ""
  var selected = normalizeNumeralStyle(style)
  if (selected === "kanji") {
    var kanji = ["", "一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]
    return number <= 10 ? kanji[number] : String(number)
  }
  if (selected === "runes") {
    var runes = ["", "ᚠ", "ᚢ", "ᚦ", "ᚨ", "ᚱ", "ᚲ", "ᚷ", "ᚹ", "ᚺ", "ᚾ"]
    return number <= 10 ? runes[number] : String(number)
  }
  if (selected === "greek") {
    var greek = ["", "α", "β", "γ", "δ", "ε", "ζ", "η", "θ", "ι", "κ"]
    return number <= 10 ? greek[number] : String(number)
  }
  return String(number)
}

function numeralPreview(style) {
  return formatWorkspaceNumber(1, style) + " "
    + formatWorkspaceNumber(2, style) + " "
    + formatWorkspaceNumber(3, style)
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
