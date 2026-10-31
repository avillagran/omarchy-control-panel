import QtQuick 6.11
import QtQuick.Controls
import qs.Commons

// Labeled numeric setting: label (with an optional qualifier note) and an
// editable value field with −/+ steppers on the first line, the slider below.
//
// `value` aliases the inner slider, so a caller's binding (`value: root.x`)
// survives user interaction: the slider, the steppers and the field all move
// it through Slider's own C++ setters, which never replace a QML binding.
// Handlers read the new value as `value`, exactly like a plain Slider:
//   onMoved: root.applySomething(value)
//
// Keyboard: the row's cursor stop is the slider. Left/Right step it, Enter
// jumps into the field to type a value, Enter/Escape there returns.
FocusScope {
  id: root

  property string label: ""
  property string note: ""
  property string description: ""
  property alias value: slider.value
  property alias from: slider.from
  property alias to: slider.to
  property alias stepSize: slider.stepSize
  property int decimals: 0
  property string suffix: ""
  property bool separator: true
  property color foreground: Color.foreground
  property color accent: Color.accent
  property string fontFamily: Style.font.family

  signal moved()

  width: parent ? parent.width : implicitWidth
  implicitWidth: Style.space(260)
  implicitHeight: body.implicitHeight + Style.space(18)
  opacity: enabled ? 1 : 0.45

  function format(v) {
    return Number(v).toFixed(root.decimals)
  }

  function syncField() {
    if (!field.activeFocus) field.text = root.format(slider.value)
  }

  // Step the slider toward `target` through increase()/decrease(), so the
  // caller's binding on `value` is preserved, then report one move.
  function moveTo(target) {
    var step = slider.stepSize > 0 ? slider.stepSize : (slider.to - slider.from) / 100
    var clamped = Math.max(Math.min(slider.from, slider.to), Math.min(Math.max(slider.from, slider.to), target))
    var steps = Math.round((clamped - slider.value) / step)
    if (steps === 0) { root.syncField(); return }
    for (var i = 0; i < Math.abs(steps); i++) {
      if (steps > 0) slider.increase()
      else slider.decrease()
    }
    root.moved()
  }

  function commitField() {
    var parsed = parseFloat(String(field.text).replace(",", ".").replace(/[^0-9.+-]/g, ""))
    if (isFinite(parsed)) root.moveTo(parsed)
    field.text = root.format(slider.value)
  }

  Rectangle {
    visible: root.separator
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    height: 1
    color: Qt.alpha(root.foreground, 0.10)
  }

  // Cursor ring: only for keyboard focus, never for a mouse click.
  Rectangle {
    visible: slider.visualFocus || field.activeFocus
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

  Column {
    id: body
    y: Style.space(9)
    width: parent.width
    spacing: Style.space(6)

    Item {
      width: parent.width
      height: Math.max(labelColumn.implicitHeight, valueBox.height)

      Column {
        id: labelColumn
        anchors.left: parent.left
        anchors.right: valueBox.left
        anchors.rightMargin: Style.space(12)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)

        Row {
          width: parent.width
          spacing: Style.space(6)

          Text {
            id: labelText
            width: Math.min(implicitWidth, parent.width - (noteText.visible ? noteText.implicitWidth + parent.spacing : 0))
            text: root.label
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }

          Text {
            id: noteText
            visible: root.note !== ""
            text: "· " + root.note
            color: Qt.alpha(root.foreground, 0.62)
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }
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

      Rectangle {
        id: valueBox
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: Math.max(Style.space(24), field.implicitHeight + Style.space(6))
        width: fieldRow.implicitWidth
        radius: Style.cornerRadius
        color: "transparent"
        border.width: 1
        border.color: field.activeFocus ? root.accent : Qt.alpha(root.foreground, 0.28)

        Row {
          id: fieldRow
          height: parent.height

          TextInput {
            id: field
            width: Math.max(Style.space(40), contentWidth + leftPadding + rightPadding + 1)
            height: parent.height
            leftPadding: Style.space(6)
            rightPadding: root.suffix !== "" ? Style.space(2) : Style.space(6)
            verticalAlignment: TextInput.AlignVCenter
            horizontalAlignment: TextInput.AlignRight
            color: activeFocus ? root.foreground : root.accent
            selectionColor: Qt.alpha(root.accent, 0.35)
            selectedTextColor: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            selectByMouse: true
            activeFocusOnTab: false
            inputMethodHints: Qt.ImhFormattedNumbersOnly
            Accessible.name: root.label
            onEditingFinished: root.commitField()
            onActiveFocusChanged: activeFocus ? selectAll() : root.syncField()
            Keys.onEscapePressed: event => {
              field.text = root.format(slider.value)
              slider.forceActiveFocus(Qt.TabFocusReason)
              event.accepted = true
            }
            Keys.onReturnPressed: event => {
              root.commitField()
              slider.forceActiveFocus(Qt.TabFocusReason)
              event.accepted = true
            }
            Keys.onEnterPressed: event => {
              root.commitField()
              slider.forceActiveFocus(Qt.TabFocusReason)
              event.accepted = true
            }
          }

          Text {
            visible: root.suffix !== ""
            height: parent.height
            rightPadding: Style.space(6)
            verticalAlignment: Text.AlignVCenter
            text: root.suffix
            color: Qt.alpha(root.foreground, 0.62)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Repeater {
            model: [-1, 1]

            Rectangle {
              id: stepper
              required property int modelData
              width: Style.space(20)
              height: parent.height
              color: stepMouse.containsMouse ? Style.hoverFillFor(root.foreground, root.accent) : "transparent"
              radius: modelData > 0 ? Style.cornerRadius : 0

              Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 1
                color: Qt.alpha(root.foreground, 0.28)
              }

              Text {
                anchors.centerIn: parent
                text: stepper.modelData > 0 ? "+" : "−"
                color: stepMouse.containsMouse ? root.foreground : Qt.alpha(root.foreground, 0.62)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              MouseArea {
                id: stepMouse
                objectName: stepper.modelData > 0 ? "stepUp" : "stepDown"
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  if (stepper.modelData > 0) slider.increase()
                  else slider.decrease()
                  root.moved()
                }
              }
            }
          }
        }
      }
    }

    Slider {
      id: slider
      width: parent.width
      height: Style.space(18)
      focus: true
      focusPolicy: Qt.StrongFocus
      snapMode: Slider.SnapAlways
      leftPadding: handleItem.width / 2
      rightPadding: handleItem.width / 2
      topPadding: 0
      bottomPadding: 0
      Accessible.name: root.label
      onMoved: root.moved()
      onValueChanged: root.syncField()
      Component.onCompleted: root.syncField()
      Keys.onReturnPressed: event => { field.forceActiveFocus(); event.accepted = true }
      Keys.onEnterPressed: event => { field.forceActiveFocus(); event.accepted = true }

      background: Item {
        x: slider.leftPadding
        y: slider.topPadding + slider.availableHeight / 2 - height / 2
        width: slider.availableWidth
        height: Math.max(3, Style.space(3))

        Rectangle {
          anchors.fill: parent
          radius: Math.min(Style.cornerRadius, height / 2)
          color: Qt.alpha(root.foreground, 0.22)
        }

        Rectangle {
          width: slider.visualPosition * parent.width
          height: parent.height
          radius: Math.min(Style.cornerRadius, height / 2)
          color: root.accent
        }
      }

      handle: Rectangle {
        id: handleItem
        x: slider.leftPadding + slider.visualPosition * slider.availableWidth - width / 2
        y: slider.topPadding + slider.availableHeight / 2 - height / 2
        width: Math.max(12, Style.space(13))
        height: width
        radius: Math.min(Style.cornerRadius, width / 2)
        color: slider.pressed || slider.hovered ? root.accent : root.foreground
        border.width: 2
        border.color: root.accent
      }
    }
  }
}
