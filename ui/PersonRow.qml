import QtQuick
import "../lib/Registry.js" as Reg

// A person (or group) in a list: the picture, the name and a line under
// it, as the contact lists of WhatsApp Web draw them.
Item {
  id: pr
  property var app: Reg.service
  readonly property var t: app.theme
  property string jid: ""
  property string name: ""
  property string sub: ""
  property string badge: ""
  property bool group: false
  property bool checked: false
  property bool checkable: false
  property string icon: ""
  property color iconBg: t.accent
  signal clicked()
  width: parent ? parent.width : 0
  height: t.sp(68)

  Rectangle {
    anchors.fill: parent
    anchors.leftMargin: pr.t.sp(10)
    anchors.rightMargin: pr.t.sp(10)
    radius: pr.t.sp(10)
    color: ma.containsMouse ? pr.t.hover : "transparent"
  }
  Avatar {
    id: pic
    visible: pr.icon === ""
    x: pr.t.sp(22)
    anchors.verticalCenter: parent.verticalCenter
    jid: pr.jid
    name: pr.name
    group: pr.group
  }
  Rectangle {
    visible: pr.icon !== ""
    x: pr.t.sp(22)
    anchors.verticalCenter: parent.verticalCenter
    width: pr.t.avatar; height: width; radius: width / 2
    color: pr.iconBg
    Icon { anchors.centerIn: parent; name: pr.icon; size: pr.t.sp(26); color: pr.t.onColor(pr.iconBg) }
  }
  Column {
    anchors.left: pic.right
    anchors.leftMargin: pr.t.sp(15)
    anchors.right: tail.left
    anchors.rightMargin: pr.t.sp(10)
    anchors.verticalCenter: parent.verticalCenter
    spacing: pr.t.sp(3)
    Text {
      width: parent.width
      text: pr.name
      color: pr.t.textBright
      font.family: pr.t.font
      font.pixelSize: pr.t.fsName
      elide: Text.ElideRight
      textFormat: Text.PlainText
    }
    Text {
      width: parent.width
      visible: pr.sub !== ""
      text: pr.sub
      color: pr.t.dim
      font.family: pr.t.font
      font.pixelSize: pr.t.fsSmall + 1
      elide: Text.ElideRight
      textFormat: Text.PlainText
    }
  }
  Item {
    id: tail
    anchors.right: parent.right
    anchors.rightMargin: pr.t.sp(26)
    anchors.verticalCenter: parent.verticalCenter
    width: Math.max(badgeBox.visible ? badgeBox.width : 0, check.visible ? check.width : 0)
    height: pr.t.sp(24)
    Rectangle {
      id: badgeBox
      visible: pr.badge !== ""
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      height: pr.t.sp(22)
      width: badgeText.implicitWidth + pr.t.sp(14)
      radius: pr.t.sp(6)
      color: pr.t.chipOn
      Text { id: badgeText; textFormat: Text.PlainText; anchors.centerIn: parent; text: pr.badge; color: pr.t.chipOnText; font.family: pr.t.font; font.pixelSize: pr.t.fsSmall }
    }
    Icon {
      id: check
      visible: pr.checkable
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      name: pr.checked ? "checkboxOn" : "checkboxOff"
      size: pr.t.sp(24)
      color: pr.checked ? pr.t.accent : pr.t.dim
    }
  }
  MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pr.clicked() }
}
