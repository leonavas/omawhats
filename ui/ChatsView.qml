import QtQuick
import QtQuick.Controls
import Quickshell
import "../lib/Util.js" as U
import "../lib/Registry.js" as Reg

// The chat list, as WhatsApp Web's side panel: "WhatsApp" with its new
// chat and menu buttons, the search pill, the filter chips, the notices
// (offline, paused, syncing), Archived, and the chats. With a query: the
// chats, contacts and messages that match. `archived` makes it the
// Archived view.
Item {
  id: cv
  property var app: Reg.service
  property var win
  property bool archived: false
  readonly property var t: app.theme
  readonly property var wa: app.wa

  property string filter: "all"   // all, unread, favorites, groups
  readonly property string query: search.text.trim()

  function focusSearch() { search.focusInput() }

  readonly property var rows: {
    var list = cv.wa.chatList
    var f = cv.filter
    var q = U.fold(cv.query)
    var digits = cv.query.replace(/\D/g, "")
    var out = []
    for (var i = 0; i < list.length; i++) {
      var c = list[i]
      if (q) {
        var name = U.fold(cv.wa.chatName(c))
        if (name.indexOf(q) < 0 && !(digits.length >= 3 && String(c.phone || "").indexOf(digits) >= 0)) continue
        if (!!c.archived !== cv.archived && !cv.archived) { /* search finds archived ones too */ }
        out.push(c)
        continue
      }
      if (!!c.archived !== cv.archived) continue
      if (!cv.archived) {
        if (f === "unread" && !(c.unread > 0 || c.marked || c.jid === cv.wa.current)) continue
        if (f === "favorites" && !(c.fav > 0)) continue
        if (f === "groups" && c.kind !== "group") continue
      }
      out.push(c)
    }
    return out
  }
  readonly property int archivedCount: {
    cv.wa.chatsRev
    var n = 0, unread = 0
    for (var k in cv.wa.chatMap) { var c = cv.wa.chatMap[k]; if (c.archived) { n++; if (c.unread > 0 || c.marked) unread++ } }
    return n
  }
  readonly property int archivedUnread: {
    cv.wa.chatsRev
    var unread = 0
    for (var k in cv.wa.chatMap) { var c = cv.wa.chatMap[k]; if (c.archived && !cv.wa.isMuted(c) && (c.unread > 0 || c.marked)) unread++ }
    return unread
  }
  readonly property int unreadChats: {
    cv.wa.chatsRev
    var n = 0
    for (var k in cv.wa.chatMap) { var c = cv.wa.chatMap[k]; if (!c.archived && (c.unread > 0 || c.marked)) n++ }
    return n
  }

  // The bridge's side of a search: contacts without a chat and messages.
  Timer { id: searchSoon; interval: 260; onTriggered: if (cv.query) cv.wa.doSearch(cv.query) }
  onQueryChanged: { if (cv.query) searchSoon.restart(); else cv.wa.search = null }
  readonly property var found: cv.wa.search && cv.wa.search.query === cv.query ? cv.wa.search : null

  // ------------------------------------------------------------ header
  Item {
    id: header
    width: parent.width
    height: cv.t.sp(64)
    visible: !cv.archived
    Text {
      textFormat: Text.PlainText
      x: cv.t.sp(20)
      anchors.verticalCenter: parent.verticalCenter
      text: "WhatsApp"
      color: cv.t.textBright
      font.family: cv.t.font
      font.pixelSize: cv.t.fsHeader
      font.weight: Font.Bold
    }
    Row {
      anchors.right: parent.right
      anchors.rightMargin: cv.t.sp(12)
      anchors.verticalCenter: parent.verticalCenter
      spacing: cv.t.sp(4)
      IconButton {
        icon: "newChat"
        tip: cv.app.tr("New chat", "Nova conversa")
        onClicked: cv.win.sideView = "newchat"
      }
      IconButton {
        id: menuBtn
        icon: "more"
        rotationAngle: 90
        tip: cv.app.tr("Menu", "Mais opções")
        onClicked: cv.win.menuAt(menuBtn, [
          { label: cv.app.tr("Starred messages", "Mensagens favoritas"), icon: "star", action: function() { cv.win.sideView = "starred" } },
          { label: cv.app.tr("Mark all as read", "Marcar todas como lidas"), icon: "markRead", enabled: cv.unreadChats > 0, action: function() {
              for (var k in cv.wa.chatMap) { var c = cv.wa.chatMap[k]; if (c.unread > 0 || c.marked) cv.wa.chatAction(c.jid, "read") } } },
          { label: cv.app.tr("Settings", "Configurações"), icon: "settings", action: function() { cv.win.sideView = "settings" } },
          { separator: true },
          { label: cv.app.tr("Log out", "Desconectar"), icon: "logout", danger: true, action: function() { cv.win.dialog("logout") } }
        ], -cv.t.sp(150), menuBtn.height)
      }
    }
  }
  SubHeader {
    visible: cv.archived
    title: cv.app.tr("Archived", "Arquivadas")
    onBack: cv.win.sideView = "chats"
  }

  SearchPill {
    id: search
    x: cv.t.sp(14)
    y: cv.t.sp(64)
    width: parent.width - cv.t.sp(28)
    visible: !cv.archived
    placeholder: cv.app.tr("Search or start a new chat", "Pesquisar ou começar uma nova conversa")
    onAccepted: { if (cv.rows.length) cv.openChat(cv.rows[0].jid) }
    onDownPressed: list.forceActiveFocus()
  }

  Flow {
    id: chips
    x: cv.t.sp(14)
    y: search.y + search.height + cv.t.sp(10)
    width: parent.width - cv.t.sp(28)
    spacing: cv.t.sp(8)
    visible: !cv.archived && cv.query === ""
    Chip { label: cv.app.tr("All", "Tudo"); on: cv.filter === "all"; onClicked: cv.filter = "all" }
    Chip { label: cv.app.tr("Unread", "Não lidas"); count: cv.unreadChats; on: cv.filter === "unread"; onClicked: cv.filter = cv.filter === "unread" ? "all" : "unread" }
    Chip { label: cv.app.tr("Favorites", "Favoritas"); on: cv.filter === "favorites"; onClicked: cv.filter = cv.filter === "favorites" ? "all" : "favorites" }
    Chip { label: cv.app.tr("Groups", "Grupos"); on: cv.filter === "groups"; onClicked: cv.filter = cv.filter === "groups" ? "all" : "groups" }
  }

  readonly property real listTop: cv.archived ? cv.t.sp(64) : (chips.visible ? chips.y + chips.height + cv.t.sp(8) : search.y + search.height + cv.t.sp(8))

  // ------------------------------------------------------------ list
  ListView {
    id: list
    y: cv.listTop
    width: parent.width
    height: parent.height - y
    clip: true
    visible: cv.query === ""
    boundsBehavior: Flickable.StopAtBounds
    cacheBuffer: cv.t.sp(800)
    reuseItems: true
    model: ScriptModel { values: cv.rows; objectProp: "jid" }
    ScrollBar.vertical: ThinScroll { app: cv.app }
    keyNavigationEnabled: true
    // The wheel / touchpad, further than Qt's.
    WheelScroll { view: list; step: cv.t.sp(130) }

    header: Column {
      width: list.width
      Notices { app: cv.app; win: cv.win; visible: !cv.archived; width: parent.width }
      // Archived, on top of the list.
      Item {
        visible: !cv.archived && cv.archivedCount > 0 && cv.filter === "all"
        width: parent.width
        height: visible ? cv.t.sp(50) : 0
        Rectangle {
          anchors.fill: parent
          anchors.leftMargin: cv.t.sp(10)
          anchors.rightMargin: cv.t.sp(10)
          radius: cv.t.sp(10)
          color: ama.containsMouse ? cv.t.hover : "transparent"
        }
        Icon { x: cv.t.sp(32); anchors.verticalCenter: parent.verticalCenter; name: "archive"; size: cv.t.sp(22); color: cv.t.accent }
        Text {
          textFormat: Text.PlainText
          x: cv.t.sp(84)
          anchors.verticalCenter: parent.verticalCenter
          text: cv.app.tr("Archived", "Arquivadas")
          color: cv.t.text
          font.family: cv.t.font
          font.pixelSize: cv.t.fsName
        }
        Text {
          textFormat: Text.PlainText
          anchors.right: parent.right
          anchors.rightMargin: cv.t.sp(28)
          anchors.verticalCenter: parent.verticalCenter
          visible: cv.archivedUnread > 0
          text: cv.archivedUnread
          color: cv.t.accent
          font.family: cv.t.font
          font.pixelSize: cv.t.fsSmall
          font.weight: Font.DemiBold
        }
        MouseArea { id: ama; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: cv.win.sideView = "archived" }
      }
      Text {
        textFormat: Text.PlainText
        visible: cv.archived
        width: parent.width
        padding: cv.t.sp(20)
        wrapMode: Text.Wrap
        horizontalAlignment: Text.AlignHCenter
        text: cv.app.tr("These chats stay archived when new messages are received. To change this setting, go to Settings > Chats on your phone.",
                        "Essas conversas continuam arquivadas quando você recebe novas mensagens. Para mudar essa configuração, acesse Configurações > Conversas no seu celular.")
        color: cv.t.dim
        font.family: cv.t.font
        font.pixelSize: cv.t.fsSmall
      }
    }

    delegate: ChatRow {
      required property var modelData
      width: list.width
      app: cv.app
      win: cv.win
      c: modelData
      onOpen: cv.openChat(modelData.jid)
    }

    footer: Item {
      width: list.width
      height: cv.t.sp(90)
      Row {
        anchors.centerIn: parent
        spacing: cv.t.sp(6)
        visible: cv.wa.everReady && list.count > 0
        Icon { name: "lock"; size: cv.t.sp(12); color: cv.t.faint; anchors.verticalCenter: parent.verticalCenter }
        Text {
          textFormat: Text.PlainText
          text: cv.app.tr("Your personal messages are ", "Suas mensagens pessoais são ")
          color: cv.t.faint; font.family: cv.t.font; font.pixelSize: cv.t.fsSmall
        }
        Text {
          textFormat: Text.PlainText
          text: cv.app.tr("end-to-end encrypted", "protegidas com a criptografia de ponta a ponta")
          color: cv.t.accent; font.family: cv.t.font; font.pixelSize: cv.t.fsSmall
        }
      }
    }

    // Empty filters say so.
    Text {
      textFormat: Text.PlainText
      anchors.centerIn: parent
      width: parent.width - cv.t.sp(60)
      visible: list.count === 0 && cv.wa.everReady && cv.filter !== "all"
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.Wrap
      text: cv.filter === "unread" ? cv.app.tr("No unread chats", "Nenhuma conversa não lida")
          : cv.filter === "favorites" ? cv.app.tr("Add people or groups to your favorites from a chat's menu", "Adicione pessoas ou grupos às Favoritas pelo menu de uma conversa")
          : cv.app.tr("No groups", "Nenhum grupo")
      color: cv.t.dim
      font.family: cv.t.font
      font.pixelSize: cv.t.fsText
    }
  }

  // ------------------------------------------------------------ search results
  SearchResults {
    y: cv.listTop
    width: parent.width
    height: parent.height - y
    visible: cv.query !== ""
    app: cv.app
    win: cv.win
    query: cv.query
    chats: cv.rows
    found: cv.found
    onOpenChat: (jid, msg) => { cv.openChat(jid, msg); search.clearText() }
  }

  function openChat(jid, msg) {
    cv.wa.open(jid, { msg: msg || "" })
    if (cv.archived && cv.wa.chat(jid) && !cv.wa.chat(jid).archived) cv.win.sideView = "chats"
    Qt.callLater(cv.win.focusComposer)
  }
}
