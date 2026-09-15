.pragma library

var presets = {
  fine: { sensitivity: -0.2, scrollFactor: 0.65, accelProfile: "adaptive" },
  balanced: { sensitivity: 0.15, scrollFactor: 0.9, accelProfile: "adaptive" },
  swift: { sensitivity: 0.5, scrollFactor: 1.2, accelProfile: "adaptive" },
  linear: { sensitivity: 0.1, scrollFactor: 0.85, accelProfile: "flat" }
}

function presetIds() {
  return ["fine", "balanced", "swift", "linear"]
}

function clampSensitivity(value) {
  var number = Number(value)
  if (!isFinite(number)) number = 0
  return Math.round(Math.max(-1, Math.min(1, number)) * 20) / 20
}

function clampScrollFactor(value) {
  var number = Number(value)
  if (!isFinite(number)) number = 1
  return Math.round(Math.max(0.1, Math.min(2, number)) * 20) / 20
}

function preset(id) {
  var value = presets[id]
  return value ? {
    sensitivity: value.sensitivity,
    scrollFactor: value.scrollFactor,
    accelProfile: value.accelProfile
  } : null
}

function presetLabelKey(id) {
  return {
    fine: "pointerFeelFine",
    balanced: "pointerFeelBalanced",
    swift: "pointerFeelSwift",
    linear: "pointerFeelLinear",
    custom: "pointerFeelCustom"
  }[id] || "pointerFeelCustom"
}

function presetDescriptionKey(id) {
  return {
    fine: "pointerFeelDescriptionFine",
    balanced: "pointerFeelDescriptionBalanced",
    swift: "pointerFeelDescriptionSwift",
    linear: "pointerFeelDescriptionLinear",
    custom: "pointerFeelDescriptionCustom"
  }[id] || "pointerFeelDescriptionCustom"
}

function detectPreset(sensitivity, scrollFactor, accelProfile) {
  var s = clampSensitivity(sensitivity)
  var scroll = clampScrollFactor(scrollFactor)
  var profile = accelProfile === "flat" ? "flat" : "adaptive"
  var ids = presetIds()
  for (var i = 0; i < ids.length; i++) {
    var value = presets[ids[i]]
    if (Math.abs(value.sensitivity - s) < 0.001
        && Math.abs(value.scrollFactor - scroll) < 0.001
        && value.accelProfile === profile)
      return ids[i]
  }
  return "custom"
}

function pointerLabel(value) {
  var number = clampSensitivity(value)
  if (number <= -0.5) return "pointerFeelVeryControlled"
  if (number < -0.1) return "pointerFeelControlled"
  if (number <= 0.15) return "pointerFeelNeutral"
  if (number < 0.6) return "pointerFeelFast"
  return "pointerFeelVeryFast"
}

function scrollLabel(value) {
  var number = clampScrollFactor(value)
  if (number <= 0.5) return "pointerFeelScrollSoft"
  if (number < 0.9) return "pointerFeelScrollMeasured"
  if (number <= 1.2) return "pointerFeelScrollNatural"
  return "pointerFeelScrollFast"
}

var practicePoints = [
  { x: 0.10, y: 0.50 },
  { x: 0.76, y: 0.14 },
  { x: 0.36, y: 0.84 },
  { x: 0.90, y: 0.56 },
  { x: 0.24, y: 0.16 },
  { x: 0.68, y: 0.80 },
  { x: 0.48, y: 0.48 },
  { x: 0.50, y: 0.08 }
]

function practicePointCount() {
  return practicePoints.length
}

function practicePoint(index) {
  var count = practicePoints.length
  var normalized = ((Math.floor(Number(index) || 0) % count) + count) % count
  return { x: practicePoints[normalized].x, y: practicePoints[normalized].y }
}

function luaDeviceStatement(name, sensitivity, scrollFactor, accelProfile) {
  var device = String(name || "")
  if (!device || device.length > 128 || /[\x00-\x1f\x7f]/.test(device)) return ""
  if (accelProfile !== "adaptive" && accelProfile !== "flat") return ""
  return "hl.device({ name = " + JSON.stringify(device)
    + ", sensitivity = " + clampSensitivity(sensitivity).toFixed(2)
    + ", scroll_factor = " + clampScrollFactor(scrollFactor).toFixed(2)
    + ", accel_profile = " + JSON.stringify(accelProfile) + " })"
}
