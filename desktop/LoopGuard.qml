// LoopGuard — detects and breaks runaway call loops
// Drop into any QML file: property var loopGuard: LoopGuard { }
// Wrap critical functions: function criticalFn() { if (loopGuard.check("criticalFn")) { ... } }
QtObject {
  id: root

  // Call counts per key, reset every window
  property var _counts: ({})
  property var _timestamps: ({})
  property var _blocked: ({})

  // Threshold: max calls within windowMs before blocking
  property int maxCalls: 3
  property int windowMs: 2000

  // Last blocked function for UI display
  property string lastBlocked: ""
  property int lastBlockedCount: 0

  function check(key) {
    var now = Date.now()
    var ts = _timestamps[key] || []
    // Remove old entries outside the window
    ts = ts.filter(function(t) { return now - t < root.windowMs })
    // If already blocked, keep blocking
    if (_blocked[key]) {
      return false
    }
    // Check threshold
    if (ts.length >= root.maxCalls) {
      _blocked[key] = true
      lastBlocked = key
      lastBlockedCount = ts.length
      console.error("[LOOPGUARD] BLOCKED '" + key + "' called " + ts.length + " times in " + root.windowMs + "ms")
      // Show toast if available
      if (typeof root.showToast === "function") {
        root.showToast("Loop detectado en: " + key + " (" + ts.length + " llamadas) — detenido")
      }
      return false
    }
    // Record this call
    ts.push(now)
    _timestamps[key] = ts
    return true
  }

  // Call when operation completes successfully — resets the counter
  function reset(key) {
    delete _counts[key]
    delete _timestamps[key]
    delete _blocked[key]
  }

  // Clear all (e.g. on user action)
  function clearAll() {
    _counts = {}
    _timestamps = {}
    _blocked = {}
    lastBlocked = ""
    lastBlockedCount = 0
  }

  // Get diagnostic info
  function diagnose() {
    var info = []
    for (var k in _timestamps) {
      var ts = _timestamps[k]
      var now = Date.now()
      ts = ts.filter(function(t) { return now - t < root.windowMs * 2 })
      if (ts.length > 0) {
        info.push(k + ": " + ts.length + " calls" + (_blocked ? " [BLOCKED]" : ""))
      }
    }
    return info.join(" | ")
  }
}
