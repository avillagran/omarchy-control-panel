// Omarchy Control Panel — BarWidget launcher.
// Click (izq): abre la ventana desktop (FloatingWindow independiente) vía
// bin/toggle-desktop.sh, el mismo patrón que gmail-panel/x-panel usan con
// Quickshell.execDetached. La ventana vive en un proceso Quickshell aparte,
// así sobrevive a reinicios de la barra.
// El comando toggle: si la ventana ya está, la cierra; si no, la abre.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui

BarWidget {
  id: root
  moduleName: "omarchy-control-panel"

  readonly property string binPath: Qt.resolvedUrl("bin/toggle-desktop.sh").toString().replace("file://", "")

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