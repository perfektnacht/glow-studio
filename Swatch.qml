import QtQuick
import qs.Commons

// One peg color in the toolbar, drawn as the peg it places: a lit dome with
// the same glow the board uses, so picking a color previews the result.
Item {
  id: root

  property color pegColor: "#ffffff"
  property bool selected: false
  property string tooltip: ""

  signal clicked()

  readonly property int diameter: Style.space(26)

  implicitWidth: diameter
  implicitHeight: diameter

  // Glow halo. Present but faint when idle so the row reads as eight lights;
  // full strength on the selected one.
  Rectangle {
    anchors.centerIn: parent
    width: root.diameter * 1.55
    height: width
    radius: width / 2
    color: Qt.rgba(root.pegColor.r, root.pegColor.g, root.pegColor.b,
                   root.selected ? 0.28 : (hover.hovered ? 0.16 : 0.06))
    Behavior on color { ColorAnimation { duration: 120 } }
  }

  Rectangle {
    id: dome
    anchors.centerIn: parent
    width: root.diameter * (root.selected ? 1.0 : 0.82)
    height: width
    radius: width / 2
    color: root.pegColor
    border.width: root.selected ? Math.max(1, Style.space(2)) : 0
    border.color: Qt.rgba(1, 1, 1, 0.85)

    Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

    // Specular highlight, offset up-left to match the board's light direction.
    Rectangle {
      width: parent.width * 0.3
      height: width
      radius: width / 2
      color: Qt.rgba(1, 1, 1, 0.75)
      x: parent.width * 0.2
      y: parent.height * 0.16
    }
  }

  HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
  TapHandler { onTapped: root.clicked() }
}
