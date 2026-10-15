import QtQuick
import QtQuick.Controls
import "../lib/Util.js" as U
import "../lib/Registry.js" as Reg

// Your profile, as WhatsApp Web shows it: the photo, your name, your
// about and your number.
Item {
  id: pv
  property var app: Reg.service
  property var win
  readonly property var t: app.theme
  readonly property var wa: app.wa
  readonly property string jid: wa.me ? wa.me.jid : ""
  readonly property var info: jid ? wa.profile(jid) : null

  Component.onCompleted: if (pv.jid) pv.wa.askProfile(pv.jid)

  component Field: Column {
    property string label: ""
    property string value: ""
    property string note: ""
    x: pv.t.sp(30)
    width: parent ? parent.width - pv.t.sp(60) : 0
    spacing: pv.t.sp(10)
    topPadding: pv.t.sp(14)
    bottomPadding: pv.t.sp(14)
    Text { text: parent.label; color: pv.t.accent; font.family: pv.t.font; font.pixelSize: pv.t.fsText }
    Text { width: parent.width; text: parent.value; color: pv.t.text; font.family: pv.t.font; font.pixelSize: pv.t.fsName; wrapMode: Text.Wrap; textFormat: Text.PlainText }
    Text { width: parent.width; visible: parent.note !== ""; text: parent.note; color: pv.t.dim; font.family: pv.t.font; font.pixelSize: pv.t.fsSmall + 1; wrapMode: Text.Wrap }
  }

  SubHeader {
    id: head
    title: pv.app.tr("Profile", "Perfil")
    onBack: pv.win.sideView = "chats"
  }
  Flickable {
    y: head.height
    width: parent.width
    height: parent.height - y
    contentHeight: col.implicitHeight + pv.t.sp(30)
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    Column {
      id: col
      width: parent.width
      Item {
        width: parent.width
        height: pv.t.sp(250)
        Avatar {
          anchors.centerIn: parent
          size: pv.t.sp(200)
          jid: pv.jid
          name: pv.wa.me ? pv.wa.me.name : ""
          source: pv.info && pv.info.photo ? pv.info.photo : ""
        }
      }
      Field {
        label: pv.app.tr("Your name", "Seu nome")
        value: pv.wa.me ? pv.wa.me.name || "" : ""
        note: pv.app.tr("This is not your username or PIN. This name will be visible to your WhatsApp contacts. Change it on your phone.",
                        "Esse não é seu nome de usuário nem seu PIN. Esse nome será visível para seus contatos do WhatsApp. Altere-o no celular.")
      }
      Field {
        label: pv.app.tr("About", "Recado")
        value: pv.info && pv.info.about ? pv.info.about : "…"
      }
      Field {
        label: pv.app.tr("Phone", "Telefone")
        value: pv.wa.me ? U.phone(pv.wa.me.phone) : ""
      }
    }
  }
}
