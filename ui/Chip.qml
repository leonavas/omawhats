import QtQuick
import "../lib/Registry.js" as Reg

// A filter chip of the chat list (Tudo, Não lidas, Favoritas, Grupos).
Rectangle {
  id: c
  property var app: Reg.service
  readonly property var t: app.theme
  property string label: ""
  property int count: 0
  property bool on: false
  signal clicked()
  height: t.sp(32)
  width: row.implicitWidth + t.sp(24)
  radius: height / 2
  color: on ? t.chipOn : (ma.containsMouse ? t.hoverStrong : "transparent")
  border.width: on ? 0 : 1
  border.color: t.lineStrong
  Row {
    id: row
    anchors.centerIn: parent
    spacing: c.t.sp(5)
    Text {
      textFormat: Text.PlainText
      text: c.label
      color: c.on ? c.t.chipOnText : c.t.dim
      font.family: c.t.font
      font.pixelSize: c.t.fsChip
      font.weight: Font.Medium
    }
    Text {
      textFormat: Text.PlainText
      visible: c.count > 0
      text: c.count
      color: c.on ? c.t.chipOnText : c.t.faint
      font.family: c.t.font
      font.pixelSize: c.t.fsSmall
      anchors.baseline: parent.children[0].baseline
    }
  }
  MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: c.clicked() }
}
