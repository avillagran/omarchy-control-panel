// Omarchy Control Panel — BarWidget launcher.
// Left click opens the standalone desktop FloatingWindow through
// bin/toggle-desktop.sh, following the gmail-panel/x-panel pattern. The window
// runs in a separate Quickshell process and survives bar restarts. The toggle
// closes an existing window or launches it when absent.
import QtQuick 6.11
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Ui

BarWidget {
  id: root
  moduleName: "omarchy-control-panel"

  readonly property string binPath: Qt.resolvedUrl("bin/toggle-desktop.sh").toString().replace("file://", "")
  readonly property string superWBindPath: Qt.resolvedUrl("bin/apply-superw-bind").toString().replace("file://", "")
  readonly property string scrollFeelPath: Qt.resolvedUrl("bin/apply-scroll-feel").toString().replace("file://", "")
  readonly property string deviceRulesPath: Qt.resolvedUrl("bin/apply-device-rules").toString().replace("file://", "")
  readonly property string displaySyncPath: Qt.resolvedUrl("bin/display-hotplug-sync").toString().replace("file://", "")

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
  Component.onCompleted: {
    root.ensurePersistentState()
    deviceRulesTimer.restart()
    root.knownScreenTopology = root.screenTopology
    // Monitors may have changed while the shell was down (or at login with a
    // different set connected). --startup only restores profile geometry when
    // the monitor combination differs from the last synced one.
    displaySyncStartupTimer.restart()
  }

  // Monitor hotplug must keep geometry, workspace ranges and the persisted Lua
  // in sync even while the Control Panel window is closed. Quickshell also
  // emits screensChanged for surface lifecycle events, so compare output names.
  readonly property string screenTopology: {
    var names = []
    for (var i = 0; i < Quickshell.screens.length; i++)
      names.push(String(Quickshell.screens[i].name || ""))
    names.sort()
    return names.join("|")
  }
  property string knownScreenTopology: ""
  onScreenTopologyChanged: {
    if (root.knownScreenTopology === "") { root.knownScreenTopology = root.screenTopology; return }
    if (root.screenTopology === root.knownScreenTopology) return
    root.knownScreenTopology = root.screenTopology
    // Hyprland adopts a new output a moment after its Wayland global appears;
    // the second pass catches a topology that was still settling.
    displaySyncTimer.restart()
    displaySyncRetryTimer.restart()
  }
  // Per-device trackpad rules (hl.device) are rebuilt by Hyprland on every
  // config reload and can come back at defaults. Replay the persisted lines
  // once Hyprland has settled; only reload events trigger this, never a poll,
  // because each hl.device re-configures libinput for that device.
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event && String(event.name || "") === "configreloaded") deviceRulesTimer.restart()
    }
  }
  Timer {
    id: deviceRulesTimer
    interval: 1500
    repeat: false
    onTriggered: Quickshell.execDetached(["bash", root.deviceRulesPath])
  }
  Timer {
    id: displaySyncStartupTimer
    interval: 3000
    repeat: false
    onTriggered: Quickshell.execDetached(["python3", root.displaySyncPath, "--startup"])
  }
  Timer {
    id: displaySyncTimer
    interval: 1500
    repeat: false
    onTriggered: Quickshell.execDetached(["python3", root.displaySyncPath])
  }
  Timer {
    id: displaySyncRetryTimer
    interval: 6000
    repeat: false
    onTriggered: Quickshell.execDetached(["python3", root.displaySyncPath])
  }
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