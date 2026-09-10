import QtQuick
import qs.Commons

// The keybind reference, shown over the board by Shift+?.
//
// It exists so the toolbar does not have to carry one. A single line of hint
// text under the controls could only ever hold as many bindings as the window
// was wide, and elided the rest — which on a tiled or laptop-width window
// meant losing the last few, Ctrl+S and Esc among them. A panel wraps
// nothing and drops nothing.
Rectangle {
  id: root

  // [{ keys: "Ctrl+S", what: "export a PNG" }, …]
  property var bindings: []

  color: Util.alpha(Color.menu.background, 0.97)
  radius: Style.cornerRadius
  border.width: Math.max(1, Style.space(1))
  border.color: Util.alpha(Color.menu.border, 0.6)

  // Anywhere on the panel dismisses it, so the pointer has the same way out
  // the keyboard does. It also stops clicks reaching the board underneath —
  // opening the reference should never cost you a stray peg.
  MouseArea {
    anchors.fill: parent
    onClicked: root.visible = false
  }

  Column {
    anchors.centerIn: parent
    spacing: Style.spacing.lg

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: "Keyboard"
      color: Color.menu.text
      font.family: Style.font.menuFamily
      font.pixelSize: Style.font.bodySmall
    }

    Column {
      spacing: Style.spacing.sm

      Repeater {
        model: root.bindings

        Row {
          required property var modelData
          spacing: Style.spacing.lg

          // Right-aligned in a fixed column so the keys form a clean edge
          // against the descriptions, however wide any one of them is.
          Text {
            width: Math.round(Style.font.bodySmall * 11)
            horizontalAlignment: Text.AlignRight
            text: parent.modelData.keys
            color: Color.menu.text
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            text: parent.modelData.what
            color: Util.alpha(Color.menu.text, 0.6)
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: "Shift + ?  or  Esc  to close"
      color: Util.alpha(Color.menu.text, 0.4)
      font.family: Style.font.menuFamily
      font.pixelSize: Style.font.caption
    }
  }
}
