import QtQuick
import qs.Commons
import qs.Ui

// Minimalist labeled toggle row: title on the left, a switch on the right,
// no surrounding border box (unlike the shell's `Toggle`, which wraps every
// row in a BorderSurface). Clicking anywhere on the row flips the switch.
Item {
  id: root

  property string label: ""
  property bool checked: false
  property color foreground: Color.foreground
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  property real titleSize: Style.font.subtitle

  signal clicked()

  width: parent.width
  implicitHeight: Math.max(track.implicitHeight, labelText.implicitHeight)

  Text {
    id: labelText
    text: root.label
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: root.titleSize
    elide: Text.ElideRight
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    width: parent.width - track.width - Style.spacing.rowPaddingX
  }

  ToggleSwitch {
    id: track
    checked: root.checked
    interactive: false
    foreground: root.foreground
    accent: root.accent
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }
}
