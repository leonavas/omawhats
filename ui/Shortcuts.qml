import QtQuick
import "../lib/Registry.js" as Reg

// The keyboard shortcuts: WhatsApp Web's own (Ctrl+Alt+…), plus Ctrl+K,
// Ctrl+N and Alt+↑/↓ for the chats, and zoom.
Item {
  id: sc
  property var app: Reg.service
  property var win
  readonly property var wa: app.wa

  // The chat list's order, archived ones aside.
  function step(d) {
    var list = sc.wa.chatList.filter(function(c) { return !c.archived })
    if (!list.length) return
    var i = -1
    for (var k = 0; k < list.length; k++) if (list[k].jid === sc.wa.current) { i = k; break }
    var n = i < 0 ? (d > 0 ? 0 : list.length - 1) : Math.max(0, Math.min(list.length - 1, i + d))
    sc.wa.open(list[n].jid)
  }
  function current() { return sc.wa.chat(sc.wa.current) }
  function zoom(d) {
    var z = Math.round((sc.app.zoom + d) * 100) / 100
    sc.app.setSetting("zoom", Math.max(0.7, Math.min(1.8, z)))
  }

  Shortcut { sequences: ["Ctrl+K", "Ctrl+Alt+/"]; onActivated: sc.win.focusSearch() }
  Shortcut { sequences: ["Ctrl+N", "Ctrl+Alt+N"]; onActivated: sc.win.openSide("newchat") }
  Shortcut { sequences: ["Alt+Down", "Ctrl+Tab", "Ctrl+Alt+Shift+]"]; onActivated: sc.step(1) }
  Shortcut { sequences: ["Alt+Up", "Ctrl+Shift+Tab", "Ctrl+Alt+Shift+["]; onActivated: sc.step(-1) }
  Shortcut { sequence: "Ctrl+Alt+E"; onActivated: { var c = sc.current(); if (c) sc.wa.chatAction(c.jid, c.archived ? "unarchive" : "archive") } }
  Shortcut { sequence: "Ctrl+Alt+Shift+M"; onActivated: { var c = sc.current(); if (c) sc.wa.chatAction(c.jid, sc.wa.isMuted(c) ? "unmute" : "mute", 0) } }
  Shortcut { sequence: "Ctrl+Alt+Shift+U"; onActivated: { var c = sc.current(); if (c) sc.wa.chatAction(c.jid, c.unread > 0 || c.marked ? "read" : "unread") } }
  Shortcut { sequence: "Ctrl+Alt+Shift+P"; onActivated: { var c = sc.current(); if (c) sc.wa.chatAction(c.jid, c.pin > 0 ? "unpin" : "pin") } }
  Shortcut { sequence: "Ctrl+Alt+Backspace"; onActivated: if (sc.wa.current) sc.win.dialog("deleteChat", { chat: sc.wa.current }) }
  Shortcut { sequence: "Ctrl+Alt+Shift+F"; onActivated: if (sc.wa.current) sc.win.openInfo("search") }
  Shortcut { sequence: "Ctrl+Alt+I"; onActivated: if (sc.wa.current) sc.win.toggleInfo() }
  Shortcut { sequences: ["Ctrl+,", "Ctrl+Alt+,"]; onActivated: sc.win.openSide("settings") }
  Shortcut { sequence: "Ctrl+Alt+P"; onActivated: sc.win.dialog("profile") }
  // whatsapp-tui's: your menu.
  Shortcut { sequence: "Alt+S"; onActivated: sc.win.toggleAccount() }
  Shortcut { sequences: ["Ctrl+=", "Ctrl++"]; onActivated: sc.zoom(0.1) }
  Shortcut { sequence: "Ctrl+-"; onActivated: sc.zoom(-0.1) }
  Shortcut { sequence: "Ctrl+0"; onActivated: sc.app.setSetting("zoom", 1.0) }
  Shortcut { sequence: "Ctrl+W"; onActivated: sc.app.hideWindow() }
  Shortcut { sequence: "Ctrl+/"; onActivated: sc.win.dialog("shortcuts") }

}
