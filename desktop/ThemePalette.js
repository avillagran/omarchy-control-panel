.pragma library

var roles = [
  "accent", "red", "green", "yellow", "blue", "magenta", "cyan", "orange",
  "bright_red", "bright_green", "bright_yellow", "bright_blue",
  "bright_magenta", "bright_cyan", "foreground", "muted"
]

function parse(raw) {
  var result = {}
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var match = lines[i].match(/^\s*([A-Za-z0-9_-]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
    if (match) result[match[1]] = match[2]
  }
  return result
}

function resolve(role, palette) {
  var colors = palette && typeof palette === "object" ? palette : ({})
  var value = colors[String(role || "")]
  if (typeof value === "string" && /^#[0-9A-Fa-f]{6}$/.test(value)) return value
  if (typeof colors.accent === "string" && /^#[0-9A-Fa-f]{6}$/.test(colors.accent)) return colors.accent
  return "#cacccc"
}
