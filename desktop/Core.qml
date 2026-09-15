import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "DisplayModel.js" as DisplayModel
import "WorkspaceModel.js" as WorkspaceModel
import "ProfileModel.js" as ProfileModel
import "ThemePalette.js" as ThemePalette
import "PointerFeelModel.js" as PointerFeelModel
import "ScrollFeelModel.js" as ScrollFeelModel

Item {
  id: root

  QtObject {
    id: loopGuard
    property var _ts: ({})
    property var _blk: ({})
    property string lastBlocked: ""
    property int lastBlockedCount: 0
    function check(key) {
      var now = Date.now()
      var ts = _ts[key] || []
      ts = ts.filter(function(t) { return now - t < 2000 })
      if (_blk[key]) return false
      if (ts.length >= 3) { _blk[key] = true; lastBlocked = key; lastBlockedCount = ts.length; console.error("[LOOPGUARD] " + key); return false }
      ts.push(now); _ts[key] = ts; return true
    }
    function clearAll() { _ts = {}; _blk = {}; lastBlocked = ""; lastBlockedCount = 0 }
  }

  // Desktop standalone - stubs for bar/settings
  property var bar: ({ barForeground: Color.foreground, fontFamily: Style.font.family, switchPanelFrom: function(){return false} })
  property var settings: ({})
  property string moduleName: "omarchy-control-panel"
  property string ipcTarget: "omarchy-control-panel"
  property bool manageIpc: false
  property bool opened: true
  signal closeRequested()
  function toggle(){ opened ? close() : open() }
  property var controller: QtObject { property bool open: root.opened; function show(){ root.opened = true } function hide(){ root.closeRequested() } function toggle(){ root.toggle() } }
  readonly property color barForeground: Color.foreground
  property var anchorItem: null
  property var hostWidget: null
  readonly property int contentWidth: 495
  property bool externalNavigation: false

  property string statusMessage: ""

  readonly property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
  readonly property color fg: barForeground

  // UI language follows the OS locale prefix (auto-detected from currentLocale).
  readonly property string uiLang: {
    var p = (currentLocale || "es_ES").toLowerCase().split("_")[0]
    var supported = ["en","es","pt","fr","de","it","nl","pl","ru","ja","ko","zh","ar","tr","sv","da","no","fi","cs"]
    return supported.indexOf(p) >= 0 ? p : "en"
  }
  function t(lang, key) {
    var table = i18nData[lang] || i18nData.en
    return table && table[key] !== undefined ? table[key] : (i18nData.en && i18nData.en[key] !== undefined ? i18nData.en[key] : key)
  }
  // UI strings live in i18n.json (next to this file) so they can be edited as
  // plain data without touching the QML. Fallback below covers the tab titles
  // until the external file loads; everything else comes from i18n.json.
  property var i18nData: ({
    en: { trackpad: "Trackpad", animation: "Animation", windows: "Windows", devices: "Devices", kblang: "Keyboard & Language", home: "Home" },
    es: { trackpad: "Trackpad", animation: "Animación", windows: "Ventanas", devices: "Dispositivos", kblang: "Teclado e Idioma", home: "Inicio" },
    pt: { trackpad: "Trackpad", animation: "Animação", windows: "Janelas", devices: "Dispositivos", kblang: "Teclado e Idioma", home: "Início" },
    fr: { trackpad: "Trackpad", animation: "Animation", windows: "Fenêtres", devices: "Périphériques", kblang: "Clavier et Langue", home: "Accueil" }
  })
  Process {
    id: i18nLoader
    command: ["bash", "-lc",
      "cat '" + Qt.resolvedUrl("i18n.json").toString().replace("file://", "") + "'"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.i18nData = JSON.parse(text) }
        catch (e) { console.error("[mcp] i18n.json parse failed:", e) }
      }
    }
  }

  readonly property var tabs: [
    { title: t(uiLang, "trackpad"), page: 0, devOnly: false },
    { title: t(uiLang, "windows"), page: 1, devOnly: false },
    { title: t(uiLang, "displays"), page: 2, devOnly: false },
    { title: t(uiLang, "kblang"), page: 3, devOnly: false },
    { title: t(uiLang, "devices"), page: 4, devOnly: false },
    { title: t(uiLang, "networkDevices"), page: 5, devOnly: true },
    { title: t(uiLang, "backup"), page: 6, devOnly: true },
    { title: t(uiLang, "profiles"), page: 7, devOnly: false }
  ]
  property int currentTab: 0
  property bool devMode: false
  property var networkDevices: []
  property var selectedNetworkDevice: null

  function setDevMode(on) {
    root.devMode = on
    if (!on && (root.currentTab === 5 || root.currentTab === 6))
      root.currentTab = 7
    root.savePrefs()
  }

  // Live system state, refreshed on open.
  property bool naturalScroll: false
  property bool animationsEnabled: true
  property bool wsAnimationOn: false
  property bool missionControlEnabled: false
  property bool missionControlBusy: false
  property string missionControlError: ""
  property string workspaceIndicatorMode: "none"
  property int workspaceIndicatorPadding: 4
  property bool nightLightOn: false
  property real cursorSensitivity: 0
  property real trackpadSensitivity: 0
  property real trackpadScrollFactor: 1
  property string trackpadAccelProfile: "adaptive"
  property bool trackpadFeelConfigured: false
  property bool pointerFeelDirty: false
  property var pointerFeelPrevious: null
  // Scroll feel (touchpad scroll acceleration + coast). DEV ONLY: the four
  // input:touchpad:scroll_* keys only exist on a compositor built with the
  // scroll patch; on stock Hyprland they are unknown config keys and would
  // raise config errors. scrollPatchSupported is probed at runtime and gates
  // both the UI controls and the writeLua emission.
  property int scrollAccelProfile: 2
  property real scrollAccelSpeed: 1.0
  property real scrollAccelMax: 3.0
  property int scrollDecel: 600
  property bool scrollFeelConfigured: false
  property string scrollIgnoreMode: "browsers"
  property bool scrollIgnoreSupported: false
  property bool scrollPatchProbed: false
  property bool scrollPatchSupported: false
  property bool disableWhileTyping: true
  property bool clickfingerBehavior: true
  property int practiceHits: 0
  property int practiceTargetIndex: 0
  property bool flatAccel: false
  property int gapsIn: 6
  property int gapsOut: 10
  property int fontBaseSize: 12
  property int cursorSize: 24
  property string kbLayout: "us"
  property int singleMonitorWorkspaces: 10
  property int multiMonitorWorkspaces: 5
  property string workspaceTopology: ""
  property string currentLocale: ""
  property string customLocale: ""
  property int slowSyncLeft: 0

  // Physical-keyboard pairing suggestion for the chosen OS locale.
  readonly property string suggestedLayout: {
    var l = currentLocale.toLowerCase()
    if (l.indexOf("es_es") === 0) return "es"
    if (l.indexOf("es_") === 0) return "latam"
    if (l.indexOf("en_gb") === 0) return "gb"
    if (l.indexOf("en") === 0) return "us"
    if (l.indexOf("pt") === 0) return "br"
    if (l.indexOf("fr") === 0) return "fr"
    if (l.indexOf("de") === 0) return "de"
    return ""
  }
  property bool suggestionDismissed: false
  onSuggestedLayoutChanged: suggestionDismissed = false
  readonly property bool showSuggestion: suggestedLayout !== ""
    && !suggestionDismissed
    && kbLayout.split(",")[0] !== suggestedLayout

  // Keyboard backlight (MacBooks and other laptops with *kbd_backlight*).
  property int kbBacklightPct: 50
  property bool kbdLedFound: false
  readonly property bool hasKbBacklight: kbdLedFound

  property bool swipe3On: false
  property bool trackpadGesturesInstalled: false
  property bool kittyInstalled: true
  property bool inertiaOn: false
  property bool tapToClick: false
  property var trackpadNames: []
  property var allMiceNames: []
  property bool middleBtnOff: false
  property bool browserCloseTabOn: true
  property string defaultTerm: ""
  property string pluginDir: Qt.resolvedUrl(".").toString().replace("file://", "")
  readonly property string binDir: Quickshell.shellDir + "/../bin"

  // APFS (Extras): driver presence + detected partitions.
  property bool apfsInstalled: false
  property var apfsList: []
  property string apfsCommandText: ""

  // Displays tab: live monitor state and the in-progress layout.
  property var displays: []
  property int displaySelectedIndex: 0
  property bool displayLoading: false
  property var monitorColors: ({})
  property var workspaceThemeColors: ({})
  // Mission Control is rendered natively by MissionControl.qml.
  // Names of outputs seen on the last state read, used to detect a hotplugged
  // (newly connected) monitor and auto-arrange it.
  property var displayKnownNames: []
  property bool displayApplying: false
  property bool displayAwaitingConfirmation: false
  // True for a few seconds after we apply a display change, so the periodic
  // display refresh does not clobber root.displays back to the (possibly not
  // yet adopted or concurrently reverted) live value before the user keeps it.
  property bool displayApplyPending: false
  // Last live/applied layout used only to classify safety. Profiles/prefs are
  // persistence, not a reliable baseline for deciding whether mode changed.
  property var displayConfirmedState: []
  property int displaySecondsRemaining: 15
  property string displayStatusMessage: ""
  property string displayRefreshMessage: ""
  // Identify-all mode: show a numbered overlay on every physical monitor.
  property bool identifyAllDisplays: false
  // True while a display tile is being dragged. Suppresses the physical
  // identify overlay during the drag so Quickshell does not create/destroy
  // Wayland PanelWindows mid-gesture (which segfaults in QWaylandWindow::setGeometry).
  property bool displayDragging: false
  readonly property string displayHelperPath: root.binDir + "/display-manager"

  // Active profile auto-apply: keeps the selected profile sticky across plugin
  // restarts and monitor hotplug. lastAppliedProfileId avoids loops.
  property string lastAppliedProfileId: ""
  property bool profileApplyQueued: false

  readonly property var displaySelected: displays.length && displaySelectedIndex < displays.length ? displays[displaySelectedIndex] : null
  readonly property int displayActiveCount: displays.filter(function(d) { return !d.disabled }).length
  readonly property bool displayValidLayout: displayActiveCount > 0 && !DisplayModel.hasOverlap(displays)

  function displayColor(name) {
    return ThemePalette.resolve(root.displayColorRole(name), root.workspaceThemeColors)
  }

  function displayColorRole(name) {
    return WorkspaceModel.explicitColorRoleForMonitor(name, root.monitorColors)
  }

  function setDisplayColor(name, color) {
    if (!name) return
    var copy = Object.assign({}, root.monitorColors)
    if (WorkspaceModel.explicitColorRoleForMonitor(name, copy) === color)
      delete copy[name]
    else
      copy[name] = color
    root.monitorColors = copy
    root.savePrefs()
    root.scheduleWorkspaceWidgetSync()
    root.statusMessage = root.t(root.uiLang, "workspaceColorSaved") + " · " + name
  }

  function indicatorModeKey(mode) {
    if (mode === "square") return "indicatorSquare"
    if (mode === "rounded") return "indicatorRounded"
    if (mode === "circle") return "indicatorCircle"
    return "indicatorNone"
  }

  function setWorkspaceIndicatorMode(mode) {
    root.workspaceIndicatorMode = WorkspaceModel.normalizeIndicatorMode(mode)
    root.savePrefs()
    root.scheduleWorkspaceWidgetSync()
    root.statusMessage = root.t(root.uiLang, "workspaceIndicatorMode") + " · "
      + root.t(root.uiLang, root.indicatorModeKey(root.workspaceIndicatorMode))
  }

  function setWorkspaceIndicatorPadding(value) {
    root.workspaceIndicatorPadding = Math.max(0, Math.min(4, Math.round(value)))
    root.savePrefs()
    root.scheduleWorkspaceWidgetSync()
  }

  function scheduleWorkspaceWidgetSync() {
    workspaceWidgetSyncTimer.restart()
  }

  function setMissionControl(on) {
    root.missionControlEnabled = on
    root.missionControlBusy = false
    root.missionControlError = ""
    root.savePrefs()
  }

  function syncMissionControlAnimation() {
    // The native overview is rendered by MissionControl.qml; no compositor
    // plugin or external reload is required when animation settings change.
  }

  function missionControlParseOutput(raw) {
    var lines = String(raw || "").trim().split("\n")
    for (var i = lines.length - 1; i >= 0; i--) {
      try { return JSON.parse(lines[i]) } catch (error) {}
    }
    return null
  }

  function displayParse(text) {
    try { return JSON.parse(String(text || "")) } catch (e) { return null }
  }

  function displayProcessError(text, fallback) {
    var parsed = displayParse(text)
    return parsed && parsed.error ? parsed.error : fallback
  }

  function displayRefresh(message) {
    if (displayStateProc.running) { if (message) displayRefreshMessage = message; return }
    displayRefreshMessage = message || ""
    displayLoading = true
    displayStatusMessage = message || displayStatusMessage
    displayStateProc.command = [displayHelperPath, "state"]
    displayStateProc.running = true
  }

  // Hotplug: when the SET of connected outputs changes (a monitor is plugged or
  // unplugged) refresh the display list automatically. Reconfiguring an existing
  // output (mode/scale/position) keeps the same names, so it does not retrigger.
  readonly property string displayScreenNames: {
    var names = []
    var s = Quickshell.screens
    for (var i = 0; i < s.length; i++) names.push(s[i].name)
    names.sort()
    return names.join(",")
  }
  onDisplayScreenNamesChanged: {
    if (!root.opened) return
    // Hyprland adopts a newly plugged output (and drops an unplugged one) a
    // moment after the Wayland global appears/disappears. A single immediate
    // read races that: the helper can return the OLD monitor list and the UI
    // stays stale in both directions (connected monitor missing / disconnected
    // monitor lingering). Re-read at +1.2s and +3.5s to catch up.
    root.displayRefresh()
    displayHotplugRetry1.restart()
    displayHotplugRetry2.restart()
  }

  Timer {
    id: displayHotplugRetry1
    interval: 1200
    repeat: false
    onTriggered: root.displayRefresh()
  }
  Timer {
    id: displayHotplugRetry2
    interval: 3500
    repeat: false
    onTriggered: root.displayRefresh()
  }

  function displayUpdate(key, value) {
    if (!displaySelected) return
    var copy = DisplayModel.clone(displays)
    copy[displaySelectedIndex][key] = value
    // A scale or mode change alters the logical size but not x, which would
    // leave a gap or overlap. Reflow so every neighbour snaps flush against the
    // changed display, keeping the intended arrangement (stacked or side-by-side).
    if (key === "scale" || key === "mode") copy = DisplayModel.reflowAroundSelected(copy, displaySelectedIndex)
    displays = copy
  }

  function displaySetResolution(value) {
    if (!displaySelected) return
    displayUpdate("mode", DisplayModel.nearestMode(displaySelected.modes, value, DisplayModel.refresh(displaySelected.mode)))
  }

  function displaySetRefresh(value) {
    if (!displaySelected) return
    displayUpdate("mode", DisplayModel.nearestMode(displaySelected.modes, DisplayModel.resolution(displaySelected.mode), value))
  }

  function displayToggleEnabled() {
    if (!displaySelected || (!displaySelected.disabled && displayActiveCount <= 1)) return
    displayUpdate("disabled", !displaySelected.disabled)
  }

  function displayApplyPreview() {
    console.warn("[CP] displayApplyPreview called, awaiting=" + root.displayAwaitingConfirmation + " applying=" + root.displayApplying + " valid=" + root.displayValidLayout)
    // Never start a new preview while one is already awaiting confirmation:
    // the snapshots/rollback timers would chain and corrupt the state.
    if (!displayValidLayout || displayApplying || displayAwaitingConfirmation) return
    displayApplying = true
    displayStatusMessage = "Applying preview…"
    displayApplyProc.command = [displayHelperPath, "preview", JSON.stringify(DisplayModel.clone(displays))]
    displayApplyProc.running = true
  }

  // Apply safe, easily-reversible changes (scale, position) immediately, with
  // no rollback timer. Resolution/orientation still go through the preview +
  // Keep/Revert flow because a bad mode can leave the screen unusable.
  function displayApplyInstant() {
    console.warn("[CP] displayApplyInstant")
    Quickshell.execDetached(["bash", "-lc", "echo \"$(date +%H:%M:%S) CP-APPLY-INSTANT displays=\" + JSON.stringify(root.displays.map(function(d){return d.name+':'+d.scale+'@'+d.x+'x'+d.y})) >> /tmp/cp-version.log"])
    if (!displayValidLayout || displayInstantProc.running) return
    // Suppress the periodic refresh from clobbering root.displays for 3s while
    // the new scale settles in Hyprland (or a concurrent hyprctl reload would
    // revert it). displayApplyPending clears itself via applySettleTimer.
    root.displayApplyPending = true
    applySettleTimer.restart()
    displayInstantProc.command = [displayHelperPath, "apply", JSON.stringify(DisplayModel.clone(displays))]
    displayInstantProc.running = true
  }

  function displayApplyChanges() {
    if (DisplayModel.requiresConfirmation(root.displays, root.displayConfirmedState))
      root.displayApplyPreview()
    else
      root.displayApplyInstant()
  }

  // Clears displayApplyPending a few seconds after an instant apply so the
  // periodic refresh resumes tracking the live layout (needed for hotplug).
  Timer {
    id: applySettleTimer
    interval: 3000
    repeat: false
    onTriggered: root.displayApplyPending = false
  }

  function displayConfirm() {
    if (displayConfirmProc.running || displayRevertProc.running) return
    displayConfirmProc.command = [displayHelperPath, "confirm"]
    displayConfirmProc.running = true
  }


  function hyprReload() {
    if (!loopGuard.check("hyprReload")) return
    console.warn("[CP] hyprReload called, awaiting=" + root.displayAwaitingConfirmation + " applying=" + root.displayApplying + " pending=" + root.hyprReloadPending)
    if (root.displayAwaitingConfirmation || root.displayApplying) {
      root.hyprReloadPending = true
    } else {
          }
  }

  onDisplayApplyingChanged: {
    if (!root.displayApplying && !root.displayAwaitingConfirmation && root.hyprReloadPending) {
      root.hyprReloadPending = false
          }
  }

  function displayRevert() {
    console.warn("[CP] displayRevert, pending=" + root.hyprReloadPending + " seconds=" + root.displaySecondsRemaining)
    if (displayRevertProc.running || displayConfirmProc.running) return
    displayStatusMessage = "Restoring previous layout…"
    displayRevertProc.command = [displayHelperPath, "revert"]
    displayRevertProc.running = true
    if (root.hyprReloadPending) {
      root.hyprReloadPending = false
          }
  }

  // Keep the previewed layout: confirm with the helper (cancels the 15s
  // rollback), then persist into saved.displays so writeLua() records the
  // hl.monitor rules alongside every other setting in control-panel.lua.
  function displayKeep() {
    console.warn("[CP] displayKeep, pending=" + root.hyprReloadPending + " seconds=" + root.displaySecondsRemaining)
    Quickshell.execDetached(["bash", "-lc", "echo \"$(date +%H:%M:%S) KEEP displays=" + JSON.stringify(root.displays.map(function(d){return d.name+':'+d.scale})) + " saved=" + JSON.stringify(root.saved.displays.map(function(d){return d.name+':'+d.scale})) + " live=$(hyprctl monitors -j 2>/dev/null | python3 -c 'import sys,json; print(json.dumps([(m.get(\"name\"),m.get(\"scale\")) for m in json.load(sys.stdin)]))' 2>/dev/null)\" >> /tmp/cp-keep.log"])
    // Stop the rollback timer immediately so it cannot fire (and revert) after
    // we confirm. displayConfirmProc.onExited also stops it, but a race could let
    // the timer expire first and revert the very change the user just kept.
    displayConfirmationTimer.stop()
    root.displayAwaitingConfirmation = false
    displayConfirm()
    saved.displays = DisplayModel.clone(displays)
    displayConfirmedState = DisplayModel.clone(displays)
    savePrefs()
    if (root.hyprReloadPending) {
      root.hyprReloadPending = false
          }
  }

  // Menu tab: inline calculator + web search (Alfred-style helpers).
  property string calcInput: ""
  property string calcResult: ""
  property bool calcValid: false
  property string calcStatus: ""
  property string searchInput: ""

  function evaluateCalc() {
    var expr = String(root.calcInput || "").trim()
    if (!expr) {
      root.calcResult = ""
      root.calcValid = false
      root.calcStatus = ""
      return
    }
    // Delegamos el cálculo a un proceso externo (Python ast-whitelist) para
    // no evaluar nunca código arbitrario dentro del shell.
    calcEvalProc.command = ["omarchy-calc", expr]
    calcEvalProc.running = true
  }

  function copyCalc() {
    if (!root.calcValid || !root.calcResult) return
    Quickshell.execDetached(["bash", "-lc", "printf %s " + Util.shellQuote(root.calcResult) + " | wl-copy"])
    root.calcStatus = root.t(root.uiLang, "calcCopied")
  }

  function webSearch() {
    var q = String(root.searchInput || "").trim()
    if (!q) return
    Quickshell.execDetached(["omarchy-launch-webapp", "https://www.google.com/search?q=" + encodeURIComponent(q)])
  }

  Process {
    id: calcEvalProc
    property string collected: ""
    stdout: SplitParser {
      onRead: function(data) { calcEvalProc.collected += data }
    }
    onExited: function() {
      var raw = String(calcEvalProc.collected || "").trim()
      calcEvalProc.collected = ""
      if (raw && raw !== "Error") {
        root.calcResult = raw
        root.calcValid = true
        root.calcStatus = ""
      } else {
        root.calcResult = ""
        root.calcValid = false
        root.calcStatus = root.t(root.uiLang, "notMath")
      }
    }
  }

  function open(payloadJson) {
    if (!loopGuard.check("open")) return
    controller.show()
    // Check first whether a display preview is still armed. If it is, skip
    // reapplySaved() because replaying control-panel.lua would re-apply the
    // previous (saved) display scale and cancel the pending preview before the
    // user gets a chance to Keep/Revert it.
    if (!root.displayAwaitingConfirmation && !displayPendingProc.running) {
      displayPendingProc.command = [root.displayHelperPath, "pending"]
      displayPendingProc.running = true
    } else {
      root.continueOpen()
    }
  }

  function continueOpen() {
    if (!loopGuard.check("continueOpen")) return
    console.warn("[CP] continueOpen, awaiting=" + root.displayAwaitingConfirmation + " pending=" + root.hyprReloadPending)
    // Re-apply everything we persist before reading, so a plugin/shell
    // restart that dropped the volatile hyprctl eval values still lands on
    // the saved state instead of whatever Hyprland's defaults are.
    reapplySaved()
  }

  // The panel only ever wrote values as volatile `hyprctl eval` calls plus a
  // generated Lua file (~/.config/hypr/control-panel.lua) that hyprland.lua
  // requires last. A plugin/shell restart does not re-run those evals, so the
  // running config can diverge from what the toggles show. Replaying the saved
  // Lua file line by line makes the system match the saved state on every open
  // and on plugin load — idempotent and covers every knob at once.
  function reapplySaved() {
    if (!loopGuard.check("reapplySaved")) return
    console.warn("[CP] reapplySaved called, awaiting=" + root.displayAwaitingConfirmation)
    var f = root.luaPath
    // Replay the generated Lua into Hyprland. Skip hl.monitor lines: re-issuing
    // them on every plugin (re)load forces Hyprland to recompute the workspace
    // grid ("cells") and repositions windows, which is the "windows jump / 287
    // by 86 cells" bug. The live monitor layout is already correct; we only need
    // to restore input/trackpad/keyboard/cursor/bindings, which are the parts
    // that can fall back to defaults between sessions.
    if (reapplyProc.running) return
    reapplyProc.command = ["bash", "-lc",
      "f='" + f + "'; [ -f \"$f\" ] || exit 0; " +
      "for i in $(seq 1 40); do hyprctl getoption general:gaps_out >/dev/null 2>&1 && break; sleep 0.25; done; " +
      "while IFS= read -r l; do l=\"${l%$'\\r'}\"; [ -z \"$l\" ] && continue; " +
      "case \"$l\" in \\#*) continue;; esac; " +
      "case \"$l\" in hl.monitor*) continue;; esac; " +
      "case \"$l\" in hl.bind*) continue;; esac; " +
      "case \"$l\" in hl.unbind*) continue;; esac; " +
      // Scroll-patch lines: replaying them here is pointless (the values
      // persist in the compositor for the whole session) and on an unpatched
      // build each eval would fail. Within-session state comes from the
      // probe/state reader on open instead.
      "case \"$l\" in *scroll_accel*|*scroll_decel*|*scroll_ignore*) continue;; esac; " +
      "hyprctl eval \"$l\" >/dev/null 2>&1 || true; done < \"$f\""]
    reapplyProc.running = true
  }

  Process {
    id: reapplyProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function() {
      // The replay and the following read are deliberately serialized. A
      // fire-and-forget replay raced refresh(), which read Hyprland defaults
      // and then rewrote those defaults to control-panel.lua.
      if (!luaStateProc.running) luaStateProc.running = true
      if (root.prefsLoaded) root.refresh()
      syncTimer.restart()
    }
  }

  function close() {
    identifyAllDisplays = false
    controller.hide()
  }

  function refresh() {
    if (!loopGuard.check("refresh")) return
    if (readProc.running) readProc.running = false
    readProc.running = true
    if (!kbdLedProbe.running) kbdLedProbe.running = true
    if (!scrollProbeProc.running) scrollProbeProc.running = true
    displayRefresh()
  }

  function run(cmd) {
    if (cmd.indexOf("hyprctl reload") >= 0) console.warn("[CP] run hyprctl reload")
    Quickshell.execDetached(["bash", "-lc", cmd])
    syncTimer.restart()
  }

  // Copy text to the system clipboard and flash a brief confirmation.
  function copyToClipboard(text) {
    if (text) {
      if (typeof Qt !== "undefined" && Qt.clipboard) Qt.clipboard.setText(text)
      else Quickshell.execDetached(["bash", "-lc", "printf '%s' " + JSON.stringify(text) + " | wl-copy 2>/dev/null || xclip -selection clipboard 2>/dev/null || true"])
      root.statusMessage = "Copied to clipboard"
      syncTimer.restart()
    }
  }

  // ---- Persistence, omasettings-style -------------------------------------
  // Applied live via hyprctl AND written to our own Lua file, which
  // hyprland.lua requires last. Reboots and config reloads therefore keep
  // every setting without this panel doing any replay. User-written files
  // are never parsed or rewritten; ours can be deleted at any time.
  property string luaPath: Quickshell.env("HOME") + "/.config/hypr/control-panel.lua"

  property var saved: ({
    naturalScroll: false,
    flatAccel: false,
    sensitivity: 0,
    trackpadSensitivity: 0,
    trackpadScrollFactor: 1,
    trackpadAccelProfile: "adaptive",
    trackpadFeelConfigured: false,
    scrollAccelProfile: 2,
    scrollAccelSpeed: 1.0,
    scrollAccelMax: 3.0,
    scrollDecel: 600,
    scrollFeelConfigured: false,
    scrollIgnoreMode: "browsers",
    disableWhileTyping: true,
    clickfingerBehavior: true,
    animations: true,
    wsAnimation: false,
    gapsIn: -1,
    gapsOut: -1,
    fontBaseSize: 12,
    cursorSize: 24,
    kbLayout: "",
    swipe3: false,
    tapToClick: false,
    browserCloseTab: true,
    middleButtonScreenshotOff: false,
    inertia: false,
    singleMonitorWorkspaces: 10,
    multiMonitorWorkspaces: 5,
    displays: []
  })

  // writeLua() is only safe once the persisted prefs are loaded; otherwise an
  // early caller (e.g. the natural-scroll sync) regenerates control-panel.lua
  // with default values and silently drops the swipe gestures and toggles.
  property bool prefsLoaded: false
  property bool readProcDone: false
  property bool luaStateProcDone: false
  readonly property bool pointerFeelReady: root.prefsLoaded && root.readProcDone && root.luaStateProcDone

  function writeLua() {
    if (!root.prefsLoaded) return
    var L = ["-- Generated by Omarchy Control Panel. Safe to delete."]
    L.push("hl.config({ input = { natural_scroll = " + (saved.naturalScroll ? "true" : "false") + " } })")
    var touchpadSettings = "tap_to_click = " + (saved.tapToClick ? "true" : "false")
    if (saved.trackpadFeelConfigured) {
      touchpadSettings += ", scroll_factor = " + PointerFeelModel.clampScrollFactor(saved.trackpadScrollFactor).toFixed(2)
      touchpadSettings += ", disable_while_typing = " + (saved.disableWhileTyping ? "true" : "false")
      touchpadSettings += ", clickfinger_behavior = " + (saved.clickfingerBehavior ? "true" : "false")
    }
    L.push("hl.config({ input = { touchpad = { " + touchpadSettings + " } } })")
    // Scroll acceleration + coast (DEV, requires a compositor built with the
    // touchpad scroll patch). Emission is gated on BOTH the runtime capability
    // probe and the user having configured values here, so a stock Hyprland
    // never sees these keys (they are unknown config keys and would raise
    // load-time config errors on it).
    if (root.scrollPatchSupported && saved.scrollFeelConfigured) {
      // "native" mode turns the patch off globally; "browsers" keeps the
      // patch away from apps with their own inertia (browsers, kitty, …).
      var effProfile = ScrollFeelModel.profileForMode(saved.scrollIgnoreMode, saved.scrollAccelProfile)
      var ignoreList = ScrollFeelModel.ignoreListForMode(saved.scrollIgnoreMode)
      var scrollStatement = ScrollFeelModel.luaConfigStatement(
        effProfile, saved.scrollAccelSpeed,
        saved.scrollAccelMax, saved.scrollDecel, ignoreList,
        root.scrollIgnoreSupported)
      if (scrollStatement) {
        L.push("-- Touchpad scroll acceleration + coast (patched compositor only)")
        L.push(scrollStatement)
      }
    }
    L.push("hl.config({ input = { sensitivity = " + Number(saved.sensitivity).toFixed(2) + " } })")
    L.push('hl.config({ input = { accel_profile = "' + (saved.flatAccel ? "flat" : "adaptive") + '" } })')
    L.push('hl.env("XCURSOR_SIZE", "' + (saved.cursorSize >= 0 ? saved.cursorSize : 24) + '")')
    L.push('hl.env("HYPRCURSOR_SIZE", "' + (saved.cursorSize >= 0 ? saved.cursorSize : 24) + '")')
    L.push("hl.config({ animations = { enabled = " + (saved.animations ? "true" : "false") + " } })")
    L.push('hl.animation({ leaf = "workspaces", enabled = ' + (saved.wsAnimation ? "true" : "false")
           + ', speed = 4, bezier = "easeOutQuint", style = "slide" })')
    if (saved.kbLayout !== "")
      L.push('hl.config({ input = { kb_layout = "' + saved.kbLayout + '" } })')
    var gi = saved.gapsIn >= 0 ? saved.gapsIn : 5
    var go = saved.gapsOut >= 0 ? saved.gapsOut : 10
    L.push("hl.config({ general = { gaps_in = " + gi + ", gaps_out = " + go + " } })")
    var workspacePlan = WorkspaceModel.assignments(
      saved.displays && saved.displays.length ? saved.displays : root.displays,
      saved.singleMonitorWorkspaces,
      saved.multiMonitorWorkspaces)
    if (workspacePlan.length) {
      L.push("-- Workspace distribution by monitor topology")
      for (var wi = 0; wi < workspacePlan.length; wi++) {
        var wr = workspacePlan[wi]
        L.push('hl.workspace_rule({ workspace = "' + wr.workspace + '", monitor = "' + wr.monitor
          + '", default = ' + (wr.default ? "true" : "false") + ', persistent = true })')
      }
    }
    // 3-finger swipe switches workspaces. We OWN this gesture (the toggle is in
    // this panel) and invert it when natural scrolling is on, so the swipe feels
    // consistent with the rest of the trackpad. Hyprland cannot unbind gestures,
    // so to avoid colliding with user.trackpad-gestures (which also defines a
    // 3-finger swipe) we disable that plugin's 3-finger assignment while our
    // 3-finger swipe gestures are persisted in a separate file
    // (~/.config/hypr/control-panel-gestures.lua) that is required by input.lua,
    // so Hyprland loads them at startup. See syncGesturesFile().
    // The Apple MTP is mouse-classified, so the global input:natural_scroll
    // often doesn't reach it. The working knob is the per-device
    // natural_scroll boolean. scroll_factor must stay >= 0 (negative is
    // rejected), so we pin it to 1 to cancel any stale negative factor and
    // let natural_scroll alone control direction.
    // Invert scroll on every mouse/touchpad so natural scrolling works everywhere.
    var mice = root.allMiceNames
    for (var mi = 0; mi < mice.length; mi++) {
      var touchpad = root.trackpadNames.indexOf(mice[mi]) >= 0
      var factor = saved.trackpadFeelConfigured && touchpad
        ? PointerFeelModel.clampScrollFactor(saved.trackpadScrollFactor).toFixed(2) : "1"
      L.push('hl.device({ name = ' + JSON.stringify(mice[mi]) + ', natural_scroll = ' + (saved.naturalScroll ? "true" : "false") + ', scroll_factor = ' + factor + ' })')
      if (saved.trackpadFeelConfigured && touchpad) {
        var feelStatement = PointerFeelModel.luaDeviceStatement(mice[mi], saved.trackpadSensitivity,
          saved.trackpadScrollFactor, saved.trackpadAccelProfile)
        if (feelStatement) L.push(feelStatement)
      }
    }

    // Display layout is intentionally NOT written to control-panel.lua.
    // Re-issuing hl.monitor on every `hyprctl reload` (triggered by sensei,
    // Omarchy, or other plugins) forces Hyprland to recompute the workspace grid
    // ("cells") and repositions windows — the "287 by 86 cells" jump bug. The
    // monitor arrangement lives in saved.displays and is applied explicitly only
    // by the display helper (user edits, profile apply, real hotplug), never by
    // an implicit reload.

    // When enabled, SUPER+W closes the active TAB in browsers (simulated Ctrl+W
    // via wtype/ydotool) instead of killing the whole window. Outside browsers it
    // falls back to closing the window normally. We unbind the default SUPER+W
    // first so the two don't collide/error.
    //
    // FIXES (verified against the sensei/Hyprland rewrite):
    //  - The browser branch used `os.execute("bash script &")`. Hyprland reaps its
    //    own children, so the detached subprocess could be killed before wtype
    //    delivered Ctrl+W — the tab never closed. We now launch it through
    //    `hl.dsp.exec_cmd(...)`, the same exec dispatcher Omarchy uses for every
    //    other keybind, which Hyprland manages as a real exec (not a reaped child).
    //  - We pass the already-detected class as $1 so the script never re-reads the
    //    active window (removes the focus/timing race between keypress and script).
    //  - The non-browser branch used `hl.dispatch(hl.dsp.window.close())`, which
    //    errors ("expected a dispatcher"). It is now `hl.dsp.window.close()` — the
    //    current close dispatcher.
    // NOTE: sensei.lua wraps hl.bind(keys:string, dispatcher, options) — passing a
    // table as arg1 errors ("expected string, got table"), so use the string +
    // function form, same as the rest of the config.
    // SUPER+W bind is NOT written to the generated Lua. Re-issuing hl.bind on
    // every plugin (re)load / hyprctl reload re-registers the key and, because it
    // uses { release = true }, Hyprland fires the callback if SUPER is held when
    // the bind is re-added — which closed the focused window in a loop. The bind
    // is applied exactly once via applySuperWBind() (called from the settings
    // toggles), never from the reloadable Lua.

    // When enabled, unbind the middle-mouse-button screenshot (mouse:274) that
    // the user.trackpad-gestures plugin defines — an uncomfortable combo for
    // some trackpads. control-panel.lua is required after gestures-generated.lua,
    // so this unbind wins the load order.
    if (saved.middleButtonScreenshotOff) {
      L.push('-- Disable middle-button screenshot (toggle "Middle-button screenshot")')
      L.push('hl.unbind("mouse:274")')
    }

    // Atomic, symlink-safe write via external script (mktemp + mv -f).
    luaWriter.command = ["bash", Quickshell.shellDir + "/../write-lua-atomic.sh",
      root.luaPath, L.join("\n")]
    luaWriter.running = true
  }

  // Keep user.trackpad-gestures from ALSO defining a 3-finger swipe, which would
  // collide with ours ("overshadowed" warning — Hyprland can't unbind gestures).
  // While our swipe3 toggle is ON we clear that plugin's generated gesture file
  // so only our (natural-scroll-aware, inverted) swipe is active; while OFF we
  // regenerate it from the plugin's defaults so it works on its own. The two are
  // mutually exclusive, so there is never a double definition.
  function syncGesturesFile() {
    var enabled = saved.swipe3 ? "true" : "false"
    var leftTarget = saved.naturalScroll ? "+1" : "-1"
    var rightTarget = saved.naturalScroll ? "-1" : "+1"
    Quickshell.execDetached(["bash", "-lc",
      "python3 '" + root.binDir + "/sync-gestures-file.py' " +
      "--enabled " + enabled + " --left '" + leftTarget + "' --right '" + rightTarget + "' --no-reload"])
      }

  function syncTrackpadGestures() {
    var tp = Quickshell.env("HOME") + "/.config/hypr/gestures-generated.lua"
    var sh = Quickshell.env("HOME") + "/.config/omarchy/plugins/user.trackpad-gestures/apply-gestures.sh"
    if (root.saved.swipe3) {
      tpSync.command = ["bash", "-lc",
        "printf '%s\\n' '-- Cleared by omarchy-control-panel (swipe3 on): 3-finger swipe owned by control-panel' > '" + tp + "'"]
    } else {
      tpSync.command = ["bash", "-lc",
        "if [ -f '" + sh + "' ]; then '" + sh + "' true clickfinger lrm threefinger screenshot false none none none none none none relative_workspace relative_workspace none none none none none none none none none none none none; else printf '%s\\n' '-- user.trackpad-gestures plugin not installed; cleared by omarchy-control-panel (swipe3 off)' > '" + tp + "'; fi"]
    }
    tpSync.running = true
  }

  Process {
    id: tpSync
    stdout: StdioCollector { waitForEnd: true }
  }

  property FileView profilesFile: FileView {
    path: root.profilesPath
    blockLoading: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadProfilesFromText(text())
    onLoadFailed: function() { root.loadProfilesFromText("") }
  }

  Process {
    id: luaWriter
    stdout: StdioCollector { waitForEnd: true }
  }

  // This Hyprland build parses hyprlang/Lua config, so runtime changes go
  // through `hyprctl eval` with an hl.config() expression instead of the
  // legacy `hyprctl keyword`.
  function hyprSet(section, key, valueLiteral) {
    Quickshell.execDetached([
      "hyprctl", "eval",
      "hl.config({ " + section + " = { " + key + " = " + valueLiteral + " } })"
    ])
    syncTimer.restart()
  }

  // Natural scrolling applies to every pointing device the user might use, so we
  // set the global input:natural_scroll flag and then invert scroll direction on
  // every mouse/touchpad via scroll_factor. The M4 real touchpad already works
  // with natural_scroll, so its scroll_factor stays neutral; everything else gets
  // -1 to invert.
  function setNaturalScroll(on, quiet) {
    saved.naturalScroll = on
    naturalScroll = on

    // Global flag for real touchpads.
    Quickshell.execDetached(["bash", "-lc",
      "hyprctl eval 'hl.config({ input = { natural_scroll = " + (on ? "true" : "false") + " } })'"])

    // Per-device scroll inversion for every mouse/touchpad.
    var names = root.allMiceNames
    for (var i = 0; i < names.length; i++) {
      var n = names[i]
      var factor = root.trackpadFeelConfigured && root.trackpadNames.indexOf(n) >= 0
        ? PointerFeelModel.clampScrollFactor(root.trackpadScrollFactor).toFixed(2) : "1"
      Quickshell.execDetached(["hyprctl", "eval",
        'hl.device({ name = ' + JSON.stringify(n) + ', natural_scroll = ' + (on ? "true" : "false") + ', scroll_factor = ' + factor + ' })'])
    }

    if (!quiet) statusMessage = root.t(root.uiLang, "invScroll") + " · " + (on ? "on" : "off")
    writeLua()
    syncTimer.restart()
    savePrefs()
  }

  function applySensitivity(v) {
    saved.sensitivity = v
    cursorSensitivity = v
    hyprSet("input", "sensitivity", Number(v).toFixed(2))
    writeLua()
  }

  function stagePointerFeel(sensitivity, scrollFactor, accelProfile) {
    root.trackpadSensitivity = PointerFeelModel.clampSensitivity(sensitivity)
    root.trackpadScrollFactor = PointerFeelModel.clampScrollFactor(scrollFactor)
    root.trackpadAccelProfile = accelProfile === "flat" ? "flat" : "adaptive"
    root.pointerFeelDirty = !root.trackpadFeelConfigured
      || Math.abs(root.trackpadSensitivity - Number(root.saved.trackpadSensitivity)) > 0.001
      || Math.abs(root.trackpadScrollFactor - Number(root.saved.trackpadScrollFactor)) > 0.001
      || root.trackpadAccelProfile !== root.saved.trackpadAccelProfile
  }

  // Live-apply only (hyprctl eval); persistence is debounced separately.
  function applyPointerFeelLive() {
    if (!root.pointerFeelReady || !root.trackpadNames.length) return
    for (var i = 0; i < root.trackpadNames.length; i++) {
      var statement = PointerFeelModel.luaDeviceStatement(root.trackpadNames[i],
        PointerFeelModel.clampSensitivity(root.trackpadSensitivity),
        PointerFeelModel.clampScrollFactor(root.trackpadScrollFactor),
        root.trackpadAccelProfile)
      if (statement) Quickshell.execDetached(["hyprctl", "eval", statement])
    }
    Quickshell.execDetached(["hyprctl", "eval",
      "hl.config({ input = { touchpad = { scroll_factor = "
        + PointerFeelModel.clampScrollFactor(root.trackpadScrollFactor).toFixed(2) + " } } })"])
  }

  // Persist the staged values (saved prefs + control-panel.lua).
  function savePointerFeel() {
    if (!root.pointerFeelReady) return
    root.saved.trackpadSensitivity = PointerFeelModel.clampSensitivity(root.trackpadSensitivity)
    root.saved.trackpadScrollFactor = PointerFeelModel.clampScrollFactor(root.trackpadScrollFactor)
    root.saved.trackpadAccelProfile = root.trackpadAccelProfile === "flat" ? "flat" : "adaptive"
    root.saved.trackpadFeelConfigured = true
    root.trackpadFeelConfigured = true
    root.pointerFeelDirty = false
    root.writeLua()
    root.savePrefs()
  }

  // Immediate live apply + persist (profile apply / restore path).
  function applyPointerFeel() {
    if (!root.pointerFeelReady) return
    if (!root.trackpadNames.length) {
      root.statusMessage = root.t(root.uiLang, "pointerFeelNoDevice")
      return
    }
    root.applyPointerFeelLive()
    root.savePointerFeel()
    root.statusMessage = root.t(root.uiLang, "pointerFeelApplied")
  }

  // User-driven change (sliders, presets): applies in real time and persists
  // the latest value. The FIRST change of the session snapshots the current
  // values so "Restore previous" can undo the whole run of adjustments.
  function userChangePointerFeel(sensitivity, scrollFactor, accelProfile) {
    if (!root.pointerFeelReady) return
    if (root.pointerFeelPrevious === null) {
      root.pointerFeelPrevious = {
        sensitivity: root.trackpadSensitivity,
        scrollFactor: root.trackpadScrollFactor,
        accelProfile: root.trackpadAccelProfile,
        configured: root.saved.trackpadFeelConfigured
      }
    }
    root.stagePointerFeel(sensitivity, scrollFactor, accelProfile)
    pointerFeelLiveTimer.restart()
    pointerFeelSaveTimer.restart()
  }

  Timer {
    id: pointerFeelLiveTimer
    interval: 120
    repeat: false
    onTriggered: root.applyPointerFeelLive()
  }

  Timer {
    id: pointerFeelSaveTimer
    interval: 600
    repeat: false
    onTriggered: root.savePointerFeel()
  }

  function selectPointerPreset(id) {
    var value = PointerFeelModel.preset(id)
    if (value) root.userChangePointerFeel(value.sensitivity, value.scrollFactor, value.accelProfile)
  }

  function restorePointerFeel() {
    if (!root.pointerFeelReady) return
    if (!root.pointerFeelPrevious) return
    var previous = root.pointerFeelPrevious
    root.pointerFeelPrevious = null
    root.stagePointerFeel(previous.sensitivity, previous.scrollFactor, previous.accelProfile)
    previous.configured ? root.applyPointerFeel() : root.resetPointerFeel(previous.sensitivity, previous.scrollFactor, previous.accelProfile)
    root.pointerFeelPrevious = null
    root.statusMessage = root.t(root.uiLang, "pointerFeelRestored")
  }

  function resetPointerFeel(sensitivity, scrollFactor, accelProfile) {
    if (!root.pointerFeelReady) return
    root.trackpadSensitivity = PointerFeelModel.clampSensitivity(sensitivity)
    root.trackpadScrollFactor = PointerFeelModel.clampScrollFactor(scrollFactor)
    root.trackpadAccelProfile = accelProfile === "flat" ? "flat" : "adaptive"
    root.trackpadFeelConfigured = false
    root.saved.trackpadSensitivity = root.trackpadSensitivity
    root.saved.trackpadScrollFactor = root.trackpadScrollFactor
    root.saved.trackpadAccelProfile = root.trackpadAccelProfile
    root.saved.trackpadFeelConfigured = false
    var liveProfile = root.flatAccel ? "flat" : "adaptive"
    for (var i = 0; i < root.trackpadNames.length; i++) {
      var statement = PointerFeelModel.luaDeviceStatement(root.trackpadNames[i], 0, 1, liveProfile)
      if (statement) Quickshell.execDetached(["hyprctl", "eval", statement])
    }
    root.pointerFeelDirty = false
    root.writeLua()
    root.savePrefs()
  }

  function setDisableWhileTyping(on) {
    if (!root.pointerFeelReady) return
    root.disableWhileTyping = on
    root.saved.disableWhileTyping = on
    root.saved.trackpadFeelConfigured = true
    root.trackpadFeelConfigured = true
    Quickshell.execDetached(["hyprctl", "eval",
      "hl.config({ input = { touchpad = { disable_while_typing = " + (on ? "true" : "false") + " } } })"])
    root.writeLua()
    root.savePrefs()
  }

  // ---- Scroll feel (DEV: touchpad scroll acceleration + coast) ------------
  // Live values are read from the compositor on open (scrollStateProc) after
  // the capability probe confirms the patch keys exist. Setters are inert on
  // an unpatched compositor: touching them cannot emit unknown config keys.

  function stageScrollFeel(profile, speed, max, decel) {
    root.scrollAccelProfile = ScrollFeelModel.clampProfile(profile)
    root.scrollAccelSpeed = ScrollFeelModel.clampSpeed(speed)
    root.scrollAccelMax = ScrollFeelModel.clampMax(max)
    root.scrollDecel = ScrollFeelModel.clampDecel(decel)
  }

  function updateScrollFeel(profile, speed, max, decel, quiet) {
    if (!root.scrollPatchSupported) return
    root.stageScrollFeel(profile, speed, max, decel)
    root.scrollFeelConfigured = true
    root.saved.scrollFeelConfigured = true
    root.saved.scrollAccelProfile = root.scrollAccelProfile
    root.saved.scrollAccelSpeed = root.scrollAccelSpeed
    root.saved.scrollAccelMax = root.scrollAccelMax
    root.saved.scrollDecel = root.scrollDecel
    var statement = ScrollFeelModel.luaConfigStatement(
      root.scrollAccelProfile, root.scrollAccelSpeed,
      root.scrollAccelMax, root.scrollDecel,
      ScrollFeelModel.ignoreListForMode(root.saved.scrollIgnoreMode),
      root.scrollIgnoreSupported)
    if (statement) Quickshell.execDetached(["hyprctl", "eval", statement])
    root.writeLua()
    root.savePrefs()
    if (!quiet) root.statusMessage = root.t(root.uiLang, "scrollFeelApplied")
  }

  function selectScrollPreset(id) {
    if (!root.scrollPatchSupported) return
    var value = ScrollFeelModel.preset(id)
    if (!value) return
    // Choosing an accel preset implies the user wants the patch active:
    // leave "native" (patch off) mode so the choice actually takes effect.
    if (root.saved.scrollIgnoreMode === "native") {
      root.saved.scrollIgnoreMode = "off"
      root.scrollIgnoreMode = "off"
    }
    root.updateScrollFeel(value.profile, value.speed, value.max, value.decel)
  }

  // Where the patch inertia applies: "off" = everywhere (incl. browsers,
  // which then feel doubly inert), "browsers" = browsers/terminals with
  // their own inertia keep it, "native" = patch off globally.
  function updateScrollIgnoreMode(mode, quiet) {
    if (!root.scrollPatchSupported || !root.scrollIgnoreSupported) return
    mode = ScrollFeelModel.clampIgnoreMode(mode)
    root.scrollIgnoreMode = mode
    root.saved.scrollIgnoreMode = mode
    root.scrollFeelConfigured = true
    root.saved.scrollFeelConfigured = true
    var effProfile = ScrollFeelModel.profileForMode(mode, root.saved.scrollAccelProfile)
    var statement = ScrollFeelModel.luaConfigStatement(
      effProfile, root.saved.scrollAccelSpeed,
      root.saved.scrollAccelMax, root.saved.scrollDecel,
      ScrollFeelModel.ignoreListForMode(mode))
    if (statement) Quickshell.execDetached(["hyprctl", "eval", statement])
    root.scrollAccelProfile = effProfile
    root.writeLua()
    root.savePrefs()
    if (!quiet) root.statusMessage = root.t(root.uiLang, "scrollIgnoreApplied")
  }

  // "Config like macOS": one click applies the whole macOS-style trackpad
  // bundle — natural (inverted) scrolling, tap to click, two-finger right
  // click, pause while typing, 3-finger workspace swipe, middle-button
  // screenshot off, inertial scrolling (Adaptive preset, except browsers and
  // terminals when the patch knows scroll_ignore_classes), system animations
  // and the workspace slide transition. Every setter applies live AND
  // rewrites control-panel.lua, so the bundle survives logout/login.
  // Scroll values use the Adaptive preset: its speed/cap/decel match the
  // macOS coasting feel the patch was tuned for.
  function applyMacOSConfig() {
    root.setNaturalScroll(true, true)
    root.setTapToClick(true)
    root.setDisableWhileTyping(true)
    root.setClickfingerBehavior(true)
    root.setSwipe3(true)
    root.setMiddleBtnOff(true)
    root.setInertia(true)
    root.applyAnimations(true)
    root.animSet(true)
    // writeLua() only persists disable_while_typing / clickfinger_behavior /
    // scroll_factor once the user has configured the trackpad feel — mark it
    // so the macOS bundle actually survives a relogin.
    root.trackpadFeelConfigured = true
    root.saved.trackpadFeelConfigured = true
    if (root.scrollPatchSupported) {
      root.selectScrollPreset("adaptive")
      if (root.scrollIgnoreSupported)
        root.updateScrollIgnoreMode("browsers", true)
    }
    root.writeLua()
    root.savePrefs()
    root.statusMessage = root.t(root.uiLang, "macConfigApplied")
  }

  Process {
    id: scrollProbeProc
    command: ["hyprctl", "getoption", "input:touchpad:scroll_decel", "-j"]
    stdout: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      root.scrollPatchProbed = true
      root.scrollPatchSupported = ScrollFeelModel.supportsPatchFromProbe(
        scrollProbeProc.stdout.text, exitCode)
      if (root.scrollPatchSupported && !scrollStateProc.running)
        scrollStateProc.running = true
    }
  }

  Process {
    id: scrollStateProc
    command: ["bash", "-lc",
      "hyprctl getoption input:touchpad:scroll_accel_profile -j; " +
      "hyprctl getoption input:touchpad:scroll_accel_speed -j; " +
      "hyprctl getoption input:touchpad:scroll_accel_max -j; " +
      "hyprctl getoption input:touchpad:scroll_decel -j; " +
      "hyprctl getoption input:touchpad:scroll_ignore_classes -j"]
    stdout: StdioCollector { waitForEnd: true }
    onRunningChanged: {
      if (running) return
      var values = ScrollFeelModel.parseLiveValues(scrollStateProc.stdout.text)
      root.scrollAccelProfile = values.profile
      root.scrollAccelSpeed = values.speed
      root.scrollAccelMax = values.max
      root.scrollDecel = values.decel
      root.scrollIgnoreSupported = values.ignoreSupported
      // Before the user configures anything here, mirror the compositor:
      // profile 0 reads as "native", a class list as "browsers", etc.
      // (Only when the compositor actually knows the ignore key.)
      if (!root.saved.scrollFeelConfigured && values.ignoreSupported) {
        root.scrollIgnoreMode = ScrollFeelModel.modeFromLive(
          values.profile, values.ignoreClasses)
        root.saved.scrollIgnoreMode = root.scrollIgnoreMode
      }
    }
  }

  function setClickfingerBehavior(on) {
    if (!root.pointerFeelReady) return
    root.clickfingerBehavior = on
    root.saved.clickfingerBehavior = on
    root.saved.trackpadFeelConfigured = true
    root.trackpadFeelConfigured = true
    Quickshell.execDetached(["hyprctl", "eval",
      "hl.config({ input = { touchpad = { clickfinger_behavior = " + (on ? "true" : "false") + " } } })"])
    root.writeLua()
    root.savePrefs()
  }

  function advancePracticeTarget() {
    root.practiceHits++
    root.practiceTargetIndex = (root.practiceTargetIndex + 1) % PointerFeelModel.practicePointCount()
  }

  function applyFontSize(v) {
    v = Math.round(Math.max(9, Math.min(26, v)))
    if (root.fontBaseSize === v) return
    root.fontBaseSize = v
    saved.fontBaseSize = v
    // Aplica en vivo al panel (sin esperar reinicio del shell)
    Style.fontBaseSize = v
    var f = Quickshell.env("HOME") + "/.config/omarchy/shell.toml"
    Quickshell.execDetached(["bash", "-lc",
      "f='" + f + "'; mkdir -p \"$(dirname \"$f\")\"; " +
      "if grep -q '^\\[font\\]' \"$f\" 2>/dev/null; then " +
      "  if grep -q '^base-size *= ' \"$f\"; then sed -i 's/^base-size *= .*/base-size = " + v + "/' \"$f\"; " +
      "  else sed -i '/^\\[font\\]/a\\base-size = " + v + "' \"$f\"; fi; " +
      "else printf '\\n[font]\\nbase-size = " + v + "\\n' >> \"$f\"; fi"])
    statusMessage = "Font size · " + v + "px"
  }

  function applyCursorSize(v) {
    v = Math.round(Math.max(8, Math.min(64, v)))
    if (root.cursorSize === v) return
    root.cursorSize = v
    saved.cursorSize = v
    // Hyprland does not expose input:cursor_size. Cursor size is controlled by
    // the XCURSOR_SIZE / HYPRCURSOR_SIZE environment variables and the current
    // cursor theme. We update the env vars and reload the cursor theme live.
    Quickshell.execDetached(["hyprctl", "eval", 'hl.env("XCURSOR_SIZE", "' + v + '")'])
    Quickshell.execDetached(["hyprctl", "eval", 'hl.env("HYPRCURSOR_SIZE", "' + v + '")'])
    // Reload the current cursor theme so the size change is visible immediately.
    // Try the GNOME/GTK theme first, then fall back to common themes.
    Quickshell.execDetached(["bash", "-lc",
      "T=$(gsettings get org.gnome.desktop.interface cursor-theme 2>/dev/null | tr -d \"'\"); " +
      "[ -z \"$T\" ] && T=${XCURSOR_THEME:-}; " +
      "[ -z \"$T\" ] && T=${HYPRCURSOR_THEME:-}; " +
      "[ -z \"$T\" ] && T=Adwaita; " +
      "hyprctl setcursor \"$T\" " + v])
    writeLua()
    statusMessage = "Cursor size · " + v
  }

  function applyGaps(key, v) {
    if (key === "gaps_in") saved.gapsIn = v
    else saved.gapsOut = v
    hyprSet("general", key, v)
    writeLua()
  }

  function applyAnimations(on) {
    saved.animations = on
    animationsEnabled = on
    hyprSet("animations", "enabled", on ? "true" : "false")
    writeLua()
  }

  // Workspace transitions use the per-animation leaf API — omarchy ships
  // workspaces disabled by default.
  function animSet(on) {
    saved.wsAnimation = on
    wsAnimationOn = on
    var expr = on
      ? 'hl.animation({ leaf = "workspaces", enabled = true, speed = 4, bezier = "easeOutQuint", style = "slide" })'
      : 'hl.animation({ leaf = "workspaces", enabled = false })'
    Quickshell.execDetached(["hyprctl", "eval", expr])
    statusMessage = root.t(root.uiLang, "wsSlide") + " · " + (on ? "on" : "off")
    writeLua()
    syncTimer.restart()
    root.syncMissionControlAnimation()
  }

  function applyKbLayout(layout) {
    kbLayout = layout
    saved.kbLayout = layout
    hyprSet("input", "kb_layout", '"' + layout + '"')
    writeLua()
    statusMessage = root.t(root.uiLang, "physKeyboard") + " · " + layout
  }

  // Apply an already-generated system locale. Uses the root-owned localectl
  // binary directly with a validated argv — no mutable plugin code as root.
  function setLocale(locale) {
    if (!locale || !/^[a-z]{2}(_[A-Z]{2})?\.UTF-8$/.test(locale)) return
    Quickshell.execDetached(["pkexec", "/usr/bin/localectl", "set-locale", locale])
    currentLocale = locale
    statusMessage = root.t(root.uiLang, "sysLanguage") + " · " + locale
    slowSyncLeft = 6
    slowSyncTimer.restart()
  }

  function setKbBacklight(pct) {
    Quickshell.execDetached(["brightnessctl", "-d", "kbd_backlight", "set", pct + "%"])
    kbBacklightPct = pct
  }

  // 3-finger horizontal swipe lives in the user.trackpad-gestures plugin,
  // so flipping it means writing that plugin's layout entry and letting it
  // regenerate its own gestures file.
  // 3-finger horizontal swipe: preference lives in OUR layout entry; when
  // natural scroll is OFF we delegate to the user.trackpad-gestures plugin
  // (it owns the standard bindings); when ON we emit swapped-direction
  // gestures from our own Lua so the swipe matches the inverted axis.
  function setSwipe3(on) {
    swipe3On = on
    saved.swipe3 = on
    savePrefs()
    syncGestures()
    syncTrackpadGestures()
    statusMessage = t(uiLang, "swipe3") + " · " + (on ? "on" : "off")
    slowSyncLeft = 3
    slowSyncTimer.restart()
  }

  function setMiddleBtnOff(on) {
    middleBtnOff = on
    saved.middleButtonScreenshotOff = on
    savePrefs()
    writeLua()
        statusMessage = "Botón central · " + (on ? "desactivado" : "activado")
  }

  // Apply the SUPER+W bind exactly once via a direct hyprctl eval. This must
  // NOT go through the reloadable Lua: re-issuing hl.bind on every plugin
  // (re)load / hyprctl reload re-registers the key, and with { release = true }
  // Hyprland fires the callback if SUPER is held when the bind is re-added —
  // which closed the focused window in a loop. Applying it once here (and only
  // when the toggle changes) avoids that.
  function applySuperWBind() {
    var scriptPath = root.binDir + "/close-tab-or-window.sh"
    var lua = 'hl.unbind("SUPER + W"); hl.bind("SUPER + W", function() ' +
      'local ok, win = pcall(function() return hl.get_active_window() end) ' +
      'local cls = "" ' +
      'if ok and win and win.class then cls = string.lower(tostring(win.class)) end ' +
      'local isBrowser = cls:match("chrome") or cls:match("chromium") or cls:match("firefox") or cls:match("edge") or cls:match("brave") or cls:match("opera") or cls:match("vivaldi") or cls:match("epiphany") or cls:match("gnome%-web") ' +
      'if isBrowser and ' + (saved.browserCloseTab ? "true" : "false") + ' then ' +
      'hl.dispatch(hl.dsp.exec_cmd(string.format("bash ' + scriptPath + ' %s &", cls))) ' +
      'else hl.dispatch(hl.dsp.window.close()) end, { release = true })'
    Quickshell.execDetached(["hyprctl", "eval", lua])
  }

  function setBrowserCloseTab(on) {
    browserCloseTabOn = on
    saved.browserCloseTab = on
    savePrefs()
    writeLua()
    root.applySuperWBind()
        statusMessage = "SUPER+W navegadores · " + (on ? "pestaña" : "ventana")
  }

  // Profiles: save/apply named sets of control-panel settings.
  property var profiles: []
  property string activeProfileId: ""
  property bool profilesLoaded: false
  property string profilesPath: Quickshell.env("HOME") + "/.local/state/omarchy/control-panel-profiles.json"

  function defaultProfiles() {
    return [
      {
        id: "default",
        name: root.t(root.uiLang, "profileDefault"),
        builtin: true,
        settings: {
          displayScale: 1,
          sensitivity: 0,
          trackpadSensitivity: 0,
          trackpadScrollFactor: 1,
          trackpadAccelProfile: "adaptive",
          trackpadFeelConfigured: false,
          disableWhileTyping: true,
          clickfingerBehavior: true,
          cursorSize: 24,
          naturalScroll: false,
          tapToClick: false,
          swipe3: false,
          middleButtonScreenshotOff: false,
          inertia: false,
          fontBaseSize: 12,
          browserCloseTab: true,
          wsAnimation: false,
          animations: true,
          flatAccel: false,
          gapsIn: 6,
          gapsOut: 10,
          kbLayout: "us",
          singleMonitorWorkspaces: 10,
          multiMonitorWorkspaces: 5
        }
      },
      {
        id: "retina",
        name: root.t(root.uiLang, "profileRetina"),
        builtin: true,
        settings: {
          displayScale: 1,
          sensitivity: 0.7,
          trackpadSensitivity: 0.5,
          trackpadScrollFactor: 1.2,
          trackpadAccelProfile: "adaptive",
          trackpadFeelConfigured: true,
          disableWhileTyping: true,
          clickfingerBehavior: true,
          cursorSize: 42,
          naturalScroll: true,
          tapToClick: true,
          swipe3: true,
          middleButtonScreenshotOff: true,
          inertia: true,
          fontBaseSize: 24,
          browserCloseTab: true,
          wsAnimation: true,
          animations: true,
          flatAccel: false,
          gapsIn: 6,
          gapsOut: 10,
          kbLayout: "us",
          singleMonitorWorkspaces: 10,
          multiMonitorWorkspaces: 5
        }
      }
    ]
  }

  // Build a { monitorName: {scale,mode,x,y,transform,disabled,mirror} } map of
  // the current live layout. Used to persist the per-monitor display config
  // inside a profile so it can be re-applied automatically on hotplug.
  function currentDisplayMap() {
    var map = {}
    var list = root.displays && root.displays.length ? root.displays : root.saved.displays
    for (var i = 0; i < list.length; i++) {
      var d = list[i]
      if (!d || !d.name) continue
      map[d.name] = {
        scale: Number(d.scale) || 1,
        mode: d.mode || "preferred",
        x: Number(d.x) || 0,
        y: Number(d.y) || 0,
        transform: Number(d.transform) || 0,
        disabled: !!d.disabled,
        mirror: d.mirror || ""
      }
    }
    return map
  }

  function currentSettings() {
    return {
      displayScale: root.displaySelected ? Number(root.displaySelected.scale) : 1,
      displays: currentDisplayMap(),
      sensitivity: saved.sensitivity,
      trackpadSensitivity: saved.trackpadSensitivity,
      trackpadScrollFactor: saved.trackpadScrollFactor,
      trackpadAccelProfile: saved.trackpadAccelProfile,
      trackpadFeelConfigured: saved.trackpadFeelConfigured,
      scrollFeelConfigured: saved.scrollFeelConfigured,
      scrollIgnoreMode: saved.scrollIgnoreMode,
      scrollAccelProfile: saved.scrollAccelProfile,
      scrollAccelSpeed: saved.scrollAccelSpeed,
      scrollAccelMax: saved.scrollAccelMax,
      scrollDecel: saved.scrollDecel,
      disableWhileTyping: saved.disableWhileTyping,
      clickfingerBehavior: saved.clickfingerBehavior,
      cursorSize: saved.cursorSize,
      naturalScroll: saved.naturalScroll,
      tapToClick: saved.tapToClick,
      swipe3: saved.swipe3,
      middleButtonScreenshotOff: saved.middleButtonScreenshotOff,
      inertia: saved.inertia,
      fontBaseSize: saved.fontBaseSize,
      browserCloseTab: saved.browserCloseTab,
      wsAnimation: saved.wsAnimation,
      animations: saved.animations,
      flatAccel: saved.flatAccel,
      gapsIn: saved.gapsIn,
      gapsOut: saved.gapsOut,
      kbLayout: saved.kbLayout,
      locale: root.currentLocale,
      nightLight: root.nightLightOn,
      defaultTerminal: root.defaultTerm,
      kbBacklightPct: root.hasKbBacklight ? root.kbBacklightPct : undefined,
      singleMonitorWorkspaces: saved.singleMonitorWorkspaces,
      multiMonitorWorkspaces: saved.multiMonitorWorkspaces
    }
  }

  function applyWorkspaceLayout(quiet) {
    if (!root.prefsLoaded) {
      workspaceTopologyTimer.restart()
      return
    }
    var plan = WorkspaceModel.assignments(root.displays,
      root.singleMonitorWorkspaces, root.multiMonitorWorkspaces)
    if (!plan.length) return
    root.saved.singleMonitorWorkspaces = root.singleMonitorWorkspaces
    root.saved.multiMonitorWorkspaces = root.multiMonitorWorkspaces
    var statements = []
    for (var i = 0; i < plan.length; i++) {
      var rule = plan[i]
      statements.push('hl.workspace_rule({ workspace = "' + rule.workspace
        + '", monitor = "' + rule.monitor + '", default = '
        + (rule.default ? "true" : "false") + ', persistent = true })')
    }
    Quickshell.execDetached(["hyprctl", "eval", statements.join("; ")])
    root.writeLua()
    root.savePrefs()
    if (!quiet) root.statusMessage = WorkspaceModel.summary(root.displays,
      root.singleMonitorWorkspaces, root.multiMonitorWorkspaces)
  }

  Timer {
    id: workspaceTopologyTimer
    interval: 350
    repeat: false
    onTriggered: root.applyWorkspaceLayout(true)
  }

  function loadProfilesFromText(raw) {
    try {
      var d = JSON.parse(raw || "{}")
      if (Array.isArray(d.profiles)) {
        var merged = ProfileModel.mergeBuiltins(defaultProfiles(), d.profiles)
        root.profiles = merged
        root.profilesLoaded = true
        root.activeProfileId = d.activeProfileId || ""
        root.lastAppliedProfileId = ""
        var normalized = { activeProfileId: root.activeProfileId, profiles: merged }
        if (JSON.stringify(normalized) !== JSON.stringify(d)) Qt.callLater(root.saveProfiles)
        // Loading profile metadata must be read-only. Applying the active
        // profile here reconfigured outputs every time the panel opened, which
        // caused visible flashes and mode/scale changes. Profiles are applied
        // only by an explicit user action or after a real monitor hotplug.
        return
      }
    } catch (e) {}
    root.profiles = defaultProfiles()
    root.profilesLoaded = true
    root.activeProfileId = "default"
    root.lastAppliedProfileId = ""
    saveProfiles()
  }

  function saveProfiles() {
    var data = { activeProfileId: root.activeProfileId, profiles: root.profiles }
    profilesFile.setText(JSON.stringify(data, null, 2) + "\n")
  }

  // Re-apply a per-monitor display map (from a profile) onto the live layout.
  // Only monitors present in BOTH the map and the live list are touched; their
  // scale/mode/position/transform are set from the saved values. This is what
  // makes a profile "sticky": unplug/replug a monitor and its saved config
  // returns instead of Hyprland's default.
  function applyDisplayMap(map) {
    if (!map || !root.displays.length) return
    var copy = DisplayModel.clone(root.displays)
    var changed = false
    for (var i = 0; i < copy.length; i++) {
      var d = copy[i]
      var saved = map[d.name]
      if (!saved) continue
      if (saved.scale !== undefined && Number(saved.scale) !== Number(d.scale)) { d.scale = Number(saved.scale); changed = true }
      if (saved.mode !== undefined && saved.mode && saved.mode !== d.mode) { d.mode = saved.mode; changed = true }
      if (saved.x !== undefined && Number(saved.x) !== Number(d.x)) { d.x = Number(saved.x); changed = true }
      if (saved.y !== undefined && Number(saved.y) !== Number(d.y)) { d.y = Number(saved.y); changed = true }
      if (saved.transform !== undefined && Number(saved.transform) !== Number(d.transform)) { d.transform = Number(saved.transform); changed = true }
      if (saved.mirror !== undefined && String(saved.mirror || "") !== String(d.mirror || "")) { d.mirror = saved.mirror || ""; changed = true }
    }
    if (!changed) return
    root.displays = copy
    root.saved.displays = DisplayModel.clone(copy)
    root.displayApplyInstant()
    root.writeLua()
    root.savePrefs()
  }

  Timer {
    id: profileApplyTimer
    interval: 200
    repeat: false
    onTriggered: root.applyQueuedProfile()
  }

  function queueApplyActiveProfile() {
    profileApplyQueued = true
    profileApplyTimer.restart()
  }

  function applyQueuedProfile() {
    if (!profileApplyQueued) return
    profileApplyQueued = false
    var id = root.activeProfileId
    if (!id) return
    if (root.lastAppliedProfileId === id) return
    if (!root.prefsLoaded || root.displays.length === 0) {
      queueApplyActiveProfile()
      return
    }
    root.applyProfile(id)
  }

  function applyProfileSettings(id) {
    if (!loopGuard.check("applyProfileSettings")) return
    console.warn("[CP] applyProfileSettings id=" + id)
    var p = null
    for (var i = 0; i < root.profiles.length; i++) {
      if (root.profiles[i].id === id) { p = root.profiles[i]; break }
    }
    if (!p) return
    var s = p.settings
    root.activeProfileId = id
    saveProfiles()
    if (s.sensitivity !== undefined) root.applySensitivity(s.sensitivity)
    if (s.trackpadFeelConfigured === true) {
      root.stagePointerFeel(s.trackpadSensitivity, s.trackpadScrollFactor, s.trackpadAccelProfile)
      root.applyPointerFeel()
      if (s.disableWhileTyping !== undefined) root.setDisableWhileTyping(s.disableWhileTyping)
      if (s.clickfingerBehavior !== undefined) root.setClickfingerBehavior(s.clickfingerBehavior)
    } else if (s.trackpadFeelConfigured === false) root.resetPointerFeel(s.trackpadSensitivity, s.trackpadScrollFactor, s.trackpadAccelProfile)
    if (s.cursorSize !== undefined) root.applyCursorSize(s.cursorSize)
    if (s.naturalScroll !== undefined) root.setNaturalScroll(s.naturalScroll, true)
    if (s.tapToClick !== undefined) root.setTapToClick(s.tapToClick)
    if (s.swipe3 !== undefined) root.setSwipe3(s.swipe3)
    if (s.middleButtonScreenshotOff !== undefined) {
      root.middleBtnOff = s.middleButtonScreenshotOff
      root.saved.middleButtonScreenshotOff = s.middleButtonScreenshotOff
    }
    if (s.inertia !== undefined) root.setInertia(s.inertia)
    if (s.fontBaseSize !== undefined) root.applyFontSize(s.fontBaseSize)
    if (s.browserCloseTab !== undefined) {
      root.browserCloseTabOn = s.browserCloseTab
      root.saved.browserCloseTab = s.browserCloseTab
    }
    if (s.wsAnimation !== undefined) root.animSet(s.wsAnimation)
    if (s.animations !== undefined) root.applyAnimations(s.animations)
    if (s.flatAccel !== undefined) {
      root.flatAccel = s.flatAccel
      root.saved.flatAccel = s.flatAccel
      root.hyprSet("input", "accel_profile", s.flatAccel ? '"flat"' : '"adaptive"')
    }
    if (s.gapsIn !== undefined) { root.gapsIn = s.gapsIn; root.applyGaps("gaps_in", s.gapsIn) }
    if (s.gapsOut !== undefined) { root.gapsOut = s.gapsOut; root.applyGaps("gaps_out", s.gapsOut) }
    if (s.kbLayout !== undefined && s.kbLayout) root.applyKbLayout(s.kbLayout)
    if (s.nightLight !== undefined && s.nightLight !== root.nightLightOn) {
      root.nightLightOn = s.nightLight
      root.run("omarchy-toggle-nightlight")
    }
    if (s.defaultTerminal !== undefined && s.defaultTerminal && s.defaultTerminal !== root.defaultTerm)
      root.run("omarchy-default-terminal " + Util.shellQuote(s.defaultTerminal))
    if (s.kbBacklightPct !== undefined && root.hasKbBacklight) root.setKbBacklight(s.kbBacklightPct)
    if (s.singleMonitorWorkspaces !== undefined) root.singleMonitorWorkspaces = s.singleMonitorWorkspaces
    if (s.multiMonitorWorkspaces !== undefined) root.multiMonitorWorkspaces = s.multiMonitorWorkspaces
    root.applyWorkspaceLayout(true)
    root.writeLua()
    root.statusMessage = root.t(root.uiLang, "profileApply") + " · " + p.name
    console.warn("[CP] applyProfileSettings done, awaiting=" + root.displayAwaitingConfirmation + " pending=" + root.hyprReloadPending)
  }

  function applyProfile(id) {
    if (!loopGuard.check("applyProfile")) return
    root.lastAppliedProfileId = id
    console.warn("[CP] applyProfile id=" + id)
    var p = null
    for (var i = 0; i < root.profiles.length; i++) {
      if (root.profiles[i].id === id) { p = root.profiles[i]; break }
    }
    if (!p) return
    var s = p.settings
    root.activeProfileId = id
    saveProfiles()
    if (s.displays) root.applyDisplayMap(s.displays)
    else if (s.displayScale !== undefined) root.applyDisplayScaleInstant(s.displayScale)
    root.applyProfileSettings(id)
  }

  function applyDisplayScale(scale) {
    if (!root.displays.length) return
    var copy = JSON.parse(JSON.stringify(root.displays))
    for (var i = 0; i < copy.length; i++) {
      if (!copy[i].disabled) copy[i].scale = Number(scale)
    }
    root.displays = copy
    // Scale is a safe change: apply instantly and keep it (no rollback timer).
    // A 15s preview+rollback here meant an unconfirmed scale silently reverted
    // to the old value, which is what the user hit. Resolution/mode still go
    // through displayApplyPreview (Keep/Revert) because a bad mode can blank
    // the screen.
    root.displayApplyInstant()
    if (root.displayAwaitingConfirmation) root.currentTab = root.tabs.length - 1
  }

  function applyDisplayScaleInstant(scale) {
    if (!root.displays.length) return
    var copy = JSON.parse(JSON.stringify(root.displays))
    for (var i = 0; i < copy.length; i++) {
      if (!copy[i].disabled) copy[i].scale = Number(scale)
    }
    root.displays = copy
    root.displayApplyInstant()
    root.saved.displays = DisplayModel.clone(copy)
    root.writeLua()
    root.savePrefs()
  }

  function createProfile(name) {
    var result = ProfileModel.create(root.profiles, name,
      root.t(root.uiLang, "profilePersonal"), root.currentSettings(), Date.now())
    root.profiles = result.profiles
    saveProfiles()
    return result.id
  }

  function duplicateProfile(id) {
    var result = ProfileModel.duplicate(root.profiles, id, " (copy)", Date.now())
    if (!result.id) return ""
    root.profiles = result.profiles
    saveProfiles()
    return result.id
  }

  function saveCurrentToProfile(id) {
    var result = ProfileModel.saveSettings(root.profiles, id, root.currentSettings())
    if (!result.found) return
    root.profiles = result.profiles
    root.activeProfileId = id
    saveProfiles()
    root.statusMessage = root.t(root.uiLang, "profileSave") + " · " + result.name
  }

  function deleteProfile(id) {
    if (id === "default" || id === "retina") return
    root.profiles = ProfileModel.remove(root.profiles, id)
    if (root.activeProfileId === id) root.activeProfileId = ""
    saveProfiles()
  }

  property string editingProfileId: ""
  function renameProfile(id, newName) {
    newName = (newName || "").trim()
    if (!newName) { editingProfileId = ""; return }
    var result = ProfileModel.rename(root.profiles, id, newName)
    if (result.found) {
      root.profiles = result.profiles
      saveProfiles()
      root.statusMessage = root.t(root.uiLang, "profileSave") + " · " + newName
    }
    editingProfileId = ""
  }

  function syncGestures(naturalNow) {
    console.info("[mcp] syncGestures swipe=", saved.swipe3, "natural=", naturalNow)
    writeLua()
    root.syncTrackpadGestures()
    root.syncGesturesFile()
  }

  function tryWriteLua() {
    if (root.readProcDone && root.luaStateProcDone && root.prefsLoaded) {
      root.writeLua()
      root.syncTrackpadGestures()
      // NOTE: do NOT call syncGesturesFile() here. syncGesturesFile() ends with
      //  (hyprctl reload), and tryWriteLua runs on EVERY refresh
      // (readProc/luaStateProc fire on each poll). That created an infinite loop:
      // refresh -> tryWriteLua -> syncGesturesFile -> hyprctl reload -> plugin
      // reloads -> refresh -> ... causing the constant window "jump". Gesture
      // files are written explicitly by the swipe3/natural-scroll toggles, which
      // is the only place a reload is actually wanted.
    }
  }

  function setInertia(on) {
    inertiaOn = on
    saved.inertia = on
    savePrefs()
    statusMessage = t(uiLang, "inertia") + " · " + (on ? "on" : "off")
  }

  // Tap to click: a light tap on the trackpad registers as a click, no
  // physical press needed. Live via hyprctl, persisted in control-panel.lua.
  function setTapToClick(on) {
    saved.tapToClick = on
    tapToClick = on
    Quickshell.execDetached(["hyprctl", "eval",
      'hl.config({ input = { touchpad = { tap_to_click = ' + (on ? "true" : "false") + ' } } })'])
    statusMessage = root.t(root.uiLang, "tapClick") + " · " + (on ? "on" : "off")
    writeLua()
    syncTimer.restart()
    savePrefs()
  }

  // UI preferences that are not Hyprland settings live in their own JSON
  // file; updateEntryInline stays reserved for standard widget keys.
  property string prefsPath: Quickshell.env("HOME") + "/.local/state/omarchy/control-panel-prefs.json"

  function loadPrefs(raw) {
    try {
      var d = JSON.parse(raw || "{}") || {}
      var needsPrefsMigration = d.singleMonitorWorkspaces === undefined
        || d.multiMonitorWorkspaces === undefined
      swipe3On = d.swipe3 === true
      saved.swipe3 = swipe3On
      inertiaOn = d.inertia === true
      saved.inertia = inertiaOn
      singleMonitorWorkspaces = Math.max(1, Math.min(10, Number(d.singleMonitorWorkspaces) || 10))
      multiMonitorWorkspaces = Math.max(1, Math.min(10, Number(d.multiMonitorWorkspaces) || 5))
      monitorColors = d.monitorColors && typeof d.monitorColors === "object" ? d.monitorColors : ({})
      savedWorkspaceVisuals = d.workspaceVisuals && typeof d.workspaceVisuals === "object" ? d.workspaceVisuals : ({})
      workspaceIndicatorMode = WorkspaceModel.normalizeIndicatorMode(d.workspaceIndicatorMode)
      workspaceIndicatorPadding = Math.max(0, Math.min(4,
        d.workspaceIndicatorPadding === undefined ? 4 : Math.round(Number(d.workspaceIndicatorPadding))))
      missionControlEnabled = d.missionControlEnabled === true
      devMode = d.devMode === true
      trackpadFeelConfigured = d.trackpadFeelConfigured === true
      saved.trackpadFeelConfigured = trackpadFeelConfigured
      scrollFeelConfigured = d.scrollFeelConfigured === true
      saved.scrollFeelConfigured = scrollFeelConfigured
      scrollIgnoreMode = ScrollFeelModel.clampIgnoreMode(d.scrollIgnoreMode)
      saved.scrollIgnoreMode = scrollIgnoreMode
      if (scrollFeelConfigured) {
        scrollAccelProfile = ScrollFeelModel.clampProfile(d.scrollAccelProfile)
        scrollAccelSpeed = ScrollFeelModel.clampSpeed(d.scrollAccelSpeed)
        scrollAccelMax = ScrollFeelModel.clampMax(d.scrollAccelMax)
        scrollDecel = ScrollFeelModel.clampDecel(d.scrollDecel)
        saved.scrollAccelProfile = scrollAccelProfile
        saved.scrollAccelSpeed = scrollAccelSpeed
        saved.scrollAccelMax = scrollAccelMax
        saved.scrollDecel = scrollDecel
      }
      if (trackpadFeelConfigured) {
        trackpadSensitivity = PointerFeelModel.clampSensitivity(d.trackpadSensitivity)
        trackpadScrollFactor = PointerFeelModel.clampScrollFactor(d.trackpadScrollFactor)
        trackpadAccelProfile = d.trackpadAccelProfile === "flat" ? "flat" : "adaptive"
        disableWhileTyping = d.disableWhileTyping !== false
        clickfingerBehavior = d.clickfingerBehavior !== false
        saved.trackpadSensitivity = trackpadSensitivity
        saved.trackpadScrollFactor = trackpadScrollFactor
        saved.trackpadAccelProfile = trackpadAccelProfile
        saved.disableWhileTyping = disableWhileTyping
        saved.clickfingerBehavior = clickfingerBehavior
      }
      saved.singleMonitorWorkspaces = singleMonitorWorkspaces
      saved.multiMonitorWorkspaces = multiMonitorWorkspaces
      naturalScroll = d.naturalScroll === true
      saved.naturalScroll = naturalScroll
      tapToClick = d.tapToClick === true
      saved.tapToClick = tapToClick
      saved.browserCloseTab = d.browserCloseTab === true
      browserCloseTabOn = saved.browserCloseTab
      saved.middleButtonScreenshotOff = d.middleButtonScreenshotOff === true
      middleBtnOff = saved.middleButtonScreenshotOff
      prefsLoaded = true
      // Rewrite once after loading to migrate older prefs files with the new
      // workspace-topology fields, without dropping any existing values.
      if (needsPrefsMigration) Qt.callLater(root.savePrefs)
      // Do NOT call syncTrackpadGestures()/writeLua() here: at this point
      // saved.sensitivity/gaps/kb_layout/accel are still at their object defaults
      // because readProc no longer writes them and luaStateProc hasn't run yet.
      // Writing now would persist those defaults and silently drop the user's
      // config. luaStateProc repopulates saved.* from the persisted Lua (the
      // source of truth) and triggers the write itself once it's done.
      // Do not refresh here. reapplyProc serializes persisted replay -> live
      // read; starting readProc from this loader would reintroduce the race.
    } catch (e) {}
  }

  function savePrefs() {
    var visuals = WorkspaceModel.workspaceVisualMap(displays, singleMonitorWorkspaces, multiMonitorWorkspaces, monitorColors, savedWorkspaceVisuals)
    prefsFile.setText(JSON.stringify({
      swipe3: swipe3On,
      inertia: inertiaOn,
      naturalScroll: naturalScroll,
      tapToClick: tapToClick,
      browserCloseTab: browserCloseTabOn,
      middleButtonScreenshotOff: middleBtnOff,
      singleMonitorWorkspaces: singleMonitorWorkspaces,
      multiMonitorWorkspaces: multiMonitorWorkspaces,
      monitorColors: monitorColors,
      workspaceIndicatorMode: workspaceIndicatorMode,
      workspaceIndicatorPadding: workspaceIndicatorPadding,
      missionControlEnabled: missionControlEnabled,
      devMode: devMode,
      trackpadFeelConfigured: trackpadFeelConfigured,
      scrollFeelConfigured: scrollFeelConfigured,
      scrollIgnoreMode: scrollIgnoreMode,
      scrollAccelProfile: scrollAccelProfile,
      scrollAccelSpeed: scrollAccelSpeed,
      scrollAccelMax: scrollAccelMax,
      scrollDecel: scrollDecel,
      trackpadSensitivity: trackpadSensitivity,
      trackpadScrollFactor: trackpadScrollFactor,
      trackpadAccelProfile: trackpadAccelProfile,
      disableWhileTyping: disableWhileTyping,
      clickfingerBehavior: clickfingerBehavior,
      workspaceVisuals: visuals
    }) + "\n")
    savedWorkspaceVisuals = visuals
  }

  // The last workspace→monitor map we wrote; keeps each display pinned to its
  // range across saves (position changes must not renumber workspaces).
  property var savedWorkspaceVisuals: ({})

  property FileView prefsFile: FileView {
    path: root.prefsPath
    blockLoading: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadPrefs(text())
    onLoadFailed: function() { root.loadPrefs("{}") }
  }

  Timer {
    id: workspaceWidgetSyncTimer
    interval: 300
    onTriggered: Quickshell.execDetached([
      root.binDir + "/install-workspace-colors-widget"
    ])
  }

  property FileView workspaceThemeFile: FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"
    blockLoading: true
    watchChanges: true
    printErrors: false
    onLoaded: root.workspaceThemeColors = ThemePalette.parse(text())
    onFileChanged: reload()
  }

  Connections {
    target: Color
    function onAccentChanged() { workspaceThemeFile.reload() }
    function onForegroundChanged() { workspaceThemeFile.reload() }
    function onUrgentChanged() { workspaceThemeFile.reload() }
  }

  function switchToKitty() {
    if (!kittyInstalled) {
      statusMessage = t(uiLang, "kittyInstall") + "…"
      run("omarchy-launch-floating-terminal-with-presentation 'omarchy-install-terminal kitty'")
      slowSyncLeft = 10
      slowSyncTimer.restart()
      return
    }
    run("omarchy-default-terminal kitty")
    statusMessage = "Terminal · kitty"
    syncTimer.restart()
  }

  function autoMountApfs(dev) {
    // The plugin never runs privileged shell strings built from QML. Show the
    // exact command so the user can copy and run it themselves.
    var base = dev.replace("/dev/", "")
    var uuid = "$(blkid -s UUID -o value " + dev + ")"
    root.apfsCommandText = "UUID=" + uuid + "; MP=/mnt/apfs-" + base + "; "
      + "pkexec bash -c \"grep -qs \\\$UUID /etc/fstab || echo 'UUID=\\\$UUID \\\$MP apfs rw,nofail,x-systemd.automount,x-systemd.device-timeout=10 0 0' >> /etc/fstab; mkdir -p \\\$MP; systemctl daemon-reload; modprobe apfs; ls \\\$MP\""
    statusMessage = "APFS · command ready to copy"
  }

  function unmountApfs(mp) {
    root.apfsCommandText = "pkexec umount '" + mp + "'"
    statusMessage = "APFS · command ready to copy"
  }

  Process {
    id: readProc
    command: ["bash", "-lc",
      "echo ANIM=$(hyprctl getoption animations:enabled -j | jq -r .bool); " +
      "echo SENS=$(hyprctl getoption input:sensitivity -j | jq -r .float); " +
      "echo TSF=$(hyprctl getoption input:touchpad:scroll_factor -j | jq -r .float); " +
      "echo DWT=$(hyprctl getoption input:touchpad:disable_while_typing -j | jq -r .bool); " +
      "echo CFB=$(hyprctl getoption input:touchpad:clickfinger_behavior -j | jq -r .bool); " +
      "echo ACCEL=$(hyprctl getoption input:accel_profile -j | jq -r .str); " +
      "echo KB=$(hyprctl getoption input:kb_layout -j | jq -r .str); " +
      "echo NL=$(omarchy-toggle-nightlight --status 2>/dev/null | jq -r .enabled); " +
      "echo WSA=$(hyprctl animations 2>/dev/null | awk '/^[[:space:]]*name: workspaces$/{f=1;next} f&&/enabled:/{print $2; exit}'); " +
      "echo LOCL=$(localectl status | sed -n 's/.*LANG=//p' | head -1); " +
      "echo TPG=$(test -f ~/.config/omarchy/plugins/user.trackpad-gestures/apply-gestures.sh && echo yes || echo no); " +
      "echo TPD=$(hyprctl devices -j | python3 '" + root.binDir + "/detect-touchpads.py'); " +
      "echo ALLMICE=$(hyprctl devices -j | python3 '" + root.binDir + "/detect-all-mice.py'); " +
      "echo APFSD=$(pacman -Qq linux-apfs-rw-dkms >/dev/null 2>&1 && echo yes || echo no); " +
      "echo DTERM=$(omarchy-default-terminal 2>/dev/null); " +
      "echo KITTY=$(command -v kitty >/dev/null 2>&1 && echo yes || echo no); " +
      "echo FSIZE=$(sed -n 's/^base-size *= *//p' \"$HOME/.config/omarchy/shell.toml\" 2>/dev/null | head -1)"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = text.split("\n")
        for (var i = 0; i < lines.length; i++) {
          var kv = lines[i].split("=")
          if (kv.length !== 2) continue
          var k = kv[0], v = kv[1]
          if (k === "ANIM") { root.animationsEnabled = v === "true" }
          else if (k === "SENS") { root.cursorSensitivity = parseFloat(v) || 0 }
          else if (k === "TSF" && !root.trackpadFeelConfigured) {
            var sf = parseFloat(v); if (!isNaN(sf) && sf > 0) { root.trackpadScrollFactor = sf; root.saved.trackpadScrollFactor = sf }
          }
          else if (k === "DWT" && !root.trackpadFeelConfigured) { root.disableWhileTyping = v === "true"; root.saved.disableWhileTyping = root.disableWhileTyping }
          else if (k === "CFB" && !root.trackpadFeelConfigured) { root.clickfingerBehavior = v === "true"; root.saved.clickfingerBehavior = root.clickfingerBehavior }
          else if (k === "ACCEL") { root.flatAccel = v.indexOf("flat") === 0 }
          else if (k === "KB") { root.kbLayout = v || "us" }
          else if (k === "NL") root.nightLightOn = v === "true"
          else if (k === "WSA") { var n = parseInt(v); if (n === 0 || n === 1) { root.wsAnimationOn = n >= 1 } }
          else if (k === "LOCL" && v !== "") root.currentLocale = v
          else if (k === "TPG") root.trackpadGesturesInstalled = v === "yes"
          else if (k === "APFSD") { root.apfsInstalled = v === "yes"; if (!apfsProbe.running) apfsProbe.running = true }
          else if (k === "TPD" && v !== "") { root.trackpadNames = v.split("|") }
          else if (k === "ALLMICE" && v !== "") { root.allMiceNames = v.split("|") }
          else if (k === "SW3") root.swipe3On = v === "relative_workspace"
          else if (k === "KITTY") root.kittyInstalled = v === "yes"
          else if (k === "INERTIA") root.inertiaOn = v === "true"
          else if (k === "DTERM" && v !== "") root.defaultTerm = v
          else if (k === "FSIZE") { var fs = parseInt(v, 10); if (!isNaN(fs) && fs > 0) { root.fontBaseSize = fs; root.saved.fontBaseSize = fs } }
        }
        root.readProcDone = true
        root.tryWriteLua()
      }
    }
  }

  // The Apple MTP is mouse-classified, so Hyprland does NOT expose
  // tap_to_click via `hyprctl devices -j`, and natural_scroll is applied
  // per-device (the global input:natural_scroll never reaches it). readProc
  // therefore cannot reliably read these two knobs. The persisted Lua file
  // (~/.config/hypr/control-panel.lua) is the source of truth, so we parse it
  // to reflect the real state in the UI instead of trusting hyprctl. The same
  // applies to the animations / workspace-animation toggles: they are NOT in the
  // small prefs JSON, so their saved.* values must come from the Lua (the
  // persisted artifact), never from readProc's live Hyprctl read (which would
  // overwrite saved.* with defaults and get persisted on the next writeLua).
  Process {
    id: luaStateProc
    command: ["bash", "-lc",
      "f='" + root.luaPath + "'; [ -f \"$f\" ] || exit 0; c=$(head -c 65536 \"$f\"); " +
      "echo NS=$(printf '%s' \"$c\" | grep -oE 'natural_scroll = (true|false)' | head -1 | grep -oE '(true|false)'); " +
      "echo TC=$(printf '%s' \"$c\" | grep -oE 'tap_to_click = (true|false)' | head -1 | grep -oE '(true|false)'); " +
      "echo AN=$(printf '%s' \"$c\" | grep -oE 'animations = { enabled = (true|false)' | head -1 | grep -oE '(true|false)'); " +
      "echo WA=$(printf '%s' \"$c\" | grep -oE 'leaf = \"workspaces\", enabled = (true|false)' | head -1 | grep -oE '(true|false)'); " +
      "echo SENS=$(printf '%s' \"$c\" | grep -oE 'sensitivity = [-0-9.]+' | head -1 | grep -oE '[-0-9.]+'); " +
      "echo GIN=$(printf '%s' \"$c\" | grep -oE 'gaps_in = [0-9]+' | head -1 | grep -oE '[0-9]+'); " +
      "echo GOUT=$(printf '%s' \"$c\" | grep -oE 'gaps_out = [0-9]+' | head -1 | grep -oE '[0-9]+'); " +
      "echo KB=$(printf '%s' \"$c\" | grep -oE 'kb_layout = \"[^\"]*\"' | head -1 | sed -E 's/kb_layout = \"([^\"]*)\"/\\1/'); " +
      "echo CSIZE=$(printf '%s' \"$c\" | grep -oE 'HYPRCURSOR_SIZE\", \"[0-9]+' | grep -oE '[0-9]+' | head -1); " +
      "echo ACC=$(printf '%s' \"$c\" | grep -oE 'accel_profile = \"(flat|adaptive)\"' | head -1 | grep -oE '(flat|adaptive)')"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = text.split("\n")
        for (var i = 0; i < lines.length; i++) {
          var kv = lines[i].split("=")
          if (kv.length !== 2) continue
          var k = kv[0], v = kv[1]
          if (k === "NS" && (v === "true" || v === "false")) { root.naturalScroll = (v === "true"); root.saved.naturalScroll = root.naturalScroll }
          if (k === "TC" && (v === "true" || v === "false")) { root.tapToClick = (v === "true"); root.saved.tapToClick = root.tapToClick }
          if (k === "AN" && (v === "true" || v === "false")) { root.animationsEnabled = (v === "true"); root.saved.animations = root.animationsEnabled }
          if (k === "WA" && (v === "true" || v === "false")) { root.wsAnimationOn = (v === "true"); root.saved.wsAnimation = root.wsAnimationOn }
          if (k === "SENS" && v !== "") { var sv = parseFloat(v); if (!isNaN(sv)) { root.cursorSensitivity = sv; root.saved.sensitivity = sv; if (!root.trackpadFeelConfigured) { root.trackpadSensitivity = sv; root.saved.trackpadSensitivity = sv } } }
          if (k === "GIN" && v !== "") { var gin = parseInt(v); if (!isNaN(gin)) { root.gapsIn = gin; root.saved.gapsIn = gin } }
          if (k === "GOUT" && v !== "") { var gout = parseInt(v); if (!isNaN(gout)) { root.gapsOut = gout; root.saved.gapsOut = gout } }
          if (k === "KB" && v !== "") { root.kbLayout = v; root.saved.kbLayout = v }
          if (k === "CSIZE" && v !== "") { var csz = parseInt(v, 10); if (!isNaN(csz) && csz > 0) { root.cursorSize = csz; root.saved.cursorSize = csz } }
          if (k === "ACC" && (v === "flat" || v === "adaptive")) { root.flatAccel = (v === "flat"); root.saved.flatAccel = root.flatAccel }
        }
        // All persisted Lua values are now in saved.*. Regenerate the Lua so it
        // keeps these real values (do NOT let readProc/writeLua ever serialize
        // the object defaults). Only after prefs are loaded to avoid a write
        // race with the JSON side.
        root.luaStateProcDone = true
        root.tryWriteLua()
      }
    }
  }
  // Dynamic locale list (system locales) for the language picker.
  property var localeOptions: []
  property string pendingInstall: ""
  property string localeInstallHint: ""
  Process {
    id: localeListProc
    command: ["bash", root.binDir + "/locale-list.sh"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var opts = []
        var lines = text.split("\n")
        for (var i = 0; i < lines.length; i++) {
          var parts = lines[i].split("\t")
          if (parts.length < 2) continue
          var v = parts[0].trim()
          if (!v) continue
          var inst = parts[1].trim() === "1"
          opts.push({ value: v, label: v, description: inst ? "installed" : "not installed", installed: inst })
        }
        root.localeOptions = opts
      }
    }
  }

  property bool localeHelperInstalled: false
  property string localeHelperPath: "/usr/local/bin/omarchy-control-panel-locale-helper"
  property string localeInstallCommand: ""
  property bool installing: false

  // Detect whether the root-owned locale helper is installed.
  Process {
    id: localeHelperProbe
    command: ["bash", "-lc", "test -x '" + root.localeHelperPath + "' && echo YES || echo NO"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.localeHelperInstalled = (text.trim() === "YES")
    }
  }

  // Install a missing locale using a ROOT-OWNED helper in /usr/local/bin.
  // The helper is installed once by the user (see showLocaleHelperInstallCommand);
  // afterwards the plugin calls it with pkexec + a validated argv. The mutable
  // plugin code itself never runs as root.
  function installLocale(v) {
    if (!v || !/^[a-z]{2}(_[A-Z]{2})?\.UTF-8$/.test(v)) return
    root.pendingInstall = v
    root.installing = true
    installProc.localeToInstall = v
    if (!installProc.running) installProc.running = true
  }

  // Show the one-time command to install the immutable root-owned helper.
  // The user runs it manually; once installed, locale install is one click.
  function showLocaleHelperInstallCommand() {
    root.localeInstallCommand = "pkexec install -o root -g root -m 755 \""
      + root.binDir + "/locale-helper\" "
      + root.localeHelperPath
  }

  Process {
    id: installProc
    property string localeToInstall: ""
    command: ["pkexec", root.localeHelperPath, localeToInstall]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.installing = false
        root.pendingInstall = ""
        if (!localeListProc.running) localeListProc.running = true
        root.refresh()
      }
    }
  }

  // Dynamic keyboard layout list (X11 layouts) for the layout picker.
  property var layoutOptions: []
  Process {
    id: layoutListProc
    command: ["bash", "-lc", "localectl list-x11-keymap-layouts 2>/dev/null | sort -u"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var opts = []
        var lines = text.split("\n")
        for (var i = 0; i < lines.length; i++) {
          var l = lines[i].trim()
          if (l) opts.push({ value: l, label: l })
        }
        root.layoutOptions = opts
      }
    }
  }

  // Keyboard backlight level.
  Process {
    id: kbdLedProbe
    command: ["bash", "-lc",
      "if [ -e /sys/class/leds/kbd_backlight/brightness ]; then " +
      "cur=$(head -c 64 /sys/class/leds/kbd_backlight/brightness); " +
      "max=$(head -c 64 /sys/class/leds/kbd_backlight/max_brightness); " +
      "echo FOUND=$(( max > 0 ? 100 * cur / max : 0 )); " +
      "else echo MISSING; fi"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var kv = text.trim().split("=")
        var pct = kv.length === 2 ? parseInt(kv[1]) : NaN
        root.kbdLedFound = !isNaN(pct)
        if (root.kbdLedFound) root.kbBacklightPct = Math.max(0, Math.min(100, pct))
      }
    }
  }

  // APFS partitions with mount state.
  Process {
    id: apfsProbe
    command: ["bash", "-lc",
      "lsblk -Jno PATH,FSTYPE,SIZE,LABEL,MOUNTPOINT 2>/dev/null | head -c 65536 | jq -c '[.. | objects | select(.fstype? == \"apfs\") | {path,fstype,size,label,mountpoint}] // []'"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var parsed = JSON.parse(text.trim())
          root.apfsList = Array.isArray(parsed) ? parsed : []
        } catch (e) { root.apfsList = [] }
      }
    }
  }

  // Re-read real system state shortly after every apply.
  Timer {
    id: syncTimer
    interval: 450
    repeat: false
    onTriggered: root.refresh()
  }

  // Slow polling for pkexec/locale-gen paced operations.
  Timer {
    id: slowSyncTimer
    interval: 2500
    repeat: true
    onTriggered: {
      root.refresh()
      if (root.slowSyncLeft-- <= 0) stop()
    }
  }

  // ---- Displays tab: live monitor layout --------------------------------
  Process {
    id: displayStateProc
    property bool outputValid: false
    stderr: StdioCollector { id: displayStateError; waitForEnd: true }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = root.displayParse(text)
        if (parsed && Array.isArray(parsed)) {
          displayStateProc.outputValid = true
          // Auto-correct corrupt/weird states (invalid mirror, an output both
          // disabled AND carrying a corrupt mirror, or every output disabled):
          // fix and apply immediately, never ask first — a working picture is
          // better than a blank one. BUT only correct in memory here: applying on
          // every refresh would re-issue hl.monitor to Hyprland on each poll and
          // move windows in a loop. The corrected layout is applied the next time
          // the user edits displays or on a real hotplug.
          var sane = DisplayModel.sanitizeDisplays(parsed)
          if (JSON.stringify(sane) !== JSON.stringify(parsed)) {
            parsed = sane
            root.displays = sane
          }
          // Do NOT overwrite root.displays with the live state while a display
          // change the user just made is still settling. A periodic refresh that
          // reads the state a moment before Hyprland adopted the new scale (or
          // after a concurrent hyprctl reload reverted it) would clobber
          // root.displays back to the old value, so a later Keep would persist
          // the OLD scale and the change would "revert". While displayApplyPending
          // is true we keep root.displays as the user set it; the live state is
          // still used for displayKnownNames / saved.displays bookkeeping below.
          if (!root.displayApplyPending) {
            root.displays = parsed
            if (!root.displayApplying && !root.displayAwaitingConfirmation)
              root.displayConfirmedState = DisplayModel.clone(parsed)
          }
          // Keep saved.displays in sync with the live layout so a later
          // writeLua() (triggered by any setting) always records the display
          // rules. Without this, a panel reload left saved.displays empty and
          // the next unrelated writeLua wiped the monitor layout from
          // control-panel.lua, losing it on the next Hyprland restart.
          // NOTE: do NOT call writeLua() here. writeLua regenerates the Lua file
          // and, even when idempotent, we never want a periodic refresh to touch
          // the persisted artifact. The displays section is no longer written to
          // the Lua (see writeLua), so there is nothing to persist on refresh.
          if (!root.saved.displays || root.saved.displays.length === 0) {
            root.saved.displays = DisplayModel.clone(parsed)
          }
          // Hotplug CONNECT: a monitor that was just plugged in is auto-placed
          // by Hyprland (often overlapping the others). Snap it flush against the
          // existing layout (which does not move) and apply, so a freshly
          // connected monitor never lands overlapped (which would error and restart).
          var currentNames = []
          for (var ci = 0; ci < parsed.length; ci++) currentNames.push(parsed[ci].name)
          // Only act when the monitor TOPOLOGY actually changed (a name appeared
          // or disappeared). Comparing against displayKnownNames avoids re-applying
          // on every periodic refresh, which would loop: displayApplyInstant() ->
          // Hyprland state change -> refresh -> re-apply -> ... and move windows.
          var topologyChanged = root.displayKnownNames.length > 0
              && JSON.stringify(root.displayKnownNames.slice().sort()) !== JSON.stringify(currentNames.slice().sort())
          if (topologyChanged) {
            // Re-apply the ACTIVE profile's per-monitor display config to any
            // monitor that matches by name. This is what keeps a profile "sticky"
            // across hotplug: the saved scale/position/mode come back instead of
            // Hyprland's default. Runs before the snap-below so a profile's
            // explicit position wins over the auto-flush heuristic.
            var activeP = null
            for (var ai = 0; ai < root.profiles.length; ai++) {
              if (root.profiles[ai].id === root.activeProfileId) { activeP = root.profiles[ai]; break }
            }
            if (activeP && activeP.settings && activeP.settings.displays) {
              var byName = {}
              for (var bi = 0; bi < parsed.length; bi++) byName[parsed[bi].name] = parsed[bi]
              var dm = activeP.settings.displays
              var replanned = parsed
              var replannedChanged = false
              for (var ki in dm) {
                if (!dm.hasOwnProperty(ki)) continue
                var live = byName[ki]
                if (!live) continue
                var sv = dm[ki]
                if (sv.scale !== undefined && Number(sv.scale) !== Number(live.scale)) { live.scale = Number(sv.scale); replannedChanged = true }
                if (sv.mode !== undefined && sv.mode && sv.mode !== live.mode) { live.mode = sv.mode; replannedChanged = true }
                if (sv.x !== undefined && Number(sv.x) !== Number(live.x)) { live.x = Number(sv.x); replannedChanged = true }
                if (sv.y !== undefined && Number(sv.y) !== Number(live.y)) { live.y = Number(sv.y); replannedChanged = true }
                if (sv.transform !== undefined && Number(sv.transform) !== Number(live.transform)) { live.transform = Number(sv.transform); replannedChanged = true }
              }
              if (replannedChanged) {
                root.displays = replanned
                root.saved.displays = DisplayModel.clone(replanned)
                // Mark the new topology as already known BEFORE applying, so the
                // refresh triggered by this same apply does not re-enter the
                // hotplug branch and loop.
                root.displayKnownNames = currentNames
                root.displayApplyInstant()
              }
            }
            var arranged = parsed
            var changed = false
            for (var ni = 0; ni < parsed.length; ni++) {
              if (root.displayKnownNames.indexOf(parsed[ni].name) < 0) {
                var before = JSON.stringify(arranged[ni])
                arranged = DisplayModel.snapDraggedFlush(arranged, ni)
                if (JSON.stringify(arranged[ni]) !== before) changed = true
              }
            }
            if (changed) {
              root.displays = arranged
              root.saved.displays = DisplayModel.clone(arranged)
              root.displayApplyInstant()
            }
          }
          root.displayKnownNames = currentNames
          var workspaceTopologyKey = currentNames.slice().sort().join("|")
          if (root.workspaceTopology !== workspaceTopologyKey) {
            // The first display read initializes the baseline only. Persisting
            // a workspace plan here can run before luaStateProc has restored
            // sensitivity/kbLayout and would rewrite them with defaults.
            if (root.workspaceTopology !== "")
              workspaceTopologyTimer.restart()
            root.workspaceTopology = workspaceTopologyKey
          }
          root.displayStatusMessage = root.displayRefreshMessage
          root.displayRefreshMessage = ""
        }
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0 || !outputValid) {
        root.displayStatusMessage = root.displayProcessError(displayStateError.text, "Could not read Hyprland display state")
        root.displayRefreshMessage = ""
      }
    }
    onRunningChanged: {
      if (running) outputValid = false
      else root.displayLoading = false
    }
  }

  Process {
    id: displayApplyProc
    stdout: StdioCollector { id: displayApplyOutput; waitForEnd: true }
    stderr: StdioCollector { id: displayApplyError; waitForEnd: true }
    onExited: function(exitCode) {
      root.displayApplying = false
      if (exitCode === 0) {
        var result = root.displayParse(displayApplyOutput.text)
        root.displayAwaitingConfirmation = true
        root.displaySecondsRemaining = result && result.timeout ? Number(result.timeout) : 15
        root.displayStatusMessage = "Keep these display settings?"
        displayConfirmationTimer.restart()
        console.warn("[CP] displayApplyPreview ok, awaiting=true seconds=" + root.displaySecondsRemaining)
      } else {
        root.displayRefresh(root.displayProcessError(displayApplyError.text, "Preview failed; the previous layout was restored"))
        console.warn("[CP] displayApplyPreview failed")
      }
    }
  }

  Process {
    id: displayConfirmProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { id: displayConfirmError; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.displayAwaitingConfirmation = false
        displayConfirmationTimer.stop()
        root.displayStatusMessage = "Display settings kept and saved for this session"
      } else {
        root.displayStatusMessage = root.displayProcessError(displayConfirmError.text, "Could not confirm display settings; automatic rollback is still active")
      }
    }
  }

  // Instant apply for safe changes (scale, position). No rollback is armed.
  Process {
    id: displayInstantProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { id: displayInstantError; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.displayStatusMessage = "Applied"
        // Persist the safe change so it survives restarts.
        // NOTE: do NOT call displayRefresh() here. displayRefresh() re-reads the
        // live Hyprland state and overwrites root.displays; if the just-applied
        // scale has not propagated yet (or a concurrent hyprctl reload reverted
        // it), that would clobber root.displays back to the old scale, so a later
        // Keep would save the OLD value and the change would appear to "revert".
        // root.displays already holds the new scale (set by applyDisplayScale /
        // applyDisplayMap before the apply), so just persist it.
        root.saved.displays = DisplayModel.clone(root.displays)
        root.displayConfirmedState = DisplayModel.clone(root.displays)
        root.savePrefs()
      } else {
        root.displayRefresh(root.displayProcessError(displayInstantError.text, "Could not apply display settings"))
      }
    }
  }

  // Check whether a preview is still awaiting confirmation (its snapshot is
  // armed on disk). If so, restore the Keep/Revert UI so the user can confirm
  // even after the popup closed on a primary-output reconfiguration.
  Process {
    id: displayPendingProc
    stdout: StdioCollector { id: displayPendingOutput; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.continueOpen()
        return
      }
      var result = root.displayParse(displayPendingOutput.text)
      if (result && result.pending === true && !root.displayAwaitingConfirmation) {
        root.displayAwaitingConfirmation = true
        root.displaySecondsRemaining = 15
        root.displayStatusMessage = "Confirm display settings?"
        // Make sure the user lands on the Profiles tab to see the dialog.
        root.currentTab = root.tabs.length - 1
        console.warn("[CP] pending restored, awaiting=true")
      } else {
        root.continueOpen()
        console.warn("[CP] no pending, continuing open")
      }
    }
  }

  Process {
    id: displayRevertProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { id: displayRevertError; waitForEnd: true }
    onExited: function(exitCode) {
      root.displayAwaitingConfirmation = false
      displayConfirmationTimer.stop()
      if (exitCode === 0)
        root.displayRefresh("Previous layout restored")
      else
        root.displayRefresh(root.displayProcessError(displayRevertError.text, "Previous layout could not be restored"))
    }
  }

  Timer {
    id: displayConfirmationTimer
    interval: 1000
    repeat: true
    running: root.displayAwaitingConfirmation && root.displaySecondsRemaining > 0
    onTriggered: {
      console.warn("[CP] confirmation timer, seconds=" + root.displaySecondsRemaining)
      root.displaySecondsRemaining--
      if (root.displaySecondsRemaining <= 0) {
        root.displayStatusMessage = "Timed out; restoring previous layout…"
        root.displayRevert()
      }
    }
  }

  // Auto-dismiss the identify-all overlay after a few seconds.
  Timer {
    id: identifyAllTimer
    interval: 3000
    repeat: false
    onTriggered: root.identifyAllDisplays = false
  }

  Component.onCompleted: {
    if (!i18nLoader.running) i18nLoader.running = true
    if (!localeListProc.running) localeListProc.running = true
    if (!layoutListProc.running) layoutListProc.running = true
    if (!localeHelperProbe.running) localeHelperProbe.running = true
    // VERSION MARKER (2026-08-31c): confirms which build is live. The plugin
    // writes a timestamp + this tag to /tmp/cp-version.log so we can tell apart
    // a stale quickshell qmlcache from the real build without relying on qslog.
    Quickshell.execDetached(["bash", "-lc", "echo \"$(date +%H:%M:%S) CP-LOAD 2026-08-31c\" >> /tmp/cp-version.log"])
    // Bring the live Hyprland config in line with what we persisted, so a
    // shell/plugin restart doesn't leave the system on Omarchy's defaults.
    // Defer slightly: execDetached + hyprctl eval needs Quickshell/Hyprland
    // to be fully up, otherwise the call fired at construction time is lost.
    applyOnLoadTimer.restart()
  }
  // Poll for the root-owned locale helper while a not-yet-installed locale is
  // selected, so the UI switches to "Install & apply" as soon as the user has
  // run the one-time install command.
  Timer {
    id: localeHelperPoller
    interval: 2000
    repeat: true
    running: root.pendingInstall !== ""
    onTriggered: if (!localeHelperProbe.running) localeHelperProbe.running = true
  }

  Timer {
    id: applyOnLoadTimer
    interval: 400
    repeat: false
    onTriggered: {
      reapplySaved()
      // Apply the SUPER+W bind once at load (direct eval, not via the reloadable
      // Lua, to avoid the release-bind re-register loop that closed windows).
      root.applySuperWBind()
    }
  }

  implicitWidth: Style.space(620)
  implicitHeight: contentColumn.implicitHeight
  Item { id: buttonPlaceholder; anchors.fill: parent }

  ColumnLayout {
    anchors.fill: parent
    spacing: 0

    PanelKeyCatcher {
      id: keyCatcher
      Layout.fillWidth: true
      Layout.preferredHeight: 0
      onCloseRequested: root.close()
      onTabRequested: function(direction) {
        root.currentTab = (root.currentTab + direction + root.tabs.length) % root.tabs.length
      }
    }

    ColumnLayout {
      id: contentColumn
      Layout.fillWidth: true
      Layout.fillHeight: true
      Layout.minimumWidth: root.width
      Layout.maximumWidth: root.width
      spacing: Style.space(12)

      Row {
        Layout.fillWidth: true
        visible: !root.externalNavigation
        spacing: Style.space(8)

        Text {
          text: "󰒓"
          color: Color.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          anchors.verticalCenter: parent.verticalCenter
        }

        Text {
          text: "Omarchy Control Panel"
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.subtitle
          font.bold: true
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      Row {
        id: tabRow
        Layout.fillWidth: true
        visible: !root.externalNavigation
        spacing: Style.space(4)

        Repeater {
          model: root.tabs

          Button {
            required property var modelData
            required property int index
            text: modelData.title
            selected: root.currentTab === index
            fontSize: Style.font.caption
            horizontalPadding: Style.space(6)
            verticalPadding: Style.space(3)
            foreground: root.fg
            onClicked: root.currentTab = index
          }
        }
      }

      PanelSeparator { visible: !root.externalNavigation; foreground: root.fg }

      // Keep/Revert confirmation is shown right under the tabs so the user can
      // always find it if a bad mode/resolution leaves the panel hard to read.
      Column {
        id: topConfirmRow
        width: parent.width
        spacing: Style.space(16)
        visible: root.displayAwaitingConfirmation
        opacity: visible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 160 } }

        Text {
          width: parent.width
          text: root.t(root.uiLang, "keepChangesPrompt")
          color: Color.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.subtitle
          font.bold: true
          wrapMode: Text.WordWrap
        }

        RowLayout {
          width: parent.width
          spacing: Style.space(16)
          Text {
            text: root.displaySecondsRemaining + "s"
            color: Color.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            Layout.alignment: Qt.AlignVCenter
          }
          Item { Layout.fillWidth: true; height: 1 }
          Button {
            text: displayRevertProc.running ? root.t(root.uiLang, "reverting") : root.t(root.uiLang, "revert")
            foreground: root.fg; fontFamily: root.fontFamily; bordered: true
            onClicked: root.displayRevert()
          }
          Button {
            text: displayConfirmProc.running ? root.t(root.uiLang, "keeping") : root.t(root.uiLang, "keepChanges")
            foreground: root.fg; fontFamily: root.fontFamily; bordered: true
            onClicked: root.displayKeep()
          }
        }

        Text {
          width: parent.width
          visible: root.displaySecondsRemaining <= 5
          text: root.t(root.uiLang, "displayRevertHint")
          color: Qt.darker(Color.foreground, 1.4)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }

      // ---------- Keyboard & Language ----------
      Column {
        Layout.fillWidth: true
        visible: root.currentTab === 3
        spacing: Style.space(8)

        Text {
          width: parent.width
          text: root.t(root.uiLang, "sysLanguage") + " — " + (root.currentLocale || "?")
          color: root.fg
          opacity: 0.7
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        SearchableDropdown {
          width: parent.width
          label: root.t(root.uiLang, "sysLanguage")
          placeholderText: root.t(root.uiLang, "sysLanguage") + "…"
          options: root.localeOptions
          value: root.currentLocale
          onChanged: function(v) {
            var opt = null
            for (var i = 0; i < root.localeOptions.length; i++) {
              if (root.localeOptions[i].value === v) { opt = root.localeOptions[i]; break }
            }
            if (opt && opt.installed) { root.setLocale(v); root.pendingInstall = "" }
            else { root.pendingInstall = v }
          }
        }

        Button {
          width: parent.width
          visible: root.pendingInstall !== "" && root.localeHelperInstalled
          enabled: !root.installing
          text: root.installing ? "Instalando…" : "Install & apply " + root.pendingInstall
          selected: true
          foreground: root.fg
          onClicked: root.installLocale(root.pendingInstall)
        }

        Button {
          width: parent.width
          visible: root.pendingInstall !== "" && !root.localeHelperInstalled
          text: "Set up locale installer (one-time)"
          selected: true
          foreground: root.fg
          onClicked: root.showLocaleHelperInstallCommand()
        }

        Text {
          width: parent.width
          visible: root.localeInstallCommand !== ""
          text: root.localeInstallCommand
          color: root.fg
          wrapMode: Text.Wrap
          font.pointSize: Style.font.caption
          opacity: 0.85
        }

        Button {
          width: parent.width
          visible: root.localeInstallCommand !== ""
          text: "Copy command to clipboard"
          foreground: root.fg
          onClicked: root.copyToClipboard(root.localeInstallCommand)
        }

        Rectangle {
          width: parent.width
          visible: root.showSuggestion
          height: suggestionRow.implicitHeight + Style.space(14)
          color: Style.selectedFillFor(root.fg, Color.accent)
          radius: Style.cornerRadius > 0 ? Style.cornerRadius : 4

          Row {
            id: suggestionRow
            anchors.centerIn: parent
            width: parent.width - Style.space(16)
            spacing: Style.space(8)

            Text {
              width: parent.width - sugApplyBtn.width - sugCloseBtn.width - parent.spacing * 2
              anchors.verticalCenter: parent.verticalCenter
              text: root.t(root.uiLang, "suggest").replace("%1", root.suggestedLayout)
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            Button {
              id: sugApplyBtn
              anchors.verticalCenter: parent.verticalCenter
              text: root.t(root.uiLang, "applyBtn")
              fontSize: Style.font.caption
              foreground: root.fg
              selected: true
              onClicked: root.applyKbLayout(root.suggestedLayout)
            }

            Button {
              id: sugCloseBtn
              anchors.verticalCenter: parent.verticalCenter
              fontFamily: root.fontFamily
              iconText: "󰅙"
              fontSize: Style.font.caption
              foreground: root.fg
              horizontalPadding: Style.space(4)
              onClicked: root.suggestionDismissed = true
            }
          }
        }

        Text {
          width: parent.width
          text: root.t(root.uiLang, "physKeyboard") + " — " + root.t(root.uiLang, "curLayout").toLowerCase() + ": " + root.kbLayout
          color: root.fg
          opacity: 0.7
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        SearchableDropdown {
          width: parent.width
          label: root.t(root.uiLang, "physKeyboard")
          placeholderText: root.t(root.uiLang, "physKeyboard") + "…"
          options: root.layoutOptions
          value: root.kbLayout.split(",")[0]
          onChanged: function(v) { root.applyKbLayout(v) }
        }

        Column {
          width: parent.width
          visible: root.hasKbBacklight
          spacing: Style.space(8)

          Text {
            text: root.t(root.uiLang, "kbdBacklight") + ": " + root.kbBacklightPct + "%"
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }

          Slider {
            width: parent.width
            from: 0
            to: 100
            stepSize: 1
            value: root.kbBacklightPct
            onMoved: root.setKbBacklight(value)
          }
        }
      }

      // ---------- Trackpad / Cursor ----------
      Column {
        Layout.fillWidth: true
        visible: root.currentTab === 0
        spacing: Style.space(10)

        Text {
          text: root.t(root.uiLang, "globalPointerSensitivity") + ": " + Number(root.cursorSensitivity).toFixed(2)
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        Slider {
          width: parent.width
          from: -1
          to: 1
          stepSize: 0.05
          value: root.cursorSensitivity
          onMoved: root.applySensitivity(value)
        }

        Rectangle {
          id: pointerFeelCard
          width: parent.width
          height: pointerFeelContent.implicitHeight + Style.space(24)
          radius: Style.cornerRadius
          color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.035)
          border.color: root.pointerFeelDirty ? Color.accent : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.16)
          border.width: 1
          enabled: root.pointerFeelReady
          opacity: root.pointerFeelReady ? 1 : 0.55

          Column {
            id: pointerFeelContent
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Style.space(12)
            spacing: Style.space(9)

            Row {
              width: parent.width
              spacing: Style.space(8)

              Column {
                width: parent.width
                spacing: Style.space(2)
                Text {
                  text: root.t(root.uiLang, "pointerFeelTitle")
                  color: root.fg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                }
                Text {
                  width: parent.width
                  elide: Text.ElideRight
                  text: (root.trackpadNames.length ? "●  " + root.trackpadNames[0] : "○  " + root.t(root.uiLang, "pointerFeelNoDevice"))
                  color: root.fg
                  opacity: root.trackpadNames.length ? 0.7 : 0.5
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }

            Grid {
              width: parent.width
              columns: 2
              columnSpacing: Style.space(6)
              rowSpacing: Style.space(6)

              Repeater {
                model: PointerFeelModel.presetIds()
                Button {
                  required property string modelData
                  width: (pointerFeelContent.width - Style.space(6)) / 2
                  text: root.t(root.uiLang, PointerFeelModel.presetLabelKey(modelData))
                  selected: PointerFeelModel.detectPreset(root.trackpadSensitivity, root.trackpadScrollFactor, root.trackpadAccelProfile) === modelData
                  bordered: true
                  foreground: root.fg
                  fontFamily: root.fontFamily
                  onClicked: root.selectPointerPreset(modelData)
                }
              }
            }

            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              text: root.t(root.uiLang, PointerFeelModel.presetDescriptionKey(
                PointerFeelModel.detectPreset(root.trackpadSensitivity, root.trackpadScrollFactor, root.trackpadAccelProfile)))
              color: root.fg
              opacity: 0.66
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Text {
              text: root.t(root.uiLang, "pointerFeelPointer") + " · "
                + root.t(root.uiLang, PointerFeelModel.pointerLabel(root.trackpadSensitivity))
                + "  " + Number(root.trackpadSensitivity).toFixed(2)
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            Slider {
              width: parent.width
              from: -1
              to: 1
              stepSize: 0.05
              value: root.trackpadSensitivity
              onMoved: root.userChangePointerFeel(value, root.trackpadScrollFactor, root.trackpadAccelProfile)
            }

            Text {
              text: root.t(root.uiLang, "pointerFeelScroll") + " · "
                + root.t(root.uiLang, PointerFeelModel.scrollLabel(root.trackpadScrollFactor))
                + "  " + Number(root.trackpadScrollFactor).toFixed(2) + "×"
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            Slider {
              width: parent.width
              from: 0.1
              to: 2
              stepSize: 0.05
              value: root.trackpadScrollFactor
              onMoved: root.userChangePointerFeel(root.trackpadSensitivity, value, root.trackpadAccelProfile)
            }

            ToggleRow {
              label: root.t(root.uiLang, "disableWhileTyping")
              checked: root.disableWhileTyping
              onClicked: root.setDisableWhileTyping(!root.disableWhileTyping)
            }

            ToggleRow {
              label: root.t(root.uiLang, "twoFingerRightClick")
              checked: root.clickfingerBehavior
              onClicked: root.setClickfingerBehavior(!root.clickfingerBehavior)
            }

            Row {
              spacing: Style.space(8)
              Button {
                text: root.t(root.uiLang, "pointerFeelRestore")
                bordered: true
                enabled: root.pointerFeelPrevious !== null
                foreground: root.fg
                fontFamily: root.fontFamily
                onClicked: root.restorePointerFeel()
              }
            }

            Text {
              text: root.t(root.uiLang, "pointerFeelPractice") + " · " + root.practiceHits + " "
                + root.t(root.uiLang, root.practiceHits === 1 ? "pointerFeelHit" : "pointerFeelHits")
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              text: root.t(root.uiLang, "pointerFeelPracticeHint")
              color: root.fg
              opacity: 0.55
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            PrecisionCircuit {
              width: parent.width
              foreground: root.fg
              accent: Color.accent
              pointIndex: root.practiceTargetIndex
              hits: root.practiceHits
              onHit: root.advancePracticeTarget()
            }
          }
        }

        Text {
          width: parent.width
          visible: !root.devMode
          wrapMode: Text.WordWrap
          text: root.t(root.uiLang, "scrollFeelDevHint")
          color: Color.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Button {
          width: parent.width
          visible: !root.devMode
          text: root.t(root.uiLang, "scrollFeelDevRepo")
          bordered: true
          foreground: root.fg
          fontFamily: root.fontFamily
          onClicked: Qt.openUrlExternally("https://github.com/avillagran/Hyprland/tree/feat/touchpad-scroll-acceleration")
        }

        // DEV ONLY: touchpad scroll acceleration + coast. Requires a compositor
        // built with the scroll patch; the capability probe decides whether the
        // controls are live or shown disabled. Never emitted to control-panel.lua
        // on a stock Hyprland.
        Rectangle {
          id: scrollFeelCard
          width: parent.width
          visible: root.devMode
          height: visible ? scrollFeelContent.implicitHeight + Style.space(24) : 0
          radius: Style.cornerRadius
          color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.035)
          border.color: Color.urgent
          border.width: 1
          enabled: root.scrollPatchSupported
          opacity: root.scrollPatchSupported ? 1 : 0.55

          Column {
            id: scrollFeelContent
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Style.space(12)
            spacing: Style.space(9)

            Row {
              width: parent.width
              spacing: Style.space(8)

              Text {
                text: root.t(root.uiLang, "scrollFeelTitle")
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
              }

              Rectangle {
                width: devBadgeText.implicitWidth + Style.space(10)
                height: devBadgeText.implicitHeight + Style.space(4)
                radius: 4
                color: Qt.alpha(Color.urgent, 0.18)
                Text {
                  id: devBadgeText
                  anchors.centerIn: parent
                  text: "DEV"
                  color: Color.urgent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
              }
            }

            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              text: root.scrollPatchSupported
                ? root.t(root.uiLang, "scrollFeelSupported")
                : root.t(root.uiLang, "scrollFeelUnsupported")
              color: root.scrollPatchSupported ? root.fg : Color.urgent
              opacity: root.scrollPatchSupported ? 0.66 : 1
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Button {
              width: parent.width
              text: root.t(root.uiLang, "macConfig")
              bordered: true
              foreground: root.fg
              fontFamily: root.fontFamily
              onClicked: root.applyMacOSConfig()
            }

            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              text: root.t(root.uiLang, "macConfigHint")
              color: root.fg
              opacity: 0.66
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Grid {
              width: parent.width
              columns: 2
              columnSpacing: Style.space(6)
              rowSpacing: Style.space(6)

              Repeater {
                model: ScrollFeelModel.presetIds()
                Button {
                  required property string modelData
                  width: (scrollFeelContent.width - Style.space(6)) / 2
                  text: root.t(root.uiLang, ScrollFeelModel.presetLabelKey(modelData))
                  selected: ScrollFeelModel.detectPreset(root.scrollAccelProfile,
                    root.scrollAccelSpeed, root.scrollAccelMax, root.scrollDecel) === modelData
                  bordered: true
                  foreground: root.fg
                  fontFamily: root.fontFamily
                  onClicked: root.selectScrollPreset(modelData)
                }
              }
            }

            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              text: root.t(root.uiLang, ScrollFeelModel.presetDescriptionKey(
                ScrollFeelModel.detectPreset(root.scrollAccelProfile, root.scrollAccelSpeed,
                  root.scrollAccelMax, root.scrollDecel)))
              color: root.fg
              opacity: 0.66
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              text: root.t(root.uiLang, "scrollIgnoreLabel")
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            Grid {
              width: parent.width
              columns: 3
              columnSpacing: Style.space(6)
              rowSpacing: Style.space(6)

              Repeater {
                model: ScrollFeelModel.ignoreModes
                Button {
                  required property string modelData
                  width: (scrollFeelContent.width - Style.space(12)) / 3
                  text: root.t(root.uiLang, ScrollFeelModel.ignoreModeLabelKey(modelData))
                  selected: root.scrollIgnoreMode === modelData
                  enabled: root.scrollIgnoreSupported
                  bordered: true
                  foreground: root.fg
                  fontFamily: root.fontFamily
                  onClicked: root.updateScrollIgnoreMode(modelData)
                }
              }
            }

            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              text: root.scrollIgnoreSupported
                ? root.t(root.uiLang, "scrollIgnoreHint")
                : root.t(root.uiLang, "scrollIgnoreUnsupported")
              color: root.scrollIgnoreSupported ? root.fg : Color.urgent
              opacity: root.scrollIgnoreSupported ? 0.66 : 1
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Text {
              visible: root.scrollAccelProfile > 0
              text: root.t(root.uiLang, "scrollFeelSpeed") + " · "
                + root.t(root.uiLang, ScrollFeelModel.speedLabel(root.scrollAccelSpeed))
                + "  " + Number(root.scrollAccelSpeed).toFixed(2) + "×"
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            Slider {
              width: parent.width
              visible: root.scrollAccelProfile > 0
              from: 0.2
              to: 3.0
              stepSize: 0.05
              value: root.scrollAccelSpeed
              onMoved: root.updateScrollFeel(root.scrollAccelProfile, value,
                root.scrollAccelMax, root.scrollDecel, true)
            }

            Text {
              visible: root.scrollAccelProfile > 0
              text: root.t(root.uiLang, "scrollFeelMax") + " · "
                + root.t(root.uiLang, ScrollFeelModel.maxLabel(root.scrollAccelMax))
                + "  " + Number(root.scrollAccelMax).toFixed(2) + "×"
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            Slider {
              width: parent.width
              visible: root.scrollAccelProfile > 0
              from: 1.0
              to: 10.0
              stepSize: 0.25
              value: root.scrollAccelMax
              onMoved: root.updateScrollFeel(root.scrollAccelProfile,
                root.scrollAccelSpeed, value, root.scrollDecel, true)
            }

            Text {
              text: root.t(root.uiLang, "scrollFeelCoast") + " · "
                + (root.scrollDecel === 0
                  ? root.t(root.uiLang, "scrollFeelCoastOff")
                  : root.scrollDecel + " ms")
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            Slider {
              width: parent.width
              from: 0
              to: 3000
              stepSize: 50
              value: root.scrollDecel
              onMoved: root.updateScrollFeel(root.scrollAccelProfile,
                root.scrollAccelSpeed, root.scrollAccelMax, value, true)
            }
          }
        }

        Text {
          text: root.t(root.uiLang, "cursorSize") + ": " + root.cursorSize
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        Slider {
          width: parent.width
          from: 8
          to: 64
          stepSize: 1
          value: root.cursorSize
          onMoved: root.applyCursorSize(value)
        }

        ToggleRow {
          label: root.t(root.uiLang, "invScroll")
          checked: root.naturalScroll
          onClicked: { root.setNaturalScroll(!root.naturalScroll, false) }
        }

        ToggleRow {
          label: root.t(root.uiLang, "globalFlatAccel")
          checked: root.flatAccel
          onClicked: { root.flatAccel = !root.flatAccel; root.hyprSet("input", "accel_profile", root.flatAccel ? '"flat"' : '"adaptive"'); root.writeLua() }
        }

        ToggleRow {
          label: root.t(root.uiLang, "tapClick")
          checked: root.tapToClick
          onClicked: { root.setTapToClick(!root.tapToClick) }
        }

        ToggleRow {
          label: root.t(root.uiLang, "swipe3")
          checked: root.swipe3On
          onClicked: { root.setSwipe3(!root.swipe3On) }
        }

        ToggleRow {
          label: root.t(root.uiLang, "middleButtonScreenshotOff")
          checked: root.middleBtnOff
          onClicked: { root.setMiddleBtnOff(!root.middleBtnOff) }
        }

        PanelSeparator { foreground: root.fg }

        ToggleRow {
          label: root.t(root.uiLang, "inertia")
          checked: root.inertiaOn
          onClicked: { root.setInertia(!root.inertiaOn) }
        }

        Text {
          width: parent.width
          text: "Terminal · " + (root.defaultTerm !== "" ? root.defaultTerm : "?")
          color: root.fg
          opacity: 0.7
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Button {
          width: parent.width
          visible: root.inertiaOn && !root.kittyInstalled
          leftAlign: true
          fontFamily: root.fontFamily
          iconText: "󰣀"
          text: root.t(root.uiLang, "kittyInstall")
          selected: true
          foreground: root.fg
          onClicked: root.switchToKitty()
        }

        Button {
          width: parent.width
          visible: root.inertiaOn && root.kittyInstalled && root.defaultTerm !== "kitty"
          leftAlign: true
          iconText: "󰆍"
          text: root.t(root.uiLang, "useKitty")
          selected: true
          foreground: root.fg
          onClicked: root.switchToKitty()
        }
      }

      // ---------- Windows ----------
      Column {
        Layout.fillWidth: true
        visible: root.currentTab === 1
        spacing: Style.space(10)

        Text {
          text: root.t(root.uiLang, "gapIn") + ": " + root.gapsIn + "px   ·   " + root.t(root.uiLang, "gapOut") + ": " + root.gapsOut + "px"
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        Slider {
          width: parent.width
          from: 0
          to: 40
          stepSize: 1
          value: root.gapsIn
          onMoved: {
            root.gapsIn = value
            root.applyGaps("gaps_in", value)
          }
        }

        Slider {
          width: parent.width
          from: 0
          to: 40
          stepSize: 1
          value: root.gapsOut
          onMoved: {
            root.gapsOut = value
            root.applyGaps("gaps_out", value)
          }
        }

        Text {
          text: root.t(root.uiLang, "fontSize") + ": " + root.fontBaseSize + "px"
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        Slider {
          width: parent.width
          from: 9
          to: 26
          stepSize: 1
          value: root.fontBaseSize
          onMoved: root.applyFontSize(value)
        }

        PanelSeparator { visible: root.devMode; foreground: Color.urgent }

        ToggleRow {
          label: root.missionControlBusy ? root.t(root.uiLang, "missionControlInstalling") : root.t(root.uiLang, "missionControl")
          visible: root.devMode
          foreground: Color.urgent
          checked: root.missionControlEnabled
          enabled: !root.missionControlBusy
          onClicked: root.setMissionControl(!root.missionControlEnabled)
        }

        Text {
          visible: root.devMode
          width: parent.width
          text: root.t(root.uiLang, "missionControlHint")
          color: Qt.darker(root.fg, 1.35)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        Text {
          visible: root.devMode && root.missionControlError !== ""
          width: parent.width
          text: root.missionControlError
          color: Color.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        Text {
          width: parent.width
          text: root.t(root.uiLang, "workspaceSetup")
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
        }

        Text {
          width: parent.width
          text: WorkspaceModel.summary(root.displays, root.singleMonitorWorkspaces, root.multiMonitorWorkspaces)
          color: root.fg
          opacity: 0.65
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        Text {
          text: root.t(root.uiLang, "oneMonitorWorkspaces") + ": " + root.singleMonitorWorkspaces
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        Slider {
          width: parent.width
          from: 1
          to: 10
          stepSize: 1
          value: root.singleMonitorWorkspaces
          onMoved: root.singleMonitorWorkspaces = Math.round(value)
        }

        Text {
          text: root.t(root.uiLang, "multiMonitorWorkspaces") + ": " + root.multiMonitorWorkspaces
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        Slider {
          width: parent.width
          from: 1
          to: 10
          stepSize: 1
          value: root.multiMonitorWorkspaces
          onMoved: root.multiMonitorWorkspaces = Math.round(value)
        }

        Button {
          width: parent.width
          text: root.t(root.uiLang, "applyWorkspaceLayout")
          selected: true
          foreground: root.fg
          onClicked: root.applyWorkspaceLayout(false)
        }
      }

      PanelSeparator { foreground: root.fg }

      // ---------- Devices ----------
      Column {
        Layout.fillWidth: true
        visible: root.currentTab === 4
        spacing: Style.space(10)

        Button {
          width: parent.width
          leftAlign: true
          fontFamily: root.fontFamily
          iconText: root.apfsInstalled ? "󰄬" : "󰏖"
          text: root.apfsInstalled
            ? root.t(root.uiLang, "apfsTitle") + " · ok"
            : root.t(root.uiLang, "apfsInstall")
          selected: !root.apfsInstalled
          foreground: root.fg
          onClicked: {
            statusMessage = root.t(root.uiLang, "apfsInstall") + "…"
            root.run("omarchy-launch-floating-terminal-with-presentation 'yay -S --needed linux-asahi-headers linux-apfs-rw-dkms && sudo depmod -a && sudo modprobe apfs'")
            slowSyncLeft = 12
            slowSyncTimer.restart()
          }
        }

        Text {
          width: parent.width
          visible: root.apfsList.length === 0
          text: root.apfsInstalled ? root.t(root.uiLang, "apfsNone") : root.t(root.uiLang, "apfsMissing")
          color: root.fg
          opacity: 0.5
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        Repeater {
          model: root.apfsList

          Column {
            required property var modelData
            width: parent.width
            spacing: Style.space(4)

            Row {
              width: parent.width
              spacing: Style.space(6)

              Text {
                width: parent.width - apfsActions.width - parent.spacing
                text: modelData.path + (modelData.label ? "  ·  " + modelData.label : "") + (modelData.size ? "  (" + modelData.size + ")" : "")
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
                anchors.verticalCenter: parent.verticalCenter
              }

              Row {
                id: apfsActions
                spacing: Style.space(4)
                anchors.verticalCenter: parent.verticalCenter

                Button {
                  visible: !modelData.mountpoint
                  text: root.t(root.uiLang, "apfsAuto")
                  fontSize: Style.font.caption
                  foreground: root.fg
                  onClicked: root.autoMountApfs(modelData.path)
                }

                Button {
                  visible: !!modelData.mountpoint
                  text: root.t(root.uiLang, "unmount")
                  fontSize: Style.font.caption
                  foreground: root.fg
                  onClicked: root.unmountApfs(modelData.mountpoint)
                }
              }
            }

            PanelSeparator { foreground: root.fg }
          }
        }

        Text {
          width: parent.width
          visible: root.apfsCommandText !== ""
          text: root.apfsCommandText
          color: root.fg
          wrapMode: Text.Wrap
          font.pixelSize: Style.font.caption
          opacity: 0.85
        }

        Button {
          width: parent.width
          visible: root.apfsCommandText !== ""
          text: "Copy APFS command"
          foreground: root.fg
          onClicked: root.copyToClipboard(root.apfsCommandText)
        }
      }

      // ---------- Network devices (manual scans only) ----------
      NetworkDevicesPage {
        Layout.fillWidth: true
        visible: root.devMode && root.currentTab === 5
        core: root
      }

      // ---------- Backup (no automatic jobs on load) ----------
      BackupPage {
        Layout.fillWidth: true
        visible: root.devMode && root.currentTab === 6
        core: root
      }

      // ---------- Profiles ----------
      ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: root.currentTab === 7
        spacing: Style.space(10)

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(12)
          Text {
            Layout.fillWidth: true
            text: root.t(root.uiLang, "profiles")
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
          }
          ToggleRow {
            Layout.preferredWidth: Style.space(150)
            label: "Dev mode"
            checked: root.devMode
            foreground: Color.urgent
            onClicked: root.setDevMode(!root.devMode)
          }
        }

        // Keep/Revert for pending display changes is also available on the
        // Profiles tab so the user can confirm after applying a profile.
        Column {
          width: parent.width
          spacing: Style.space(16)
          visible: root.displayAwaitingConfirmation
          opacity: visible ? 1 : 0
          Behavior on opacity { NumberAnimation { duration: 180 } }

          Rectangle {
            width: parent.width
            height: Style.space(1)
            color: Color.accent
            opacity: 0.6
          }

          Text {
            width: parent.width
            text: root.t(root.uiLang, "displayConfirmPrompt") + " " + root.displaySecondsRemaining + "s"
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.Wrap
          }

          RowLayout {
            width: parent.width
            spacing: Style.space(8)

            Button {
              Layout.fillWidth: true
              text: root.t(root.uiLang, "keep") + " (" + root.displaySecondsRemaining + "s)"
              foreground: root.fg
              selected: true
              onClicked: root.displayKeep()
            }
            Button {
              Layout.fillWidth: true
              text: root.t(root.uiLang, "revert")
              foreground: root.fg
              bordered: true
              onClicked: root.displayRevert()
            }
          }
        }

        Button {
          width: parent.width
          text: "+ " + root.t(root.uiLang, "profileNew")
          foreground: root.fg
          selected: true
          onClicked: { root.createProfile(""); root.statusMessage = root.t(root.uiLang, "profileNew") }
        }

        Column {
          id: profileColumn
          Layout.fillWidth: true
          spacing: Style.space(8)

          Repeater {
            model: root.profiles

              Rectangle {
                required property var modelData
                width: parent.width
                height: profileCard.height + Style.space(12)
                color: root.activeProfileId === modelData.id ? Style.selectedFillFor(root.fg, Color.accent) : Color.popups.background
                border.color: root.activeProfileId === modelData.id ? Color.accent : "transparent"
                border.width: Style.space(1)
                radius: Style.cornerRadius

                Column {
                  id: profileCard
                  width: parent.width - Style.space(16)
                  anchors.centerIn: parent
                  spacing: Style.space(6)

                  RowLayout {
                    width: parent.width
                    spacing: Style.space(8)
                    Text {
                      visible: root.editingProfileId !== modelData.id
                      text: modelData.name + (root.activeProfileId === modelData.id ? " · " + root.t(root.uiLang, "current") : "")
                      color: root.fg
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      font.bold: root.activeProfileId === modelData.id
                      Layout.fillWidth: true
                      verticalAlignment: Text.AlignVCenter
                      MouseArea {
                        anchors.fill: parent
                        enabled: !modelData.builtin
                        onDoubleClicked: root.editingProfileId = modelData.id
                      }
                    }
                    TextField {
                      visible: root.editingProfileId === modelData.id
                      text: modelData.name
                      placeholderText: root.t(root.uiLang, "profilePersonal")
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      selectByMouse: true
                      Layout.fillWidth: true
                      Keys.onEscapePressed: root.editingProfileId = ""
                      onAccepted: root.renameProfile(modelData.id, text)
                      onActiveFocusChanged: if (visible && activeFocus) selectAll()
                      Component.onCompleted: if (visible) forceActiveFocus()
                    }
                    Text {
                      visible: modelData.builtin
                      text: "Default"
                      color: Qt.darker(root.fg, 1.4)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }

                  RowLayout {
                    width: parent.width
                    spacing: Style.space(6)
                    Button {
                      Layout.fillWidth: true
                      text: root.t(root.uiLang, "profileApply")
                      foreground: root.fg
                      selected: true
                      onClicked: root.applyProfile(modelData.id)
                    }
                    Button {
                      Layout.fillWidth: true
                      text: root.t(root.uiLang, "profileDuplicate")
                      foreground: root.fg
                      bordered: true
                      onClicked: root.duplicateProfile(modelData.id)
                    }
                  }
                  RowLayout {
                    width: parent.width
                    spacing: Style.space(6)
                    visible: !modelData.builtin
                    Button {
                      Layout.fillWidth: true
                      text: root.t(root.uiLang, "profileSave")
                      foreground: root.fg
                      bordered: true
                      onClicked: root.saveCurrentToProfile(modelData.id)
                    }
                    Button {
                      Layout.fillWidth: true
                      text: root.t(root.uiLang, "profileDelete")
                      foreground: root.fg
                      bordered: true
                      onClicked: root.deleteProfile(modelData.id)
                    }
                  }
                }
              }
            }
          }
        }

      // ---------- Displays ----------
      Column {
        Layout.fillWidth: true
        visible: root.currentTab === 2
        spacing: Style.space(10)

        RowLayout {
          width: parent.width
          spacing: Style.space(12)
          Text {
            text: "󰍺"
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.display
          }
          Column {
            Layout.fillWidth: true
            Text { width: parent.width; text: root.t(root.uiLang, "displays"); color: root.fg; font.family: root.fontFamily; font.pixelSize: Style.font.title; font.bold: true; elide: Text.ElideRight }
            Text { width: parent.width; text: root.displays.length + (root.displays.length === 1 ? " " + root.t(root.uiLang, "displayCount") : " " + root.t(root.uiLang, "displaysCount")); color: Qt.darker(root.fg, 1.4); font.family: root.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; font.letterSpacing: 1.1; elide: Text.ElideRight }
          }
          // Loading indicator lives in the (fixed-height) header with reserved
          // space, so it never shifts the canvas/content when it flashes.
          Text {
            Layout.alignment: Qt.AlignVCenter
            text: root.t(root.uiLang, "readingDisplays")
            color: Qt.darker(root.fg, 1.4)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            opacity: root.displayLoading ? 1 : 0
          }
          Button {
            Layout.alignment: Qt.AlignVCenter
            text: root.t(root.uiLang, "identify")
            foreground: root.fg
            fontFamily: root.fontFamily
            bordered: true
            active: root.identifyAllDisplays
            onClicked: {
              root.identifyAllDisplays = !root.identifyAllDisplays
              if (root.identifyAllDisplays) identifyAllTimer.restart()
            }
          }
        }

        PanelSeparator { foreground: root.fg }

        Text {
          visible: !root.displayLoading && root.displays.length === 0
          width: parent.width
          text: root.t(root.uiLang, "noDisplays")
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          horizontalAlignment: Text.AlignHCenter
        }

        Rectangle {
          id: displayCanvas
          visible: root.displays.length > 0
          width: parent.width
          height: Math.min(240, Math.max(170, root.contentWidth * 0.31))
          radius: Style.cornerRadius
          color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.035)
          border.color: root.displayValidLayout ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.18) : Color.urgent
          border.width: 1

          // Commit a drag: convert canvas px to logical coords, keep the layout
          // connected (flush), and auto-apply the new position. Lives on the
          // canvas (a normal child of root) because Repeater delegates cannot
          // reliably reach the `root` id to run processes.
          function commitDrag(idx, px, py) {
            var copy = DisplayModel.clone(root.displays)
            copy[idx].x = Math.round((px - Style.space(16)) / zoom + minX)
            copy[idx].y = Math.round((py - Style.space(16)) / zoom + minY)
            copy = DisplayModel.snapDraggedFlush(copy, idx)
            root.displays = copy
            root.displayApplyChanges()
          }

          property real minX: {
            var v = Infinity; root.displays.forEach(function(d) { if (!d.disabled && !d.mirror) v = Math.min(v, d.x) }); return isFinite(v) ? v : 0
          }
          property real minY: {
            var v = Infinity; root.displays.forEach(function(d) { if (!d.disabled && !d.mirror) v = Math.min(v, d.y) }); return isFinite(v) ? v : 0
          }
          property real maxX: {
            var v = 1; root.displays.forEach(function(d) { var s = DisplayModel.logicalSize(d); if (!d.disabled && !d.mirror) v = Math.max(v, d.x + s.width) }); return v
          }
          property real maxY: {
            var v = 1; root.displays.forEach(function(d) { var s = DisplayModel.logicalSize(d); if (!d.disabled && !d.mirror) v = Math.max(v, d.y + s.height) }); return v
          }
          property real zoom: Math.min((width - Style.space(32)) / Math.max(1, maxX - minX), (height - Style.space(32)) / Math.max(1, maxY - minY))

          Repeater {
            model: root.displays
            Rectangle {
              required property var modelData
              required property int index
              property var logical: DisplayModel.logicalSize(modelData)
              property string assignedColorRole: root.displayColorRole(modelData.name)
              property color assignedColor: assignedColorRole
                ? ThemePalette.resolve(assignedColorRole, root.workspaceThemeColors)
                : root.fg
              visible: !modelData.disabled
              x: Style.space(16) + (modelData.x - displayCanvas.minX) * displayCanvas.zoom
              y: Style.space(16) + (modelData.y - displayCanvas.minY) * displayCanvas.zoom
              width: Math.max(Style.space(70), logical.width * displayCanvas.zoom)
              height: Math.max(Style.space(44), logical.height * displayCanvas.zoom)
              radius: Style.cornerRadius
              color: index === root.displaySelectedIndex
                ? Style.selectedFillFor(root.fg, assignedColor)
                : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.04)
              border.color: assignedColorRole
                ? assignedColor
                : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, index === root.displaySelectedIndex ? 0.75 : 0.2)
              border.width: index === root.displaySelectedIndex ? 2 : 1
              opacity: modelData.mirror ? 0.65 : 1

              Text {
                anchors.centerIn: parent
                text: (index + 1) + "  " + modelData.name + (modelData.mirror ? "\nMirrors " + modelData.mirror : "")
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
              }
              MouseArea {
                anchors.fill: parent
                enabled: !root.displayAwaitingConfirmation
                drag.target: parent
                drag.axis: Drag.XAndYAxis
                cursorShape: root.displayAwaitingConfirmation ? Qt.ArrowCursor : Qt.SizeAllCursor
                onPressed: {
                  if (root.displayAwaitingConfirmation) return
                  root.displayDragging = true
                  root.displaySelectedIndex = index
                }
                onReleased: {
                  root.displayDragging = false
                  if (!root.displayAwaitingConfirmation) displayCanvas.commitDrag(index, parent.x, parent.y)
                }
              }
            }
          }
        }

        Text {
          visible: !root.displayValidLayout
          text: root.displayActiveCount === 0 ? root.t(root.uiLang, "displayAtLeastOne") : root.t(root.uiLang, "displayNoOverlap")
          color: Color.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        PanelSeparator { visible: root.displays.length > 0; foreground: root.fg }

        Flow {
          visible: root.displays.length > 0
          width: parent.width
          spacing: Style.space(8)
          Repeater {
            model: root.displays
            Button {
              required property var modelData
              required property int index
              text: (index + 1) + " · " + modelData.name
              foreground: root.fg
              fontFamily: root.fontFamily
              bordered: true
              enabled: !root.displayAwaitingConfirmation
              active: index === root.displaySelectedIndex
              onClicked: { if (!root.displayAwaitingConfirmation) root.displaySelectedIndex = index }
            }
          }
        }

        Column {
          visible: root.displaySelected !== null
          width: parent.width
          spacing: Style.space(6)

          Text {
            width: parent.width
            text: root.t(root.uiLang, "workspaceMonitorColor") + " · " + (root.displaySelected ? root.displaySelected.name : "")
            color: Qt.darker(root.fg, 1.4)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          Flow {
            width: parent.width
            spacing: Style.space(8)
            Repeater {
              model: ThemePalette.roles
              Rectangle {
                required property var modelData
                width: Style.space(24)
                height: Style.space(24)
                radius: width / 2
                color: ThemePalette.resolve(modelData, root.workspaceThemeColors)
                border.color: root.displaySelected && root.displayColorRole(root.displaySelected.name) === modelData ? root.fg : "transparent"
                border.width: root.displaySelected && root.displayColorRole(root.displaySelected.name) === modelData ? Style.space(2) : 0

                Text {
                  anchors.centerIn: parent
                  text: root.displaySelected && root.displayColorRole(root.displaySelected.name) === parent.modelData ? "✓" : ""
                  color: "#101014"
                  font.family: root.fontFamily
                  font.bold: true
                }
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: if (root.displaySelected) root.setDisplayColor(root.displaySelected.name, parent.modelData)
                }
              }
            }
          }
          Text {
            width: parent.width
            text: root.t(root.uiLang, "workspaceMonitorColorHint")
            color: Qt.darker(root.fg, 1.35)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.Wrap
          }

          Text {
            width: parent.width
            text: root.t(root.uiLang, "workspaceIndicatorMode")
            color: Qt.darker(root.fg, 1.4)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          RowLayout {
            width: parent.width
            spacing: Style.space(16)

            Flow {
              Layout.fillWidth: true
              spacing: Style.space(8)
              Repeater {
                model: ["square", "rounded", "circle", "none"]
                Button {
                  required property string modelData
                  text: root.t(root.uiLang, root.indicatorModeKey(modelData))
                  foreground: root.fg
                  bordered: true
                  selected: root.workspaceIndicatorMode === modelData
                  onClicked: root.setWorkspaceIndicatorMode(modelData)
                }
              }
            }

            ColumnLayout {
              Layout.preferredWidth: Style.space(180)
              spacing: Style.space(4)

              Text {
                Layout.fillWidth: true
                text: root.t(root.uiLang, "workspaceIndicatorPadding") + " · " + root.workspaceIndicatorPadding + " px"
                color: Qt.darker(root.fg, 1.25)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Slider {
                Layout.fillWidth: true
                from: 0
                to: 4
                stepSize: 1
                snapMode: Slider.SnapAlways
                value: root.workspaceIndicatorPadding
                onMoved: root.setWorkspaceIndicatorPadding(value)
              }
            }
          }
        }

        GridLayout {
          visible: root.displaySelected !== null
          width: parent.width
          columns: 3
          columnSpacing: Style.space(10)
          rowSpacing: Style.space(10)

          Dropdown {
            Layout.fillWidth: true
            label: options.length === 1 ? root.t(root.uiLang, "resolution") + " · " + root.t(root.uiLang, "native") : root.t(root.uiLang, "resolution")
            foreground: root.fg; fontFamily: root.fontFamily
            options: root.displaySelected ? DisplayModel.resolutionOptions(root.displaySelected.modes) : []
            value: root.displaySelected ? DisplayModel.resolution(root.displaySelected.mode) : ""
            opacity: options.length > 1 ? 1 : 0.72
            enabled: !root.displayAwaitingConfirmation
            onChanged: function(value) { if (!root.displayAwaitingConfirmation) root.displaySetResolution(value) }
          }
          Dropdown {
            Layout.fillWidth: true
            label: root.t(root.uiLang, "refreshRate")
            foreground: root.fg; fontFamily: root.fontFamily
            options: root.displaySelected ? DisplayModel.refreshOptions(root.displaySelected.modes, DisplayModel.resolution(root.displaySelected.mode)) : []
            value: root.displaySelected ? DisplayModel.refresh(root.displaySelected.mode) : ""
            enabled: !root.displayAwaitingConfirmation
            onChanged: function(value) { if (!root.displayAwaitingConfirmation) root.displaySetRefresh(value) }
          }
          Dropdown {
            Layout.fillWidth: true
            label: root.t(root.uiLang, "orientation")
            foreground: root.fg; fontFamily: root.fontFamily
            options: [{value:"0",label:root.t(root.uiLang, "landscape")},{value:"1",label:root.t(root.uiLang, "portrait")},{value:"2",label:root.t(root.uiLang, "landscapeFlipped")},{value:"3",label:root.t(root.uiLang, "portraitFlipped")}]
            value: root.displaySelected ? String(root.displaySelected.transform) : "0"
            enabled: !root.displayAwaitingConfirmation
            onChanged: function(value) { if (!root.displayAwaitingConfirmation) root.displayUpdate("transform", Number(value)) }
          }
        }

        // Free scale slider (50%–400%). Hyprland accepts fractional scales, so
        // the user can dial in the exact text size per display instead of
        // picking from a fixed list.
        Column {
          visible: root.displaySelected !== null
          width: parent.width
          spacing: Style.space(4)

          Row {
            width: parent.width
            spacing: Style.space(8)
            Text {
              id: scaleLabel
              text: root.t(root.uiLang, "scale")
              color: Qt.darker(root.fg, 1.4)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              anchors.verticalCenter: parent.verticalCenter
            }
            Item { width: 1; height: 1; visible: false }
            Text {
              width: parent.width - scaleLabel.width - parent.spacing
              horizontalAlignment: Text.AlignRight
              text: Math.round((root.displaySelected ? Number(root.displaySelected.scale) : 1) * 100) + "%"
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          // Scale as discrete buttons read straight from the monitor's accepted
          // scales (computed from its resolution by DisplayModel.validScales),
          // not a free slider. Hyprland only honours scales that divide the
          // mode's resolution, so offering exactly those avoids invalid picks.
          Flow {
            width: parent.width
            spacing: Style.space(6)
            Repeater {
              model: root.displaySelected ? DisplayModel.validScales(root.displaySelected.mode) : []
              delegate: Button {
                required property var modelData
                text: Math.round(modelData * 100) + "%"
                selected: root.displaySelected && Math.abs(Number(root.displaySelected.scale) - modelData) < 0.001
                foreground: root.fg; fontFamily: root.fontFamily; bordered: true
                enabled: !root.displayAwaitingConfirmation
                onClicked: {
                  if (root.displayAwaitingConfirmation) return
                  root.displayUpdate("scale", modelData)
                  root.displayApplyChanges()
                }
              }
            }
          }
        }

        RowLayout {
          visible: root.displaySelected !== null
          width: parent.width
          spacing: Style.space(10)
          Dropdown {
            Layout.fillWidth: true
            label: root.t(root.uiLang, "multiDisplay")
            foreground: root.fg; fontFamily: root.fontFamily
            options: [{value:"",label:root.t(root.uiLang, "extendDesktop")}].concat(root.displays.filter(function(d){return root.displaySelected && d.name !== root.displaySelected.name && !d.disabled}).map(function(d){return {value:d.name,label:root.t(root.uiLang, "duplicate") + " " + d.name}}))
            value: root.displaySelected ? root.displaySelected.mirror : ""
            enabled: !root.displayAwaitingConfirmation
            onChanged: function(value) { if (!root.displayAwaitingConfirmation) root.displayUpdate("mirror", value) }
          }
          Button {
            Layout.alignment: Qt.AlignBottom
            text: root.displaySelected && root.displaySelected.disabled ? root.t(root.uiLang, "connectDisplay") : root.t(root.uiLang, "disconnectDisplay")
            foreground: root.fg; fontFamily: root.fontFamily; bordered: true
            enabled: root.displaySelected && (root.displaySelected.disabled || root.displayActiveCount > 1) && !root.displayAwaitingConfirmation
            onClicked: { if (!root.displayAwaitingConfirmation) root.displayToggleEnabled() }
          }
        }

        PanelSeparator { foreground: root.fg }

        // Bottom region of the Displays tab. When a preview is armed, the
        // in-panel Keep/Revert confirmation replaces the refresh/apply bar so
        // the user can decide when they reopen the panel. The preview snapshot
        // persists on disk, so the dialog reappears after shell restart too.
        Item {
          id: actionHost
          width: parent.width
          // Grow to fit the active child; collapse the other to 0.
          height: root.displayAwaitingConfirmation ? confirmRow.height : barRow.height
          Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
          clip: true

          // ----- Refresh / Apply bar -----
          RowLayout {
            id: barRow
            width: parent.width
            spacing: Style.space(10)
            opacity: root.displayAwaitingConfirmation ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: 160 } }
            Text {
              Layout.fillWidth: true
              Layout.alignment: Qt.AlignVCenter
              text: root.displayStatusMessage || root.t(root.uiLang, "displayPreviewHint")
              color: Qt.darker(root.fg, 1.25)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
            Button {
              Layout.alignment: Qt.AlignVCenter
              text: root.t(root.uiLang, "refresh")
              foreground: root.fg; fontFamily: root.fontFamily; bordered: true
              enabled: !root.displayAwaitingConfirmation
              onClicked: root.displayRefresh()
            }
            Button {
              Layout.alignment: Qt.AlignVCenter
              text: root.displayApplying ? root.t(root.uiLang, "applying") : root.t(root.uiLang, "apply")
              foreground: root.fg; fontFamily: root.fontFamily; bordered: true
              enabled: root.displayValidLayout && !root.displayApplying && !root.displayAwaitingConfirmation
              onClicked: root.displayApplyChanges()
            }
          }

          // ----- In-panel Keep/Revert confirmation (large, visible) -----
          Rectangle {
            id: confirmCardBg
            anchors.fill: confirmRow
            color: Color.popups.background
            border.color: Color.accent
            border.width: Style.space(2)
            radius: Style.cornerRadius * 2
            opacity: confirmRow.opacity
            visible: confirmRow.visible
            z: -1
          }

          Column {
            id: confirmRow
            width: parent.width
            spacing: Style.space(16)
            opacity: root.displayAwaitingConfirmation ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 160 } }
            visible: root.displayAwaitingConfirmation

            Text {
              width: parent.width
              text: root.t(root.uiLang, "keepChangesPrompt")
              color: Color.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
              wrapMode: Text.WordWrap
            }

            RowLayout {
              width: parent.width
              spacing: Style.space(16)
              Text {
                text: root.displaySecondsRemaining + "s"
                color: Color.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                Layout.alignment: Qt.AlignVCenter
              }
              Item { Layout.fillWidth: true; height: 1 }
              Button {
                text: displayRevertProc.running ? root.t(root.uiLang, "reverting") : root.t(root.uiLang, "revert")
                foreground: root.fg; fontFamily: root.fontFamily; bordered: true
                onClicked: root.displayRevert()
              }
              Button {
                text: displayConfirmProc.running ? root.t(root.uiLang, "keeping") : root.t(root.uiLang, "keepChanges")
                foreground: root.fg; fontFamily: root.fontFamily; bordered: true
                onClicked: root.displayKeep()
              }
            }

            Text {
              width: parent.width
              visible: root.displaySecondsRemaining <= 5
              text: root.t(root.uiLang, "displayRevertHint")
              color: Qt.darker(Color.foreground, 1.4)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }
        }
      }

      PanelSeparator { foreground: root.fg }

      // ---------- Animation ----------
      Column {
        Layout.fillWidth: true
        visible: root.currentTab === 1
        spacing: Style.space(10)


        ToggleRow {
          label: root.t(root.uiLang, "browserCloseTab")
          visible: root.devMode
          foreground: Color.urgent
          checked: root.browserCloseTabOn
          onClicked: { root.setBrowserCloseTab(!root.browserCloseTabOn) }
        }
        ToggleRow {
          label: root.t(root.uiLang, "sysAnims")
          checked: root.animationsEnabled
          onClicked: { root.applyAnimations(!root.animationsEnabled) }
        }
        PanelSeparator { foreground: root.fg }
        ToggleRow {
          label: root.t(root.uiLang, "wsSlide")
          checked: root.wsAnimationOn
          onClicked: { root.animSet(!root.wsAnimationOn) }
        }

        PanelSeparator { foreground: root.fg }

        ToggleRow {
          label: root.t(root.uiLang, "nightLight")
          checked: root.nightLightOn
          onClicked: { root.nightLightOn = !root.nightLightOn; root.run("omarchy-toggle-nightlight") }
        }
      }

      Text {
        width: parent.width
        visible: statusMessage !== ""
        text: statusMessage
        color: root.fg
        opacity: 0.55
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }
  }

  // Physical-monitor highlight for the Displays tab. Draws an accent border
  // (and, in identify-all mode, a big index) on real monitors so the user can
  // match each canvas tile to the physical display.
  DisplayIdentifyOverlay {
    id: displayIdentify
    displays: root.displays
    selectedName: root.opened && root.currentTab === 2 && root.displaySelected ? root.displaySelected.name : ""
    identifyAll: root.opened && root.currentTab === 2 && root.identifyAllDisplays
    dragActive: root.displayDragging
    // Per-monitor color chosen in the Displays tab; accent when unset.
    colorFor: function(name) {
      var role = root.displayColorRole(name)
      return role ? ThemePalette.resolve(role, root.workspaceThemeColors) : ""
    }
  }

  // Keep/Revert confirmation is shown INSIDE the Displays tab. The snapshot
  // of the previous layout is kept on disk, so when the user reopens the
  // panel (or restarts the shell) while a preview is still armed, the dialog
  // reappears and lets them Keep or Revert.
}
