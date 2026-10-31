pragma ComponentBehavior: Bound
import QtQuick 6.11
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons

ShellRoot {
  AppTheme { id: theme }
  MissionControl { id: missionControl }
  Shortcut {
    sequence: "SUPER+SHIFT+UP"
    onActivated: missionControl.toggle()
  }

  FloatingWindow {
    id: win
    // Stable compositor/launcher identifier, not a translatable UI label.
    title: "Control Panel"
    visible: true
    color: theme.app

    readonly property bool narrow: width < Math.max(720, theme.body * 34)
    property real fontScale: Style.fontScale
    property var navigationTabs: core.tabs.filter(function(tab) {
      return !tab.devOnly || core.devMode
    })
    implicitWidth: theme.windowWidth(win.screen ? win.screen.width : 1640)
    implicitHeight: theme.windowHeight(win.screen ? win.screen.height : 900, 620)

    Behavior on implicitWidth { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
    Behavior on implicitHeight { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
    Component.onCompleted: win.scheduleResize()
    onFontScaleChanged: scheduleResize()

    function scheduleResize() { resizeTimer.restart() }
    Timer { id: resizeTimer; interval: 60; onTriggered: win.doResize() }
    // Retain the standalone window's resolution/font-change sizing behavior.
    Timer { interval: 250; repeat: true; running: win.visible; onTriggered: win.doResize() }

    function doResize() {
      if (!core) return
      var targetW = theme.windowWidth(win.screen ? win.screen.width : 1640)
      var chromeH = header.implicitHeight + 3 + win.contentPadY * 2
      if (win.narrow) chromeH += sidebar.implicitHeight
      if (footer.visible) chromeH += footer.implicitHeight
      var targetH = theme.windowHeight(win.screen ? win.screen.height : 900, core.implicitHeight + chromeH)
      if (Math.round(win.implicitWidth) !== targetW) win.implicitWidth = targetW
      if (Math.round(win.implicitHeight) !== targetH) win.implicitHeight = targetH
    }

    function selectTab(index) {
      if (index < 0 || index >= navigationTabs.length) return
      core.currentTab = navigationTabs[index].page
      navigation.currentIndex = index
      navigation.positionViewAtIndex(index, ListView.Contain)
      if (navigation.currentItem) navigation.currentItem.forceActiveFocus(Qt.TabFocusReason)
    }

    function navigationIndexForPage(page) {
      for (var i = 0; i < navigationTabs.length; i++)
        if (navigationTabs[i].page === page) return i
      return 0
    }

    Shortcut { sequence: "Escape"; onActivated: win.visible = false }
    Shortcut { sequence: "Ctrl+Tab"; onActivated: win.selectTab((win.navigationIndexForPage(core.currentTab) + 1) % win.navigationTabs.length) }
    Shortcut { sequence: "Ctrl+Shift+Tab"; onActivated: win.selectTab((win.navigationIndexForPage(core.currentTab) + win.navigationTabs.length - 1) % win.navigationTabs.length) }

    // Header icon button: square, bordered, follows the theme radius.
    component ActionButton: AbstractButton {
      id: action
      property bool primary: false
      implicitWidth: Math.max(theme.controlHeight * 0.66, actionLabel.implicitWidth + 16)
      implicitHeight: Math.max(theme.controlHeight * 0.66, actionLabel.implicitHeight + 8)
      padding: 4
      hoverEnabled: true
      focusPolicy: Qt.StrongFocus
      Accessible.name: text
      contentItem: Text {
        id: actionLabel
        text: action.text
        color: action.primary ? theme.app : theme.text
        font.family: theme.fontUi
        font.pixelSize: theme.body
        font.bold: action.primary
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        wrapMode: Text.Wrap
      }
      background: Rectangle {
        radius: theme.radius
        color: action.primary ? theme.accent : (action.hovered || action.down ? theme.hoverFill : theme.transparent)
        border.width: 1
        border.color: action.visualFocus ? theme.accent : theme.border
      }
    }

    readonly property int contentPadX: Math.round(theme.padding * 2.1)
    readonly property int contentPadY: Math.round(theme.padding * 1.8)
    readonly property string activeProfileName: {
      for (var i = 0; i < core.profiles.length; i++) {
        var profile = core.profiles[i]
        if (profile.id === core.activeProfileId)
          return profile.builtin ? core.t(core.uiLang, profile.name) : profile.name
      }
      return core.t(core.uiLang, "noActiveProfile")
    }

    // Pointer in window coordinates, for Omi's eyes in the header.
    property real pointerX: 0
    property real pointerY: 0
    property bool pointerInside: false

    Rectangle {
      anchors.fill: parent
      color: theme.app
      radius: theme.radius

      HoverHandler {
        onPointChanged: {
          var p = parent.mapToItem(null, point.position.x, point.position.y)
          win.pointerX = p.x
          win.pointerY = p.y
        }
        onHoveredChanged: win.pointerInside = hovered
      }
      border.color: theme.border
      border.width: 1
      clip: true

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: 1
        spacing: 0

        Item {
          id: header
          Layout.fillWidth: true
          implicitHeight: Math.max(headerContent.implicitHeight + theme.padding, theme.controlHeight + 12)

          MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.SizeAllCursor
            onPressed: win.startSystemMove()
          }

          RowLayout {
            id: headerContent
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: theme.padding + 4
            anchors.rightMargin: theme.padding + 4
            spacing: theme.gap

            // Brand mark: Omi from the bundled Task Manager (blinks, eyes follow
            // the pointer anywhere in the window). The gear stays as the
            // fallback while the Task Manager is not installed.
            Item {
              implicitWidth: Math.max(22, theme.body + 10)
              implicitHeight: implicitWidth

              Loader {
                id: omiLoader
                anchors.fill: parent
                source: core.taskManagerDir + "/OmiFace.qml"
                onLoaded: {
                  item.tint = Qt.binding(function() { return theme.accent })
                  item.cursorX = Qt.binding(function() { return win.pointerX })
                  item.cursorY = Qt.binding(function() { return win.pointerY })
                  item.cursorValid = Qt.binding(function() { return win.pointerInside })
                }
              }

              Rectangle {
                anchors.fill: parent
                visible: omiLoader.status !== Loader.Ready
                radius: theme.radius
                color: theme.transparent
                border.color: theme.accent
                border.width: 1
                Text {
                  anchors.centerIn: parent
                  text: "󰒓"
                  color: theme.accent
                  font.family: theme.fontUi
                  font.pixelSize: theme.body + 2
                }
              }
            }

            Text {
              Layout.fillWidth: true
              Layout.minimumWidth: 0
              textFormat: Text.StyledText
              text: "<b>Omarchy</b> <font color=\"" + theme.textMuted + "\">/</font> <b>"
                + core.t(core.uiLang, "controlPanelTitle") + "</b>"
              color: theme.text
              font.family: theme.fontUi
              font.pixelSize: theme.body
              elide: Text.ElideRight
            }

            Text {
              visible: !win.narrow
              textFormat: Text.StyledText
              text: core.t(core.uiLang, "profileLabel") + " <font color=\"" + theme.text + "\">"
                + win.activeProfileName + "</font>"
              color: theme.textMuted
              font.family: theme.fontUi
              font.pixelSize: theme.caption
            }

            ActionButton {
              id: closeButton
              text: "×"
              Accessible.name: core.t(core.uiLang, "close")
              ToolTip.visible: hovered
              ToolTip.text: core.t(core.uiLang, "close")
              onClicked: win.visible = false
            }
          }
        }

        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: theme.border }

        GridLayout {
          Layout.fillWidth: true
          Layout.fillHeight: true
          Layout.minimumHeight: 0
          columns: win.narrow ? 1 : 2
          columnSpacing: 0
          rowSpacing: 0

          Rectangle {
            id: sidebar
            Layout.fillWidth: win.narrow
            Layout.preferredWidth: win.narrow ? -1 : 188
            Layout.minimumWidth: win.narrow ? 0 : 188
            Layout.maximumWidth: win.narrow ? Infinity : 188
            Layout.fillHeight: !win.narrow
            Layout.minimumHeight: 0
            implicitHeight: theme.controlHeight + 14
            Layout.preferredHeight: win.narrow ? implicitHeight : -1
            color: theme.panelDeep

            // Hairline toward the content: right edge when vertical, bottom
            // edge when the navigation folds into a top strip.
            Rectangle {
              visible: !win.narrow
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              width: 1
              color: theme.border
            }
            Rectangle {
              visible: win.narrow
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              height: 1
              color: theme.border
            }

            ListView {
              id: navigation
              anchors.fill: parent
              anchors.leftMargin: 7
              anchors.rightMargin: 8
              anchors.topMargin: win.narrow ? 7 : 12
              anchors.bottomMargin: 7
              clip: true
              model: win.navigationTabs
              currentIndex: win.navigationIndexForPage(core.currentTab)
              orientation: win.narrow ? ListView.Horizontal : ListView.Vertical
              spacing: 2
              boundsBehavior: Flickable.StopAtBounds
              keyNavigationEnabled: false
              ScrollBar.vertical: ScrollBar { policy: win.narrow ? ScrollBar.AlwaysOff : ScrollBar.AsNeeded }
              ScrollBar.horizontal: ScrollBar { policy: win.narrow ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }
              onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
              delegate: AbstractButton {
                id: navButton
                required property var modelData
                required property int index
                readonly property bool current: core.currentTab === modelData.page
                width: win.narrow ? Math.max(96, navLabel.implicitWidth + leftPadding + rightPadding) : navigation.width
                height: Math.max(theme.controlHeight - 4, navLabel.implicitHeight + 16)
                padding: 8
                leftPadding: 12
                rightPadding: modelData.devOnly ? 12 + devBadge.implicitWidth + 6 : 10
                hoverEnabled: true
                focusPolicy: Qt.StrongFocus
                Accessible.role: Accessible.PageTab
                Accessible.name: modelData.title
                Accessible.selected: current
                onClicked: win.selectTab(index)
                onActiveFocusChanged: if (activeFocus) navigation.positionViewAtIndex(index, ListView.Contain)
                Keys.onUpPressed: event => { win.selectTab(Math.max(0, index - 1)); event.accepted = true }
                Keys.onDownPressed: event => { win.selectTab(Math.min(win.navigationTabs.length - 1, index + 1)); event.accepted = true }
                Keys.onLeftPressed: event => { win.selectTab(Math.max(0, index - 1)); event.accepted = true }
                Keys.onRightPressed: event => { win.selectTab(Math.min(win.navigationTabs.length - 1, index + 1)); event.accepted = true }
                Keys.onPressed: event => {
                  if (event.key === Qt.Key_Home) { win.selectTab(0); event.accepted = true }
                  else if (event.key === Qt.Key_End) { win.selectTab(win.navigationTabs.length - 1); event.accepted = true }
                }
                contentItem: Text {
                  id: navLabel
                  text: navButton.modelData.title
                  color: navButton.current || navButton.hovered ? theme.text : theme.textMuted
                  font.family: theme.fontUi
                  font.pixelSize: theme.body
                  font.bold: navButton.current
                  verticalAlignment: Text.AlignVCenter
                  elide: Text.ElideRight
                  wrapMode: Text.NoWrap
                }
                background: Rectangle {
                  radius: theme.radius
                  color: navButton.current ? theme.selectedFill
                    : (navButton.hovered ? theme.hoverFill : theme.transparent)
                  border.width: navButton.visualFocus ? 1 : 0
                  border.color: theme.accent

                  // Current-page marker: an accent edge, left when vertical,
                  // bottom when the navigation is a horizontal strip.
                  Rectangle {
                    visible: navButton.current
                    color: theme.accent
                    x: 0
                    y: win.narrow ? parent.height - height : 0
                    width: win.narrow ? parent.width : 2
                    height: win.narrow ? 2 : parent.height
                  }

                  // Development features carry a quiet marker instead of
                  // the urgent color: they are optional, not alarming.
                  Text {
                    id: devBadge
                    visible: navButton.modelData.devOnly
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: "DEV"
                    color: theme.textMuted
                    opacity: 0.75
                    font.family: theme.fontUi
                    font.pixelSize: Math.max(8, theme.caption - 2)
                    font.letterSpacing: 0.5
                  }
                }
              }
            }
          }

          Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumWidth: 0
            Layout.minimumHeight: 0

            Flickable {
              id: contentFlick
              anchors.fill: parent
              contentWidth: width
              contentHeight: core.implicitHeight + win.contentPadY * 2
              clip: true
              boundsBehavior: Flickable.StopAtBounds
              // Match native kinetic-scroll feel: small content movement per
              // wheel tick and a short, springy flick deceleration.
              maximumFlickVelocity: 1400
              flickDeceleration: 2600
              ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

              // Keep the keyboard cursor in view as it moves between rows.
              readonly property Item focusedItem: Window.activeFocusItem
              onFocusedItemChanged: ensureVisible(focusedItem)
              function ensureVisible(item) {
                var probe = item
                while (probe && probe !== core) probe = probe.parent
                if (!probe || !item.visible) return
                var top = item.mapToItem(contentFlick.contentItem, 0, 0).y - theme.padding
                var bottom = top + item.height + theme.padding * 2
                if (top < contentY) contentY = Math.max(0, top)
                else if (bottom > contentY + height) contentY = Math.min(Math.max(0, contentHeight - height), bottom - height)
              }

              Core {
                id: core
                x: win.contentPadX
                y: win.contentPadY
                width: contentFlick.width - win.contentPadX * 2
                externalNavigation: true
                onCloseRequested: win.visible = false
                onImplicitHeightChanged: win.scheduleResize()
                onImplicitWidthChanged: win.scheduleResize()
                onCurrentTabChanged: contentFlick.contentY = 0
                Component.onCompleted: win.scheduleResize()
              }
            }
          }
        }

        // Always outside the settings scroller: display rollback stays reachable.
        Rectangle {
          id: footer
          Layout.fillWidth: true
          visible: core.displayAwaitingConfirmation
          implicitHeight: footerContent.implicitHeight + theme.padding * 2
          color: theme.selectedFill
          onVisibleChanged: {
            win.scheduleResize()
            if (visible) Quickshell.execDetached(["hyprctl", "eval", "hl.dispatch(hl.dsp.window.center())"])
          }
          Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; height: 1; color: theme.border }
          ColumnLayout {
            id: footerContent
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: theme.padding
            anchors.leftMargin: win.contentPadX
            anchors.rightMargin: win.contentPadX
            spacing: theme.gap
            RowLayout {
              Layout.fillWidth: true
              spacing: theme.gap
              Text {
                Layout.fillWidth: true
                text: core.t(core.uiLang, "displayConfirmPrompt") + " · " + core.displaySecondsRemaining
                color: theme.text
                font.family: theme.fontUi
                font.pixelSize: theme.body
                wrapMode: Text.Wrap
              }
              ActionButton {
                primary: true
                text: core.t(core.uiLang, "keep")
                onClicked: core.displayKeep()
              }
              ActionButton {
                text: core.t(core.uiLang, "revert")
                onClicked: core.displayRevert()
              }
            }
            Text {
              Layout.fillWidth: true
              text: core.t(core.uiLang, "displayRevertHint")
              color: theme.textMuted
              font.family: theme.fontUi
              font.pixelSize: theme.caption
              wrapMode: Text.Wrap
            }
          }
        }
      }
    }
  }
}
