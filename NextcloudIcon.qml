import QtQuick
import QtQuick.Shapes
import qs.Commons

Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Color.foreground

  width: iconSize * 1.2
  height: iconSize
  implicitWidth: iconSize * 1.2
  implicitHeight: iconSize

  Shape {
    anchors.fill: parent
    antialiasing: true
    layer.enabled: true
    layer.samples: 4
    scale: 0.95

    ShapePath {
      fillColor: root.color
      strokeWidth: 0

      startX: root.width * 0.20
      startY: root.height * 0.70

      PathArc {
        x: root.width * 0.20
        y: root.height * 0.30
        radiusX: root.width * 0.15
        radiusY: root.height * 0.20
        useLargeArc: false
        direction: PathArc.Counterclockwise
      }

      PathArc {
        x: root.width * 0.50
        y: root.height * 0.20
        radiusX: root.width * 0.20
        radiusY: root.height * 0.25
        useLargeArc: false
        direction: PathArc.Counterclockwise
      }

      PathArc {
        x: root.width * 0.80
        y: root.height * 0.30
        radiusX: root.width * 0.20
        radiusY: root.height * 0.25
        useLargeArc: false
        direction: PathArc.Counterclockwise
      }

      PathArc {
        x: root.width * 0.80
        y: root.height * 0.70
        radiusX: root.width * 0.15
        radiusY: root.height * 0.20
        useLargeArc: false
        direction: PathArc.Counterclockwise
      }

      PathLine { x: root.width * 0.20; y: root.height * 0.70 }
    }
  }
}
