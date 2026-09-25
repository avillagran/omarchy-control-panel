// Omarchy Control Panel — BarWidget launcher.
// Left click opens the standalone desktop FloatingWindow through
// bin/toggle-desktop.sh, following the gmail-panel/x-panel pattern. The window
// runs in a separate Quickshell process and survives bar restarts. The toggle
// closes an existing window or launches it when absent.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui

BarWidget {
  id: root
  moduleName: "omarchy-control-panel"

  readonly property string binPath: Qt.resolvedUrl("bin/toggle-desktop.sh").toString().replace("file://", "")
  readonly property string superWBindPath: Qt.resolvedUrl("bin/apply-superw-bind").toString().replace("file://", "")
  readonly property string scrollFeelPath: Qt.resolvedUrl("bin/apply-scroll-feel").toString().replace("file://", "")

  // Shape contract for shell.summon/hide/toggle routing (Bar.findPanelWidget
  // requires open/close/opened on the bar-widget root).
  readonly property bool opened: false
  readonly property bool popoutSwitchClosing: false

  // Invoke through bash as a second line of defence: local installs/copies can
  // lose the executable bit, which used to make every bar click fail silently.
  function open() { Quickshell.execDetached(["bash", root.binPath]) }
  function close() { Quickshell.execDetached(["bash", root.binPath]) }
  function toggle() { Quickshell.execDetached(["bash", root.binPath]) }
  function closeForPopoutSwitch() {}

  // This widget exists with the main shell, unlike the standalone settings
  // window. Restore persistent runtime state at login and repair it after a
  // Hyprland reload or another component resets the live values.
  function ensurePersistentState() {
    Quickshell.execDetached(["bash", root.superWBindPath])
    Quickshell.execDetached(["bash", root.scrollFeelPath])
  }
  Component.onCompleted: root.ensurePersistentState()
  Timer {
    interval: 5000
    repeat: true
    running: true
    onTriggered: root.ensurePersistentState()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰒓"
    tooltipText: "Omarchy Control Panel — click: ventana independiente (sobrevive reinicios del bar)"

    onPressed: function(b) {
      if (b === Qt.LeftButton) root.toggle()
    }
  }
}