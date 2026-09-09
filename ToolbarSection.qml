import QtQuick
import qs.Commons

// One labelled cluster of controls in the Glow Studio toolbar.
//
// The toolbar is a Flow of these sections rather than a flat Flow of bare
// controls: the caption names the cluster, and because a section is a single
// Flow child it wraps to the next line as a unit when the window narrows,
// rather than spilling lone buttons across the break. The caption band is
// reserved even when there is no caption, so an uncaptioned section keeps
// the same height as its siblings and its button still lands on the shared
// controls line instead of one caption higher.
Item {
  id: root

  property string label: ""

  default property alias controls: row.data

  // Reserved from the font rather than measured off a hidden Text, so an
  // empty label and a real one keep identical geometry.
  readonly property int captionBand: Math.round(Style.font.caption * 1.4)

  implicitWidth: row.implicitWidth
  implicitHeight: captionBand + Style.spacing.labelGap + Style.spacing.controlHeight

  Text {
    id: caption
    visible: root.label.length > 0
    anchors { left: parent.left; right: parent.right; top: parent.top }
    text: root.label
    color: Util.alpha(Color.menu.text, 0.45)
    font.family: Style.font.menuFamily
    font.pixelSize: Style.font.caption
    elide: Text.ElideRight
  }

  Row {
    id: row
    anchors { left: parent.left; top: parent.top; topMargin: root.captionBand + Style.spacing.labelGap }
    spacing: Style.spacing.controlGap
  }
}
