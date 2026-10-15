import QtQuick
import "../lib/Registry.js" as Reg

// The notices on top of the chat list, as WhatsApp Web's: a new version,
// no connection, notifications paused, chats still syncing.
Column {
  id: n
  property var app: Reg.service
  property var win
  readonly property var t: app.theme
  readonly property var wa: app.wa
  spacing: t.sp(6)
  readonly property var up: app.updater
  topPadding: (newVersion.visible || offline.visible || paused.visible || sync.visible) ? t.sp(4) : 0
  bottomPadding: topPadding

  component Banner: Rectangle {
    id: bn
    property string icon: ""
    property color iconBg: n.t.warning
    property string title: ""
    property string sub: ""
    property string action: ""
    // The whole card answers a click, not only its link.
    property bool clickable: false
    signal act()
    x: n.t.sp(10)
    width: n.width - n.t.sp(20)
    height: col.implicitHeight + n.t.sp(24)
    radius: n.t.sp(12)
    color: bn.clickable && whole.containsMouse ? n.t.mix(n.t.chip, n.t.fg, 0.06) : n.t.chip
    MouseArea { id: whole; anchors.fill: parent; z: 1; visible: bn.clickable; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: bn.act() }
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
      Text { textFormat: Text.PlainText; width: parent.width; text: bn.title; color: n.t.textBright; font.family: n.t.font; font.pixelSize: n.t.fsText; wrapMode: Text.Wrap }
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

  // A new version (core/Updater.qml): a click updates and restarts the
  // shell; faded while it runs.
  Banner {
    id: newVersion
    visible: !!n.up && n.up.phase !== ""
    clickable: !!n.up && n.up.phase !== "updating"
    opacity: n.up && n.up.phase === "updating" ? 0.7 : 1
    icon: n.up && n.up.phase === "updating" ? "sync" : "download"
    iconBg: n.t.accent
    title: !n.up ? "" : n.up.phase === "updating" ? n.app.tr("Updating to ", "Atualizando para a versão ") + n.up.latest + "…"
         : n.up.phase === "updated" ? n.app.tr("Version ", "Versão ") + n.up.latest + n.app.tr(" installed", " instalada")
         : n.app.tr("Update available", "Atualização disponível")
    sub: !n.up ? "" : n.up.phase === "updating" ? n.app.tr("The shell restarts and the window comes back.", "O shell reinicia e a janela volta.")
       : n.up.phase === "updated" ? ""
       : n.app.tr("Version ", "Versão ") + n.up.latest + "."
    action: !n.up || n.up.phase === "updating" ? ""
          : n.up.phase === "updated" ? n.app.tr("Restart the shell to use it", "Reinicie o shell para usar")
          : n.app.tr("Click to update", "Clique para atualizar")
    onAct: n.up.update()
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
