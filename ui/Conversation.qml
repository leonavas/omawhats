import QtQuick
import "../lib/Util.js" as U
import "../lib/Labels.js" as L
import "../lib/Registry.js" as Reg

// The open chat, as WhatsApp Web's: the header (picture, name, online or
// typing, search and menu), the messages over the doodled background,
// and the message box, or the bar of what's selected. Files dropped on it
// go to the preview before sending.
Item {
  id: conv
  property var app: Reg.service
  property var win
  property string chat: ""
  readonly property var t: app.theme
  readonly property var wa: app.wa
  readonly property var c: wa.chat(chat)
  readonly property bool group: chat.indexOf("@g.us") > 0 || (!!c && c.kind === "group")
  readonly property var info: wa.profile(chat)

  // Selecting messages (to delete, forward or star them together).
  property bool selecting: false
  property var selected: ({})
  property int selectedRev: 0
  readonly property int selectedCount: { conv.selectedRev; return Object.keys(conv.selected).length }
  function toggleSelect(m) {
    var s = conv.selected
    if (s[m.id]) delete s[m.id]
    else s[m.id] = m
    conv.selectedRev++
    if (!conv.selecting) conv.selecting = true
  }
  function endSelect() { conv.selecting = false; conv.selected = ({}); conv.selectedRev++ }

  // The message you're answering, or editing.
  property var replyTo: null
  property var editing: null
  onChatChanged: { conv.replyTo = null; conv.editing = null; conv.endSelect() }

  function focusComposer() { composer.focusInput() }
  function reply(m) { conv.editing = null; conv.replyTo = m; composer.focusInput() }
  function startEdit(m) { conv.replyTo = null; conv.editing = m; composer.startEdit(m) }

  Component.onCompleted: { if (conv.group || !conv.info) conv.wa.askProfile(conv.chat) }

  // ------------------------------------------------------------ background
  Rectangle { anchors.fill: parent; color: conv.t.chatBg }
  Image {
    anchors.fill: parent
    visible: conv.app.doodleOn
    source: Qt.resolvedUrl(conv.t.dark ? "../assets/doodle-white.png" : "../assets/doodle-black.png")
    fillMode: Image.Tile
    // The tile at WhatsApp's own size, 374 × 666 points.
    sourceSize.width: 374
    sourceSize.height: 666
    horizontalAlignment: Image.AlignLeft
    verticalAlignment: Image.AlignTop
    opacity: conv.t.doodleAlpha * (conv.t.dark ? 1 : 1.2)
    smooth: true
    cache: true
    asynchronous: true
  }

  // ------------------------------------------------------------ header
  Rectangle {
    id: header
    width: parent.width
    height: conv.t.headerHeight + conv.t.sp(4)
    color: conv.t.header
    z: 10
    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: conv.t.line }

    Avatar {
      id: pic
      x: conv.t.sp(16)
      anchors.verticalCenter: parent.verticalCenter
      size: conv.t.avatarHeader
      jid: conv.chat
      name: conv.wa.chatName(conv.c) || conv.wa.nameOf(conv.chat)
      group: conv.group
    }
    Column {
      anchors.left: pic.right
      anchors.leftMargin: conv.t.sp(14)
      anchors.right: tools.left
      anchors.rightMargin: conv.t.sp(10)
      anchors.verticalCenter: parent.verticalCenter
      spacing: conv.t.sp(1)
      Row {
        width: parent.width
        spacing: conv.t.sp(4)
        Text {
          id: title
          width: Math.min(implicitWidth, parent.width - (badge.visible ? badge.width + 4 : 0))
          text: conv.c ? conv.wa.chatName(conv.c) : conv.wa.nameOf(conv.chat)
          color: conv.t.textBright
          font.family: conv.t.font
          font.pixelSize: conv.t.fsName
          font.weight: Font.Medium
          elide: Text.ElideRight
          textFormat: Text.PlainText
        }
        Icon { id: badge; visible: !!conv.c && !!conv.c.verified; name: "verified"; size: conv.t.sp(16); color: conv.t.blue; anchors.verticalCenter: title.verticalCenter }
      }
      Text {
        width: parent.width
        visible: text !== ""
        text: conv.subtitle
        color: conv.typing ? conv.t.accent : conv.t.dim
        font.family: conv.t.font
        font.pixelSize: conv.t.fsSmall + 1
        elide: Text.ElideRight
        textFormat: Text.PlainText
      }
    }
    MouseArea {
      anchors.left: parent.left
      anchors.right: tools.left
      height: parent.height
      cursorShape: Qt.PointingHandCursor
      onClicked: conv.win.toggleInfo()
    }
    Row {
      id: tools
      anchors.right: parent.right
      anchors.rightMargin: conv.t.sp(14)
      anchors.verticalCenter: parent.verticalCenter
      spacing: conv.t.sp(6)
      IconButton {
        icon: "search"
        tip: conv.app.tr("Search", "Pesquisar")
        active: conv.win.infoOpen && conv.win.infoView === "search"
        onClicked: conv.win.openInfo("search")
      }
      IconButton {
        id: menuBtn
        icon: "more"
        rotationAngle: 90
        tip: conv.app.tr("Menu", "Mais opções")
        onClicked: conv.win.menuAt(menuBtn, conv.menuItems(), -conv.t.sp(200), menuBtn.height)
      }
    }
  }

  readonly property var typing: wa.typingIn(chat)
  readonly property string subtitle: {
    var tr = conv.app.tr
    var tp = conv.typing
    if (tp) {
      var verb = tp.state === "recording" ? tr("recording audio…", "gravando áudio…") : tr("typing…", "digitando…")
      if (conv.group && tp.who) return tp.who.replace(/^~/, "") + tr(" is ", " está ") + verb
      return verb
    }
    if (conv.group) {
      var p = conv.info
      if (p && p.members && p.members.length) {
        var names = p.members.map(function(x) { return x.me ? tr("You", "Você") : (x.name || (x.push ? "~" + x.push : U.phone(x.phone))) })
        return names.join(", ")
      }
      return tr("click here for group info", "clique para mostrar os dados do grupo")
    }
    if (conv.c && conv.c.kind === "self") return tr("Message yourself", "Mande mensagens para você")
    if (conv.c && conv.c.kind === "official") return tr("Official WhatsApp account", "Conta oficial do WhatsApp")
    conv.wa.presenceRev
    var pr = conv.wa.presence[conv.chat]
    if (pr && pr.online) return "online"
    if (pr && pr.last_seen) return U.lastSeen(pr.last_seen, conv.app.lang, conv.app.clock24)
    return tr("click here for contact info", "clique para mostrar os dados do contato")
  }

  function menuItems() {
    var tr = conv.app.tr
    var c = conv.c
    var items = [
      { label: conv.group ? tr("Group info", "Dados do grupo") : tr("Contact info", "Dados do contato"), icon: "info", action: function() { conv.win.openInfo("") } },
      { label: tr("Select messages", "Selecionar mensagens"), icon: "select", action: function() { conv.selecting = true } }
    ]
    if (c) {
      var muted = conv.wa.isMuted(c)
      items.push(muted ? { label: tr("Unmute notifications", "Reativar notificações"), icon: "bell", action: function() { conv.wa.chatAction(c.jid, "unmute") } }
                       : { label: tr("Mute notifications", "Silenciar notificações"), icon: "muted", sub: [
                           { label: tr("8 hours", "8 horas"), action: function() { conv.wa.chatAction(c.jid, "mute", 8 * 3600) } },
                           { label: tr("1 week", "1 semana"), action: function() { conv.wa.chatAction(c.jid, "mute", 7 * 86400) } },
                           { label: tr("Always", "Sempre"), action: function() { conv.wa.chatAction(c.jid, "mute", 0) } } ] })
      items.push(c.fav > 0 ? { label: tr("Remove from Favorites", "Remover das Favoritas"), icon: "heartFilled", action: function() { conv.wa.chatAction(c.jid, "unfavorite") } }
                           : { label: tr("Add to Favorites", "Adicionar às Favoritas"), icon: "heart", action: function() { conv.wa.chatAction(c.jid, "favorite") } })
    }
    items.push({ label: tr("Close chat", "Fechar conversa"), icon: "close", action: function() { conv.wa.close() } })
    items.push({ separator: true })
    items.push({ label: tr("Clear chat", "Limpar conversa"), icon: "nosign", action: function() { conv.win.dialog("clearChat", { chat: conv.chat }) } })
    items.push({ label: tr("Delete chat", "Apagar conversa"), icon: "delete", danger: true, action: function() { conv.win.dialog("deleteChat", { chat: conv.chat }) } })
    return items
  }

  // ------------------------------------------------------------ messages
  MessageList {
    id: list
    app: conv.app
    win: conv.win
    view: conv
    chat: conv.chat
    y: header.height
    width: parent.width
    height: bottom.y - y
  }

  // ------------------------------------------------------------ bottom
  Item {
    id: bottom
    width: parent.width
    height: conv.selecting ? selectBar.height : (readOnly.visible ? readOnly.height : composer.height)
    y: parent.height - height

    Composer {
      id: composer
      visible: !conv.selecting && !readOnly.visible
      width: parent.width
      app: conv.app
      win: conv.win
      view: conv
      chat: conv.chat
    }

    Rectangle {
      id: readOnly
      visible: !conv.selecting && !!conv.c && !!conv.c.ro
      width: parent.width
      height: conv.t.sp(64)
      color: conv.t.panel
      Text {
        textFormat: Text.PlainText
        anchors.centerIn: parent
        width: parent.width - conv.t.sp(40)
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: conv.c && conv.c.ro ? L.error("read_only_" + conv.c.ro, conv.app.lang) : ""
        color: conv.t.dim
        font.family: conv.t.font
        font.pixelSize: conv.t.fsText
      }
    }

    Rectangle {
      id: selectBar
      visible: conv.selecting
      width: parent.width
      height: conv.t.sp(62)
      color: conv.t.panel
      Rectangle { width: parent.width; height: 1; color: conv.t.line }
      IconButton {
        id: endBtn
        x: conv.t.sp(16)
        anchors.verticalCenter: parent.verticalCenter
        icon: "close"
        onClicked: conv.endSelect()
      }
      Text {
        textFormat: Text.PlainText
        anchors.left: endBtn.right
        anchors.leftMargin: conv.t.sp(16)
        anchors.verticalCenter: parent.verticalCenter
        text: conv.selectedCount === 1 ? conv.app.tr("1 selected", "1 selecionada") : conv.app.tr(conv.selectedCount + " selected", conv.selectedCount + " selecionadas")
        color: conv.t.text
        font.family: conv.t.font
        font.pixelSize: conv.t.fsName
      }
      Row {
        anchors.right: parent.right
        anchors.rightMargin: conv.t.sp(20)
        anchors.verticalCenter: parent.verticalCenter
        spacing: conv.t.sp(10)
        readonly property var msgs: { conv.selectedRev; var out = []; for (var k in conv.selected) out.push(conv.selected[k]); return out }
        IconButton {
          icon: "star"
          tip: conv.app.tr("Star", "Favoritar")
          enabledState: parent.msgs.length > 0
          onClicked: { var all = parent.msgs.every(function(m) { return m.star }); conv.wa.star(conv.chat, parent.msgs.map(function(m) { return m.id }), !all); conv.endSelect() }
        }
        IconButton {
          icon: "delete"
          tip: conv.app.tr("Delete", "Apagar")
          enabledState: parent.msgs.length > 0
          onClicked: conv.win.dialog("deleteMsgs", { chat: conv.chat, msgs: parent.msgs, done: conv.endSelect })
        }
        IconButton {
          icon: "forward"
          tip: conv.app.tr("Forward", "Encaminhar")
          enabledState: parent.msgs.length > 0
          onClicked: conv.win.dialog("forward", { chat: conv.chat, msgs: parent.msgs, done: conv.endSelect })
        }
      }
    }
  }

  // ------------------------------------------------------------ dropped files
  DropArea {
    anchors.fill: parent
    keys: ["text/uri-list"]
    onEntered: drag => { if (!conv.c || !conv.c.ro) dropHint.visible = true }
    onExited: dropHint.visible = false
    onDropped: drop => {
      dropHint.visible = false
      if (!drop.hasUrls || (conv.c && conv.c.ro)) return
      var files = drop.urls.map(function(u) { return U.unfileUrl(String(u)) })
      conv.win.dialog("sendFiles", { chat: conv.chat, files: files, reply: conv.replyTo ? conv.replyTo.id : "" })
      conv.replyTo = null
    }
  }
  Rectangle {
    id: dropHint
    visible: false
    anchors.fill: parent
    anchors.topMargin: header.height
    color: conv.t.alpha(conv.t.panel, 0.92)
    Column {
      anchors.centerIn: parent
      spacing: conv.t.sp(14)
      Icon { anchors.horizontalCenter: parent.horizontalCenter; name: "attach"; size: conv.t.sp(56); color: conv.t.accent }
      Text { textFormat: Text.PlainText; text: conv.app.tr("Drop files here", "Solte os arquivos aqui"); color: conv.t.text; font.family: conv.t.font; font.pixelSize: conv.t.px(20) }
    }
  }
}
