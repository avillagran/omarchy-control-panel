pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

Item {
  id: root
  property bool enabled: true
  property bool open: false
  property var toplevels: ToplevelManager.toplevels.values

  function updateEnabled(raw) {
    try {
      var value = JSON.parse(raw || "{}")
      root.enabled = value.missionControlEnabled === true
    } catch (error) {
      root.enabled = false
    }
  }

  FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/control-panel-prefs.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.updateEnabled(text())
    onFileChanged: reload()
  }

  function toggle() {
    if (!enabled) return
    open = !open
  }

  function close() { open = false }

  function workspaceId(toplevel) {
    try { return Number(toplevel.workspace.id) || 0 } catch (error) { return 0 }
  }

  function title(toplevel) {
    return String(toplevel.title || toplevel.appId || "Window")
  }

  Variants {
    model: Quickshell.screens
    delegate: PanelWindow {
      required property var modelData
      screen: modelData
      visible: root.open
      color: "transparent"
      WlrLayershell.namespace: "omarchy-control-panel-mission-control"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
      anchors { top: true; bottom: true; left: true; right: true }

      Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0.03, 0.04, 0.07, 0.93)

        ColumnLayout {
          anchors.fill: parent
          anchors.margins: Style.space(36)
          spacing: Style.space(18)

          RowLayout {
            Layout.fillWidth: true
            Text {
              Layout.fillWidth: true
              text: "Mission Control"
              color: Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.heading
              font.bold: true
            }
            Text {
              text: "SUPER+SHIFT+↑  ·  ESC to close"
              color: Color.foreground
              opacity: 0.65
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
          }

          GridView {
            id: windows
            Layout.fillWidth: true
            Layout.fillHeight: true
            cellWidth: Math.max(220, width / 3)
            cellHeight: 150
            clip: true
            model: root.toplevels
            delegate: Rectangle {
              required property var modelData
              width: windows.cellWidth - Style.space(14)
              height: windows.cellHeight - Style.space(14)
              radius: Style.cornerRadius
              color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)
              border.color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.18)
              border.width: 1

              Column {
                anchors.fill: parent
                anchors.margins: Style.space(14)
                spacing: Style.space(8)
                Text {
                  text: "Workspace " + root.workspaceId(modelData)
                  color: Color.accent
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }
                Text {
                  width: parent.width
                  text: root.title(modelData)
                  color: Color.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  font.bold: true
                  elide: Text.ElideRight
                }
                Text {
                  width: parent.width
                  text: String(modelData.appId || "")
                  color: Color.foreground
                  opacity: 0.6
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }
              }

              MouseArea {
                anchors.fill: parent
                onClicked: {
                  try { modelData.activate() } catch (error) {}
                  root.close()
                }
              }
            }
          }
        }

        TapHandler {
          acceptedButtons: Qt.RightButton
          onTapped: root.close()
        }
      }

      Shortcut { sequence: "Escape"; onActivated: root.close() }
    }
  }
}
