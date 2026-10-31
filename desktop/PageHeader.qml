import QtQuick 6.11
import qs.Commons

// Page title with one line of context underneath. Page-level actions, when a
// page genuinely needs them (Displays: Identify, Save layout), sit at the
// right; most pages have none because settings apply as they change.
Item {
  id: root

  property string title: ""
  property string subtitle: ""
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  default property alias actions: actionRow.data

  width: parent ? parent.width : implicitWidth
  implicitHeight: Math.max(textColumn.implicitHeight, actionRow.implicitHeight) + Style.space(8)

  Column {
    id: textColumn
    anchors.left: parent.left
    anchors.right: actionRow.left
    anchors.rightMargin: actionRow.implicitWidth > 0 ? Style.space(12) : 0
    anchors.top: parent.top
    spacing: Style.space(3)

    Text {
      width: parent.width
      text: root.title
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.title
      font.bold: true
      elide: Text.ElideRight
    }

    Text {
      width: parent.width
      visible: root.subtitle !== ""
      text: root.subtitle
      color: Qt.alpha(root.foreground, 0.62)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }
  }

  Row {
    id: actionRow
    anchors.right: parent.right
    anchors.top: parent.top
    spacing: Style.space(8)
  }
}
