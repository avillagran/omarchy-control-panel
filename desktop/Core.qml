import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "DisplayModel.js" as DisplayModel

Item {
  id: root
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

  // LoopGuard
  property var loopGuard: QtObject {
    id: _lg
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

  property string statusMessage: ""
  readonly property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
  readonly property color fg: barForeground

  readonly property string uiLang: {
    var p = (currentLocale || "es_ES").toLowerCase().split("_")[0]
    var supported = ["en","es","pt","fr","de","it","nl","pl","ru","ja","ko","zh","ar","tr","sv","da","no","fi","cs"]
    return supported.indexOf(p) >= 0 ? p : "en"
  }
  function t(lang, key) {
    var table = i18nData[lang] || i18nData.en
    return table && table[key] !== undefined ? table[key] : (i18nData.en && i18nData.en[key] !== undefined ? i18nData.en[key] : key)
  }
  property var i18nData: ({})
  property int currentTab: 2

  // Display properties
  property var displays: []
  property bool displayAwaitingConfirmation: false
  property int displaySecondsRemaining: 0
  property var displaySelected: null
  property bool displayDragging: false
  property bool identifyAllDisplays: false
  property bool displayApplying: false
  property bool displayApplyPending: false

  // Profile properties
  property var profiles: []
  property string activeProfileId: ""

  // Functions
  function open() { opened = true }
  function close() { closeRequested() }
  function displayKeep() { displayAwaitingConfirmation = false; displaySecondsRemaining = 0 }
  function displayRevert() { displayAwaitingConfirmation = false; displaySecondsRemaining = 0 }
  function applyProfile(id) { console.warn("[CP] applyProfile " + id) }
  function hyprReload() { console.warn("[CP] hyprReload - no-op") }
  function reapplySaved() { console.warn("[CP] reapplySaved") }
  function refresh() { console.warn("[CP] refresh") }
  function applyProfileSettings(id) { console.warn("[CP] applyProfileSettings " + id) }
}
