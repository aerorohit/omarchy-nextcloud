import QtQuick
import qs.Commons

Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Color.foreground

  width: iconSize * 1.6
  height: iconSize
  implicitWidth: iconSize * 1.6
  implicitHeight: iconSize

  // Nextcloud logo: three ring circles side by side.
  // Centre is largest, left and right are smaller.
  // Rings just touch each other symmetrically.

  readonly property real strokeWidth: Math.max(1.5, iconSize * 0.14)
  readonly property real centreRadius: iconSize * 0.40
  readonly property real sideRadius: iconSize * 0.22

  // Centre ring (largest)
  Rectangle {
    anchors.centerIn: parent
    width: root.centreRadius * 2
    height: root.centreRadius * 2
    radius: root.centreRadius
    color: "transparent"
    border.color: root.color
    border.width: root.strokeWidth
  }

  // Left ring — right edge just touches centre ring left edge
  Rectangle {
    anchors.verticalCenter: parent.verticalCenter
    x: parent.width / 2 - root.centreRadius - root.sideRadius * 2 + root.strokeWidth
    width: root.sideRadius * 2
    height: root.sideRadius * 2
    radius: root.sideRadius
    color: "transparent"
    border.color: root.color
    border.width: root.strokeWidth
  }

  // Right ring — left edge just touches centre ring right edge
  Rectangle {
    anchors.verticalCenter: parent.verticalCenter
    x: parent.width / 2 + root.centreRadius - root.strokeWidth
    width: root.sideRadius * 2
    height: root.sideRadius * 2
    radius: root.sideRadius
    color: "transparent"
    border.color: root.color
    border.width: root.strokeWidth
  }
}
