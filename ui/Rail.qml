import QtQuick
import "../lib/Registry.js" as Reg

// WhatsApp Web's rail: the tabs on top (Chats with what's unread, starred
// messages), settings and your photo at the bottom (your menu).
Rectangle {
  id: rail
  property var app: Reg.service
  property var win
  readonly property var t: app.theme
  readonly property var wa: app.wa
  color: t.rail

  component RailButton: Item {
    id: rb
    property string icon: ""
    property string iconOn: ""
    property bool on: false
    property string tip: ""
    property int badge: 0
    property bool dot: false
    signal clicked()
    width: rail.width
    height: rail.t.sp(52)
    Rectangle {
      anchors.centerIn: parent
      width: rail.t.sp(40)
      height: width
      radius: width / 2
      color: rb.on ? rail.t.selected : (ma.containsMouse ? rail.t.hover : "transparent")
    }
    Icon {
      anchors.centerIn: parent
      name: rb.on && rb.iconOn ? rb.iconOn : rb.icon
      size: rail.t.sp(24)
      color: rb.on ? rail.t.text : rail.t.icon
    }
    Rectangle {
      visible: rb.badge > 0
      x: parent.width / 2 + rail.t.sp(3)
      y: rail.t.sp(5)
      height: rail.t.sp(18)
      width: Math.max(height, badgeText.implicitWidth + rail.t.sp(10))
      radius: height / 2
      color: rail.t.badge
      Text {
        id: badgeText
        anchors.centerIn: parent
        text: rb.badge > 99 ? "99+" : rb.badge
        color: rail.t.badgeText
        font.family: rail.t.font
        font.pixelSize: rail.t.sp(11)
        font.weight: Font.DemiBold
      }
    }
    Rectangle {
      visible: rb.dot && rb.badge === 0
      x: parent.width / 2 + rail.t.sp(7)
      y: rail.t.sp(11)
      width: rail.t.sp(9); height: width; radius: width / 2
      color: rail.t.badge
    }
    MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: rb.clicked() }
    Tip { text: rb.tip; shown: ma.containsMouse }
  }

  Column {
    y: rail.t.sp(8)
    width: parent.width
    RailButton {
      icon: "chat"; iconOn: "chatFilled"
      on: ["chats", "archived", "newchat"].indexOf(rail.win.sideView) >= 0
      tip: rail.app.tr("Chats", "Conversas")
      badge: rail.app.attention.chats
      onClicked: rail.win.sideView = "chats"
    }
    RailButton {
      icon: "star"; iconOn: "starFilled"
      on: rail.win.sideView === "starred"
      tip: rail.app.tr("Starred messages", "Mensagens favoritas")
      onClicked: rail.win.sideView = "starred"
    }
  }

  Column {
    anchors.bottom: parent.bottom
    anchors.bottomMargin: rail.t.sp(10)
    width: parent.width
    spacing: rail.t.sp(2)
    RailButton {
      icon: "settings"; iconOn: "settingsFilled"
      on: rail.win.sideView === "settings"
      tip: rail.app.tr("Settings", "Configurações")
      dot: rail.wa.conn !== "ready"
      onClicked: rail.win.sideView = "settings"
    }
    Item {
      width: rail.width
      height: rail.t.sp(52)
      Rectangle {
        anchors.centerIn: parent
        width: rail.t.sp(34); height: width; radius: width / 2
        color: "transparent"
        border.width: rail.win.accountOpen ? 2 : 0
        border.color: rail.t.text
      }
      Avatar {
        id: me
        anchors.centerIn: parent
        size: rail.t.sp(28)
        jid: rail.wa.me ? rail.wa.me.jid : ""
        name: rail.wa.me ? rail.wa.me.name : ""
      }
      // A newer version, as the TUI's arrow by your photo: the menu has it.
      Rectangle {
        readonly property string phase: rail.app.updater ? rail.app.updater.phase : ""
        visible: phase === "available" || phase === "updated"
        x: me.x + me.width - width / 2 - rail.t.sp(1)
        y: me.y - rail.t.sp(3)
        width: rail.t.sp(16); height: width; radius: width / 2
        color: rail.t.green
        border.width: 2
        border.color: rail.t.rail
        Text {
          anchors.centerIn: parent
          text: parent.phase === "updated" ? "↻" : "↑"
          color: rail.t.onColor(rail.t.green)
          font.family: rail.t.font
          font.pixelSize: rail.t.sp(10)
          font.weight: Font.Bold
        }
      }
      MouseArea { id: pma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: rail.win.toggleAccount() }
      Tip { text: rail.app.tr("You · Alt+S", "Você · Alt+S"); shown: pma.containsMouse && !rail.win.accountOpen }
    }
  }
}
