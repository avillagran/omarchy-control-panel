import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons

// Draws a colored accent border (and a big number) on physical monitors so the
// user can tell which tile in the layout canvas maps to which real display.
// Two modes:
//   - selectedName !== "": highlight only that monitor (used while selecting
//     or dragging a tile).
//   - identifyAll === true: show the index on every monitor (the "Identify"
//     button), so multi-display setups are unambiguous.
//
// The border is drawn as FOUR thin edge windows instead of one full-screen
// window with a transparent center: some GPU/driver combos (e.g. Intel Mesa)
// hand Qt an opaque (XRGB) surface, which turns a "transparent" center into a
// solid black rectangle covering the whole screen. Strip windows cover only
// the border pixels, so no per-pixel alpha is required anywhere except the
// rounded corners of the identify index popup.
Item {
  id: root
  property var displays: []
  property string selectedName: ""
  property bool identifyAll: false
  // When true (a tile is being dragged) the physical overlay is hidden so we
  // don't create/destroy Wayland windows mid-drag (avoids a Quickshell segfault).
  property bool dragActive: false

  readonly property bool active: selectedName !== "" || identifyAll
  readonly property int borderW: Style.space(6)

  // Optional resolver (name => color) for the per-monitor color chosen in the
  // Displays tab; falls back to the accent color when unset.
  property var colorFor: null

  function _stripColor(name) {
    if (root.colorFor) {
      var c = root.colorFor(name)
      if (c) return c
    }
    return Color.accent
  }

  function _showBorder(name) {
    if (root.dragActive || root.indexOf(name) < 0) return false
    if (root.identifyAll) return true
    return name === root.selectedName
  }

  component EdgeStrip: PanelWindow {
    required property var screenData
    screen: screenData
    visible: root._showBorder(screenData.name)
    color: root._stripColor(screenData.name)
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region {}
  }

  // Top edge.
  Variants {
    model: Quickshell.screens
    EdgeStrip {
      required property var modelData
      screenData: modelData
      anchors { top: true; left: true; right: true }
      implicitHeight: root.borderW
    }
  }

  // Bottom edge.
  Variants {
    model: Quickshell.screens
    EdgeStrip {
      required property var modelData
      screenData: modelData
      anchors { bottom: true; left: true; right: true }
      implicitHeight: root.borderW
    }
  }

  // Left edge (inset vertically so corners are not drawn twice).
  Variants {
    model: Quickshell.screens
    EdgeStrip {
      required property var modelData
      screenData: modelData
      anchors { left: true; top: true; bottom: true }
      implicitWidth: root.borderW
      margins { top: root.borderW; bottom: root.borderW }
    }
  }

  // Right edge.
  Variants {
    model: Quickshell.screens
    EdgeStrip {
      required property var modelData
      screenData: modelData
      anchors { right: true; top: true; bottom: true }
      implicitWidth: root.borderW
      margins { top: root.borderW; bottom: root.borderW }
    }
  }

  // Big centered index, only in identify-all mode. Sized to its content and
  // centered with margins so the window covers only the popup itself.
  Variants {
    model: Quickshell.screens
    PanelWindow {
      id: indexWin
      required property var modelData
      screen: modelData
      visible: root.identifyAll && !root.dragActive && root.indexOf(modelData.name) >= 0
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      mask: Region {}
      implicitWidth: indexRect.width
      implicitHeight: indexRect.height
      margins {
        left: Math.max(0, Math.round((modelData.width - indexRect.width) / 2))
        top: Math.max(0, Math.round((modelData.height - indexRect.height) / 2))
      }

      Rectangle {
        id: indexRect
        width: Style.space(180)
        height: Style.space(130)
        radius: Style.cornerRadius * 2
        color: Color.popups.background
        border.color: root._stripColor(modelData.name)
        border.width: Style.normalBorderWidth
        Column {
          anchors.centerIn: parent
          spacing: Style.space(6)
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.indexOf(modelData.name) >= 0 ? String(root.indexOf(modelData.name) + 1) : "?"
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.space(58)
            font.bold: true
          }
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: modelData.name
            color: Qt.darker(Color.foreground, 1.3)
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }
        }
      }
    }
  }

  function indexOf(name) {
    for (var i = 0; i < root.displays.length; i++)
      if (root.displays[i].name === name) return i
    return -1
  }
}
