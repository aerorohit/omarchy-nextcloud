import QtQuick
import QtQuick.Shapes
import qs.Commons

Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Color.foreground

  width: iconSize
  height: iconSize
  implicitWidth: iconSize
  implicitHeight: iconSize

  Shape {
    anchors.fill: parent
    antialiasing: true
    layer.enabled: true
    layer.samples: 4

    ShapePath {
      fillColor: root.color
      strokeWidth: 0

      // Nextcloud mark silhouette
      //
      // The shape is constructed as one continuous path:
      //   - left rounded lobe
      //   - tall central arch
      //   - right rounded lobe
      //   - flat lower edge

      startX: root.width * 0.08
      startY: root.height * 0.72

      // Left lobe
      PathCubic {
        control1X: root.width * 0.08
        control1Y: root.height * 0.55
        control2X: root.width * 0.20
        control2Y: root.height * 0.43
        x: root.width * 0.34
        y: root.height * 0.48
      }

      // Transition into central arch
      PathCubic {
        control1X: root.width * 0.34
        control1Y: root.height * 0.28
        control2X: root.width * 0.42
        control2Y: root.height * 0.12
        x: root.width * 0.50
        y: root.height * 0.12
      }

      // Top of central arch
      PathCubic {
        control1X: root.width * 0.64
        control1Y: root.height * 0.12
        control2X: root.width * 0.72
        control2Y: root.height * 0.28
        x: root.width * 0.72
        y: root.height * 0.48
      }

      // Right lobe
      PathCubic {
        control1X: root.width * 0.86
        control1Y: root.height * 0.43
        control2X: root.width * 0.92
        control2Y: root.height * 0.56
        x: root.width * 0.92
        y: root.height * 0.72
      }

      // Right bottom
      PathLine {
        x: root.width * 0.92
        y: root.height * 0.82
      }

      // Flat bottom
      PathLine {
        x: root.width * 0.08
        y: root.height * 0.82
      }

      // Close
      PathLine {
        x: root.width * 0.08
        y: root.height * 0.72
      }
    }
  }
}
