import QtQuick
import Quickshell
import qs.Commons

// Simple desktop panel - no Layouts, no focus issues
PanelWindow {
  id: win
  visible: true
  width: 600
  height: 750
  color: Color.background

  // Center on screen
  Component.onCompleted: {
    x = Math.round((screen.width - width) / 2)
    y = Math.round((screen.height - height) / 2)
  }

  Rectangle {
    anchors.fill: parent
    color: Color.background
    radius: Style.cornerRadius
    border.color: Qt.alpha(Color.foreground, 0.15)
    border.width: 1
    clip: true

    Column {
      anchors.fill: parent
      anchors.margins: 16
      spacing: 12

      Row {
        width: parent.width
        height: 28
        spacing: 8

        Text {
          text: "Control Panel"
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: 16
          font.bold: true
          anchors.verticalCenter: parent.verticalCenter
        }

        Item { width: parent.width - x - closeBtn.width - 8; height: 1 }

        Rectangle {
          id: closeBtn
          width: 28; height: 28; radius: 6
          color: closeMouse.containsMouse ? Color.accent : "transparent"
          border.color: Qt.alpha(Color.foreground, 0.2)
          border.width: 1
          anchors.verticalCenter: parent.verticalCenter

          Text {
            anchors.centerIn: parent
            text: "x"
            color: closeMouse.containsMouse ? Color.background : Color.foreground
            font.family: Style.font.family
            font.pixelSize: 14
          }
          MouseArea { id: closeMouse; anchors.fill: parent; hoverEnabled: true; onClicked: win.visible = false }
        }
      }

      Rectangle { width: parent.width; height: 1; color: "#333"; opacity: 0.4 }

      Text {
        text: "Desktop panel working! ESC to close."
        color: Color.foreground
        font.pixelSize: 14
      }
    }
  }

  // ESC closes
  Keys.onEscapePressed: win.visible = false
}
