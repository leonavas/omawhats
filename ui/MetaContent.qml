import QtQuick
import "../lib/Util.js" as U
import "../lib/Registry.js" as Reg

// A message's corner: starred, "Edited", the time and, for yours, the ticks.
Row {
  id: mc
  property var app: Reg.service
  readonly property var t: app.theme
  property var m
  property bool over: false
  readonly property color ink: over ? "white" : t.faint
  spacing: t.sp(3)
  height: t.sp(15)
  Icon { visible: !!mc.m.star; name: "starFilled"; size: mc.t.sp(12); color: mc.ink; anchors.verticalCenter: parent.verticalCenter }
  Text {
    textFormat: Text.PlainText
    visible: !!mc.m.edited
    text: mc.app.tr("Edited", "Editada")
    color: mc.ink
    font.family: mc.t.font
    font.pixelSize: mc.t.fsMeta
    anchors.verticalCenter: parent.verticalCenter
    rightPadding: mc.t.sp(2)
  }
  Text {
    textFormat: Text.PlainText
    text: U.clock(mc.m.ts, mc.app.clock24)
    color: mc.ink
    font.family: mc.t.font
    font.pixelSize: mc.t.fsMeta
    anchors.verticalCenter: parent.verticalCenter
  }
  Ticks {
    visible: mc.m.from_me && mc.m.kind !== "revoked"
    app: mc.app
    status: mc.m.status
    base: mc.ink
    overMedia: mc.over
    anchors.verticalCenter: parent.verticalCenter
  }
}
