import QtQuick
import "PointerFeelModel.js" as PointerFeelModel

Rectangle {
  id: circuit

  property color foreground: "white"
  property color accent: "orange"
  property int pointIndex: 0
  property int hits: 0
  signal hit()

  implicitHeight: 104
  radius: 10
  color: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.025)
  border.color: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.13)
  border.width: 1

  function pointPosition(index, itemWidth, itemHeight) {
    var point = PointerFeelModel.practicePoint(index)
    var margin = 18
    return {
      x: margin + point.x * Math.max(0, width - margin * 2 - itemWidth),
      y: margin + point.y * Math.max(0, height - margin * 2 - itemHeight)
    }
  }

  onWidthChanged: route.requestPaint()
  onHeightChanged: route.requestPaint()
  onForegroundChanged: route.requestPaint()
  onAccentChanged: route.requestPaint()

  Canvas {
    id: route
    anchors.fill: parent
    antialiasing: true

    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var count = PointerFeelModel.practicePointCount()
      if (!count) return
      var first = circuit.pointPosition(0, 0, 0)
      ctx.beginPath()
      ctx.moveTo(first.x, first.y)
      for (var i = 1; i < count; i++) {
        var previous = circuit.pointPosition(i - 1, 0, 0)
        var point = circuit.pointPosition(i, 0, 0)
        var bend = i % 2 ? -11 : 11
        ctx.quadraticCurveTo((previous.x + point.x) / 2,
          (previous.y + point.y) / 2 + bend, point.x, point.y)
      }
      ctx.lineWidth = 1.5
      ctx.setLineDash([3, 7])
      ctx.strokeStyle = circuit.accent
      ctx.globalAlpha = 0.32
      ctx.stroke()
      ctx.setLineDash([])
      ctx.globalAlpha = 1
    }
  }

  Repeater {
    model: PointerFeelModel.practicePointCount()
    Rectangle {
      required property int index
      property var location: circuit.pointPosition(index, width, height)
      width: 8
      height: 8
      x: location.x
      y: location.y
      rotation: 45
      radius: 1
      color: index === circuit.pointIndex
        ? Qt.rgba(circuit.accent.r, circuit.accent.g, circuit.accent.b, 0.18)
        : Qt.rgba(circuit.foreground.r, circuit.foreground.g, circuit.foreground.b, 0.34)
      border.color: index === circuit.pointIndex
        ? circuit.accent : Qt.rgba(circuit.foreground.r, circuit.foreground.g, circuit.foreground.b, 0.18)
      border.width: 1
    }
  }

  Rectangle {
    id: target
    property var location: circuit.pointPosition(circuit.pointIndex, width, height)
    width: 30
    height: 30
    x: location.x
    y: location.y
    rotation: 45
    radius: 5
    color: Qt.rgba(circuit.accent.r, circuit.accent.g, circuit.accent.b, 0.14)
    border.color: circuit.accent
    border.width: 2

    Behavior on x { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }
    Behavior on y { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }

    Rectangle {
      anchors.centerIn: parent
      width: 8
      height: 8
      rotation: -45
      radius: width / 2
      color: circuit.accent
    }

    Rectangle {
      anchors.centerIn: parent
      width: parent.width + 10
      height: width
      rotation: -45
      radius: width / 2
      color: "transparent"
      border.color: circuit.accent
      border.width: 1
      SequentialAnimation on opacity {
        loops: Animation.Infinite
        NumberAnimation { from: 0.5; to: 0.08; duration: 850; easing.type: Easing.OutQuad }
        NumberAnimation { from: 0.08; to: 0.5; duration: 850; easing.type: Easing.InQuad }
      }
    }

    MouseArea {
      anchors.fill: parent
      anchors.margins: -8
      cursorShape: Qt.CrossCursor
      onClicked: circuit.hit()
    }
  }
}