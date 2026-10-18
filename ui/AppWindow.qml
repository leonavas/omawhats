import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import "../lib/Util.js" as U
import "../lib/Registry.js" as Reg

// The WhatsApp window, laid out as WhatsApp Web: the rail of tabs on the
// left, the side panel (chats, archived, new chat, settings…), the open
// chat (or the welcome screen) and, when asked, the contact's or group's
// info on the right. Menus, dialogs, the emoji panel and the media viewer
// float over it. Before the phone is linked it's the QR screen.
FloatingWindow {
  id: appWin
  property var app: Reg.service
  // The views have their own copy of lib/Registry.js, not Service.qml's
  // (the window comes through a LazyLoader): the app goes in it from here,
  // before they read it.
  readonly property bool _registered: { if (appWin.app) Reg.service = appWin.app; return true }
  onAppChanged: if (appWin.app) Reg.service = appWin.app
  readonly property var t: app.theme
  readonly property var wa: app.wa

  // chats, archived, newchat, newgroup, settings, starred
  property string sideView: "chats"
  property bool infoOpen: false
  property string infoView: ""     // "", media, starred
  // Whose info the panel shows: "" for the open chat's, or a person's
  // picked in it (a sender's name or picture, a mention, a reaction).
  property string infoChat: ""
  property string searchChat: ""   // the chat whose messages are searched (the info side)
  // Your menu (the photo at the foot of the rail, Alt+S), whatsapp-tui's.
  property bool accountOpen: false
  readonly property bool menusShown: menus.shown

  // While a launch maps it, the one-time title its window rule looks for
  // (Service.launchWindow).
  title: app.launchTitle || (app.attention.chats > 0 ? "(" + app.attention.chats + ") " : "") + app.windowTitleBase
  visible: app.windowOpen
  implicitWidth: Math.round(app.setting("windowWidth", 1280))
  implicitHeight: Math.round(app.setting("windowHeight", 820))
  minimumSize: Qt.size(t.sp(760), t.sp(500))
  color: t.panel

  onClosed: app.hideWindow()
  onVisibleChanged: if (!visible) app.windowFocused = false

  // ---------------------------------------------------------------- api
  function menu(items, x, y) { menus.open(items, x, y) }
  function menuAt(item, items, dx, dy) {
    var p = item.mapToItem(root, dx || 0, dy === undefined ? item.height : dy)
    menus.open(items, p.x, p.y)
  }
  function dialog(name, args) { dialogs.show(name, args || {}) }
  function closeDialog() { dialogs.hide() }
  function viewMedia(m) { viewer.msg = m; viewer.active = true }
  function toast(text) { toastBox.show(text) }
  // Files picked in Omarchy's chooser (`omarchy-file-select`, the desktop
  // portal's), in its own process: Qt's FileDialog runs GTK's inside the
  // shell, and a GVfs hiccup there took the whole shell down.
  // `cb([paths])`; filter: "Name (*.a *.b)"; single: one file.
  function pickFiles(title, filter, cb, single) {
    if (picker.running) return
    var args = ["--title", title]
    if (!single) args.push("--multiple")
    var m = /\((.*)\)\s*$/.exec(filter || "")
    if (m) args.push("--extensions", m[1].split(/\s+/).map(function(g) { return g.replace(/^\*\./, "") }).filter(function(e) { return e }).join(" "))
    picker.cb = cb
    picker.command = ["sh", "-c", 'command -v omarchy-file-select >/dev/null 2>&1 || exit 127; exec omarchy-file-select "$@"', "pick"].concat(args)
    picker.running = true
  }
  function focusComposer() { if (main.item && main.item.focusComposer) main.item.focusComposer() }
  function focusSearch() { appWin.sideView = "chats"; if (side.item && side.item.focusSearch) side.item.focusSearch() }
  function openInfo(view) { appWin.infoChat = ""; appWin.infoView = view || ""; appWin.infoOpen = true }
  // Someone's info beside the conversation, as the TUI's: the chat's own
  // when it's the open one.
  function showProfile(jid) {
    if (!jid || jid === appWin.wa.current) { appWin.openInfo(""); return }
    appWin.infoChat = jid; appWin.infoView = ""; appWin.infoOpen = true
  }
  // The header's click: closes the chat's info, or shows it in place of someone's.
  function toggleInfo() {
    if (appWin.infoOpen && appWin.infoChat === "" && appWin.infoView === "") appWin.infoOpen = false
    else appWin.openInfo("")
  }
  function openSide(view) { appWin.sideView = view }
  function toggleAccount() { menus.close(); appWin.accountOpen = !appWin.accountOpen }

  // A chat's menu (its row's, or the chat header's).
  function chatMenu(c) {
    if (!c) return []
    var tr = appWin.app.tr
    var wa = appWin.wa
    var muted = wa.isMuted(c)
    var unread = c.unread > 0 || c.marked
    var items = []
    items.push(c.archived ? { label: tr("Unarchive chat", "Desarquivar conversa"), icon: "unarchive", action: function() { wa.chatAction(c.jid, "unarchive") } }
                          : { label: tr("Archive chat", "Arquivar conversa"), icon: "archive", action: function() { wa.chatAction(c.jid, "archive") } })
    items.push(muted ? { label: tr("Unmute notifications", "Reativar notificações"), icon: "bell", action: function() { wa.chatAction(c.jid, "unmute") } }
                     : { label: tr("Mute notifications", "Silenciar notificações"), icon: "muted", sub: [
                         { label: tr("8 hours", "8 horas"), action: function() { wa.chatAction(c.jid, "mute", 8 * 3600) } },
                         { label: tr("1 week", "1 semana"), action: function() { wa.chatAction(c.jid, "mute", 7 * 86400) } },
                         { label: tr("Always", "Sempre"), action: function() { wa.chatAction(c.jid, "mute", 0) } } ] })
    if (!c.archived)
      items.push(c.pin > 0 ? { label: tr("Unpin chat", "Desafixar conversa"), icon: "unpin", action: function() { wa.chatAction(c.jid, "unpin") } }
                           : { label: tr("Pin chat", "Fixar conversa"), icon: "pin", action: function() { wa.chatAction(c.jid, "pin") } })
    items.push(unread ? { label: tr("Mark as read", "Marcar como lida"), icon: "markRead", action: function() { wa.chatAction(c.jid, "read") } }
                      : { label: tr("Mark as unread", "Marcar como não lida"), icon: "unread", action: function() { wa.chatAction(c.jid, "unread") } })
    items.push(c.fav > 0 ? { label: tr("Remove from Favorites", "Remover das Favoritas"), icon: "heartFilled", action: function() { wa.chatAction(c.jid, "unfavorite") } }
                         : { label: tr("Add to Favorites", "Adicionar às Favoritas"), icon: "heart", action: function() { wa.chatAction(c.jid, "favorite") } })
    items.push({ separator: true })
    items.push({ label: tr("Clear chat", "Limpar conversa"), icon: "nosign", action: function() { appWin.dialog("clearChat", { chat: c.jid }) } })
    items.push({ label: tr("Delete chat", "Apagar conversa"), icon: "delete", danger: true, action: function() { appWin.dialog("deleteChat", { chat: c.jid }) } })
    return items
  }

  Connections {
    target: appWin.app
    function onDialogRequested(name, args) { appWin.dialog(name, args) }
  }
  Connections {
    target: appWin.wa
    function onCurrentChanged() { if (appWin.infoOpen && (appWin.infoView !== "media" || appWin.infoChat !== "")) appWin.infoOpen = false; appWin.infoChat = ""; appWin.searchChat = "" }
  }

  Item {
    id: root
    anchors.fill: parent
    focus: true

    // Esc that nothing else took: the info panel, a side view, the chat.
    Keys.onEscapePressed: {
      if (appWin.infoOpen) appWin.infoOpen = false
      else if (appWin.sideView !== "chats") appWin.sideView = "chats"
      else if (appWin.wa.current) appWin.wa.close()
    }

    readonly property bool active: Window.active
    // A window on its way into the scratchpad (a background launch) has the
    // focus for a moment: that is not you looking at it.
    onActiveChanged: appWin.app.windowFocused = active && appWin.visible && !appWin.app.stowing

    // ------------------------------------------------------------ not linked
    Loader {
      anchors.fill: parent
      active: !appWin.wa.linked
      sourceComponent: LoginView { app: appWin.app }
    }

    Item {
      id: shell
      anchors.fill: parent
      visible: appWin.wa.linked

      Rail {
        id: rail
        app: appWin.app
        win: appWin
        width: appWin.t.railWidth
        height: parent.height
      }
      Rectangle { x: rail.width; width: 1; height: parent.height; color: appWin.t.line }

      QtObject {
        id: sideWidth
        property int saved: Math.round(appWin.app.setting("sideWidth", 0))
        readonly property int value: saved > 0 ? Math.max(appWin.t.sp(300), Math.min(saved, Math.round(shell.width * 0.5)))
                                               : Math.max(appWin.t.sp(340), Math.min(Math.round((shell.width - rail.width) * 0.32), appWin.t.sp(480)))
      }

      Loader {
        id: side
        x: rail.width + 1
        width: sideWidth.value
        height: parent.height
        sourceComponent: SidePanel { app: appWin.app; win: appWin }
      }

      // The side panel's edge: drag to make it wider or narrower.
      MouseArea {
        id: grip
        x: side.x + side.width - 3
        width: 6
        height: parent.height
        z: 5
        hoverEnabled: true
        cursorShape: Qt.SplitHCursor
        property real startX: 0
        property int startW: 0
        onPressed: mouse => { startX = mapToItem(shell, mouse.x, 0).x; startW = sideWidth.value }
        onPositionChanged: mouse => {
          if (!pressed) return
          var nx = mapToItem(shell, mouse.x, 0).x
          sideWidth.saved = Math.round(Math.max(appWin.t.sp(300), Math.min(startW + (nx - startX), shell.width * 0.5)))
        }
        onReleased: appWin.app.setSetting("sideWidth", sideWidth.saved)
        onDoubleClicked: { sideWidth.saved = 0; appWin.app.setSetting("sideWidth", 0) }
      }
      Rectangle { x: side.x + side.width; width: 1; height: parent.height; color: grip.containsMouse || grip.pressed ? appWin.t.alpha(appWin.t.accent, 0.6) : appWin.t.line }

      Item {
        id: mainArea
        x: side.x + side.width + 1
        width: parent.width - x
        height: parent.height

        readonly property int infoWidth: Math.max(appWin.t.sp(340), Math.min(Math.round(width * 0.36), appWin.t.sp(460)))
        readonly property bool infoShown: appWin.infoOpen && appWin.wa.current !== ""

        Loader {
          id: main
          width: parent.width - (mainArea.infoShown ? mainArea.infoWidth + 1 : 0)
          height: parent.height
          sourceComponent: appWin.wa.current !== "" ? convC : introC
        }
        Component { id: convC; Conversation { app: appWin.app; win: appWin; chat: appWin.wa.current } }
        Component { id: introC; Intro { app: appWin.app } }

        Rectangle { visible: mainArea.infoShown; x: main.width; width: 1; height: parent.height; color: appWin.t.line }
        Loader {
          id: info
          active: mainArea.infoShown
          x: parent.width - width
          width: mainArea.infoWidth
          height: parent.height
          sourceComponent: InfoPanel { app: appWin.app; win: appWin; chat: appWin.infoChat || appWin.wa.current }
        }
      }
    }

    // ------------------------------------------------------------ overlays
    Loader {
      id: viewer
      property var msg: null
      anchors.fill: parent
      active: false
      z: 850
      sourceComponent: MediaViewer {
        app: appWin.app
        win: appWin
        msg: viewer.msg
        onClosed: viewer.active = false
      }
    }

    DialogHost {
      id: dialogs
      app: appWin.app
      win: appWin
      anchors.fill: parent
    }

    MenuLayer {
      id: menus
      app: appWin.app
      anchors.fill: parent
    }

    Loader {
      anchors.fill: parent
      active: appWin.accountOpen && appWin.wa.linked
      z: 870
      sourceComponent: AccountMenu {
        app: appWin.app
        win: appWin
        onClosed: { appWin.accountOpen = false; root.forceActiveFocus() }
      }
    }

    Rectangle {
      id: toastBox
      property string text: ""
      function show(s) { toastBox.text = s; toastBox.opacity = 1; toastTimer.restart() }
      z: 950
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: appWin.t.sp(28)
      width: Math.min(parent.width - appWin.t.sp(80), toastText.implicitWidth + appWin.t.sp(40))
      height: toastText.implicitHeight + appWin.t.sp(24)
      radius: appWin.t.sp(8)
      color: appWin.t.textBright
      opacity: 0
      visible: opacity > 0
      Behavior on opacity { NumberAnimation { duration: 180 } }
      Text {
        id: toastText
        textFormat: Text.PlainText
        anchors.centerIn: parent
        width: Math.min(implicitWidth, toastBox.parent.width - appWin.t.sp(120))
        text: toastBox.text
        color: appWin.t.bg
        font.family: appWin.t.font
        font.pixelSize: appWin.t.fsText
        wrapMode: Text.Wrap
        horizontalAlignment: Text.AlignHCenter
      }
      Timer { id: toastTimer; interval: 3800; onTriggered: toastBox.opacity = 0 }
    }

    Shortcuts {
      app: appWin.app
      win: appWin
    }

    Process {
      id: picker
      property var cb: null
      stdout: StdioCollector {
        onStreamFinished: {
          var files = String(text).split("\n").map(function(f) { return f.trim() }).filter(function(f) { return f })
          var cb = picker.cb
          picker.cb = null
          if (files.length && cb) cb(files)
        }
      }
      onExited: (code, status) => {
        if (code === 127) appWin.toast(appWin.app.tr("The file chooser needs a newer Omarchy (omarchy-file-select).", "O seletor de arquivos precisa de um Omarchy mais novo (omarchy-file-select)."))
        else if (code === 2) appWin.toast(appWin.app.tr("The file chooser didn't open.", "O seletor de arquivos não abriu."))
      }
    }
  }

  // The window's size is remembered.
  onWidthChanged: sizeSave.restart()
  onHeightChanged: sizeSave.restart()
  Timer {
    id: sizeSave
    interval: 1200
    onTriggered: if (appWin.visible && appWin.width > 400) { appWin.app.setSetting("windowWidth", appWin.width); appWin.app.setSetting("windowHeight", appWin.height) }
  }
}
