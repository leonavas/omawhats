import QtQuick
import "../lib/Registry.js" as Reg

// A small tooltip beside its parent (below, above or to the right), after
// a moment's hover.
Item {
  id: tip
  property var app: Reg.service
  readonly property var t: app.theme
  property string text: ""
  property bool shown: false
  // below, above, right
  property string placement: parent && parent.width < tip.t.sp(80) && parent.x < tip.t.sp(10) ? "right" : "below"
  anchors.fill: parent
  z: 999

  Timer { id: wait; interval: 550; onTriggered: card.visible = tip.shown && tip.text !== "" }
  onShownChanged: { if (shown) wait.restart(); else { wait.stop(); card.visible = false } }

  Rectangle {
    id: card
    visible: false
    width: label.implicitWidth + tip.t.sp(16)
    height: label.implicitHeight + tip.t.sp(10)
    radius: tip.t.sp(6)
    color: tip.t.textBright
    x: tip.placement === "right" ? tip.width + tip.t.sp(4) : Math.round((tip.width - width) / 2)
    y: tip.placement === "right" ? Math.round((tip.height - height) / 2) : (tip.placement === "above" ? -height - tip.t.sp(6) : tip.height + tip.t.sp(6))
    Text {
      id: label
      anchors.centerIn: parent
      text: tip.text
      color: tip.t.bg
      font.family: tip.t.font
      font.pixelSize: tip.t.fsSmall
    }
  }
}
