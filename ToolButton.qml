import QtQuick
import qs.Commons

// Text button for the Glow Studio toolbar. Uses the shared state tokens so it
// picks up hover/selected treatment from whatever theme is active.
Item {
  id: root

  property string label: ""
  property string shortcut: ""
  property bool active: false
  property bool enabled: true
  property color foreground: Color.menu.text
  property color accent: Color.menu.selectedText

  signal clicked()

  readonly property color activeColor: root.active ? root.accent : root.foreground

  implicitWidth: text.implicitWidth + Style.spacing.controlPaddingX * 2
  implicitHeight: Style.spacing.controlHeight
  opacity: root.enabled ? 1 : 0.35

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: root.active
      ? Style.selectedFillFor(root.accent, root.accent)
      : (hover.hovered && root.enabled ? Style.hoverFillFor(root.foreground, root.accent)
                                       : Style.normalFillFor(root.foreground, root.accent))
    border.width: root.active ? Style.selectedBorderWidth : Style.normalBorderWidth
    border.color: root.active
      ? Style.selectedBorderFor(root.accent, root.accent)
      : Style.normalBorderFor(root.foreground, root.accent)

    Behavior on color { ColorAnimation { duration: 100 } }
  }

  Text {
    id: text
    anchors.centerIn: parent
    text: root.label
    color: root.activeColor
    font.family: Style.font.menuFamily
    font.pixelSize: Style.font.bodySmall
    Behavior on color { ColorAnimation { duration: 100 } }
  }

  HoverHandler {
    id: hover
    enabled: root.enabled
    cursorShape: Qt.PointingHandCursor
  }

  TapHandler {
    enabled: root.enabled
    onTapped: root.clicked()
  }
}
