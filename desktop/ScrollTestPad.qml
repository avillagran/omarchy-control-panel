import QtQuick 6.11
import qs.Commons

// A strip of ruled lines that moves with real wheel and touchpad input. Input
// reaches it after Hyprland (and the scroll patch, when installed) has applied
// natural direction, scroll factor and coasting, so what moves here is what
// every application receives. It reads input only and changes nothing.
Rectangle {
  id: root

  property string label: ""
  property color foreground: Color.foreground
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  property real offset: 0
  readonly property int lineGap: Math.max(16, Style.space(24))
  readonly property int lineCount: Math.ceil(height / lineGap) + 1

  width: parent ? parent.width : implicitWidth
  implicitHeight: Style.space(104)
  radius: Style.cornerRadius
  color: Qt.alpha(root.foreground, 0.035)
  border.width: 1
  border.color: Qt.alpha(root.foreground, 0.12)
  clip: true

  Repeater {
    model: root.lineCount

    Rectangle {
      required property int index
      readonly property real span: root.lineCount * root.lineGap
      x: 1
      width: root.width - 2
      height: 1
      y: ((index * root.lineGap + root.offset) % span + span) % span
      color: Qt.alpha(root.foreground, 0.12)
    }
  }

  Text {
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.margins: Style.space(8)
    text: root.label
    color: Qt.alpha(root.foreground, 0.62)
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }

  Text {
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.margins: Style.space(8)
    text: Math.round(root.offset) + " px"
    color: root.accent
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.NoButton
    cursorShape: Qt.SizeVerCursor
    onWheel: function(wheel) {
      root.offset += wheel.pixelDelta.y !== 0
        ? wheel.pixelDelta.y
        : wheel.angleDelta.y / 120 * root.lineGap
      wheel.accepted = true
    }
  }
}
