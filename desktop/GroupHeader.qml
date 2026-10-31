import QtQuick 6.11
import qs.Commons

// Section label inside a page: short uppercase title in the accent color, an
// optional note on the right, and a hairline rule. Rows below it carry their
// own separators, so a group reads as one ruled list.
Item {
  id: root

  property string title: ""
  property string note: ""
  property color foreground: Color.foreground
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  // Space above the label; the first group on a page sets this to 0.
  property int topGap: Style.space(18)

  width: parent ? parent.width : implicitWidth
  implicitHeight: topGap + Math.max(titleText.implicitHeight, noteText.implicitHeight) + Style.space(6) + rule.height

  Text {
    id: titleText
    y: root.topGap
    anchors.left: parent.left
    anchors.right: noteText.left
    anchors.rightMargin: Style.space(8)
    text: root.title
    color: root.accent
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
    font.capitalization: Font.AllUppercase
    font.letterSpacing: 0.6
    elide: Text.ElideRight
  }

  Text {
    id: noteText
    y: root.topGap
    anchors.right: parent.right
    visible: root.note !== ""
    width: visible ? Math.min(implicitWidth, root.width * 0.5) : 0
    text: root.note
    color: Qt.alpha(root.foreground, 0.62)
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    elide: Text.ElideRight
    horizontalAlignment: Text.AlignRight
  }

  Rectangle {
    id: rule
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    height: 1
    color: Qt.alpha(root.foreground, 0.12)
  }
}
