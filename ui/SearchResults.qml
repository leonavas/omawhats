import QtQuick
import QtQuick.Controls
import Quickshell
import "../lib/Util.js" as U
import "../lib/Format.js" as F
import "../lib/Labels.js" as L
import "../lib/Registry.js" as Reg

// What the side panel's search found, as WhatsApp Web lists it: Chats,
// Contacts (people you have no chat with yet), Messages; a phone number
// that is on WhatsApp can be messaged right away.
Item {
  id: sr
  property var app: Reg.service
  property var win
  property string query: ""
  property var chats: []
  property var found: null
  readonly property var t: app.theme
  readonly property var wa: app.wa
  signal openChat(string jid, string msg)

  readonly property var rows: {
    var out = []
    var tr = sr.app.tr
    if (sr.found && sr.found.number && sr.found.number.exists && !sr.wa.chat(sr.found.number.jid))
      out.push({ key: "number", type: "number", n: sr.found.number })
    if (sr.chats.length) {
      out.push({ key: "h-chats", type: "header", label: tr("Chats", "Conversas") })
      sr.chats.slice(0, 50).forEach(function(c) { out.push({ key: "c-" + c.jid, type: "chat", c: c }) })
    }
    var contacts = sr.found ? sr.found.contacts || [] : []
    if (contacts.length) {
      out.push({ key: "h-contacts", type: "header", label: tr("Contacts", "Contatos") })
      contacts.forEach(function(p) { out.push({ key: "p-" + p.jid, type: "contact", p: p }) })
    }
    var msgs = sr.found ? sr.found.messages || [] : []
    if (msgs.length) {
      out.push({ key: "h-msgs", type: "header", label: tr("Messages", "Mensagens") })
      msgs.forEach(function(m) { out.push({ key: "m-" + m.chat + m.id, type: "msg", m: m }) })
    }
    if (!out.length && sr.found) out.push({ key: "none", type: "none" })
    return out
  }

  ListView {
    id: list
    anchors.fill: parent
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    model: ScriptModel { values: sr.rows; objectProp: "key" }
    ScrollBar.vertical: ThinScroll { app: sr.app }
    delegate: Loader {
      required property var modelData
      width: list.width
      sourceComponent: modelData.type === "header" ? headerC : modelData.type === "chat" ? chatC : modelData.type === "contact" ? contactC
                     : modelData.type === "msg" ? msgC : modelData.type === "number" ? numberC : noneC
      property var row: modelData
    }
  }

  Component {
    id: headerC
    Text {
      textFormat: Text.PlainText
      height: sr.t.sp(52)
      leftPadding: sr.t.sp(28)
      verticalAlignment: Text.AlignVCenter
      text: parent.row.label
      color: sr.t.accent
      font.family: sr.t.font
      font.pixelSize: sr.t.fsText
    }
  }
  Component {
    id: chatC
    ChatRow { app: sr.app; win: sr.win; c: parent.row.c; onOpen: sr.openChat(c.jid, "") }
  }
  Component {
    id: contactC
    PersonRow {
      app: sr.app
      jid: parent.row.p.jid
      name: parent.row.p.name
      sub: U.phone(parent.row.p.phone)
      onClicked: sr.openChat(parent.row.p.jid, "")
    }
  }
  Component {
    id: numberC
    PersonRow {
      app: sr.app
      jid: parent.row.n.jid
      name: U.phone(parent.row.n.phone)
      sub: sr.app.tr("Message this number", "Conversar com este número")
      onClicked: sr.openChat(parent.row.n.jid, "")
    }
  }
  Component {
    id: noneC
    Text {
      textFormat: Text.PlainText
      width: parent.width
      padding: sr.t.sp(40)
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.Wrap
      text: sr.app.tr("No chats, contacts or messages found", "Nenhuma conversa, contato ou mensagem encontrada")
      color: sr.t.dim
      font.family: sr.t.font
      font.pixelSize: sr.t.fsText
    }
  }
  Component {
    id: msgC
    Item {
      id: mr
      readonly property var m: parent.row.m
      height: sr.t.sp(72)
      Rectangle {
        anchors.fill: parent
        anchors.leftMargin: sr.t.sp(10)
        anchors.rightMargin: sr.t.sp(10)
        radius: sr.t.sp(10)
        color: mma.containsMouse ? sr.t.hover : "transparent"
      }
      Column {
        x: sr.t.sp(28)
        width: parent.width - sr.t.sp(56)
        anchors.verticalCenter: parent.verticalCenter
        spacing: sr.t.sp(4)
        Item {
          width: parent.width
          height: chatName.implicitHeight
          Text {
            id: chatName
            textFormat: Text.PlainText
            width: parent.width - date.width - sr.t.sp(8)
            text: sr.wa.nameOf(mr.m.chat)
            color: sr.t.textBright
            font.family: sr.t.font
            font.pixelSize: sr.t.fsName
            elide: Text.ElideRight
          }
          Text {
            id: date
            textFormat: Text.PlainText
            anchors.right: parent.right
            text: U.listTime(mr.m.ts, sr.app.lang, sr.app.clock24)
            color: sr.t.dim
            font.family: sr.t.font
            font.pixelSize: sr.t.fsSmall
          }
        }
        Row {
          width: parent.width
          spacing: sr.t.sp(3)
          Ticks { visible: mr.m.from_me; status: mr.m.status; app: sr.app; anchors.verticalCenter: parent.verticalCenter }
          Text {
            width: parent.width - x
            textFormat: Text.StyledText
            elide: Text.ElideRight
            maximumLineCount: 1
            color: sr.t.dim
            font.family: sr.t.font
            font.pixelSize: sr.t.fsText
            text: {
              var plain = F.plain(mr.m.text, mr.m.mentions)
              var q = sr.query
              var at = U.fold(plain).indexOf(U.fold(q))
              var start = Math.max(0, at - 24)
              var piece = plain.slice(start)
              var who = !mr.m.from_me && mr.m.name && String(mr.m.chat).indexOf("@g.us") > 0 ? F.esc(mr.m.name.replace(/^~/, "")) + ": " : ""
              if (at < 0) return who + F.esc(piece)
              var rel = at - start
              return who + (start > 0 ? "…" : "") + F.esc(piece.slice(0, rel)) + "<font color=\"" + sr.t.hex(sr.t.accent) + "\">" + F.esc(piece.slice(rel, rel + q.length)) + "</font>" + F.esc(piece.slice(rel + q.length))
            }
          }
        }
      }
      MouseArea { id: mma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: sr.openChat(mr.m.chat, mr.m.id) }
    }
  }
}
