import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

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

  // UI language follows the OS locale prefix (es/en/pt/fr, else en).
  readonly property string uiLang: {
    var p = (currentLocale || "es_ES").toLowerCase().split("_")[0]
    return (p === "es" || p === "en" || p === "pt" || p === "fr") ? p : "en"
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
    { title: t(uiLang, "animation") },
    { title: t(uiLang, "windows") },
    { title: t(uiLang, "devices") },
    { title: t(uiLang, "kblang") }
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
  property string defaultTerm: ""

  // APFS (Extras): driver presence + detected partitions.
  property bool apfsInstalled: false
  property var apfsList: []

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
    refresh()
    if (!luaStateProc.running) luaStateProc.running = true
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
      "while IFS= read -r l; do l=\"${l%$'\\r'}\"; [ -z \"$l\" ] && continue; " +
      "case \"$l\" in \\#*) continue;; esac; " +
      "hyprctl eval \"$l\" >/dev/null 2>&1 || true; done < \"$f\""])
    syncTimer.restart()
  }

  function close() {
    controller.hide()
  }

  function refresh() {
    if (readProc.running) readProc.running = false
    readProc.running = true
    if (!kbdLedProbe.running) kbdLedProbe.running = true
  }

  function run(cmd) {
    Quickshell.execDetached(["bash", "-lc", cmd])
    syncTimer.restart()
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
    tapToClick: false
  })

  function writeLua() {
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
    // 3-finger swipe switches workspaces. This is the single source of truth
    // for that gesture (the user.trackpad-gestures plugin restores its own
    // shell.json from a backup and would drop it). control-panel.lua is
    // required after gestures-generated.lua, so these win the load order.
    if (saved.swipe3) {
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
        'hl.gesture({ fingers = 3, direction = "left", action = ocp_swipe("+1") })',
        'hl.gesture({ fingers = 3, direction = "right", action = ocp_swipe("-1") })'
      ]
      L.push(g.join("\n"))
    }
    // The Apple MTP is mouse-classified, so the global input:natural_scroll
    // often doesn't reach it. The working knob is the per-device
    // natural_scroll boolean. scroll_factor must stay >= 0 (negative is
    // rejected), so we pin it to 1 to cancel any stale negative factor and
    // let natural_scroll alone control direction.
    L.push('hl.device({ name = "apple-mtp-multi-touch", natural_scroll = ' + (saved.naturalScroll ? "true" : "false") + ', scroll_factor = 1 })')

    // Atomic write (tmp + mv) so a concurrent hyprctl reload can never read
    // a half-written file and blame a phantom syntax error mid-file.
    luaWriter.command = ["bash", "-lc",
      "mkdir -p ~/.config/hypr && printf '%s\\n' \"$1\" > '" + root.luaPath + ".tmp' && mv '" + root.luaPath + ".tmp' '" + root.luaPath + "' && "
      + "grep -qs 'require(\"control-panel\")' ~/.config/hypr/hyprland.lua || "
      + "echo 'require(\"control-panel\")' >> ~/.config/hypr/hyprland.lua",
      "bash", L.join("\n")]
    luaWriter.running = true
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

  // Locales may not be generated yet; enable in locale.gen, generate, apply.
  // pkexec + locale-gen take seconds, so reflect optimistically and poll.
  function setLocale(locale) {
    if (!locale) return
    run("pkexec bash -c \"sed -i 's/^#" + locale + "/" + locale + "/' /etc/locale.gen && locale-gen >/dev/null 2>&1 && localectl set-locale " + locale + "\"")
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
    statusMessage = t(uiLang, "swipe3") + " · " + (on ? "on" : "off")
    slowSyncLeft = 3
    slowSyncTimer.restart()
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
    } catch (e) {}
  }

  function savePrefs() {
    prefsWriter.command = ["bash", "-lc",
      "mkdir -p ~/.local/state/omarchy && printf '%s\\n' \"$1\" > '" + prefsPath + ".tmp' && mv '" + prefsPath + ".tmp' '" + prefsPath + "'",
      "bash", JSON.stringify({ swipe3: swipe3On, inertia: inertiaOn, naturalScroll: naturalScroll, tapToClick: tapToClick })]
    prefsWriter.running = true
  }

  Process {
    id: prefsWriter
    stdout: StdioCollector { waitForEnd: true }
  }

  Process {
    id: prefsLoader
    command: ["bash", "-lc", "cat '" + root.prefsPath + "' 2>/dev/null || true"]
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
    var base = dev.replace("/dev/", "")
    run("pkexec bash -c 'UUID=$(blkid -s UUID -o value " + dev + "); MP=/mnt/apfs-" + base + "; "
      + "grep -qs \"$UUID\" /etc/fstab || echo \"UUID=$UUID $MP apfs rw,nofail,x-systemd.automount,x-systemd.device-timeout=10 0 0\" >> /etc/fstab; "
      + "mkdir -p \"$MP\"; systemctl daemon-reload; modprobe apfs 2>/dev/null; ls \"$MP\"'")
    statusMessage = "APFS · automount · " + dev
    syncTimer.restart()
  }

  function unmountApfs(mp) {
    run("pkexec umount '" + mp + "'")
    statusMessage = "APFS · umount · " + mp
    syncTimer.restart()
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
          if (k === "ANIM") root.animationsEnabled = v === "true"
          else if (k === "SENS") root.cursorSensitivity = parseFloat(v) || 0
          else if (k === "ACCEL") root.flatAccel = v.indexOf("flat") === 0
          else if (k === "GIN") { var gin = parseInt(v); if (!isNaN(gin)) root.gapsIn = gin }
          else if (k === "GOUT") { var gout = parseInt(v); if (!isNaN(gout)) root.gapsOut = gout }
          else if (k === "KB") { root.kbLayout = v || "us"; if (!root.saved.kbLayout) root.saved.kbLayout = root.kbLayout.split(",")[0] }
          else if (k === "NL") root.nightLightOn = v === "true"
          else if (k === "WSA") { var n = parseInt(v); if (n === 0 || n === 1) root.wsAnimationOn = n >= 1 }
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
  // to reflect the real state in the UI instead of trusting hyprctl.
  Process {
    id: luaStateProc
    command: ["bash", "-lc",
      "f='" + root.luaPath + "'; [ -f \"$f\" ] || exit 0; " +
      "echo NS=$(grep -oE 'natural_scroll = (true|false)' \"$f\" | head -1 | grep -oE '(true|false)'); " +
      "echo TC=$(grep -oE 'tap_to_click = (true|false)' \"$f\" | head -1 | grep -oE '(true|false)')"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = text.split("\n")
        for (var i = 0; i < lines.length; i++) {
          var kv = lines[i].split("=")
          if (kv.length !== 2) continue
          var k = kv[0], v = kv[1]
          if (k === "NS" && (v === "true" || v === "false")) root.naturalScroll = (v === "true")
          if (k === "TC" && (v === "true" || v === "false")) root.tapToClick = (v === "true")
        }
      }
    }
  }

  // Keyboard backlight level.
  Process {
    id: kbdLedProbe
    command: ["bash", "-lc",
      "if [ -e /sys/class/leds/kbd_backlight/brightness ]; then " +
      "cur=$(cat /sys/class/leds/kbd_backlight/brightness); " +
      "max=$(cat /sys/class/leds/kbd_backlight/max_brightness); " +
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
      "lsblk -Jno PATH,FSTYPE,SIZE,LABEL,MOUNTPOINT 2>/dev/null | jq -c '[.. | objects | select(.fstype? == \"apfs\") | {path,fstype,size,label,mountpoint}] // []'"]
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

  Component.onCompleted: {
    prefsLoader.running = true
    if (!i18nLoader.running) i18nLoader.running = true
    // Bring the live Hyprland config in line with what we persisted, so a
    // shell/plugin restart doesn't leave the system on Omarchy's defaults.
    // Defer slightly: execDetached + hyprctl eval needs Quickshell/Hyprland
    // to be fully up, otherwise the call fired at construction time is lost.
    applyOnLoadTimer.restart()
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
        visible: root.currentTab === 4
        spacing: Style.space(8)

        Text {
          width: parent.width
          text: root.t(root.uiLang, "sysLanguage") + " — " + (root.currentLocale || "?")
          color: root.fg
          opacity: 0.7
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Flow {
          width: parent.width
          spacing: Style.space(6)

          Repeater {
            model: ["es_CL.UTF-8", "es_ES.UTF-8", "es_MX.UTF-8", "en_US.UTF-8", "pt_BR.UTF-8", "fr_FR.UTF-8"]

            Button {
              required property string modelData
              text: modelData.replace(".UTF-8", "")
              selected: root.currentLocale.indexOf(modelData) === 0 || root.currentLocale.indexOf(modelData.split(".")[0]) === 0
              fontSize: Style.font.caption
              foreground: root.fg
              onClicked: root.setLocale(modelData)
            }
          }
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

        Flow {
          width: parent.width
          spacing: Style.space(6)

          Repeater {
            model: ["us", "es", "latam", "gb", "de", "fr", "br"]

            Button {
              required property string modelData
              text: modelData
              selected: root.kbLayout.split(",")[0] === modelData
              fontSize: Style.font.caption
              foreground: root.fg
              onClicked: root.applyKbLayout(modelData)
            }
          }
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

        ToggleRow { labelKey: "invScroll"; checked: root.naturalScroll; action: function() { root.setNaturalScroll(!root.naturalScroll, false) } }

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

        ToggleRow { labelKey: "flatAccel"; checked: root.flatAccel; action: function() { root.flatAccel = !root.flatAccel; root.hyprSet("input", "accel_profile", root.flatAccel ? '"flat"' : '"adaptive"'); root.writeLua() } }

        ToggleRow { labelKey: "tapClick"; checked: root.tapToClick; action: function() { root.setTapToClick(!root.tapToClick) } }

        ToggleRow { labelKey: "swipe3"; checked: root.swipe3On; action: function() { root.setSwipe3(!root.swipe3On) } }

        PanelSeparator { foreground: root.fg }

        ToggleRow {
          labelKey: "inertia"
          checked: root.inertiaOn
          action: function() { root.setInertia(!root.inertiaOn) }
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

      // ---------- Animation ----------
      Column {
        width: parent.width
        visible: root.currentTab === 1
        spacing: Style.space(10)

        ToggleRow { labelKey: "sysAnims"; checked: root.animationsEnabled; action: function() { root.applyAnimations(!root.animationsEnabled) } }
        PanelSeparator { foreground: root.fg }
        ToggleRow { labelKey: "wsSlide"; checked: root.wsAnimationOn; action: function() { root.animSet(!root.wsAnimationOn) } }

        PanelSeparator { foreground: root.fg }

        ToggleRow { labelKey: "nightLight"; checked: root.nightLightOn; action: function() { root.nightLightOn = !root.nightLightOn; root.run("omarchy-toggle-nightlight") } }
      }

      // ---------- Windows ----------
      Column {
        width: parent.width
        visible: root.currentTab === 2
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

      // ---------- Devices ----------
      Column {
        width: parent.width
        visible: root.currentTab === 3
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

  // Inline component for one toggle row, used across the panel.
  component ToggleRow: Row {
    property string labelKey: ""
    property bool checked: false
    property var action: null
    width: parent.width
    spacing: 0

    ToggleSwitch {
      checked: parent.checked
      foreground: root.fg
      onToggled: if (parent.action) parent.action()
    }

    Text {
      text: root.t(root.uiLang, parent.labelKey)
      color: root.fg
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      anchors.verticalCenter: parent.verticalCenter
      leftPadding: Style.space(8)
    }
  }
}
