import QtQuick
import "../lib/Registry.js" as Reg

// What the right side shows with no chat open, as WhatsApp Web's welcome:
// a picture, a few words, shortcuts to start, and the encryption note.
Rectangle {
  id: intro
  property var app: Reg.service
  readonly property var t: app.theme
  color: t.chatBg

  Column {
    anchors.centerIn: parent
    anchors.verticalCenterOffset: -intro.t.sp(20)
    spacing: intro.t.sp(18)
    width: Math.min(intro.width - intro.t.sp(80), intro.t.sp(520))

    // A laptop and a phone, in the theme's colors.
    Item {
      anchors.horizontalCenter: parent.horizontalCenter
      width: intro.t.sp(220)
      height: intro.t.sp(150)
      Rectangle {
        anchors.centerIn: parent
        width: intro.t.sp(190); height: width; radius: width / 2
        color: intro.t.alpha(intro.t.accent, 0.09)
      }
      Icon { anchors.centerIn: parent; anchors.horizontalCenterOffset: -intro.t.sp(18); name: "laptop"; size: intro.t.sp(130); color: intro.t.alpha(intro.t.accent, 0.85) }
      Rectangle {
        x: parent.width / 2 + intro.t.sp(34)
        y: intro.t.sp(52)
        width: intro.t.sp(46); height: intro.t.sp(80); radius: intro.t.sp(9)
        color: intro.t.chatBg
        border.width: intro.t.sp(4)
        border.color: intro.t.accent
        Icon { anchors.centerIn: parent; name: "chatFilled"; size: intro.t.sp(24); color: intro.t.accent }
      }
    }

    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      text: intro.app.tr("WhatsApp for Omarchy", "WhatsApp para Omarchy")
      color: intro.t.textBright
      font.family: intro.t.font
      font.pixelSize: intro.t.px(30)
      font.weight: Font.Light
    }
    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.Wrap
      lineHeight: 1.25
      text: intro.app.tr("Send and receive messages without keeping your phone online.\nUse WhatsApp on up to 4 linked devices and 1 phone at the same time.",
                         "Envie e receba mensagens sem precisar manter seu celular conectado.\nUse o WhatsApp em até 4 aparelhos conectados e 1 celular ao mesmo tempo.")
      color: intro.t.dim
      font.family: intro.t.font
      font.pixelSize: intro.t.fsText
    }

    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      topPadding: intro.t.sp(10)
      spacing: intro.t.sp(24)
      Repeater {
        model: [
          { icon: "newChat", label: intro.app.tr("New chat", "Nova conversa"), action: function() { intro.app.appWindow.openSide("newchat") } },
          { icon: "star", label: intro.app.tr("Starred", "Favoritas"), action: function() { intro.app.appWindow.openSide("starred") } },
          { icon: "settings", label: intro.app.tr("Settings", "Configurações"), action: function() { intro.app.appWindow.openSide("settings") } }
        ]
        delegate: Column {
          required property var modelData
          spacing: intro.t.sp(8)
          Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: intro.t.sp(56); height: width; radius: width / 2
            color: qa.containsMouse ? intro.t.hoverStrong : intro.t.chip
            Icon { anchors.centerIn: parent; name: modelData.icon; size: intro.t.sp(24); color: intro.t.text }
            MouseArea { id: qa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: modelData.action() }
          }
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: modelData.label
            color: intro.t.dim
            font.family: intro.t.font
            font.pixelSize: intro.t.fsSmall
          }
        }
      }
    }
  }

  Row {
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: intro.t.sp(36)
    spacing: intro.t.sp(6)
    Icon { name: "lock"; size: intro.t.sp(13); color: intro.t.faint; anchors.verticalCenter: parent.verticalCenter }
    Text {
      text: intro.app.tr("Your personal messages are end-to-end encrypted", "Suas mensagens pessoais são protegidas com a criptografia de ponta a ponta")
      color: intro.t.faint
      font.family: intro.t.font
      font.pixelSize: intro.t.fsSmall
    }
  }
}
