.pragma library

// Scroll feel model for the touchpad scroll-acceleration/coast patch.
// The four Hyprland options only exist on a compositor built with the patch
// (see write-up in Core.qml); every helper here is pure so it can be tested
// without a live compositor.

var presets = {
  native: { profile: 0, speed: 1.0, max: 3.0, decel: 0 },
  linear: { profile: 1, speed: 1.0, max: 3.0, decel: 300 },
  adaptive: { profile: 2, speed: 1.0, max: 3.0, decel: 600 },
  glide: { profile: 2, speed: 1.3, max: 4.0, decel: 1000 }
}

function presetIds() {
  return ["native", "linear", "adaptive", "glide"]
}

function clampProfile(value) {
  var number = Math.round(Number(value))
  if (!isFinite(number)) number = 2
  return Math.max(0, Math.min(2, number))
}

function clampSpeed(value) {
  var number = Number(value)
  if (!isFinite(number)) number = 1.0
  return Math.round(Math.max(0.2, Math.min(3.0, number)) * 20) / 20
}

function clampMax(value) {
  var number = Number(value)
  if (!isFinite(number)) number = 3.0
  return Math.round(Math.max(1.0, Math.min(10.0, number)) * 4) / 4
}

function clampDecel(value) {
  var number = Math.round(Number(value))
  if (!isFinite(number)) number = 600
  return Math.max(0, Math.min(3000, Math.round(number / 50) * 50))
}

function preset(id) {
  var value = presets[id]
  return value ? {
    profile: value.profile,
    speed: value.speed,
    max: value.max,
    decel: value.decel
  } : null
}

function presetLabelKey(id) {
  return {
    native: "scrollFeelNative",
    linear: "scrollFeelLinear",
    adaptive: "scrollFeelAdaptive",
    glide: "scrollFeelGlide",
    custom: "scrollFeelCustom"
  }[id] || "scrollFeelCustom"
}

function presetDescriptionKey(id) {
  return {
    native: "scrollFeelDescriptionNative",
    linear: "scrollFeelDescriptionLinear",
    adaptive: "scrollFeelDescriptionAdaptive",
    glide: "scrollFeelDescriptionGlide",
    custom: "scrollFeelDescriptionCustom"
  }[id] || "scrollFeelDescriptionCustom"
}

function detectPreset(profile, speed, max, decel) {
  var p = clampProfile(profile)
  var s = clampSpeed(speed)
  var m = clampMax(max)
  var d = clampDecel(decel)
  var ids = presetIds()
  for (var i = 0; i < ids.length; i++) {
    var value = presets[ids[i]]
    if (value.profile === p
        && Math.abs(value.speed - s) < 0.001
        && Math.abs(value.max - m) < 0.001
        && Math.abs(value.decel - d) < 0.001)
      return ids[i]
  }
  return "custom"
}

function speedLabel(value) {
  var number = clampSpeed(value)
  if (number <= 0.5) return "scrollFeelSpeedGentle"
  if (number <= 1.0) return "scrollFeelSpeedBalanced"
  if (number <= 2.0) return "scrollFeelSpeedResponsive"
  return "scrollFeelSpeedAggressive"
}

function maxLabel(value) {
  var number = clampMax(value)
  if (number <= 2.0) return "scrollFeelMaxMild"
  if (number <= 3.5) return "scrollFeelMaxModerate"
  if (number <= 6.0) return "scrollFeelMaxStrong"
  return "scrollFeelMaxExtreme"
}

