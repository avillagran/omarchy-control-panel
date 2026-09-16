.pragma library

var numeralStyles = ["arabic", "kanji", "runes", "greek"]

function normalizeNumeralStyle(value) {
  return numeralStyles.indexOf(value) >= 0 ? value : "arabic"
}

// Hyprland 0.56 provides numbered workspaces via `name`/`address`; older
// Quickshell objects used `id`. Special workspaces intentionally return 0.
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
