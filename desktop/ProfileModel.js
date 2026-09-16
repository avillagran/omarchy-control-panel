.pragma library

function clone(value) {
  return JSON.parse(JSON.stringify(value))
}

function mergeBuiltins(builtins, stored) {
  var result = clone(builtins || [])
  var list = stored || []
  for (var i = 0; i < list.length; i++) {
    var item = list[i]
    if (item && item.id !== "default" && item.id !== "retina") result.push(clone(item))
  }
  return result
}

function create(profiles, name, fallbackName, settings, now) {
  var item = {
    id: "personal-" + now,
    name: name || fallbackName,
    builtin: false,
    settings: clone(settings)
  }
  return { profiles: clone(profiles || []).concat([item]), id: item.id }
}

function duplicate(profiles, id, copySuffix, now) {
  var list = clone(profiles || [])
  for (var i = 0; i < list.length; i++) {
    if (list[i].id !== id) continue
    var item = {
      id: "personal-" + now,
      name: list[i].name + copySuffix,
      builtin: false,
      settings: clone(list[i].settings)
    }
    list.push(item)
    return { profiles: list, id: item.id }
  }
  return { profiles: list, id: "" }
}

function saveSettings(profiles, id, settings) {
  var list = clone(profiles || [])
  for (var i = 0; i < list.length; i++) {
    if (list[i].id === id) {
      var next = clone(settings)
      // Section headers save current input/window settings. They must not erase
      // layouts saved for other physical monitor combinations.
      if (next.displayLayouts === undefined && list[i].settings && list[i].settings.displayLayouts)
        next.displayLayouts = clone(list[i].settings.displayLayouts)
      list[i].settings = next
      return { profiles: list, found: true, name: list[i].name }
    }
  }
  return { profiles: list, found: false, name: "" }
}

// Preserve every non-display setting while replacing just the stable
// per-output layout map. The persistent hotplug helper uses this map after a
// monitor reconnect, so a user drag in the Displays canvas must update it.
function saveDisplayMap(profiles, id, displays) {
  var list = clone(profiles || [])
  for (var i = 0; i < list.length; i++) {
    if (list[i].id === id) {
      var settings = clone(list[i].settings || {})
      settings.displays = clone(displays || {})
      list[i].settings = settings
      return { profiles: list, found: true, name: list[i].name }
    }
  }
  return { profiles: list, found: false, name: "" }
}

// A connector name is not a physical monitor identity. Store every layout
// under the detected EDID-derived monitor combination, while retaining the
// legacy map for older callers and a one-display fallback.
function saveDisplayLayout(profiles, id, topology, displays) {
  var list = clone(profiles || [])
  var key = String(topology || "")
  if (!key || !displays || typeof displays !== "object")
    return { profiles: list, found: false, name: "" }
  for (var i = 0; i < list.length; i++) {
    if (list[i].id !== id) continue
    var settings = clone(list[i].settings || {})
    var layouts = clone(settings.displayLayouts || {})
    layouts[key] = clone(displays)
    settings.displayLayouts = layouts
    settings.displays = clone(displays)
    list[i].settings = settings
    return { profiles: list, found: true, name: list[i].name }
  }
  return { profiles: list, found: false, name: "" }
}

function rename(profiles, id, name) {
  var list = clone(profiles || [])
  for (var i = 0; i < list.length; i++) {
    if (list[i].id === id && !list[i].builtin) {
      list[i].name = name
      return { profiles: list, found: true }
    }
  }
  return { profiles: list, found: false }
}

function remove(profiles, id) {
  if (id === "default" || id === "retina") return clone(profiles || [])
  return clone(profiles || []).filter(function(item) { return item.id !== id })
}
