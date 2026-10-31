import QtQuick 6.11
import QtQuick.Controls
import qs.Commons
import qs.Ui

// Labeled setting row: title (and an optional description) on the left, the
// native Omarchy switch on the right. The whole row is the control: a click,
// Space or Enter flips it. Keyboard focus draws the cursor ring outside the
// row, like ToggleSwitch's own cursor ring, so a bordered switch never fades.
//
// `checked` is AbstractButton's property. The row is not checkable: callers
// bind `checked` to real state and flip that state in `onClicked`.
AbstractButton {
  id: root

  property string label: ""
  property string description: ""
  property color foreground: Color.foreground
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  property real titleSize: Style.font.body
  // Hairline above the row; consecutive rows form a ruled list.
  property bool separator: true

  width: parent ? parent.width : implicitWidth
  implicitWidth: labelColumn.implicitWidth + track.width + Style.space(12)
  implicitHeight: Math.max(track.height, labelColumn.implicitHeight) + topPadding + bottomPadding
  topPadding: Style.space(9)
  bottomPadding: Style.space(9)
  leftPadding: 0
  rightPadding: 0
  hoverEnabled: true
  focusPolicy: Qt.StrongFocus
  opacity: enabled ? 1 : 0.45

  Accessible.role: Accessible.CheckBox
  Accessible.name: label
  Accessible.checked: checked

  Keys.onReturnPressed: event => { root.clicked(); event.accepted = true }
  Keys.onEnterPressed: event => { root.clicked(); event.accepted = true }

  HoverHandler { cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }

  contentItem: Item {
    implicitHeight: Math.max(track.height, labelColumn.implicitHeight)

    Column {
      id: labelColumn
      anchors.left: parent.left
      anchors.right: track.left
      anchors.rightMargin: Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)

      Text {
        width: parent.width
        text: root.label
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: root.titleSize
        wrapMode: Text.WordWrap
        maximumLineCount: 2
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        visible: root.description !== ""
        text: root.description
        color: Qt.alpha(root.foreground, 0.62)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }
    }

    ToggleSwitch {
      id: track
      checked: root.checked
      interactive: false
      hasCursor: root.hovered
      foreground: root.foreground
      accent: root.accent
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
    }
  }

  background: Item {
    Rectangle {
      visible: root.separator
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      height: 1
      color: Qt.alpha(root.foreground, 0.10)
    }

    Rectangle {
      visible: root.visualFocus
      anchors.fill: parent
      anchors.leftMargin: -Style.space(8)
      anchors.rightMargin: -Style.space(8)
      anchors.topMargin: Style.space(2)
      anchors.bottomMargin: Style.space(2)
      color: "transparent"
      radius: Style.cornerRadius
      border.width: 1
      border.color: root.accent
    }
  }
}
