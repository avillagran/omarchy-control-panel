import QtQuick 6.11
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Task Manager page. omarchy-task-manager stays its own plugin and repo; the
// panel ships it on by default, is its on/off switch and edits the same prefs
// as the card's gear (through the plugin's own `task-manager pref K V`). The
// activity graph is loaded from the installed plugin's folder
// (ActivityGraph.qml), so both plugins always draw the same thing; Omi lives
// in the panel header.
Column {
  id: root

  required property var core
  property bool active: false

  readonly property string pluginId: core.taskManagerId
  readonly property string pluginDir: Quickshell.env("HOME") + "/.config/omarchy/plugins/" + pluginId
  readonly property string launcher: pluginDir + "/bin/task-manager-launch.sh"
  readonly property string keybindScript: pluginDir + "/bin/task-manager-keybind.sh"
  readonly property string installUrl: "https://raw.githubusercontent.com/avillagran/omarchy-task-manager/main/install.sh"

  property bool probed: false
  property bool installed: false
  property bool pluginEnabled: false
  property bool watchdogOn: false
  property bool keybindOn: false
  property bool busy: false
  property var hist: ({})
  property var prefs: ({})
  property real cpuNow: 0
  property real memNow: 0
  property int frozenCount: 0

  readonly property bool running: installed && pluginEnabled
  // Same defaults as the Task Manager card.
  readonly property int maxRam: pref("watchMaxRam", 94)
  readonly property int maxCpu: pref("watchMaxCpu", 0)
  readonly property string barMode: {
    var m = prefs["barMode"]
    if (m === "off" || m === "numbers" || m === "graph") return m
    return pref("barStats", false) ? "numbers" : "off"
  }

  spacing: 0

  function t(key) { return core.t(core.uiLang, key) }

  function pref(k, dflt) {
    var v = prefs[k]
    return v !== undefined && v !== null && v !== "" ? (typeof dflt === "number" ? Number(v) : v) : dflt
  }

  // Optimistic local update; the helper persists it and the card picks it
  // up from `state.prefs` on its next poll.
  function setPref(k, v) {
    var p = Object.assign({}, prefs)
    p[k] = v
    prefs = p
    var s = typeof v === "string" ? v : typeof v === "number" ? String(v) : (v ? "1" : "0")
    Quickshell.execDetached([launcher, "pref", k, s])
  }

  // Sliders write once the value settles, not on every drag step.
  property string pendingKey: ""
  property int pendingValue: 0
  function setPrefSoon(k, v) {
    var p = Object.assign({}, prefs)
    p[k] = v
    prefs = p
    pendingKey = k
    pendingValue = v
    prefWriteTimer.restart()
  }
  Timer {
    id: prefWriteTimer
    interval: 350
    onTriggered: if (root.pendingKey !== "") root.setPref(root.pendingKey, root.pendingValue)
  }

  function probe() {
    if (!probeProc.running) probeProc.running = true
  }

  function setEnabled(on) {
    if (busy) return
    busy = true
    pluginEnabled = on
    var cmd
    if (on && installed) cmd = "bash '" + pluginDir + "/install.sh' --enable"
    else if (on) cmd = "curl -fsSL '" + installUrl + "' | bash"
    else cmd = "bash '" + pluginDir + "/install.sh' --disable"
    actionProc.command = ["bash", "-lc", cmd]
    actionProc.running = true
  }

  function setKeybind(on) {
    keybindOn = on
    Quickshell.execDetached([keybindScript, on ? "enable" : "disable"])
    keybindRecheck.restart()
  }

  // Ship it by default: the first time the panel runs without the Task
  // Manager installed, install it once. Turning it off later is remembered.
  function maybeAutoInstall() {
    if (!probed || !core.prefsLoaded || core.taskManagerOffered) return
    core.taskManagerOffered = true
    core.savePrefs()
    if (!installed) setEnabled(true)
  }

  Component.onCompleted: probe()
  onActiveChanged: if (active) { probe(); pollTimer.restart() }
  Connections {
    target: root.core
    function onPrefsLoadedChanged() { root.maybeAutoInstall() }
  }

  Process {
    id: probeProc
    command: ["bash", "-lc",
      "echo INST=$(test -f '" + root.pluginDir + "/manifest.json' && echo yes || echo no); " +
      "echo EN=$(omarchy plugin list --json 2>/dev/null | python3 -c 'import json,sys\n" +
      "d=json.load(sys.stdin)\nd=d if isinstance(d,list) else d.get(\"plugins\",[])\n" +
      "print(\"yes\" if any(p.get(\"id\")==\"" + root.pluginId + "\" and p.get(\"enabled\") for p in d) else \"no\")' 2>/dev/null); " +
      "echo WD=$(systemctl --user is-active omarchy-task-manager.service 2>/dev/null); " +
      "echo KB=$('" + root.keybindScript + "' status 2>/dev/null)"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = text.split("\n")
        for (var i = 0; i < lines.length; i++) {
          var kv = lines[i].split("=")
          if (kv[0] === "INST") root.installed = kv[1] === "yes"
          else if (kv[0] === "EN" && !root.busy) root.pluginEnabled = kv[1] === "yes"
          else if (kv[0] === "WD") root.watchdogOn = kv[1] === "active"
          else if (kv[0] === "KB") root.keybindOn = kv[1] === "enabled"
        }
        root.probed = true
        root.maybeAutoInstall()
        if (root.active && root.running) root.pollHistory()
      }
    }
  }

  Process {
    id: actionProc
    onExited: {
      root.busy = false
      root.probe()
    }
  }

  // The keybind helper writes lua that Hyprland reloads on its own; read the
  // real state back once it has settled.
  Timer {
    id: keybindRecheck
    interval: 900
    onTriggered: root.probe()
  }

  function pollHistory() {
    if (!histProc.running) histProc.running = true
    if (!stateProc.running) stateProc.running = true
  }

  // Same cadence as the Task Manager card: the watchdog samples every 2 s.
  Timer {
    id: pollTimer
    interval: 2000
    repeat: true
    running: root.active && root.running
    onTriggered: root.pollHistory()
  }

  Process {
    id: histProc
    command: [root.launcher, "history"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var h = JSON.parse(text || "{}")
          root.hist = h
          if (h.cpu && h.cpu.length) root.cpuNow = h.cpu[h.cpu.length - 1]
          if (h.mem && h.mem.length) root.memNow = h.mem[h.mem.length - 1]
        } catch (e) {}
      }
    }
  }

  Process {
    id: stateProc
    command: [root.launcher, "state"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var d = JSON.parse(text || "{}")
          var n = 0
          ;(d.apps || []).forEach(function(a) { if (a.frozen) n++ })
          ;(d.background || []).forEach(function(b) { if (b.frozen) n++ })
          root.frozenCount = n
          // Never clobber a slider value that is still waiting to be written.
          if (d.prefs && !prefWriteTimer.running) root.prefs = d.prefs
        } catch (e) {}
      }
    }
  }

  PageHeader {
    title: root.t("taskManager")
    subtitle: root.t("taskManagerSubtitle")
    foreground: root.core.fg
    fontFamily: root.core.fontFamily

    Button {
      visible: root.running
      text: root.t("taskManagerOpen")
      bordered: true
      foreground: root.core.fg
      onClicked: Quickshell.execDetached(["omarchy-shell", "shell", "toggle", root.pluginId])
    }
  }

  // Live numbers + status.
  Column {
    width: parent.width
    topPadding: Style.space(6)
    bottomPadding: Style.space(8)
    spacing: Style.space(3)

    Text {
      text: root.running
        ? "CPU " + root.cpuNow.toFixed(0) + "%   ·   RAM " + root.memNow.toFixed(0) + "%"
        : root.t("taskManagerOff")
      color: root.core.fg
      font.family: root.core.fontFamily
      font.pixelSize: Style.font.subtitle
      font.weight: Font.DemiBold
    }
    Text {
      text: !root.running ? root.t("taskManagerOffHint")
        : root.frozenCount > 0 ? root.t("taskManagerPaused").replace("%1", root.frozenCount)
        : root.watchdogOn ? root.t("taskManagerWatching")
        : root.t("taskManagerWatchdogOff")
      color: Qt.alpha(root.core.fg, 0.62)
      font.family: root.core.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  Loader {
    width: parent.width
    active: root.running && root.active
    visible: active
    source: root.core.taskManagerDir + "/ActivityGraph.qml"
    onLoaded: {
      item.hist = Qt.binding(function() { return root.hist })
      item.showCores = Qt.binding(function() { return root.pref("graphDetail", false) === true })
      item.textColor = Qt.binding(function() { return root.core.fg })
      item.accentColor = Qt.binding(function() { return Color.accent })
    }
  }

  GroupHeader {
    title: root.t("groupGeneral")
    foreground: root.core.fg
    fontFamily: root.core.fontFamily
  }

  ToggleRow {
    separator: false
    label: root.busy ? root.t("taskManagerWorking") : root.t("taskManagerEnable")
    description: root.t("taskManagerEnableHint")
    checked: root.pluginEnabled && (root.installed || root.busy)
    enabled: root.probed && !root.busy
    onClicked: root.setEnabled(!checked)
  }

  ToggleRow {
    visible: root.running
    label: root.t("tmKeybind")
    description: "SUPER + SHIFT + T"
    checked: root.keybindOn
    onClicked: root.setKeybind(!root.keybindOn)
  }

  // ---- Watchdog: when to pause apps on its own ----
  GroupHeader {
    visible: root.running
    title: root.t("tmGroupWatchdog")
    note: root.t("tmWatchdogHint")
    foreground: root.core.fg
    fontFamily: root.core.fontFamily
  }

  SliderRow {
    visible: root.running
    separator: false
    label: root.t("tmMaxRam")
    suffix: "%"
    from: 50
    to: 99
    stepSize: 1
    value: root.maxRam
    foreground: root.core.fg
    fontFamily: root.core.fontFamily
    onMoved: root.setPrefSoon("watchMaxRam", Math.round(value))
  }

  ToggleRow {
    visible: root.running
    label: root.t("tmCpuTrigger")
    checked: root.maxCpu > 0
    onClicked: root.setPref("watchMaxCpu", root.maxCpu > 0 ? 0 : 90)
  }

  SliderRow {
    visible: root.running && root.maxCpu > 0
    label: root.t("tmMaxCpu")
    suffix: "%"
    from: 50
    to: 99
    stepSize: 1
    value: Math.max(50, root.maxCpu)
    foreground: root.core.fg
    fontFamily: root.core.fontFamily
    onMoved: root.setPrefSoon("watchMaxCpu", Math.round(value))
  }

  // ---- Bar and graphs ----
  GroupHeader {
    visible: root.running
    title: root.t("tmGroupDisplay")
    foreground: root.core.fg
    fontFamily: root.core.fontFamily
  }

  Item {
    visible: root.running
    width: parent.width
    height: barModeRow.implicitHeight + Style.space(18)

    Text {
      anchors.left: parent.left
      anchors.right: barModeRow.left
      anchors.rightMargin: Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      text: root.t("tmBarMode")
      color: root.core.fg
      font.family: root.core.fontFamily
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
    }

    Row {
      id: barModeRow
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(4)

      Repeater {
        model: [
          { mode: "off", key: "tmBarIcon" },
          { mode: "numbers", key: "tmBarNumbers" },
          { mode: "graph", key: "tmBarGraph" }
        ]
        Button {
          required property var modelData
          text: root.t(modelData.key)
          bordered: true
          selected: root.barMode === modelData.mode
          foreground: root.core.fg
          onClicked: root.setPref("barMode", modelData.mode)
        }
      }
    }
  }

  ToggleRow {
    visible: root.running
    label: root.t("tmSparklines")
    checked: root.pref("sparklines", false) === true
    onClicked: root.setPref("sparklines", !(root.pref("sparklines", false) === true))
  }

  ToggleRow {
    visible: root.running
    label: root.t("tmCores")
    checked: root.pref("graphDetail", false) === true
    onClicked: root.setPref("graphDetail", !(root.pref("graphDetail", false) === true))
  }
}
