import QtQuick 6.11
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import "ThemePalette.js" as ThemePalette
import "WorkspaceNumerals.js" as WorkspaceModel

Item {
  id: root

  property var bar
  property string moduleName: "control-panel-workspaces"
  property var settings: ({})
  property var workspaceVisuals: ({})
  property var themeColors: ({})
  property string workspaceIndicatorMode: "none"
  property int workspaceIndicatorPadding: 4
  property string workspaceNumeralStyle: "arabic"
  property bool prefsLoaded: false
  property string prefsPath: Quickshell.env("HOME") + "/.local/state/omarchy/control-panel-prefs.json"
  property string themePath: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"
  readonly property string hotplugHelper: Quickshell.env("HOME")
    + "/.config/omarchy/plugins/io.github.avillagran.omarchy-control-panel/bin/display-hotplug-sync"
  // Quickshell emits screensChanged for window/layer-surface lifecycle events as
  // well as actual output hotplug. Only an output-name topology change may
  // reapply a display profile; a control-panel window must be read-only.
  readonly property string screenTopology: {
    var names = []
    for (var i = 0; i < Quickshell.screens.length; i++)
      names.push(String(Quickshell.screens[i].name || ""))
    names.sort()
    return names.join("|")
  }
  property string knownScreenTopology: ""
  property bool hotplugBaselineReady: false
  readonly property bool vertical: bar ? bar.vertical : false
  readonly property int barSize: bar ? bar.barSize : 26
  readonly property color fallbackColor: bar ? bar.foreground : "white"

  // Omarchy 4.6+ gives every monitor its own block of ten workspaces
  // (default/hypr/monitor-workspaces.lua) and its bar shows each monitor's own
  // block numbered 1-10. With it present this strip follows the same rules,
  // keeping only the colors; without it, the strip below is unchanged.
  readonly property int omarchySlots: 10
  property bool omarchyWorkspaces: false
  property var omarchyBlocks: ({})

  function readOmarchyBlocks(text) {
    var next = {}
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var match = /^(\d+)\t([^\t]*)\t.+$/.exec(lines[i])
      if (match && match[2]) next[match[2]] = Number(match[1])
    }
    omarchyBlocks = next
  }

  function blockOf(id) { return Math.floor((id - 1) / omarchySlots) }
  function slotOf(id) { return (id - 1) % omarchySlots + 1 }

  readonly property var hyprMonitor: {
    var values = Hyprland.monitors.values
    for (var i = 0; i < values.length; i++)
      if (values[i].name === root.screenName) return values[i]
    return null
  }

  function shownWorkspaceNumber() {
    return hyprMonitor ? WorkspaceModel.workspaceNumber(hyprMonitor.activeWorkspace) : 0
  }

  // Until Hyprland has written the file, the workspace a monitor shows is in
  // its own block.
  readonly property int omarchyBlock: {
    var block = omarchyBlocks[screenName]
    if (block !== undefined) return block
    var shown = shownWorkspaceNumber()
    return shown > 0 ? blockOf(shown) : 0
  }

  function labelFor(id) {
    return omarchyWorkspaces && blockOf(id) === omarchyBlock ? slotOf(id) : id
  }

  function applySettings() {
    // shell.json may retain an old nested `settings` snapshot. Once the
    // authoritative prefs file loads, never let that stale copy overwrite it.
    if (root.prefsLoaded) return
    if (!settings || typeof settings !== "object") return
    if (["square", "rounded", "circle", "none"].indexOf(settings.workspaceIndicatorMode) >= 0)
      workspaceIndicatorMode = settings.workspaceIndicatorMode
    if (settings.workspaceIndicatorPadding !== undefined)
      workspaceIndicatorPadding = Math.max(0, Math.min(4, Math.round(Number(settings.workspaceIndicatorPadding))))
    workspaceNumeralStyle = WorkspaceModel.normalizeNumeralStyle(settings.workspaceNumeralStyle)
    if (settings.workspaceVisuals && typeof settings.workspaceVisuals === "object")
      workspaceVisuals = settings.workspaceVisuals
  }

  onSettingsChanged: applySettings()

  function loadPrefs(raw) {
    try {
      var data = JSON.parse(String(raw || "{}")) || {}
      workspaceVisuals = data.workspaceVisuals && typeof data.workspaceVisuals === "object"
        ? data.workspaceVisuals : ({})
      workspaceIndicatorMode = ["square", "rounded", "circle", "none"].indexOf(data.workspaceIndicatorMode) >= 0
        ? data.workspaceIndicatorMode : "none"
      workspaceIndicatorPadding = Math.max(0, Math.min(4,
        data.workspaceIndicatorPadding === undefined ? 4 : Math.round(Number(data.workspaceIndicatorPadding))))
      workspaceNumeralStyle = WorkspaceModel.normalizeNumeralStyle(data.workspaceNumeralStyle)
      prefsLoaded = true
    } catch (e) {
      workspaceVisuals = ({})
      workspaceIndicatorMode = "none"
      workspaceIndicatorPadding = 4
      workspaceNumeralStyle = "arabic"
    }
  }

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (WorkspaceModel.workspaceNumber(values[i]) === id) return values[i]
    }
    return null
  }

  // The monitor this bar instance sits on (each bar window is per-screen).
  readonly property string screenName: {
    var w = root.QsWindow.window || (bar && bar.targetWindow ? bar.targetWindow(root) : null)
    var screen = w ? w.screen : null
    var monitor = screen ? Hyprland.monitorFor(screen) : null
    return monitor ? String(monitor.name || "") : screen ? String(screen.name || "") : ""
  }

  // Name of the monitor a live workspace currently sits on ("" if unknown).
  function liveMonitorOf(ws) {
    var mon = ws && ws.monitor
    return mon ? String(mon.name || mon || "") : ""
  }

  function focusedWorkspaceNumber() {
    return WorkspaceModel.workspaceNumber(Hyprland.focusedWorkspace)
  }

  // All shaped indicators use the same extent for the active numeral style.
  // Roman labels such as III/VII/VIII must never resize individual boxes.
  function uniformIndicatorExtent() {
    var widest = numberMetrics.height
    var ids = workspaceIds()
    for (var i = 0; i < ids.length; i++) {
      var width = numberMetrics.advanceWidth(
        WorkspaceModel.formatWorkspaceNumber(labelFor(ids[i]), workspaceNumeralStyle))
      widest = Math.max(widest, width)
    }
    return Math.min(barSize, Math.ceil(widest + 2 * workspaceIndicatorPadding))
  }

  // As Omarchy's bar: the first five of this monitor's block, any of the rest
  // that exist, then workspaces only visiting this monitor.
  function omarchyWorkspaceIds() {
    var base = omarchyBlock * omarchySlots
    var ids = [base + 1, base + 2, base + 3, base + 4, base + 5]
    var guests = []
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      var id = WorkspaceModel.workspaceNumber(values[i])
      if (id <= 0) continue
      if (blockOf(id) === omarchyBlock) {
        if (ids.indexOf(id) === -1) ids.push(id)
      } else if (liveMonitorOf(values[i]) === screenName && guests.indexOf(id) === -1) {
        guests.push(id)
      }
    }
    ids.sort(function(a, b) { return a - b })
    guests.sort(function(a, b) { return a - b })
    return ids.concat(guests)
  }

  function workspaceIds() {
    if (omarchyWorkspaces) return omarchyWorkspaceIds()
    var ids = []
    var values = Hyprland.workspaces.values
    var i, id, key

    // Every bar shows the complete workspace strip. Colors retain the monitor
    // association, while the persisted map keeps 1…N in physical monitor order.
    for (key in workspaceVisuals) {
      id = Number(key)
      if (isFinite(id) && id > 0 && Math.floor(id) === id && ids.indexOf(id) === -1)
        ids.push(id)
    }
    // Include dynamically-created numbered workspaces before the panel has a
    // chance to persist their mapping.
    for (i = 0; i < values.length; i++) {
      id = WorkspaceModel.workspaceNumber(values[i])
      if (id > 0 && ids.indexOf(id) === -1) ids.push(id)
    }
    if (ids.length === 0) ids = [1, 2, 3, 4, 5]
    ids.sort(function(a, b) { return a - b })
    return ids
  }

  function visual(id) {
    var value = workspaceVisuals[String(id)]
    return value && typeof value === "object" ? value : ({
      colorRole: id <= 5 ? "accent" : "green",
      monitor: ""
    })
  }

  function themeColor(value) {
    if (typeof value === "string" && /^#[0-9A-Fa-f]{6}$/.test(value)) return value
    return ThemePalette.resolve(value, root.themeColors)
  }

  function focusWorkspace(id) {
    if (!bar) return
    // A slot of this monitor's block goes through Omarchy, which brings it to
    // this monitor; focusing the bare number would create a missing one on
    // whichever monitor has focus.
    if (omarchyWorkspaces && blockOf(id) === omarchyBlock && screenName) {
      bar.run("hyprctl dispatch " + Util.shellQuote("o.workspaces.focus(" + slotOf(id) + ", " + JSON.stringify(screenName) + ")"))
      return
    }
    bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })"))
  }

  function scheduleHotplugSync() {
    hotplugTimer.restart()
    hotplugRetryTimer.restart()
  }

  implicitWidth: grid.implicitWidth + (vertical ? 0 : Style.spaceReal(1.5))
  implicitHeight: grid.implicitHeight

  FileView {
    id: prefsFile
    path: root.prefsPath
    blockLoading: true
    watchChanges: true
    printErrors: false
    onLoaded: root.loadPrefs(text())
    onLoadFailed: function() { root.loadPrefs("{}") }
    onFileChanged: reload()
  }

  FileView {
    path: (Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy") + "/default/hypr/monitor-workspaces.lua"
    blockLoading: true
    printErrors: false
    onLoaded: root.omarchyWorkspaces = true
    onLoadFailed: function() { root.omarchyWorkspaces = false }
  }

  FileView {
    path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omarchy/monitors/workspaces"
    blockLoading: true
    watchChanges: true
    printErrors: false
    onLoaded: root.readOmarchyBlocks(text())
    onLoadFailed: function() { root.omarchyBlocks = ({}) }
    onFileChanged: reload()
  }

  FileView {
    id: themeFile
    path: root.themePath
    blockLoading: true
    watchChanges: true
    printErrors: false
    onLoaded: root.themeColors = ThemePalette.parse(text())
    onFileChanged: reload()
  }

  Connections {
    target: Color
    function onAccentChanged() { themeFile.reload() }
    function onForegroundChanged() { themeFile.reload() }
    function onUrgentChanged() { themeFile.reload() }
  }

  Connections {
    target: Quickshell
    function onScreensChanged() {
      if (!root.hotplugBaselineReady) {
        root.knownScreenTopology = root.screenTopology
        root.hotplugBaselineReady = true
        return
      }
      if (root.screenTopology === root.knownScreenTopology) return
      root.knownScreenTopology = root.screenTopology
      root.scheduleHotplugSync()
    }
  }

  Process {
    id: hotplugProc
    command: [root.hotplugHelper]
  }

  Timer {
    id: hotplugTimer
    interval: 1500
    repeat: false
    onTriggered: if (!hotplugProc.running) hotplugProc.running = true
  }

  Timer {
    id: hotplugRetryTimer
    interval: 5000
    repeat: false
    onTriggered: {
      if (hotplugProc.running) restart()
      else hotplugProc.running = true
    }
  }

  Component.onCompleted: {
    prefsFile.reload()
    applySettings()
    knownScreenTopology = screenTopology
    hotplugBaselineReady = true
  }

  // Quickshell may deliver a shared path watcher event to only one bar-window
  // instance. Poll lightly as a fallback so every monitor follows the slider.
  Timer {
    interval: 1000
    repeat: true
    running: true
    onTriggered: prefsFile.reload()
  }

  FontMetrics {
    id: numberMetrics
    font.family: root.bar ? root.bar.fontFamily : "monospace"
    font.pixelSize: Style.font.body
    font.bold: true
  }

  GridLayout {
    id: grid
    anchors.fill: parent
    anchors.rightMargin: root.vertical ? 0 : Style.spaceReal(1.5)
    columns: root.vertical ? 1 : root.workspaceIds().length
    columnSpacing: root.vertical ? 0 : Style.space(1)
    rowSpacing: root.vertical ? Style.space(2) : 0

    Repeater {
      model: root.workspaceIds()

      Item {
        id: delegate
        required property int modelData
        readonly property var workspace: root.workspaceById(modelData)
        readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0
        readonly property bool focused: root.omarchyWorkspaces
          ? root.shownWorkspaceNumber() === modelData
          : root.focusedWorkspaceNumber() === modelData
        readonly property var workspaceVisual: root.visual(modelData)
        readonly property color workspaceColor: root.themeColor(workspaceVisual.colorRole || workspaceVisual.color) || root.fallbackColor
        readonly property string indicatorMode: root.workspaceIndicatorMode
        readonly property int indicatorExtent: root.uniformIndicatorExtent()

        implicitWidth: root.vertical ? root.barSize
          : indicatorMode !== "none" ? indicatorExtent
          : Math.ceil(numberLabel.implicitWidth + 2 * root.workspaceIndicatorPadding)
        implicitHeight: root.barSize
        opacity: occupied || focused ? 1 : 0.48

        Rectangle {
          id: indicatorFrame
          anchors.centerIn: parent
          width: delegate.indicatorMode === "none" ? parent.width : delegate.indicatorExtent
          height: delegate.indicatorMode === "none" ? parent.height : delegate.indicatorExtent
          radius: delegate.indicatorMode === "square" ? 0
            : delegate.indicatorMode === "circle" ? Math.min(width, height) / 2
            : delegate.indicatorMode === "rounded" ? Math.max(4, Math.min(width, height) / 4) : 0
          color: delegate.focused ? delegate.workspaceColor : "transparent"
          border.color: delegate.workspaceColor
          border.width: delegate.indicatorMode !== "none" && !delegate.focused ? 1 : 0

          Text {
            id: numberLabel
            anchors.centerIn: parent
            text: WorkspaceModel.formatWorkspaceNumber(root.labelFor(delegate.modelData), root.workspaceNumeralStyle)
            color: delegate.focused ? "#101014" : delegate.workspaceColor
            font.family: root.bar ? root.bar.fontFamily : "monospace"
            font.pixelSize: Style.font.body
            font.bold: true
          }
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.focusWorkspace(delegate.modelData)
          onEntered: {
            if (root.bar && delegate.workspaceVisual.monitor)
              root.bar.showTooltip(delegate, "Escritorio " + root.labelFor(delegate.modelData) + " · " + delegate.workspaceVisual.monitor)
          }
          onExited: if (root.bar) root.bar.hideTooltip(delegate)
          hoverEnabled: true
        }
      }
    }
  }
}
