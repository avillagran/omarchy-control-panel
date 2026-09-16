pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

Item {
  id: root

  property bool quickViewEnabled: true
  property bool open: false
  property var clients: []
  property var workspaces: []
  property var prefs: ({})
  // This is presentation order only: workspace identity and its Hyprland number
  // never change. A fresh row starts in numerical order and a dragged card can
  // be inserted between its neighbors for the rest of this QuickView session.
  property var workspaceOrder: ({})
  // A hover order is deliberately separate from the committed order. Releasing
  // a workspace anywhere except a defined header discards it, so a card can
  // never be left floating between workspace slots.
  property var previewWorkspaceOrder: ({})
  property string draggedAddress: ""

  function updatePreferences(raw) {
    try {
      root.prefs = JSON.parse(raw || "{}")
      root.quickViewEnabled = root.prefs.missionControlEnabled === true
    } catch (error) {
      root.prefs = ({})
      root.quickViewEnabled = false
    }
  }

  FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/control-panel-prefs.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.updatePreferences(text())
    onFileChanged: reload()
  }

  function toggle() {
    if (!quickViewEnabled) return
    open = !open
    if (open) refresh()
  }

  function close() { open = false }

  function refresh() {
    if (!refreshProc.running) refreshProc.running = true
    Hyprland.refreshToplevels()
    Hyprland.refreshWorkspaces()
  }

  // Hyprland 0.56 serializes numbered workspaces through `name` while older
  // builds use `id`; special workspaces deliberately stay out of QuickView.
  function workspaceNumber(workspace) {
    if (!workspace) return 0
    var number = Number(workspace.id) || Number(workspace.name) || 0
    return number > 0 && Math.floor(number) === number ? number : 0
  }

  function normalizedAddress(address) {
    return String(address || "").replace(/^0x/i, "").toLowerCase()
  }

  function applySnapshot(raw) {
    try {
      var snapshot = JSON.parse(raw || "{}")
      root.clients = Array.isArray(snapshot.clients) ? snapshot.clients.filter(function(client) {
        return client && root.workspaceNumber(client.workspace) > 0 && client.mapped !== false
      }) : []
      root.workspaces = Array.isArray(snapshot.workspaces) ? snapshot.workspaces.filter(function(workspace) {
        return root.workspaceNumber(workspace) > 0 && String(workspace.monitor || "") !== ""
      }) : []
      root.workspaces.sort(function(a, b) { return root.workspaceNumber(a) - root.workspaceNumber(b) })
    } catch (error) {
      root.clients = []
      root.workspaces = []
    }
  }

  function workspaceForScreen(screenName) {
    var rows = root.workspaces.filter(function(workspace) {
      return String(workspace.monitor || "") === String(screenName || "")
    })
    rows.sort(function(a, b) { return root.workspaceNumber(a) - root.workspaceNumber(b) })
    var savedOrder = root.previewWorkspaceOrder[String(screenName)] || root.workspaceOrder[String(screenName)]
    if (!Array.isArray(savedOrder)) return rows
    var byId = ({})
    for (var i = 0; i < rows.length; i++) byId[String(workspaceNumber(rows[i]))] = rows[i]
    var ordered = []
    for (var j = 0; j < savedOrder.length; j++) {
      var item = byId[String(savedOrder[j])]
      if (item) { ordered.push(item); delete byId[String(savedOrder[j])] }
    }
    Object.keys(byId).map(Number).sort(function(a, b) { return a - b }).forEach(function(id) { ordered.push(byId[String(id)]) })
    return ordered
  }

  function insertWorkspace(screenName, sourceId, targetId) {
    sourceId = workspaceNumber({ id: sourceId })
    targetId = workspaceNumber({ id: targetId })
    if (!sourceId || !targetId || sourceId === targetId) return
    var current = workspaceForScreen(screenName).map(function(workspace) { return workspaceNumber(workspace) })
    var from = current.indexOf(sourceId)
    var to = current.indexOf(targetId)
    if (from < 0 || to < 0) return
    current.splice(from, 1)
    if (from < to) to--
    current.splice(to, 0, sourceId)
    var next = ({})
    for (var key in root.workspaceOrder) next[key] = root.workspaceOrder[key]
    next[String(screenName)] = current
    root.workspaceOrder = next
  }

  function previewWorkspaceInsert(screenName, sourceId, targetId) {
    sourceId = workspaceNumber({ id: sourceId })
    targetId = workspaceNumber({ id: targetId })
    if (!sourceId || !targetId || sourceId === targetId) return
    var current = workspaceForScreen(screenName).map(function(workspace) { return workspaceNumber(workspace) })
    var from = current.indexOf(sourceId)
    var to = current.indexOf(targetId)
    if (from < 0 || to < 0) return
    current.splice(from, 1)
    if (from < to) to--
    current.splice(to, 0, sourceId)
    var next = ({})
    for (var key in root.previewWorkspaceOrder) next[key] = root.previewWorkspaceOrder[key]
    next[String(screenName)] = current
    root.previewWorkspaceOrder = next
  }

  function commitWorkspaceInsert(screenName) {
    var preview = root.previewWorkspaceOrder[String(screenName)]
    if (!Array.isArray(preview)) return
    var next = ({})
    for (var key in root.workspaceOrder) next[key] = root.workspaceOrder[key]
    next[String(screenName)] = preview
    root.workspaceOrder = next
    root.previewWorkspaceOrder = ({})
  }

  function cancelWorkspaceInsert() { root.previewWorkspaceOrder = ({}) }

  function clientsForWorkspace(workspace) {
    var id = workspaceNumber(workspace)
    return root.clients.filter(function(client) { return root.workspaceNumber(client.workspace) === id })
  }

  function clientTitle(client) { return String(client.title || client.class || "Window") }

  function colorRoleForWorkspace(workspace) {
    var id = String(workspaceNumber(workspace))
    var visual = root.prefs.workspaceVisuals && root.prefs.workspaceVisuals[id]
    if (visual && visual.colorRole) return String(visual.colorRole)
    var monitor = String(workspace.monitor || "")
    return root.prefs.monitorColors && root.prefs.monitorColors[monitor]
      ? String(root.prefs.monitorColors[monitor]) : "accent"
  }

  function workspaceColor(workspace) {
    var color = Color[colorRoleForWorkspace(workspace)]
    return color || Color.accent
  }

  function workspaceTint(workspace, alpha) {
    var color = workspaceColor(workspace)
    return Qt.rgba(color.r, color.g, color.b, alpha)
  }

  function focusWindow(address) {
    if (!/^0x[0-9a-f]+$/i.test(String(address))) return
    Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.focus({ window = 'address:" + address + "' })"])
    close()
  }

  function moveWindow(address, workspace) {
    if (!/^0x[0-9a-f]+$/i.test(String(address))) return
    var destination = workspaceNumber(workspace)
    if (!destination) return
    Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.window.move({ workspace = " + destination + ", follow = false, window = 'address:" + address + "' })"])
    refreshTimer.restart()
  }

  Process {
    id: refreshProc
    command: ["bash", "-lc", "python3 -c 'import json, subprocess; run=lambda a: json.loads(subprocess.check_output(a)); print(json.dumps({\"clients\": run([\"hyprctl\", \"clients\", \"-j\"]), \"workspaces\": run([\"hyprctl\", \"workspaces\", \"-j\"])}))'"]
    stdout: StdioCollector { waitForEnd: true }
    onRunningChanged: if (!running) root.applySnapshot(stdout.text)
  }

  Timer { id: refreshTimer; interval: 180; repeat: false; onTriggered: root.refresh() }
  Timer { interval: 750; repeat: true; running: root.open; onTriggered: root.refresh() }

  IpcHandler {
    target: "omarchy-control-panel-quickview"
    function toggle(): string { root.toggle(); return "ok" }
    function open(): string { if (root.quickViewEnabled) { root.open = true; root.refresh() }; return "ok" }
    function close(): string { root.close(); return "ok" }
  }

  Variants {
    model: Quickshell.screens
    delegate: PanelWindow {
      required property var modelData
      screen: modelData
      visible: root.open
      color: "transparent"
      WlrLayershell.namespace: "omarchy-control-panel-quickview"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
      anchors { top: true; bottom: true; left: true; right: true }

      Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0.03, 0.04, 0.07, 0.95)

        ColumnLayout {
          anchors.fill: parent
          anchors.margins: Style.space(32)
          spacing: Style.space(16)

          RowLayout {
            Layout.fillWidth: true
            Text {
              Layout.fillWidth: true
              text: "QuickView"
              color: Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.heading
              font.bold: true
            }
            Text {
              text: "Drag windows between workspaces · drag a workspace header to insert it · ESC to close"
              color: Color.foreground
              opacity: 0.68
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
          }

          ListView {
            id: workspaces
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            orientation: ListView.Horizontal
            spacing: Style.space(16)
            model: root.workspaceForScreen(modelData.name)
            boundsBehavior: Flickable.StopAtBounds
            add: Transition { NumberAnimation { properties: "x,opacity"; duration: 220; easing.type: Easing.OutCubic } }
            displaced: Transition { NumberAnimation { properties: "x"; duration: 260; easing.type: Easing.OutCubic } }
            remove: Transition { NumberAnimation { properties: "x,opacity"; duration: 160; easing.type: Easing.OutCubic } }

            delegate: Rectangle {
              id: workspaceCard
              required property var modelData
              required property int index
              readonly property int workspaceId: root.workspaceNumber(modelData)
              property bool isWorkspaceCard: true
              property bool workspaceDragAccepted: false
              // The row always consumes the available monitor width; no card
              // can overflow off the edge simply because a monitor is narrow.
              width: Math.max(1, (workspaces.width - workspaces.spacing * Math.max(0, workspaces.count - 1)) / Math.max(1, workspaces.count))
              height: Math.max(220, Math.min(360, workspaces.height))
              radius: Style.cornerRadius
              color: root.workspaceTint(modelData, workspaceDrop.containsDrag || workspaceHeaderDrop.containsDrag ? 0.20 : 0.10)
              border.width: workspaceDrop.containsDrag || workspaceHeaderDrop.containsDrag ? 3 : 2
              border.color: root.workspaceColor(modelData)
              Drag.active: workspaceDrag.active
              Drag.source: workspaceCard
              Drag.hotSpot.x: width / 2
              Drag.hotSpot.y: height / 2
              Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
              Behavior on y { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

              ColumnLayout {
                anchors.fill: parent
                anchors.margins: Style.space(12)
                spacing: Style.space(8)

                Rectangle {
                  id: workspaceHeader
                  Layout.fillWidth: true
                  Layout.preferredHeight: Style.space(30)
                  radius: Style.cornerRadius
                  color: root.workspaceTint(modelData, workspaceDrag.active ? 0.35 : 0.16)
                  Text {
                    anchors.centerIn: parent
                    text: "Workspace " + workspaceCard.workspaceId
                    color: root.workspaceColor(modelData)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }
                  DragHandler {
                    id: workspaceDrag
                    // A workspace has fixed slots. Do not give the handler a
                    // target: otherwise an invalid release leaves the card at
                    // arbitrary x/y instead of returning to its defined slot.
                    target: null
                    onActiveChanged: {
                      if (active) workspaceCard.workspaceDragAccepted = false
                      else if (!workspaceCard.workspaceDragAccepted) root.cancelWorkspaceInsert()
                    }
                  }
                  DropArea {
                    id: workspaceHeaderDrop
                    anchors.fill: parent
                    onEntered: function(drag) {
                      var source = drag.source
                      if (source && source.isWorkspaceCard)
                        root.previewWorkspaceInsert(modelData.name, source.workspaceId, workspaceCard.workspaceId)
                    }
                    onDropped: function(drop) {
                      var source = drop.source
                      if (source && source.isWorkspaceCard) {
                        source.workspaceDragAccepted = true
                        root.commitWorkspaceInsert(modelData.name)
                      }
                    }
                  }
                }

                Item {
                  id: windowArea
                  Layout.fillWidth: true
                  Layout.fillHeight: true
                  clip: true
                  Repeater {
                    model: root.clientsForWorkspace(modelData)
                    delegate: Rectangle {
                      id: windowCard
                      required property var modelData
                      property string windowAddress: String(modelData.address || "")
                      property bool isWindowCard: true
                      property bool dropAccepted: false
                      property real homeX: x
                      property real homeY: y
                      width: Math.max(120, windowArea.width - Style.space(2))
                      height: Math.max(92, Math.min(140, windowArea.height / Math.max(1, root.clientsForWorkspace(workspaceCard.modelData).length)))
                      y: index * (height + Style.space(6))
                      radius: Style.cornerRadius
                      z: cardDrag.active ? 10 : 1
                      color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, cardDrag.active ? 0.22 : 0.12)
                      border.width: 1
                      border.color: root.workspaceTint(workspaceCard.modelData, 0.72)
                      Drag.active: cardDrag.active
                      Drag.source: windowCard
                      Drag.hotSpot.x: width / 2
                      Drag.hotSpot.y: height / 2
                      Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                      Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                      Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                      scale: cardDrag.active ? 1.05 : 1

                      Repeater {
                        model: Hyprland.toplevels
                        delegate: ScreencopyView {
                          required property var modelData
                          anchors.fill: parent
                          captureSource: root.normalizedAddress(modelData.address) === root.normalizedAddress(windowCard.windowAddress) ? modelData.wayland : null
                          live: root.open
                          visible: captureSource !== null && hasContent
                        }
                      }

                      Rectangle {
                        anchors.fill: parent
                        radius: parent.radius
                        color: Qt.rgba(0.02, 0.03, 0.05, 0.30)
                      }
                      Column {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: Style.space(8)
                        spacing: Style.space(2)
                        Text {
                          width: parent.width
                          text: root.clientTitle(modelData)
                          color: Color.foreground
                          font.family: Style.font.family
                          font.pixelSize: Style.font.caption
                          font.bold: true
                          elide: Text.ElideRight
                        }
                        Text {
                          width: parent.width
                          text: String(modelData.class || "")
                          color: Color.foreground
                          opacity: 0.68
                          font.family: Style.font.family
                          font.pixelSize: Style.font.caption
                          elide: Text.ElideRight
                        }
                      }

                      function returnToOrigin() {
                        windowCard.x = windowCard.homeX
                        windowCard.y = windowCard.homeY
                      }
                      DragHandler {
                        id: cardDrag
                        target: windowCard
                        onActiveChanged: {
                          if (active) {
                            windowCard.homeX = windowCard.x
                            windowCard.homeY = windowCard.y
                            windowCard.dropAccepted = false
                            root.draggedAddress = windowCard.windowAddress
                          } else {
                            root.draggedAddress = ""
                            if (!windowCard.dropAccepted) windowCard.returnToOrigin()
                          }
                        }
                      }
                      TapHandler { onTapped: if (!cardDrag.active) root.focusWindow(windowCard.windowAddress) }
                    }
                  }
                }
              }

              DropArea {
                id: workspaceDrop
                anchors.fill: parent
                onDropped: function(drop) {
                  var source = drop.source
                  if (source && source.isWindowCard) {
                    source.dropAccepted = true
                    root.moveWindow(source.windowAddress, workspaceCard.modelData)
                  }
                }
              }
            }
          }
        }

        TapHandler { acceptedButtons: Qt.RightButton; onTapped: root.close() }
      }
      Shortcut { sequence: "Escape"; onActivated: root.close() }
    }
  }
}
