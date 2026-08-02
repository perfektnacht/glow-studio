import QtQuick
import qs.Commons
import qs.Ui

// Bar entry point: a peg-grid glyph that toggles the board.
BarWidget {
  id: root
  moduleName: "perfektnacht.lite-brite"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // nf-fa-th — a 3x3 grid, which is as close to a peg board as the icon
    // font gets.
    text: ""
    tooltipText: "Lite-Brite"
    onPressed: function(pressedButton) {
      if (!root.bar) return
      if (pressedButton !== Qt.LeftButton) return
      root.bar.run("omarchy-shell shell toggle perfektnacht.lite-brite '{}'")
    }
  }
}
