import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "DisplayModel.js" as DisplayModel

Panel {
  id: root
  moduleName: "omarchy-control-panel"
  ipcTarget: "omarchy-control-panel"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null

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
    { title: t(uiLang, "trackpad") },
    { title: t(uiLang, "windows") },
    { title: t(uiLang, "displays") },
    { title: t(uiLang, "kblang") },
    { title: t(uiLang, "devices") }
  ]
  property int currentTab: 0

  // Live system state, refreshed on open.
  property bool naturalScroll: false
  property bool animationsEnabled: true
  property bool wsAnimationOn: false
  property bool nightLightOn: false
  property real cursorSensitivity: 0
  property bool flatAccel: false
  property int gapsIn: 6
  property int gapsOut: 10
  property string kbLayout: "us"
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
  property bool kittyInstalled: true
  property bool inertiaOn: false
  property bool tapToClick: false
  property bool middleBtnOff: false
  property bool browserCloseTabOn: false
  property string defaultTerm: ""

  // APFS (Extras): driver presence + detected partitions.
  property bool apfsInstalled: false
  property var apfsList: []
  property string apfsCommandText: ""

  // Displays tab: live monitor state and the in-progress layout.
  property var displays: []
  property int displaySelectedIndex: 0
  property bool displayLoading: false
  // Names of outputs seen on the last state read, used to detect a hotplugged
  // (newly connected) monitor and auto-arrange it.
  property var displayKnownNames: []
  property bool displayApplying: false
  property bool displayAwaitingConfirmation: false
  property int displaySecondsRemaining: 15
  property string displayStatusMessage: ""
  property string displayRefreshMessage: ""
  // Identify-all mode: show a numbered overlay on every physical monitor.
  property bool identifyAllDisplays: false
  // True while a display tile is being dragged. Suppresses the physical
  // identify overlay during the drag so Quickshell does not create/destroy
  // Wayland PanelWindows mid-gesture (which segfaults in QWaylandWindow::setGeometry).
  property bool displayDragging: false
  readonly property string displayHelperPath: Qt.resolvedUrl("bin/display-manager").toString().replace("file://", "")

  readonly property var displaySelected: displays.length && displaySelectedIndex < displays.length ? displays[displaySelectedIndex] : null
  readonly property int displayActiveCount: displays.filter(function(d) { return !d.disabled }).length
  readonly property bool displayValidLayout: displayActiveCount > 0 && !DisplayModel.hasOverlap(displays)

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
    if (root.opened) root.displayRefresh()
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
    if (!displayValidLayout || displayInstantProc.running) return
    displayInstantProc.command = [displayHelperPath, "apply", JSON.stringify(DisplayModel.clone(displays))]
    displayInstantProc.running = true
  }
  function displayConfirm() {
    if (displayConfirmProc.running || displayRevertProc.running) return
    displayConfirmProc.command = [displayHelperPath, "confirm"]
    displayConfirmProc.running = true
  }

  function displayRevert() {
    if (displayRevertProc.running || displayConfirmProc.running) return
    displayStatusMessage = "Restoring previous layout…"
    displayRevertProc.command = [displayHelperPath, "revert"]
    displayRevertProc.running = true
  }

  // Keep the previewed layout: confirm with the helper (cancels the 15s
  // rollback), then persist into saved.displays so writeLua() records the
  // hl.monitor rules alongside every other setting in control-panel.lua.
  function displayKeep() {
    displayConfirm()
    saved.displays = DisplayModel.clone(displays)
    writeLua()
    savePrefs()
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
    controller.show()
    // Re-apply everything we persist before reading, so a plugin/shell
    // restart that dropped the volatile hyprctl eval values still lands on
    // the saved state instead of whatever Hyprland's defaults are.
    reapplySaved()
    // Do NOT refresh() immediately: readProc reads live Hyprland state and writes
    // it into saved.*. If we refresh before the persisted prefs are loaded (and
    // before reapplySaved() finishes applying the lua, since both are async),
    // readProc can overwrite saved.* with default Hyprland values and the next
    // writeLua() persists those defaults — silently dropping the user's config.
    // Once prefsLoaded is true the source of truth is in place; otherwise the
    // prefsLoader triggers the refresh itself on completion (see loadPrefs()).
    if (root.prefsLoaded) refresh()
    if (!luaStateProc.running) luaStateProc.running = true
    // If a display preview (Keep/Revert) is still armed, the popup may have
    // closed when the output reconfigured on scale change — restore the
    // confirmation dialog on reopen so the user can Keep/Revert without losing
    // the pending state.
    if (!root.displayAwaitingConfirmation && !displayPendingProc.running) {
      displayPendingProc.command = [root.displayHelperPath, "pending"]
      displayPendingProc.running = true
    }
  }

  // The panel only ever wrote values as volatile `hyprctl eval` calls plus a
  // generated Lua file (~/.config/hypr/control-panel.lua) that hyprland.lua
  // requires last. A plugin/shell restart does not re-run those evals, so the
  // running config can diverge from what the toggles show. Replaying the saved
  // Lua file line by line makes the system match the saved state on every open
  // and on plugin load — idempotent and covers every knob at once.
  function reapplySaved() {
    var f = root.luaPath
    Quickshell.execDetached(["bash", "-lc",
      "f='" + f + "'; [ -f \"$f\" ] || exit 0; " +
      "for i in $(seq 1 40); do hyprctl getoption general:gaps_out >/dev/null 2>&1 && break; sleep 0.25; done; " +
      "while IFS= read -r l; do l=\"${l%$'\\r}\"; [ -z \"$l\" ] && continue; " +
      "case \"$l\" in \\#*) continue;; esac; " +
      "hyprctl eval \"$l\" >/dev/null 2>&1 || true; done < \"$f\""])
    syncTimer.restart()
  }

  function close() {
    identifyAllDisplays = false
    controller.hide()
  }

  function refresh() {
    if (readProc.running) readProc.running = false
    readProc.running = true
    if (!kbdLedProbe.running) kbdLedProbe.running = true
    displayRefresh()
  }

  function run(cmd) {
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
    animations: true,
    wsAnimation: false,
    gapsIn: -1,
    gapsOut: -1,
    kbLayout: "",
    swipe3: false,
    tapToClick: false,
    browserCloseTab: false,
    middleButtonScreenshotOff: false,
    displays: []
  })

  // writeLua() is only safe once the persisted prefs are loaded; otherwise an
  // early caller (e.g. the natural-scroll sync) regenerates control-panel.lua
  // with default values and silently drops the swipe gestures and toggles.
  property bool prefsLoaded: false

  function writeLua() {
    if (!root.prefsLoaded) return
    var L = ["-- Generated by Omarchy Control Panel. Safe to delete."]
    L.push("hl.config({ input = { natural_scroll = " + (saved.naturalScroll ? "true" : "false") + " } })")
    L.push("hl.config({ input = { touchpad = { tap_to_click = " + (saved.tapToClick ? "true" : "false") + " } } })")
    L.push("hl.config({ input = { sensitivity = " + Number(saved.sensitivity).toFixed(2) + " } })")
    L.push('hl.config({ input = { accel_profile = "' + (saved.flatAccel ? "flat" : "adaptive") + '" } })')
    L.push("hl.config({ animations = { enabled = " + (saved.animations ? "true" : "false") + " } })")
    L.push('hl.animation({ leaf = "workspaces", enabled = ' + (saved.wsAnimation ? "true" : "false")
           + ', speed = 4, bezier = "easeOutQuint", style = "slide" })')
    if (saved.kbLayout !== "")
      L.push('hl.config({ input = { kb_layout = "' + saved.kbLayout + '" } })')
    var gi = saved.gapsIn >= 0 ? saved.gapsIn : 5
    var go = saved.gapsOut >= 0 ? saved.gapsOut : 10
    L.push("hl.config({ general = { gaps_in = " + gi + ", gaps_out = " + go + " } })")
    // 3-finger swipe switches workspaces. We OWN this gesture (the toggle is in
    // this panel) and invert it when natural scrolling is on, so the swipe feels
    // consistent with the rest of the trackpad. Hyprland cannot unbind gestures,
    // so to avoid colliding with user.trackpad-gestures (which also defines a
    // 3-finger swipe) we disable that plugin's 3-finger assignment while our
    // swipe3 toggle is on — see syncTrackpadGestures(). The two are mutually
    // exclusive, so there is never a double definition / "overshadowed" warning.
    if (saved.swipe3) {
      var leftTarget = saved.naturalScroll ? "+1" : "-1"
      var rightTarget = saved.naturalScroll ? "-1" : "+1"
      var g = [
        'local function ocp_swipe(dir)',
        '  local distance, triggered = 0, false',
        '  local function consume(event)',
        '    if triggered then return end',
        '    distance = distance + math.abs(event.delta.x)',
        '    if distance >= 25 then',
        '      triggered = true',
        '      hl.dispatch(hl.dsp.focus({ workspace = dir }))',
        '    end',
        '  end',
        '  return {',
        '    start = function(e) distance = 0; triggered = false; consume(e) end,',
        '    update = consume,',
        '    finish = function() distance = 0; triggered = false end,',
        '  }',
        'end',
        'hl.gesture({ fingers = 3, direction = "left", action = ocp_swipe("' + leftTarget + '") })',
        'hl.gesture({ fingers = 3, direction = "right", action = ocp_swipe("' + rightTarget + '") })'
      ]
      L.push(g.join("\n"))
    }
    // The Apple MTP is mouse-classified, so the global input:natural_scroll
    // often doesn't reach it. The working knob is the per-device
    // natural_scroll boolean. scroll_factor must stay >= 0 (negative is
    // rejected), so we pin it to 1 to cancel any stale negative factor and
    // let natural_scroll alone control direction.
    L.push('hl.device({ name = "apple-mtp-multi-touch", natural_scroll = ' + (saved.naturalScroll ? "true" : "false") + ', scroll_factor = 1 })')

    // Persisted display layout (Displays tab). One hl.monitor rule per output,
    // same expressions the display helper sends to Hyprland. These reload with
    // the rest of control-panel.lua so the arrangement survives restarts.
    if (saved.displays && saved.displays.length) {
      L.push("-- Display layout")
      DisplayModel.clone(saved.displays).forEach(function(d) {
        if (d.disabled) {
          L.push('hl.monitor({ output = "' + d.name + '", disabled = true })')
        } else {
          var mode = String(d.mode || "preferred").replace(/Hz$/, "")
          L.push('hl.monitor({ output = "' + d.name + '", mode = "' + mode + '", position = "' + d.x + 'x' + d.y + '", scale = ' + (Number(d.scale) || 1) + ', transform = ' + (Number(d.transform) || 0) + (d.mirror ? ', mirror = "' + d.mirror + '"' : '') + ' })')
        }
      })
    }

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
    if (saved.browserCloseTab) {
      var scriptPath = Qt.resolvedUrl("bin/close-tab-or-window.sh").toString().replace("file://", "")
      L.push('-- SUPER+W closes browser tabs (toggle "Close tab in browsers")')
      L.push('hl.unbind("SUPER + W")')
      L.push([
        'hl.bind("SUPER + W", function()',
        '  local ok, win = pcall(function() return hl.get_active_window() end)',
        '  local cls = ""',
        '  if ok and win and win.class then cls = string.lower(tostring(win.class)) end',
        '  if cls:match("chrome") or cls:match("chromium") or cls:match("firefox") or cls:match("edge") or cls:match("brave") or cls:match("opera") or cls:match("vivaldi") or cls:match("epiphany") or cls:match("gnome%-web") then',
        '    hl.dispatch(hl.dsp.exec_cmd("bash ' + scriptPath + ' \'" .. cls .. "\' &"))',
        '  else',
        '    hl.dsp.window.close()',
        '  end',
        'end)'
      ].join("\n"))
    }

    // When enabled, unbind the middle-mouse-button screenshot (mouse:274) that
    // the user.trackpad-gestures plugin defines — an uncomfortable combo for
    // some trackpads. control-panel.lua is required after gestures-generated.lua,
    // so this unbind wins the load order.
    if (saved.middleButtonScreenshotOff) {
      L.push('-- Disable middle-button screenshot (toggle "Middle-button screenshot")')
      L.push('hl.unbind("mouse:274")')
    }

    // Atomic, symlink-safe write via external script (mktemp + mv -f).
    luaWriter.command = ["bash", Qt.resolvedUrl("write-lua-atomic.sh").toString().replace("file://", ""),
      root.luaPath, L.join("\n")]
    luaWriter.running = true
  }

  // Keep user.trackpad-gestures from ALSO defining a 3-finger swipe, which would
  // collide with ours ("overshadowed" warning — Hyprland can't unbind gestures).
  // While our swipe3 toggle is ON we clear that plugin's generated gesture file
  // so only our (natural-scroll-aware, inverted) swipe is active; while OFF we
  // regenerate it from the plugin's defaults so it works on its own. The two are
  // mutually exclusive, so there is never a double definition.
  function syncTrackpadGestures() {
    var tp = Quickshell.env("HOME") + "/.config/hypr/gestures-generated.lua"
    if (root.saved.swipe3) {
      tpSync.command = ["bash", "-lc",
        "printf '%s\\n' '-- Cleared by omarchy-control-panel (swipe3 on): 3-finger swipe owned by control-panel' > '" + tp + "'"]
    } else {
      var sh = Quickshell.env("HOME") + "/.config/omarchy/plugins/user.trackpad-gestures/apply-gestures.sh"
      tpSync.command = ["bash", sh, "true", "clickfinger", "lrm", "threefinger", "screenshot", "false",
        "none", "none", "none", "none", "none", "none",
        "relative_workspace", "relative_workspace", "none", "none", "none", "none",
        "none", "none", "none", "none", "none", "none"]
    }
    tpSync.running = true
  }

  Process {
    id: tpSync
    stdout: StdioCollector { waitForEnd: true }
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

  // The Apple MTP touchpad is classified as a mouse by Hyprland, so the
  // global input:natural_scroll never reaches it. Set it per-device (works
  // via scrollFactor -1) plus globally for real touchpads.
  function setNaturalScroll(on, quiet) {
    console.info("[mcp] setNaturalScroll", on)
    // Update the visible state FIRST: syncGestures below needs the fresh
    // value, and the 450ms poll would otherwise feed it a stale one.
    saved.naturalScroll = on
    naturalScroll = on
    // For the Apple MTP pad (mouse-classified) the deterministic knob is the
    // per-device natural_scroll boolean. scroll_factor must stay >= 0, so we
    // pin it to 1 to drop any stale negative factor; natural_scroll alone
    // flips direction. (Global input:natural_scroll is ignored by this device.)
    Quickshell.execDetached(["hyprctl", "eval",
      'hl.device({ name = "apple-mtp-multi-touch", natural_scroll = ' + (on ? "true" : "false") + ', scroll_factor = 1 })'])
    Quickshell.execDetached(["bash", "-lc",
      "hyprctl eval 'hl.config({ input = { natural_scroll = " + (on ? "true" : "false") + " } })'"])
    if (!quiet) statusMessage = root.t(root.uiLang, "invScroll") + " · " + (on ? "on" : "off")
    writeLua()
    syncGestures(on)
    syncTimer.restart()
    savePrefs()
  }

  function applySensitivity(v) {
    saved.sensitivity = v
    cursorSensitivity = v
    hyprSet("input", "sensitivity", Number(v).toFixed(2))
    writeLua()
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
    run("hyprctl reload")
    statusMessage = "Botón central · " + (on ? "desactivado" : "activado")
  }

  function setBrowserCloseTab(on) {
    browserCloseTabOn = on
    saved.browserCloseTab = on
    savePrefs()
    writeLua()
    run("hyprctl reload")
    statusMessage = "SUPER+W navegadores · " + (on ? "pestaña" : "ventana")
  }

  function syncGestures(naturalNow) {
    console.info("[mcp] syncGestures swipe=", saved.swipe3, "natural=", naturalNow)
    // 3-finger swipe gestures are owned exclusively by the user.trackpad-gestures
    // plugin (gestures-generated.lua + its shell.json). Do NOT call
    // updateEntryInline here: it targets standard shell widget keys, not user
    // plugins, and would both error and clobber the plugin's gesture config.
    writeLua()
  }

  function setInertia(on) {
    inertiaOn = on
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
      swipe3On = d.swipe3 === true
      saved.swipe3 = swipe3On
      inertiaOn = d.inertia === true
      naturalScroll = d.naturalScroll === true
      saved.naturalScroll = naturalScroll
      tapToClick = d.tapToClick === true
      saved.tapToClick = tapToClick
      saved.browserCloseTab = d.browserCloseTab === true
      browserCloseTabOn = saved.browserCloseTab
      saved.middleButtonScreenshotOff = d.middleButtonScreenshotOff === true
      middleBtnOff = saved.middleButtonScreenshotOff
      prefsLoaded = true
      // Do NOT call syncTrackpadGestures()/writeLua() here: at this point
      // saved.sensitivity/gaps/kb_layout/accel are still at their object defaults
      // because readProc no longer writes them and luaStateProc hasn't run yet.
      // Writing now would persist those defaults and silently drop the user's
      // config. luaStateProc repopulates saved.* from the persisted Lua (the
      // source of truth) and triggers the write itself once it's done.
      // The persisted config is now the source of truth. If the panel is already
      // open, refresh the UI from live state NOW — this is the only safe moment,
      // because readProc must never overwrite saved.* with default Hyprland
      // values before our config is in place (see open()/readProc note below).
      if (root.opened) root.refresh()
    } catch (e) {}
  }

  function savePrefs() {
    prefsWriter.command = ["bash", Qt.resolvedUrl("write-prefs-atomic.sh").toString().replace("file://", ""),
      prefsPath, JSON.stringify({ swipe3: swipe3On, inertia: inertiaOn, naturalScroll: naturalScroll, tapToClick: tapToClick, browserCloseTab: browserCloseTabOn, middleButtonScreenshotOff: middleBtnOff })]
    prefsWriter.running = true
  }

  Process {
    id: prefsWriter
    stdout: StdioCollector { waitForEnd: true }
  }

  Process {
    id: prefsLoader
    command: ["bash", "-lc", "head -c 65536 '" + root.prefsPath + "' 2>/dev/null || true"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.loadPrefs(text)
    }
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
      "echo ACCEL=$(hyprctl getoption input:accel_profile -j | jq -r .str); " +
      "echo GIN=$(hyprctl getoption general:gaps_in -j | jq -r '.css // empty' | cut -d' ' -f1); " +
      "echo GOUT=$(hyprctl getoption general:gaps_out -j | jq -r '.css // empty' | cut -d' ' -f1); " +
      "echo KB=$(hyprctl getoption input:kb_layout -j | jq -r .str); " +
      "echo NL=$(omarchy-toggle-nightlight --status 2>/dev/null | jq -r .enabled); " +
      "echo WSA=$(hyprctl animations 2>/dev/null | awk '/^[[:space:]]*name: workspaces$/{f=1;next} f&&/enabled:/{print $2; exit}'); " +
      "echo LOCL=$(localectl status | sed -n 's/.*LANG=//p' | head -1); " +
      "echo DEV=$(hyprctl devices -j | jq -r '[.mice[] | select(.name | test(\"apple|mtp|touchpad|trackpad\")) | .scrollFactor][0] // empty'); " +
      "echo APFSD=$(pacman -Qq linux-apfs-rw-dkms >/dev/null 2>&1 && echo yes || echo no); " +
      "echo DTERM=$(omarchy-default-terminal 2>/dev/null); " +
      "echo KITTY=$(command -v kitty >/dev/null 2>&1 && echo yes || echo no)"]
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
          else if (k === "ACCEL") { root.flatAccel = v.indexOf("flat") === 0 }
          else if (k === "GIN") { var gin = parseInt(v); if (!isNaN(gin)) root.gapsIn = gin }
          else if (k === "GOUT") { var gout = parseInt(v); if (!isNaN(gout)) root.gapsOut = gout }
          else if (k === "KB") { root.kbLayout = v || "us" }
          else if (k === "NL") root.nightLightOn = v === "true"
          else if (k === "WSA") { var n = parseInt(v); if (n === 0 || n === 1) { root.wsAnimationOn = n >= 1 } }
          else if (k === "LOCL" && v !== "") root.currentLocale = v
          else if (k === "APFSD") { root.apfsInstalled = v === "yes"; if (!apfsProbe.running) apfsProbe.running = true }
          else if (k === "SW3") root.swipe3On = v === "relative_workspace"
          else if (k === "KITTY") root.kittyInstalled = v === "yes"
          else if (k === "INERTIA") root.inertiaOn = v === "true"
          else if (k === "DTERM" && v !== "") root.defaultTerm = v
        }
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
          if (k === "SENS" && v !== "") { var sv = parseFloat(v); if (!isNaN(sv)) { root.cursorSensitivity = sv; root.saved.sensitivity = sv } }
          if (k === "GIN" && v !== "") { var gin = parseInt(v); if (!isNaN(gin)) { root.gapsIn = gin; root.saved.gapsIn = gin } }
          if (k === "GOUT" && v !== "") { var gout = parseInt(v); if (!isNaN(gout)) { root.gapsOut = gout; root.saved.gapsOut = gout } }
          if (k === "KB" && v !== "") { root.kbLayout = v; root.saved.kbLayout = v }
          if (k === "ACC" && (v === "flat" || v === "adaptive")) { root.flatAccel = (v === "flat"); root.saved.flatAccel = root.flatAccel }
        }
        // All persisted Lua values are now in saved.*. Regenerate the Lua so it
        // keeps these real values (do NOT let readProc/writeLua ever serialize
        // the object defaults). Only after prefs are loaded to avoid a write
        // race with the JSON side.
        if (root.prefsLoaded) root.syncTrackpadGestures()
      }
    }
  }
  // Dynamic locale list (system locales) for the language picker.
  property var localeOptions: []
  property string pendingInstall: ""
  property string localeInstallHint: ""
  Process {
    id: localeListProc
    command: ["bash", Qt.resolvedUrl("locale-list.sh").toString().replace("file://", "")]
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
      + Qt.resolvedUrl("locale-helper").toString().replace("file://", "") + "\" "
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
          // better than a blank one.
          var sane = DisplayModel.sanitizeDisplays(parsed)
          if (JSON.stringify(sane) !== JSON.stringify(parsed)) {
            parsed = sane
            root.displays = sane
            root.displayApplyInstant()
          }
          root.displays = parsed
          // Keep saved.displays in sync with the live layout so a later
          // writeLua() (triggered by any setting) always records the display
          // rules. Without this, a panel reload left saved.displays empty and
          // the next unrelated writeLua wiped the monitor layout from
          // control-panel.lua, losing it on the next Hyprland restart.
          if (!root.saved.displays || root.saved.displays.length === 0) {
            root.saved.displays = DisplayModel.clone(parsed)
            // First state read after startup: prefs are loaded and the display
            // layout is now known. Regenerate control-panel.lua.
            root.writeLua()
          }
          // Hotplug CONNECT: a monitor that was just plugged in is auto-placed
          // by Hyprland (often overlapping the others). Snap it flush against the
          // existing layout (which does not move) and apply, so a freshly
          // connected monitor never lands overlapped (which would error and restart).
          var currentNames = []
          for (var ci = 0; ci < parsed.length; ci++) currentNames.push(parsed[ci].name)
          if (root.displayKnownNames.length > 0) {
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
          root.displayStatusMessage = root.displayRefreshMessage
          root.displayRefreshMessage = ""
          // Restore a pending Keep/Revert confirmation if a preview is still
          // armed (e.g. the popup closed when the primary output reconfigured).
          if (!root.displayAwaitingConfirmation && !displayPendingProc.running) {
            displayPendingProc.command = [root.displayHelperPath, "pending"]
            displayPendingProc.running = true
          }
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
      } else {
        root.displayRefresh(root.displayProcessError(displayApplyError.text, "Preview failed; the previous layout was restored"))
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
        root.saved.displays = DisplayModel.clone(root.displays)
        root.writeLua()
        root.displayRefresh()
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
      if (exitCode !== 0) return
      var result = root.displayParse(displayPendingOutput.text)
      if (result && result.pending === true && !root.displayAwaitingConfirmation) {
        root.displayAwaitingConfirmation = true
        root.displaySecondsRemaining = 15
        root.displayStatusMessage = "Confirm display settings?"
        displayConfirmationTimer.restart()
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
    onTriggered: {
      root.displaySecondsRemaining--
      if (root.displaySecondsRemaining <= 0) {
        stop()
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
    prefsLoader.running = true
    if (!i18nLoader.running) i18nLoader.running = true
    if (!localeListProc.running) localeListProc.running = true
    if (!layoutListProc.running) layoutListProc.running = true
    if (!localeHelperProbe.running) localeHelperProbe.running = true
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
      if (!luaStateProc.running) luaStateProc.running = true
    }
  }

  implicitWidth: buttonPlaceholder.implicitWidth
  implicitHeight: buttonPlaceholder.implicitHeight
  Item { id: buttonPlaceholder; anchors.fill: parent }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(495))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) {
        root.currentTab = (root.currentTab + direction + root.tabs.length) % root.tabs.length
      }
    }

    Column {
      id: contentColumn
      width: parent.width
      spacing: Style.space(12)

      Row {
        width: parent.width
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
        width: parent.width
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

      PanelSeparator { foreground: root.fg }

      // ---------- Keyboard & Language ----------
      Column {
        width: parent.width
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
        width: parent.width
        visible: root.currentTab === 0
        spacing: Style.space(10)

        Toggle {
          label: root.t(root.uiLang, "invScroll")
          checked: root.naturalScroll
          onClicked: { root.setNaturalScroll(!root.naturalScroll, false) }
        }

        Text {
          text: root.t(root.uiLang, "speed") + ": " + Number(root.cursorSensitivity).toFixed(2)
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

        Toggle {
          label: root.t(root.uiLang, "flatAccel")
          checked: root.flatAccel
          onClicked: { root.flatAccel = !root.flatAccel; root.hyprSet("input", "accel_profile", root.flatAccel ? '"flat"' : '"adaptive"'); root.writeLua() }
        }

        Toggle {
          label: root.t(root.uiLang, "tapClick")
          checked: root.tapToClick
          onClicked: { root.setTapToClick(!root.tapToClick) }
        }

        Toggle {
          label: root.t(root.uiLang, "swipe3")
          checked: root.swipe3On
          onClicked: { root.setSwipe3(!root.swipe3On) }
        }

        Toggle {
          label: root.t(root.uiLang, "middleButtonScreenshotOff")
          checked: root.middleBtnOff
          onClicked: { root.setMiddleBtnOff(!root.middleBtnOff) }
        }

        PanelSeparator { foreground: root.fg }

        Toggle {
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
        width: parent.width
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
      }

      PanelSeparator { foreground: root.fg }

      // ---------- Devices ----------
      Column {
        width: parent.width
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

      // ---------- Displays ----------
      Column {
        width: parent.width
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
          height: Math.min(240, Math.max(170, panel.contentWidth * 0.31))
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
            root.displayApplyInstant()
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
              visible: !modelData.disabled
              x: Style.space(16) + (modelData.x - displayCanvas.minX) * displayCanvas.zoom
              y: Style.space(16) + (modelData.y - displayCanvas.minY) * displayCanvas.zoom
              width: Math.max(Style.space(70), logical.width * displayCanvas.zoom)
              height: Math.max(Style.space(44), logical.height * displayCanvas.zoom)
              radius: Style.cornerRadius
              color: index === root.displaySelectedIndex ? Style.selectedFillFor(root.fg, Color.accent) : Style.hoverFillFor(root.fg, Color.accent)
              border.color: index === root.displaySelectedIndex ? Color.accent : root.fg
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
                drag.target: parent
                drag.axis: Drag.XAndYAxis
                cursorShape: Qt.SizeAllCursor
                onPressed: {
                  root.displayDragging = true
                  root.displaySelectedIndex = index
                }
                onReleased: {
                  root.displayDragging = false
                  displayCanvas.commitDrag(index, parent.x, parent.y)
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
              active: index === root.displaySelectedIndex
              onClicked: root.displaySelectedIndex = index
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
            onChanged: function(value) { root.displaySetResolution(value) }
          }
          Dropdown {
            Layout.fillWidth: true
            label: root.t(root.uiLang, "refreshRate")
            foreground: root.fg; fontFamily: root.fontFamily
            options: root.displaySelected ? DisplayModel.refreshOptions(root.displaySelected.modes, DisplayModel.resolution(root.displaySelected.mode)) : []
            value: root.displaySelected ? DisplayModel.refresh(root.displaySelected.mode) : ""
            onChanged: function(value) { root.displaySetRefresh(value) }
          }
          Dropdown {
            Layout.fillWidth: true
            label: root.t(root.uiLang, "orientation")
            foreground: root.fg; fontFamily: root.fontFamily
            options: [{value:"0",label:root.t(root.uiLang, "landscape")},{value:"1",label:root.t(root.uiLang, "portrait")},{value:"2",label:root.t(root.uiLang, "landscapeFlipped")},{value:"3",label:root.t(root.uiLang, "portraitFlipped")}]
            value: root.displaySelected ? String(root.displaySelected.transform) : "0"
            onChanged: function(value) { root.displayUpdate("transform", Number(value)) }
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
                onClicked: { root.displayUpdate("scale", modelData); root.displayApplyPreview() }
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
            onChanged: function(value) { root.displayUpdate("mirror", value) }
          }
          Button {
            Layout.alignment: Qt.AlignBottom
            text: root.displaySelected && root.displaySelected.disabled ? root.t(root.uiLang, "connectDisplay") : root.t(root.uiLang, "disconnectDisplay")
            foreground: root.fg; fontFamily: root.fontFamily; bordered: true
            enabled: root.displaySelected && (root.displaySelected.disabled || root.displayActiveCount > 1)
            onClicked: root.displayToggleEnabled()
          }
        }

        PanelSeparator { foreground: root.fg }

        Item {
          id: barHost
          width: parent.width
          height: root.displayAwaitingConfirmation ? 0 : barRow.height
          opacity: root.displayAwaitingConfirmation ? 0 : 1
          Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
          Behavior on opacity { NumberAnimation { duration: 160 } }
          clip: true
          RowLayout {
            id: barRow
            width: parent.width
            spacing: Style.space(10)
            Text {
              Layout.fillWidth: true
              Layout.alignment: Qt.AlignVCenter
              text: root.displayStatusMessage || root.t(root.uiLang, "displayPreviewHint")
              color: root.displayAwaitingConfirmation ? Color.accent : Qt.darker(root.fg, 1.25)
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
              onClicked: root.displayApplyPreview()
            }
          }
        }

        // Keep/Revert confirmation now lives in a global LayerSurface
        // (confirmOverlay) so it survives the popup closing when the output
        // reconfigures on a scale change. See the PanelWindow at the end.
      }

      PanelSeparator { foreground: root.fg }

      // ---------- Animation ----------
      Column {
        width: parent.width
        visible: root.currentTab === 1
        spacing: Style.space(10)


        Toggle {
          label: root.t(root.uiLang, "browserCloseTab")
          checked: root.browserCloseTabOn
          onClicked: { root.setBrowserCloseTab(!root.browserCloseTabOn) }
        }
        Toggle {
          label: root.t(root.uiLang, "sysAnims")
          checked: root.animationsEnabled
          onClicked: { root.applyAnimations(!root.animationsEnabled) }
        }
        PanelSeparator { foreground: root.fg }
        Toggle {
          label: root.t(root.uiLang, "wsSlide")
          checked: root.wsAnimationOn
          onClicked: { root.animSet(!root.wsAnimationOn) }
        }

        PanelSeparator { foreground: root.fg }

        Toggle {
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
  }

  // Keep/Revert confirmation as a GLOBAL LayerSurface so it stays visible even
  // after the control-panel popup closes (changing a monitor's scale reconfigures
  // the output and Quickshell tears down the popup). The user can confirm or
  // revert from this overlay regardless of the popup's state.
  PanelWindow {
    id: confirmOverlay
    visible: root.displayAwaitingConfirmation
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    anchors { top: true; bottom: true; left: true; right: true }

    // Fade + scale the card in/out instead of popping it.
    Behavior on opacity { NumberAnimation { duration: 160 } }
    opacity: root.displayAwaitingConfirmation ? 1 : 0

    Column {
      anchors.centerIn: parent
      width: Math.min(Style.space(520), parent.width - Style.space(40))
      spacing: Style.space(10)

      Rectangle {
        width: parent.width
        radius: Style.cornerRadius * 2
        color: Color.popups.background
        border.color: Color.accent
        border.width: Style.normalBorderWidth
        // Animate height so the card grows/shrinks smoothly.
        height: overlayInner.height + Style.space(20)
        Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        clip: true

        Column {
          id: overlayInner
          anchors.fill: parent
          anchors.margins: Style.space(10)
          spacing: Style.space(10)

          Text {
            width: parent.width
            text: root.t(root.uiLang, "keepChangesPrompt")
            color: Color.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
            wrapMode: Text.WordWrap
          }

          RowLayout {
            width: parent.width
            spacing: Style.space(10)
            Text { text: root.displaySecondsRemaining + "s"; color: Color.accent; font.family: root.fontFamily; font.pixelSize: Style.font.subtitle; font.bold: true; Layout.alignment: Qt.AlignVCenter }
            Item { Layout.fillWidth: true; height: 1 }
            Button { text: displayRevertProc.running ? root.t(root.uiLang, "reverting") : root.t(root.uiLang, "revert"); foreground: root.fg; fontFamily: root.fontFamily; bordered: true; onClicked: root.displayRevert() }
            Button { text: displayConfirmProc.running ? root.t(root.uiLang, "keeping") : root.t(root.uiLang, "keepChanges"); foreground: root.fg; fontFamily: root.fontFamily; bordered: true; onClicked: root.displayKeep() }
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
  }
}

