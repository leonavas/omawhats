import QtQuick
import QtQuick.Controls
import Quickshell
import "../lib/Util.js" as U
import "../lib/Registry.js" as Reg

// "New chat": your contacts on WhatsApp, by name (a letter over each
// group), the search over them, and a number typed in to message anyone.
Item {
  id: nc
  property var app: Reg.service
  property var win
  readonly property var t: app.theme
  readonly property var wa: app.wa

  Component.onCompleted: { nc.wa.loadContacts(); search.focusInput() }

  readonly property string query: search.text.trim()
  readonly property var rows: {
    var list = nc.wa.contacts || []
    var q = U.fold(nc.query)
    var digits = nc.query.replace(/\D/g, "")
    var out = []
    var me = nc.wa.me
    if (!q) {
      if (me) out.push({ key: "self", type: "self" })
      out.push({ key: "h-contacts", type: "header", label: nc.app.tr("Contacts on WhatsApp", "Contatos no WhatsApp") })
    }
    var letter = ""
    for (var i = 0; i < list.length; i++) {
      var p = list[i]
      if (q && U.fold(p.name).indexOf(q) < 0 && !(digits.length >= 3 && p.phone.indexOf(digits) >= 0)) continue
      if (!q) {
        var l = U.fold(p.name).charAt(0).toUpperCase()
        if (!/[A-Z]/.test(l)) l = "#"
        if (l !== letter) { letter = l; out.push({ key: "l-" + l, type: "letter", label: l }) }
      }
      out.push({ key: p.jid, type: "contact", p: p })
    }
    // A number nobody saved: message it anyway (WhatsApp checks it).
    if (digits.length >= 8 && nc.query.replace(/[\d\s()+-]/g, "") === "") {
      var full = digits.length <= 11 ? "55" + digits : digits
      out.unshift({ key: "number", type: "number", jid: full + "@s.whatsapp.net", phone: full })
    }
    return out
  }

  SubHeader {
    id: head
    title: nc.app.tr("New chat", "Nova conversa")
    onBack: nc.win.sideView = "chats"
  }
  SearchPill {
    id: search
    x: nc.t.sp(14)
    y: head.height
    width: parent.width - nc.t.sp(28)
    placeholder: nc.app.tr("Search name or number", "Pesquisar nome ou número")
    onEscaped: nc.win.sideView = "chats"
    onAccepted: { for (var i = 0; i < nc.rows.length; i++) if (nc.rows[i].type === "contact" || nc.rows[i].type === "number") { nc.start(nc.rows[i].p ? nc.rows[i].p.jid : nc.rows[i].jid); return } }
  }

  ListView {
    id: list
    y: search.y + search.height + nc.t.sp(8)
    width: parent.width
    height: parent.height - y
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    model: ScriptModel { values: nc.rows; objectProp: "key" }
    ScrollBar.vertical: ThinScroll { app: nc.app }
    delegate: Loader {
      required property var modelData
      property var row: modelData
      width: list.width
      sourceComponent: modelData.type === "header" || modelData.type === "letter" ? headC : modelData.type === "self" ? selfC : modelData.type === "number" ? numberC : contactC
    }
    BusyIndicator {
      anchors.centerIn: parent
      running: nc.wa.contacts === null
      visible: running
    }
  }

  function start(jid) {
    nc.win.sideView = "chats"
    nc.wa.open(jid)
    Qt.callLater(nc.win.focusComposer)
  }

  Component {
    id: headC
    Text {
      textFormat: Text.PlainText
      height: nc.t.sp(parent.row.type === "letter" ? 44 : 52)
      leftPadding: nc.t.sp(28)
      verticalAlignment: Text.AlignVCenter
      text: parent.row.label
      color: parent.row.type === "letter" ? nc.t.dim : nc.t.accent
      font.family: nc.t.font
      font.pixelSize: nc.t.fsText
    }
  }
  Component {
    id: selfC
    PersonRow {
      app: nc.app
      jid: nc.wa.me.jid
      name: (nc.wa.me.name || U.phone(nc.wa.me.phone)) + nc.app.tr(" (You)", " (você)")
      sub: nc.app.tr("Message yourself", "Enviar mensagem para você")
      onClicked: nc.start(nc.wa.me.jid)
    }
  }
  Component {
    id: numberC
    PersonRow {
      app: nc.app
      icon: "person"
      name: U.phone(parent.row.phone)
      sub: nc.app.tr("Start a chat with this number", "Iniciar conversa com este número")
      onClicked: nc.start(parent.row.jid)
    }
  }
  Component {
    id: contactC
    PersonRow {
      app: nc.app
      jid: parent.row.p.jid
      name: parent.row.p.name
      sub: U.phone(parent.row.p.phone)
      onClicked: nc.start(parent.row.p.jid)
    }
  }
}
