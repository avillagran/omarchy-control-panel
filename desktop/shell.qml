pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons

ShellRoot {
  AppTheme { id: theme }

  FloatingWindow {
    id: win
    // Stable compositor/launcher identifier, not a translatable UI label.
    title: "Control Panel"
    visible: true
    color: theme.app

    readonly property int pad: theme.padding
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
      var chromeH = header.implicitHeight + sectionTitle.implicitHeight + win.pad * 4 + theme.gap * 3
      if (win.narrow) chromeH += sidebar.implicitHeight + theme.gap
      if (footer.visible) chromeH += footer.implicitHeight + theme.gap
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

    // Shared native control semantics with an explicit Omareel surface.
    component ActionButton: AbstractButton {
      id: action
      property bool primary: false
      implicitWidth: Math.max(36, actionLabel.implicitWidth + 24)
      implicitHeight: Math.max(theme.controlHeight, actionLabel.implicitHeight + 16)
      padding: 8
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
        color: action.primary ? theme.accent : (action.hovered || action.down ? theme.panelAlt : theme.panel)
        border.width: action.activeFocus ? 2 : 1
        border.color: action.activeFocus ? theme.accent : theme.border
      }
    }

    Rectangle {
      anchors.fill: parent
      color: theme.app
      radius: theme.radius
      border.color: theme.border
      border.width: 1
      clip: true

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: win.pad
        spacing: theme.gap

        Item {
          id: header
          Layout.fillWidth: true
          implicitHeight: Math.max(headerContent.implicitHeight, theme.controlHeight)

          MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.SizeAllCursor
            onPressed: win.startSystemMove()
          }

          RowLayout {
            id: headerContent
            anchors.fill: parent
            spacing: theme.gap
            Text {
              Layout.fillWidth: true
              Layout.minimumWidth: 0
              text: core.t(core.uiLang, "controlPanelTitle")
              color: theme.text
              font.family: theme.fontUi
              font.pixelSize: theme.body
              font.bold: true
              elide: Text.ElideRight
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
          columnSpacing: theme.gap
          rowSpacing: theme.gap

          Rectangle {
            id: sidebar
            Layout.fillWidth: win.narrow
            Layout.preferredWidth: win.narrow ? -1 : 194
            Layout.minimumWidth: win.narrow ? 0 : 194
            Layout.maximumWidth: win.narrow ? Infinity : 194
            Layout.fillHeight: !win.narrow
            Layout.minimumHeight: 0
            implicitHeight: theme.controlHeight + 16
            Layout.preferredHeight: win.narrow ? implicitHeight : -1
            radius: theme.radius
            color: theme.panelDeep
            border.color: theme.border

            ColumnLayout {
              anchors.fill: parent
              anchors.margins: 8
              spacing: theme.gap
              ColumnLayout {
                visible: !win.narrow
                Layout.fillWidth: true
                spacing: 4
                Text {
                  Layout.fillWidth: true
                  text: core.t(core.uiLang, "currentProfile")
                  color: theme.textMuted
                  font.family: theme.fontUi
                  font.pixelSize: theme.caption
                  wrapMode: Text.Wrap
                }
                Text {
                  Layout.fillWidth: true
                  text: {
                    for (var i = 0; i < core.profiles.length; i++) {
                      var profile = core.profiles[i]
                      if (profile.id === core.activeProfileId)
                        return profile.builtin ? core.t(core.uiLang, profile.name) : profile.name
                    }
                    return core.t(core.uiLang, "noActiveProfile")
                  }
                  color: theme.text
                  font.family: theme.fontUi
                  font.pixelSize: theme.body
                  elide: Text.ElideRight
                }
                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: theme.border }
              }

              ListView {
                id: navigation
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 0
                clip: true
                model: win.navigationTabs
                currentIndex: win.navigationIndexForPage(core.currentTab)
                orientation: win.narrow ? ListView.Horizontal : ListView.Vertical
                spacing: 4
                boundsBehavior: Flickable.StopAtBounds
                keyNavigationEnabled: false
                ScrollBar.vertical: ScrollBar { policy: win.narrow ? ScrollBar.AlwaysOff : ScrollBar.AsNeeded }
                ScrollBar.horizontal: ScrollBar { policy: win.narrow ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }
                onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
                delegate: AbstractButton {
                  id: navButton
                  required property var modelData
                  required property int index
                  width: win.narrow ? Math.max(112, navLabel.implicitWidth + 28) : navigation.width
                  height: Math.max(theme.controlHeight, navLabel.implicitHeight + 16)
                  padding: 8
                  leftPadding: 12
                  rightPadding: 12
                  hoverEnabled: true
                  focusPolicy: Qt.StrongFocus
                  Accessible.role: Accessible.PageTab
                  Accessible.name: modelData.title
                  Accessible.selected: core.currentTab === modelData.page
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
                    color: navButton.modelData.devOnly ? theme.urgent
                      : (core.currentTab === navButton.modelData.page ? theme.accent : theme.text)
                    font.family: theme.fontUi
                    font.pixelSize: theme.body
                    font.bold: core.currentTab === navButton.modelData.page
                    verticalAlignment: Text.AlignVCenter
                    wrapMode: win.narrow ? Text.NoWrap : Text.Wrap
                  }
                  background: Rectangle {
                    radius: theme.radius
                    color: core.currentTab === navButton.modelData.page
                      ? (navButton.modelData.devOnly ? Qt.alpha(theme.urgent, 0.14) : theme.accentSoft)
                      : (navButton.hovered ? theme.panelAlt : theme.transparent)
                    border.width: navButton.activeFocus ? 2 : 1
                    border.color: navButton.modelData.devOnly ? theme.urgent
                      : (navButton.activeFocus ? theme.accent : (core.currentTab === navButton.modelData.page ? theme.border : theme.transparent))
                  }
                }
              }
            }
          }

          ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumWidth: 0
            Layout.minimumHeight: 0
            spacing: theme.gap
            Text {
              id: sectionTitle
              Layout.fillWidth: true
              Layout.minimumWidth: 0
              text: core.currentTab >= 0 && core.currentTab < core.tabs.length ? core.tabs[core.currentTab].title : ""
              color: theme.text
              font.family: theme.fontUi
              font.pixelSize: theme.body
              font.bold: true
              elide: Text.ElideRight
            }
            Rectangle {
              Layout.fillWidth: true
              Layout.fillHeight: true
              Layout.minimumWidth: 0
              Layout.minimumHeight: 0
              radius: theme.radius
              color: theme.panel
              border.color: theme.border
              clip: true
              Flickable {
                id: contentFlick
                anchors.fill: parent
                anchors.margins: theme.padding
                contentWidth: width
                contentHeight: core.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                // Match native kinetic-scroll feel: small content movement per
                // wheel tick and a short, springy flick deceleration.
                maximumFlickVelocity: 1400
                flickDeceleration: 2600
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                Core {
                  id: core
                  anchors.left: parent.left
                  anchors.right: parent.right
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
        }

        // Always outside the settings scroller: display rollback stays reachable.
        Rectangle {
          id: footer
          Layout.fillWidth: true
          visible: core.displayAwaitingConfirmation
          implicitHeight: footerContent.implicitHeight + 16
          radius: theme.radius
          color: theme.accentSoft
          border.color: theme.border
          onVisibleChanged: {
            win.scheduleResize()
            if (visible) Quickshell.execDetached(["hyprctl", "eval", "hl.dispatch(hl.dsp.window.center())"])
          }
          ColumnLayout {
            id: footerContent
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 8
            spacing: theme.gap
            RowLayout {
              Layout.fillWidth: true
              Text {
                Layout.fillWidth: true
                text: core.t(core.uiLang, "displayConfirmPrompt") + " · " + core.displaySecondsRemaining
                color: theme.text
                font.family: theme.fontUi
                font.pixelSize: theme.body
                wrapMode: Text.Wrap
              }
            }
            RowLayout {
              Layout.fillWidth: true
              spacing: theme.gap
              ActionButton {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                primary: true
                text: core.t(core.uiLang, "keep")
                onClicked: core.displayKeep()
              }
              ActionButton {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
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
