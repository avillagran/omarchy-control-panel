import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "ThemePalette.js" as ThemePalette

QtObject {
  id: theme

  property var palette: ({})
  function paletteColor(role, fallback) {
    var value = palette[role]
    return typeof value === "string" && value.length > 0 ? value : fallback
  }

  // Exact semantic surfaces from the active Omarchy theme. Color.* remains a
  // safe fallback only while colors.toml is loading.
  readonly property color app: paletteColor("background", Color.background)
  readonly property color panel: paletteColor("lighter_background", app)
  readonly property color panelAlt: paletteColor("selection", panel)
  readonly property color panelDeep: paletteColor("darker_background", app)
  readonly property color border: paletteColor("muted", Qt.alpha(Color.foreground, 0.16))
  readonly property color text: paletteColor("foreground", Color.foreground)
  readonly property color textMuted: paletteColor("light_foreground", Qt.alpha(text, 0.72))
  readonly property color accent: paletteColor("accent", Color.accent)
  readonly property color urgent: Color.urgent
  readonly property color accentSoft: paletteColor("selection", Qt.tint(app, Qt.alpha(accent, 0.14)))
  readonly property color transparent: Qt.rgba(0, 0, 0, 0)
  readonly property int radius: 6
  readonly property int gap: 8
  readonly property int padding: 12
  readonly property string fontUi: Style.font.family
  readonly property int body: Style.font.body
  readonly property int caption: Style.font.caption
  readonly property int controlHeight: Math.max(36, body + 20)

  property FileView themeFile: FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"
    blockLoading: true
    watchChanges: true
    printErrors: false
    onLoaded: theme.palette = ThemePalette.parse(text())
    onFileChanged: reload()
  }

  property Connections colorConnections: Connections {
    target: Color
    function onAccentChanged() { theme.themeFile.reload() }
    function onForegroundChanged() { theme.themeFile.reload() }
  }

  // Structural dimensions do not scale with Style.space()/Retina fonts.
  function windowWidth(screenWidth) {
    return Math.round(Math.min(screenWidth * 0.96, 1280, Math.max(980, screenWidth * 0.72)))
  }
  function windowHeight(screenHeight, contentHeight) {
    return Math.round(Math.min(screenHeight * 0.92, Math.max(620, contentHeight)))
  }
}
