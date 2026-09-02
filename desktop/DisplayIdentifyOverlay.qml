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
Item {
  id: root
  property var displays: []
  property string selectedName: ""
  property bool identifyAll: false
  // When true (a tile is being dragged) the physical overlay is hidden so we
  // don't create/destroy Wayland windows mid-drag (avoids a Quickshell segfault).
  property bool dragActive: false

  readonly property bool active: selectedName !== "" || identifyAll

  Variants {
    model: Quickshell.screens
    PanelWindow {
      id: win
      required property var modelData
      screen: modelData
      visible: root.active && !root.dragActive && root.indexOf(modelData.name) >= 0
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      // The overlay is purely visual (a border + index). An empty Region mask
      // makes the window click-through so it never swallows mouse input.
      mask: Region {}
      anchors { top: true; bottom: true; left: true; right: true }

      readonly property int displayIndex: root.indexOf(modelData.name)
      readonly property bool isSelected: modelData.name === root.selectedName

      // Accent border around the whole physical monitor.
      Rectangle {
        anchors.fill: parent
        color: "transparent"
        border.color: Color.accent
        border.width: win.isSelected || root.identifyAll ? Style.space(6) : 0
        radius: Style.cornerRadius
      }

      // Big centered index, only in identify-all mode.
      Rectangle {
        visible: root.identifyAll
        anchors.centerIn: parent
        width: Style.space(180)
        height: Style.space(130)
        radius: Style.cornerRadius * 2
        color: Color.popups.background
        border.color: Color.accent
        border.width: Style.normalBorderWidth
        Column {
          anchors.centerIn: parent
          spacing: Style.space(6)
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: win.displayIndex >= 0 ? String(win.displayIndex + 1) : "?"
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
