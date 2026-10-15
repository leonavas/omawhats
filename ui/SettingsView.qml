import QtQuick
import QtQuick.Controls
import "../lib/Bar.js" as Bar
import "../lib/Util.js" as U
import "../lib/Registry.js" as Reg

// Settings, as WhatsApp Web's: your card on top, then privacy, chats,
// notifications, language, keyboard shortcuts and Log out.
Item {
  id: sv
  property var app: Reg.service
  property var win
  readonly property var t: app.theme
  readonly property var wa: app.wa

  component Section: Text {
    textFormat: Text.PlainText
    width: parent ? parent.width : 0
    leftPadding: sv.t.sp(28)
    topPadding: sv.t.sp(22)
    bottomPadding: sv.t.sp(10)
    color: sv.t.accent
    font.family: sv.t.font
    font.pixelSize: sv.t.fsText
  }

  component Toggle: Item {
    id: tg
    property string label: ""
    property string sub: ""
    property bool on: false
    signal toggled(bool value)
    width: parent ? parent.width : 0
    height: Math.max(sv.t.sp(56), col.implicitHeight + sv.t.sp(20))
    Rectangle { anchors.fill: parent; anchors.leftMargin: sv.t.sp(10); anchors.rightMargin: sv.t.sp(10); radius: sv.t.sp(10); color: tma.containsMouse ? sv.t.hover : "transparent" }
    Column {
      id: col
      x: sv.t.sp(28)
      width: parent.width - sv.t.sp(110)
      anchors.verticalCenter: parent.verticalCenter
      spacing: sv.t.sp(3)
      Text { textFormat: Text.PlainText; width: parent.width; text: tg.label; color: sv.t.text; font.family: sv.t.font; font.pixelSize: sv.t.fsName - 1; wrapMode: Text.Wrap }
      Text { textFormat: Text.PlainText; width: parent.width; visible: tg.sub !== ""; text: tg.sub; color: sv.t.dim; font.family: sv.t.font; font.pixelSize: sv.t.fsSmall + 1; wrapMode: Text.Wrap }
    }
    Rectangle {
      anchors.right: parent.right
      anchors.rightMargin: sv.t.sp(28)
      anchors.verticalCenter: parent.verticalCenter
      width: sv.t.sp(38); height: sv.t.sp(22); radius: height / 2
      color: tg.on ? sv.t.accent : sv.t.alpha(sv.t.fg, 0.25)
      Behavior on color { ColorAnimation { duration: 120 } }
      Rectangle {
        width: sv.t.sp(16); height: width; radius: width / 2
        anchors.verticalCenter: parent.verticalCenter
        x: tg.on ? parent.width - width - sv.t.sp(3) : sv.t.sp(3)
        color: tg.on ? sv.t.onColor(sv.t.accent) : sv.t.bg
        Behavior on x { NumberAnimation { duration: 120 } }
      }
    }
    MouseArea { id: tma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: tg.toggled(!tg.on) }
  }

  component Choice: Item {
    id: ch
    property string label: ""
    property string icon: ""
    property string value: ""
    property bool danger: false
    signal clicked()
    width: parent ? parent.width : 0
    height: sv.t.sp(58)
    Rectangle { anchors.fill: parent; anchors.leftMargin: sv.t.sp(10); anchors.rightMargin: sv.t.sp(10); radius: sv.t.sp(10); color: cma.containsMouse ? sv.t.hover : "transparent" }
    Icon { visible: ch.icon !== ""; x: sv.t.sp(28); anchors.verticalCenter: parent.verticalCenter; name: ch.icon; size: sv.t.sp(22); color: ch.danger ? sv.t.danger : sv.t.icon }
    Text {
      textFormat: Text.PlainText
      x: ch.icon !== "" ? sv.t.sp(72) : sv.t.sp(28)
      anchors.verticalCenter: parent.verticalCenter
      text: ch.label
      color: ch.danger ? sv.t.danger : sv.t.text
      font.family: sv.t.font
      font.pixelSize: sv.t.fsName - 1
    }
    Text {
      textFormat: Text.PlainText
      anchors.right: parent.right
      anchors.rightMargin: sv.t.sp(28)
      anchors.verticalCenter: parent.verticalCenter
      text: ch.value
      color: sv.t.dim
      font.family: sv.t.font
      font.pixelSize: sv.t.fsText
    }
    MouseArea { id: cma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ch.clicked() }
  }

  SubHeader {
    id: head
    title: sv.app.tr("Settings", "Configurações")
    onBack: sv.win.sideView = "chats"
  }

  Flickable {
    y: head.height
    width: parent.width
    height: parent.height - y
    contentHeight: col.implicitHeight + sv.t.sp(30)
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ThinScroll { app: sv.app }

    Column {
      id: col
      width: parent.width

      // Your card: a click opens the profile.
      Item {
        width: parent.width
        height: sv.t.sp(100)
        Rectangle { anchors.fill: parent; anchors.leftMargin: sv.t.sp(10); anchors.rightMargin: sv.t.sp(10); radius: sv.t.sp(12); color: mema.containsMouse ? sv.t.hover : "transparent" }
        Avatar {
          id: meAv
          x: sv.t.sp(24)
          anchors.verticalCenter: parent.verticalCenter
          size: sv.t.sp(76)
          jid: sv.wa.me ? sv.wa.me.jid : ""
          name: sv.wa.me ? sv.wa.me.name : ""
        }
        Column {
          anchors.left: meAv.right
          anchors.leftMargin: sv.t.sp(18)
          anchors.right: parent.right
          anchors.rightMargin: sv.t.sp(20)
          anchors.verticalCenter: parent.verticalCenter
          spacing: sv.t.sp(4)
          Text { textFormat: Text.PlainText; width: parent.width; text: sv.wa.me ? (sv.wa.me.name || "") : ""; color: sv.t.textBright; font.family: sv.t.font; font.pixelSize: sv.t.px(18); elide: Text.ElideRight }
          Text { textFormat: Text.PlainText; width: parent.width; text: sv.wa.me ? U.phone(sv.wa.me.phone) : ""; color: sv.t.dim; font.family: sv.t.font; font.pixelSize: sv.t.fsText }
        }
        MouseArea { id: mema; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: sv.win.dialog("profile") }
      }
      Rectangle { x: sv.t.sp(28); width: parent.width - sv.t.sp(56); height: 1; color: sv.t.line }

      Section { text: sv.app.tr("Privacy", "Privacidade") }
      Toggle {
        label: sv.app.tr("Read receipts", "Confirmações de leitura")
        sub: sv.app.tr("If you turn this off, people won't see the blue ticks on what you read here.", "Se desativar, as pessoas não verão os tiques azuis no que você ler aqui.")
        on: sv.app.setting("readReceipts", true) !== false
        onToggled: value => sv.app.setSetting("readReceipts", value)
      }

      Section { text: sv.app.tr("Chats", "Conversas") }
      Toggle {
        label: sv.app.tr("Enter sends the message", "Enter envia a mensagem")
        sub: sv.app.tr("Shift+Enter starts a new line", "Shift+Enter quebra a linha")
        on: sv.app.enterSends
        onToggled: value => sv.app.setSetting("enterSends", value)
      }
      Toggle {
        label: sv.app.tr("Chat doodles", "Rabiscos no fundo da conversa")
        sub: sv.app.tr("WhatsApp's drawings behind the messages", "Os desenhos do WhatsApp atrás das mensagens")
        on: sv.app.doodleOn
        onToggled: value => sv.app.setSetting("doodle", value)
      }
      Toggle {
        label: sv.app.tr("Download photos automatically", "Baixar fotos automaticamente")
        on: sv.app.autoPhotos
        onToggled: value => sv.app.setSetting("autoPhotos", value)
      }
      Toggle {
        label: sv.app.tr("Theme font", "Fonte do tema")
        sub: sv.app.tr("Off: the system's sans-serif font", "Desligado: a fonte sem serifa do sistema")
        on: sv.app.setting("font", "theme") === "theme"
        onToggled: value => sv.app.setSetting("font", value ? "theme" : "system")
      }
      Choice {
        id: zoomChoice
        label: sv.app.tr("Zoom", "Zoom")
        icon: "zoomIn"
        value: Math.round(sv.app.zoom * 100) + "%"
        onClicked: sv.win.menuAt(zoomChoice, [80, 90, 100, 110, 125, 150].map(function(z) {
          return { label: z + "%", checked: Math.round(sv.app.zoom * 100) === z, action: function() { sv.app.setSetting("zoom", z / 100) } }
        }), width - sv.t.sp(160), height)
      }

      Section { text: sv.app.tr("Notifications", "Notificações") }
      Toggle {
        label: sv.app.tr("Message notifications", "Notificações de mensagens")
        on: sv.app.notificationsOn
        onToggled: value => sv.app.setNotifySetting("notifications", value)
      }
      Toggle {
        label: sv.app.tr("Show previews", "Mostrar prévias")
        sub: sv.app.tr("The message's text in the notification", "O texto da mensagem na notificação")
        on: sv.app.previewOn
        onToggled: value => sv.app.setNotifySetting("notificationPreview", value)
      }
      Toggle {
        label: sv.app.tr("Reactions", "Reações")
        sub: sv.app.tr("Notify reactions to your messages", "Notificar reações às suas mensagens")
        on: sv.app.reactionNotices
        onToggled: value => sv.app.setSetting("reactionNotifications", value)
      }
      Toggle {
        label: sv.app.tr("Sounds", "Sons")
        on: sv.app.soundOn
        onToggled: value => sv.app.setSetting("sound", value)
      }
      Choice {
        id: pauseChoice
        label: sv.app.paused ? sv.app.tr("Resume notifications", "Reativar notificações") : sv.app.tr("Pause notifications", "Pausar notificações")
        icon: sv.app.paused ? "bell" : "muted"
        value: sv.app.paused ? sv.app.tr("until ", "até ") + Bar.clockLabel(sv.app.pausedUntil, Date.now() / 1000, sv.app.lang) : ""
        onClicked: {
          if (sv.app.paused) { sv.app.resume(); return }
          sv.win.menuAt(pauseChoice, [
            { label: sv.app.tr("30 minutes", "30 minutos"), action: function() { sv.app.pause(30) } },
            { label: sv.app.tr("1 hour", "1 hora"), action: function() { sv.app.pause(60) } },
            { label: sv.app.tr("2 hours", "2 horas"), action: function() { sv.app.pause(120) } },
            { label: sv.app.tr("Until tomorrow", "Até amanhã"), action: function() { sv.app.pause(Bar.minutesToTomorrow(Date.now() / 1000)) } }
          ], width - sv.t.sp(220), height)
        }
      }

      Section { text: sv.app.tr("App", "Aplicativo") }
      Choice {
        id: langChoice
        label: sv.app.tr("Language", "Idioma")
        icon: "language"
        value: sv.app.lang === "pt-BR" ? "Português" : "English"
        onClicked: sv.win.menuAt(langChoice, [
          { label: "Português (Brasil)", checked: sv.app.lang === "pt-BR", action: function() { sv.app.setSetting("lang", "pt-BR") } },
          { label: "English", checked: sv.app.lang !== "pt-BR", action: function() { sv.app.setSetting("lang", "en") } }
        ], width - sv.t.sp(220), height)
      }
      Choice {
        label: sv.app.tr("Clock", "Relógio")
        icon: "clock"
        value: sv.app.clock24 ? "24h" : "12h"
        onClicked: sv.app.setSetting("clock", sv.app.clock24 ? "12h" : "24h")
      }
      // New versions (core/Updater.qml): the background checks, and this
      // version, a click looks now (or updates, when one is waiting).
      Toggle {
        label: sv.app.tr("Check for updates", "Procurar atualizações")
        sub: sv.app.tr("A notice on top of the chats when GitHub has a new version", "Um aviso no topo das conversas quando houver versão nova no GitHub")
        on: sv.app.updater.auto
        onToggled: value => sv.app.setSetting("updateCheck", value)
      }
      Choice {
        readonly property var up: sv.app.updater
        label: up.phase === "available" ? sv.app.tr("Update to ", "Atualizar para a versão ") + up.latest
             : up.phase === "updating" ? sv.app.tr("Updating…", "Atualizando…")
             : up.phase === "updated" ? sv.app.tr("Restart the shell to update", "Reinicie o shell para atualizar")
             : up.checking ? sv.app.tr("Checking for updates…", "Procurando atualizações…")
             : sv.app.tr("Check now", "Procurar agora")
        icon: up.phase !== "" ? "download" : "refresh"
        value: up.version ? "v" + up.version : ""
        onClicked: up.phase !== "" ? up.update() : up.check(true)
      }
      Choice {
        label: sv.app.tr("Keyboard shortcuts", "Atalhos do teclado")
        icon: "keyboard"
        onClicked: sv.win.dialog("shortcuts")
      }
      Choice {
        label: sv.app.tr("Linked device", "Aparelho conectado")
        icon: "laptop"
        value: sv.wa.conn === "ready" ? sv.app.tr("connected", "conectado") : sv.app.tr("offline", "desconectado")
        onClicked: {}
      }
      Choice {
        label: sv.app.tr("Log out", "Desconectar")
        icon: "logout"
        danger: true
        onClicked: sv.win.dialog("logout")
      }
    }
  }
}
