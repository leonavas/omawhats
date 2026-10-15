import QtQuick
import "../lib/Registry.js" as Reg

// A side view's header: the back arrow and its title.
Item {
  id: h
  property var app: Reg.service
  readonly property var t: app.theme
  property string title: ""
  property string icon: "back"
  signal back()
  width: parent ? parent.width : 0
  height: t.sp(64)

  IconButton {
    id: backBtn
    x: h.t.sp(10)
    anchors.verticalCenter: parent.verticalCenter
    icon: h.icon
    color: h.t.text
    onClicked: h.back()
  }
  Text {
    anchors.left: backBtn.right
    anchors.leftMargin: h.t.sp(14)
    anchors.right: parent.right
    anchors.rightMargin: h.t.sp(16)
    anchors.verticalCenter: parent.verticalCenter
    text: h.title
    color: h.t.textBright
    font.family: h.t.font
    font.pixelSize: h.t.px(19)
    font.weight: Font.Medium
    elide: Text.ElideRight
  }
}
