// LoopGuard.qml — previene loops infinitos detectando llamadas repetidas
// Persiste estado en archivo para sobrevivir recargas del plugin
import QtQuick

QtObject {
  id: root
  property int maxCalls: 3
  property int windowMs: 2000
  property string lastBlocked: ""
  property int lastBlockedCount: 0
  property string stateFile: "/tmp/cp-loopguard.json"

  function _read() {
    try {
      var f = new File(stateFile)
      if (!f.exists) return {}
      return JSON.parse(f.read())
    } catch(e) { return {} }
  }

  function _write(s) {
    try { new File(stateFile).write(JSON.stringify(s)) } catch(e) {}
  }

  function check(key) {
    var now = Date.now()
    var state = _read()
    var ts = state["ts_" + key] || []
    ts = ts.filter(function(t) { return now - t < windowMs })
    if (state["blk_" + key]) return false
    if (ts.length >= maxCalls) {
      state["blk_" + key] = true
      _write(state)
      lastBlocked = key
      lastBlockedCount = ts.length
      console.error("[LOOPGUARD] BLOCKED '" + key + "' — " + ts.length + " llamadas en " + windowMs + "ms")
      return false
    }
    ts.push(now)
    state["ts_" + key] = ts
    _write(state)
    return true
  }

  function reset(key) {
    var state = _read()
    delete state["ts_" + key]
    delete state["blk_" + key]
    _write(state)
  }

  function clearAll() {
    _write({})
    lastBlocked = ""
    lastBlockedCount = 0
  }
}