// A single hl.config statement carrying all four patch options plus the
// ignore-class list. Returns "" for out-of-range profiles so callers never
// emit a broken literal. `ignoreClasses` is a composer-managed list
// (browsers/terminals with their own inertia); empty = apply everywhere.
// `includeIgnore` lets callers on a 4-key patch build (accel+coast but no
// scroll_ignore_classes yet) emit the legacy statement without the key.
function luaConfigStatement(profile, speed, max, decel, ignoreClasses, includeIgnore) {
  var p = clampProfile(profile)
  if (p !== Math.round(Number(profile))) return ""
  var stmt = "hl.config({ input = { touchpad = {"
    + " scroll_accel_profile = " + p
    + ", scroll_accel_speed = " + clampSpeed(speed).toFixed(2)
    + ", scroll_accel_max = " + clampMax(max).toFixed(2)
    + ", scroll_decel = " + clampDecel(decel)
  if (includeIgnore !== false)
    stmt += ", scroll_ignore_classes = \"" + String(ignoreClasses || "") + "\""
  return stmt + " } } })"
}

// Window classes that ship their own touchpad scroll inertia and therefore
// feel "doubly inert" when the patch also accelerates/coasts them.
var ignoreClassesBrowsers = "google-chrome,chromium,firefox,brave-browser,microsoft-edge,vivaldi,kitty"

var ignoreModes = ["off", "browsers", "native"]

function clampIgnoreMode(mode) {
  return ignoreModes.indexOf(mode) >= 0 ? mode : "browsers"
}

function ignoreModeLabelKey(mode) {
  return {
    off: "scrollIgnoreOff",
    browsers: "scrollIgnoreBrowsers",
    native: "scrollIgnoreNative"
  }[clampIgnoreMode(mode)]
}

// Derive the effective ignore mode from live compositor values (used on
// probe when the panel has no saved preference yet).
function modeFromLive(profile, ignoreClasses) {
  if (clampProfile(profile) === 0) return "native"
  var list = String(ignoreClasses || "")
  if (list.indexOf("chromium") >= 0 || list.indexOf("kitty") >= 0) return "browsers"
  if (list.trim() === "") return "off"
  return "browsers"
}

// Live ignore list for a mode; "" means the patch applies everywhere.
function ignoreListForMode(mode) {
  return clampIgnoreMode(mode) === "browsers" ? ignoreClassesBrowsers : ""
}

// Effective accel profile for a mode; "native" turns the patch off globally.
function profileForMode(mode, profile) {
  return clampIgnoreMode(mode) === "native" ? 0 : clampProfile(profile)
}

// Capability probe: `hyprctl getoption input:touchpad:scroll_decel -j` only
// yields parseable JSON with the option name on a compositor that knows the
// key. Anything else (error text, empty output, garbage) means unpatched.
function supportsPatchFromProbe(stdoutText, exitCode) {
  if (exitCode !== 0) return false
  var text = String(stdoutText || "")
  if (text.indexOf("scroll_decel") < 0) return false
  try {
    var parsed = JSON.parse(text.trim())
    return typeof parsed === "object" && parsed !== null
  } catch (e) {
    return false
  }
}

// Parse the four `hyprctl getoption` JSON lines into current values.
// Unknown keys or malformed lines fall back to the patch defaults so the UI
// always has sane numbers to show.
function parseLiveValues(lines) {
  var values = { profile: 2, speed: 1.0, max: 3.0, decel: 600, ignoreClasses: "", ignoreSupported: false }
  var list = String(lines || "").split("\n")
  for (var i = 0; i < list.length; i++) {
    var line = list[i].trim()
    if (!line || line.charAt(0) !== "{") continue
    try {
      var parsed = JSON.parse(line)
      var option = String(parsed["option"] || "")
      if (option.indexOf("scroll_ignore_classes") >= 0) {
        values.ignoreClasses = String(parsed["str"] || "")
        values.ignoreSupported = true
        continue
      }
      var raw = parsed["float"] !== undefined ? parsed["float"] : parsed["int"]
      var value = Number(raw)
      if (!isFinite(value)) continue
      if (option.indexOf("scroll_accel_profile") >= 0) values.profile = clampProfile(value)
      else if (option.indexOf("scroll_accel_speed") >= 0) values.speed = clampSpeed(value)
      else if (option.indexOf("scroll_accel_max") >= 0) values.max = clampMax(value)
      else if (option.indexOf("scroll_decel") >= 0) values.decel = clampDecel(value)
    } catch (e) {}
  }
  return values
}
