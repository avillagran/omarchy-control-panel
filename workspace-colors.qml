import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import "ThemePalette.js" as ThemePalette

Item {
  id: root

  property var bar
  property string moduleName: "control-panel-workspaces"
  property var settings: ({})
  property var workspaceVisuals: ({})
  property var themeColors: ({})
  property string workspaceIndicatorMode: "none"
  property int workspaceIndicatorPadding: 4
  property string prefsPath: Quickshell.env("HOME") + "/.local/state/omarchy/control-panel-prefs.json"
  property string themePath: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"
  readonly property bool vertical: bar ? bar.vertical : false
  readonly property int barSize: bar ? bar.barSize : 26
  readonly property color fallbackColor: bar ? bar.foreground : "white"

  function applySettings() {
    if (!settings || typeof settings !== "object") return
    if (["square", "rounded", "circle", "none"].indexOf(settings.workspaceIndicatorMode) >= 0)
      workspaceIndicatorMode = settings.workspaceIndicatorMode
    if (settings.workspaceIndicatorPadding !== undefined)
      workspaceIndicatorPadding = Math.max(0, Math.min(4, Math.round(Number(settings.workspaceIndicatorPadding))))
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
    } catch (e) {
      workspaceVisuals = ({})
      workspaceIndicatorMode = "none"
      workspaceIndicatorPadding = 4
    }
  }

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }
    return null
  }

  function workspaceIds() {
    var ids = [1, 2, 3, 4, 5]
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      var id = values[i].id
      if (id > 0 && id <= 10 && ids.indexOf(id) === -1) ids.push(id)
    }
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
    bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })"))
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

  Component.onCompleted: {
    prefsFile.reload()
    applySettings()
  }

  // Quickshell may deliver a shared path watcher event to only one bar-window
  // instance. Poll lightly as a fallback so every monitor follows the slider.
  Timer {
    interval: 1000
    repeat: true
    running: true
    onTriggered: prefsFile.reload()
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
        readonly property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === modelData
        readonly property var workspaceVisual: root.visual(modelData)
        readonly property color workspaceColor: root.themeColor(workspaceVisual.colorRole || workspaceVisual.color) || root.fallbackColor
        readonly property string indicatorMode: root.workspaceIndicatorMode
        readonly property int indicatorExtent: Math.min(root.barSize,
          Math.ceil(Math.max(numberLabel.implicitWidth, numberLabel.implicitHeight) + 2 * root.workspaceIndicatorPadding))

        implicitWidth: root.vertical ? root.barSize
          : indicatorMode !== "none" ? indicatorExtent : Style.space(20)
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
          color: delegate.indicatorMode !== "none" && delegate.focused ? delegate.workspaceColor : "transparent"
          border.color: delegate.workspaceColor
          border.width: delegate.indicatorMode !== "none" && !delegate.focused ? 1 : 0

          Text {
            id: numberLabel
            anchors.centerIn: parent
            text: delegate.focused ? "\uDB85\uDCFB" : (delegate.modelData === 10 ? "0" : String(delegate.modelData))
            color: delegate.indicatorMode !== "none" && delegate.focused ? "#101014" : delegate.workspaceColor
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
              root.bar.showTooltip(delegate, "Escritorio " + delegate.modelData + " · " + delegate.workspaceVisual.monitor)
          }
          onExited: if (root.bar) root.bar.hideTooltip(delegate)
          hoverEnabled: true
        }
      }
    }
  }
}
