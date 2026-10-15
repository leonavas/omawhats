import QtQuick
import "../lib/Registry.js" as Reg

// The notices on top of the chat list, as WhatsApp Web's: no connection,
// notifications paused, chats still syncing.
Column {
  id: n
  property var app: Reg.service
  property var win
  readonly property var t: app.theme
  readonly property var wa: app.wa
  spacing: t.sp(6)
  topPadding: (offline.visible || paused.visible || sync.visible) ? t.sp(4) : 0
  bottomPadding: topPadding

  component Banner: Rectangle {
    id: bn
    property string icon: ""
    property color iconBg: n.t.warning
    property string title: ""
    property string sub: ""
    property string action: ""
    signal act()
    x: n.t.sp(10)
    width: n.width - n.t.sp(20)
    height: col.implicitHeight + n.t.sp(24)
    radius: n.t.sp(12)
    color: n.t.chip
    Rectangle {
      id: circle
      x: n.t.sp(14)
      anchors.verticalCenter: parent.verticalCenter
      width: n.t.sp(44); height: width; radius: width / 2
      color: bn.iconBg
      Icon { anchors.centerIn: parent; name: bn.icon; size: n.t.sp(24); color: n.t.onColor(bn.iconBg) }
    }
    Column {
      id: col
      anchors.left: circle.right
      anchors.leftMargin: n.t.sp(14)
      anchors.right: parent.right
      anchors.rightMargin: n.t.sp(14)
      anchors.verticalCenter: parent.verticalCenter
      spacing: n.t.sp(2)
      Text { width: parent.width; text: bn.title; color: n.t.textBright; font.family: n.t.font; font.pixelSize: n.t.fsText; wrapMode: Text.Wrap }
      Text {
        width: parent.width
        visible: bn.sub !== "" || bn.action !== ""
        textFormat: Text.StyledText
        text: bn.sub + (bn.action ? (bn.sub ? " " : "") + "<a href=\"x\"><font color=\"" + n.t.hex(n.t.accent) + "\">" + bn.action + "</font></a>" : "")
        color: n.t.dim
        font.family: n.t.font
        font.pixelSize: n.t.fsSmall
        wrapMode: Text.Wrap
        linkColor: n.t.accent
        onLinkActivated: bn.act()
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.NoButton; cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
      }
    }
  }

  Banner {
    id: offline
    visible: n.wa.conn === "offline" || n.wa.conn === "replaced" || (n.wa.conn === "connecting" && n.wa.everReady)
    icon: n.wa.conn === "replaced" ? "devices" : "wifi"
    iconBg: n.t.warning
    title: n.wa.conn === "replaced" ? n.app.tr("WhatsApp is open on another window", "O WhatsApp está aberto em outra janela")
         : n.wa.conn === "connecting" ? n.app.tr("Connecting…", "Conectando…") : n.app.tr("Computer not connected", "Computador não conectado")
    sub: n.wa.conn === "replaced" ? "" : n.app.tr("Make sure your computer has an active internet connection.", "Verifique se o computador está conectado à internet.")
  }
  Banner {
    id: paused
    visible: n.app.paused
    icon: "muted"
    iconBg: n.t.blue
    title: n.app.tr("Notifications are paused", "As notificações estão pausadas")
    action: n.app.tr("Resume", "Reativar")
    onAct: n.app.resume()
  }
  Banner {
    id: sync
    visible: n.wa.syncProgress >= 0 && n.wa.syncProgress < 100 && n.wa.conn === "ready"
    icon: "sync"
    iconBg: n.t.accent
    title: n.app.tr("Syncing older messages… ", "Sincronizando mensagens antigas… ") + n.wa.syncProgress + "%"
    sub: n.app.tr("Keep your phone connected.", "Mantenha o celular conectado.")
  }
}
