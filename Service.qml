import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import "core"
import "ui"
import "lib/Util.js" as U
import "lib/Labels.js" as L
import "lib/Format.js" as F
import "lib/Registry.js" as Registry

// The whole app, once per shell: the link to WhatsApp (core/Store.qml and
// its bridge), preferences, the window, desktop notifications. The bar
// widget is only a door into it (Widget.qml).
Item {
  id: root

  // Host injection (ignored when absent).
  property var shell: null
  property var manifest: null

  readonly property string pluginId: "leonavas.omawhats"
  readonly property bool _registered: { Registry.service = root; return true }
  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string configDir: (Quickshell.env("XDG_CONFIG_HOME") || home + "/.config") + "/omawhats"
  readonly property string cacheDir: (Quickshell.env("XDG_CACHE_HOME") || home + "/.cache") + "/omawhats"
  readonly property string dataDir: (Quickshell.env("XDG_DATA_HOME") || home + "/.local/share") + "/omawhats"
  readonly property string downloadsDir: Quickshell.env("XDG_DOWNLOAD_DIR") || home + "/Downloads"
  readonly property string pluginDir: String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "").replace(/\/$/, "")

  // ---------------------------------------------------------------- settings
  property var settings: ({})
  property bool settingsLoaded: false
  function setting(key, fallback) { var v = root.settings[key]; return v === undefined || v === null ? fallback : v }
  function setSetting(key, value) {
    var s = U.copy(root.settings)
    s[key] = value
    root.settings = s
    saveSettingsSoon.restart()
  }

  // Portuguese when the system speaks it, the clock is Brazil's, or the
  // linked number is; the settings can say otherwise.
  readonly property bool _ptHint: ["LANGUAGE", "LC_ALL", "LC_MESSAGES", "LANG"].some(function(k) { return String(Quickshell.env(k) || "").indexOf("pt") === 0 })
                                  || /^America\/(Sao_Paulo|Fortaleza|Recife|Bahia|Belem|Manaus|Cuiaba|Campo_Grande|Porto_Velho|Boa_Vista|Rio_Branco|Araguaina|Maceio|Santarem|Noronha)/.test(String(Quickshell.env("TZ") || root._zone))
                                  || (!!store.me && String(store.me.phone || "").indexOf("55") === 0)
  property string _zone: ""
  Process {
    running: true
    command: ["readlink", "/etc/localtime"]
    stdout: StdioCollector { onStreamFinished: root._zone = String(text).replace(/^.*zoneinfo\//, "").trim() }
  }
  readonly property string lang: setting("lang", root._ptHint ? "pt-BR" : "en")
  readonly property bool clock24: setting("clock", "24h") !== "12h"
  readonly property bool enterSends: setting("enterSends", true) !== false
  // Desktop notifications and their text are the bar widget's settings
  // ("notifications", "notificationText"), as whatsapp-tui's widget keeps
  // them; the app's own settings stand in while no widget is on the bar.
  readonly property bool notificationsOn: root.barOptions.notifications !== undefined ? root.barOptions.notifications !== false
                                                                                     : setting("notifications", true) !== false
  readonly property bool previewOn: root.barOptions.notificationText !== undefined ? root.barOptions.notificationText !== false
                                                                                   : setting("notificationPreview", true) !== false
  // The widget's writer, set while one is on the bar: a toggle in the app
  // lands in the widget's settings (shell.json), where the bar reads it.
  property var barWriter: null
  function setNotifySetting(key, value) {
    if (root.barWriter) root.barWriter(key === "notificationPreview" ? "notificationText" : key, value)
    else root.setSetting(key, value)
  }
  readonly property bool soundOn: setting("sound", false) === true
  readonly property bool reactionNotices: setting("reactionNotifications", true) !== false
  readonly property bool doodleOn: setting("doodle", true) !== false
  readonly property real zoom: setting("zoom", 1.0)
  readonly property bool autoPhotos: setting("autoPhotos", true) !== false
  function tr(en, pt) { return root.lang === "pt-BR" ? pt : en }

  // Read once the folders are in place (`ready`, below).
  FileView {
    id: settingsFile
    path: root.ready ? root.configDir + "/settings.json" : ""
    printErrors: false
    blockLoading: true
    onLoaded: {
      try { root.settings = JSON.parse(text()) || {} } catch (e) { root.settings = {} }
      root.settingsLoaded = true
    }
    onLoadFailed: { root.settings = {}; root.settingsLoaded = true }
  }
  Timer { id: saveSettingsSoon; interval: 600; onTriggered: settingsFile.setText(JSON.stringify(root.settings, null, 2)) }

  // Drafts per chat, kept across restarts.
  function draft(chat) { var d = root.setting("drafts", {}); return d[chat] || "" }
  function setDraft(chat, text) {
    var d = U.copy(root.setting("drafts", {}))
    if (text) d[chat] = text
    else delete d[chat]
    root.setSetting("drafts", d)
  }

  // ---------------------------------------------------------------- whatsapp
  Store {
    id: store
    app: root
    dataDir: root.dataDir
    cacheDir: root.cacheDir
    enabled: root.ready && root.running
    onIncoming: m => root.notifyMessage(m)
    onReacted: ev => root.notifyReaction(ev)
    onFailed: text => { if (root.appWindow) root.appWindow.toast(text) }
  }
  readonly property alias wa: store

  // New versions of the plugin on GitHub: the notice on top of the chat
  // list, the bar's preview and menu (core/Updater.qml).
  Updater { id: updaterObj; app: root }
  readonly property alias updater: updaterObj

  readonly property var attention: store.attention
  // Notifications paused until (unix seconds); 0 when not.
  readonly property real pausedUntil: Number(setting("pausedUntil", 0))
  property real nowSec: Date.now() / 1000
  Timer { interval: 30000; repeat: true; running: true; onTriggered: root.nowSec = Date.now() / 1000 }
  readonly property bool paused: root.pausedUntil > root.nowSec
  function pause(minutes) { root.nowSec = Date.now() / 1000; root.setSetting("pausedUntil", Math.round(root.nowSec + minutes * 60)) }
  function resume() { root.setSetting("pausedUntil", 0) }

  // ---------------------------------------------------------------- running
  // Whether WhatsApp runs (the bridge, linked to the phone): the bar widget
  // starts it at login (Launch on Login) or on a click, and "Quit WhatsApp"
  // stops it, as whatsapp-tui's widget does with whatsapp-tui. Stopped,
  // nothing counts or notifies.
  property bool running: Quickshell.env("OMAWHATS_OPEN") === "1"
  property real startedAt: 0
  onRunningChanged: if (running) root.startedAt = Date.now() / 1000
  function start() { root.running = true }
  function quit() {
    root.windowOpen = false
    root.running = false
  }

  // ---------------------------------------------------------------- window
  property bool windowOpen: Quickshell.env("OMAWHATS_OPEN") === "1"
  property bool windowFocused: false
  signal dialogRequested(string name, var args)

  // Shown, put away or closed, the way the bar widget's settings say
  // (`barOptions`, pushed by Widget.qml): a click on the focused window
  // parks it in a Hyprland special workspace (Omarchy's scratchpad,
  // SUPER+S), where it stays as it was, or leaves it be; a window opened
  // with "Open in Scratchpad" goes straight there, and one opened in the
  // background (Launch in Foreground off) is parked at once. Closing it
  // (hideWindow) unmaps it; the app keeps counting and notifying either way.
  property var barOptions: ({ specialName: "scratchpad", openInSpecial: true, hideMode: "Special workspace", launchForeground: true })
  property bool autoStarted: false
  // A plain name only: it goes into Hyprland dispatches.
  readonly property string specialName: {
    var n = String(root.barOptions.specialName || "")
    return /^[A-Za-z0-9_-]{1,32}$/.test(n) ? n : "scratchpad"
  }
  readonly property var toplevel: root.windowOpen ? root.ourToplevel() : null
  readonly property bool parked: root.workspaceOf(root.toplevel) === "special:" + root.specialName
  readonly property bool specialShown: {
    var m = Hyprland.focusedMonitor
    var ipc = m ? m.lastIpcObject : null
    var s = ipc ? ipc["specialWorkspace"] : null
    return !!s && String(s.name || "") === "special:" + root.specialName
  }
  // On while a background launch puts the window away: Hyprland focuses it
  // for a moment on the way, which must not count as reading it.
  property bool stowing: false

  function showWindow() {
    if (!root.windowOpen) { root.launchWindow(true); return }
    if (root.parked) {
      if (root.barOptions.openInSpecial !== false) { if (!root.specialShown) root.toggleSpecial() }
      else root.moveToActive()
    }
    root.raiseSoon()
  }
  function hideWindow() { root.windowOpen = false }
  // Left click: open it, bring it back, put it away.
  function toggleWindow() {
    if (!root.windowOpen) root.launchWindow(root.barOptions.launchForeground !== false)
    else if (root.windowFocused && root.barOptions.hideMode === "Special workspace") root.park()
    else if (root.parked) root.showWindow()
    else root.raiseSoon()
  }

  // A Quickshell window can't be born in a hidden workspace: it maps on the
  // current one, and once Hyprland lists it, it moves on.
  property bool _launchForeground: true
  property string _launchBack: ""
  function launchWindow(foreground) {
    root.running = true
    root._launchForeground = foreground
    root._launchBack = root.lastOtherAddress
    root.stowing = !foreground
    root.windowOpen = true
    placeTimer.ticks = 0
    placeTimer.restart()
  }
  Timer {
    id: placeTimer
    property int ticks: 0
    interval: 50
    repeat: true
    onTriggered: {
      var address = root.windowAddress()
      if (!address && ++ticks < 60 && root.windowOpen) return
      stop()
      if (!address || !root.windowOpen) { root.stowing = false; return }
      var special = "special:" + root.specialName
      if (!root._launchForeground) {
        root.moveWindow(address, special, true)
        backgroundFix.restart()
      } else if (root.barOptions.openInSpecial !== false) {
        // Not silent: the scratchpad opens with it.
        root.moveWindow(address, special, false)
        root.raiseSoon()
      } else root.raiseSoon()
    }
  }

  // Moving the window that just took the focus makes Hyprland refocus, and
  // its pick can be a window in the scratchpad, which opens it on screen.
  // A background launch puts that back: scratchpad hidden, focus on the
  // window you were using.
  Timer {
    id: backgroundFix
    interval: 200
    onTriggered: {
      var lua = Hyprland.usingLua === true
      var hide = lua ? "hl.dsp.workspace.toggle_special(" + root.luaStr(root.specialName) + ")" : "togglespecialworkspace " + root.specialName
      var back = root._launchBack
      var focus = back.length === 0 ? "" : lua ? "hl.dsp.focus({ window = " + root.luaStr(back) + " })" : "focuswindow " + back
      Quickshell.execDetached(["bash", "-c",
        'shown=$(hyprctl monitors -j | jq -r \'.[] | select(.focused) | .specialWorkspace.name\'); '
        + '[ "$shown" = "special:$1" ] && hyprctl dispatch "$2" >/dev/null; '
        + '[ -n "$3" ] && hyprctl dispatch "$3" >/dev/null; exit 0',
        "whatsapp-background", root.specialName, hide, focus])
      stowEnd.restart()
    }
  }
  Timer { id: stowEnd; interval: 300; onTriggered: root.stowing = false }

  function park() {
    var address = root.windowAddress()
    if (!address) return
    if (root.parked && root.specialShown) { root.toggleSpecial(); return }
    root.moveWindow(address, "special:" + root.specialName, true)
  }

  function moveToActive() {
    var address = root.windowAddress()
    var ws = Hyprland.focusedWorkspace ? String(Hyprland.focusedWorkspace.name || "") : ""
    if (address && ws && ws.indexOf("special:") !== 0) root.moveWindow(address, ws, false)
  }

  // A value as a Lua string literal, for the Lua dispatches: whatever is in
  // it (a workspace's name, an address) stays a string.
  function luaStr(v) {
    return '"' + String(v).replace(/[\\"]/g, "\\$&").replace(/\n/g, "\\n").replace(/\r/g, "\\r").replace(/\0/g, "") + '"'
  }
  function hyprDispatch(luaForm, legacyForm) {
    Hyprland.dispatch(Hyprland.usingLua === true ? luaForm : legacyForm)
  }
  function moveWindow(address, workspace, silent) {
    root.hyprDispatch("hl.dsp.window.move({ window = " + root.luaStr(address) + ", workspace = " + root.luaStr(workspace) + (silent ? ", silent = true" : "") + " })",
                      (silent ? "movetoworkspacesilent " : "movetoworkspace ") + workspace + "," + address)
  }
  function toggleSpecial() {
    root.hyprDispatch("hl.dsp.workspace.toggle_special(" + root.luaStr(root.specialName) + ")", "togglespecialworkspace " + root.specialName)
  }

  function windowAddress() {
    var t = root.ourToplevel()
    if (!t || !t.address) return ""
    var a = String(t.address)
    return "address:" + (a.indexOf("0x") === 0 ? a : "0x" + a)
  }
  function workspaceOf(t) {
    if (!t) return ""
    if (t.workspace && t.workspace.name) return String(t.workspace.name)
    var ipc = t.lastIpcObject
    return ipc && ipc["workspace"] && ipc["workspace"]["name"] ? String(ipc["workspace"]["name"]) : ""
  }

  // The window you were using, to give the focus back to after a
  // background launch.
  property string lastOtherAddress: ""
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name === "activespecial" || event.name === "activespecialv2") Hyprland.refreshMonitors()
      if (event.name === "openwindow") {
        var f = event.parse(4)   // address, workspace, class, title
        if (f.length >= 4 && root.isOurTitle(f[3])) root.tagWindow(f[0])
      }
    }
    function onActiveToplevelChanged() {
      var t = Hyprland.activeToplevel
      if (!t || !t.address || root.isOurTitle(t.title) || root.workspaceOf(t).indexOf("special:") === 0) return
      var a = String(t.address)
      root.lastOtherAddress = "address:" + (a.indexOf("0x") === 0 ? a : "0x" + a)
    }
  }

  // Focus the window through Hyprland (a click on the bar doesn't move focus).
  function raiseSoon() { raiseTimer.restart() }
  readonly property string windowTitleBase: "Omawhats"
  function isOurTitle(title) {
    title = String(title || "")
    return title === root.windowTitleBase || /^\(\d+\) Omawhats$/.test(title)
  }
  function ourToplevel() {
    var list = Hyprland.toplevels ? (Hyprland.toplevels.values || []) : []
    for (var i = 0; i < list.length; i++) if (root.isOurTitle(list[i].title)) return list[i]
    return null
  }
  Timer {
    id: raiseTimer
    interval: 150
    onTriggered: {
      var t = root.ourToplevel()
      if (!t || !t.address) return
      var addr = String(t.address)
      if (addr.indexOf("0x") !== 0) addr = "0x" + addr
      Hyprland.dispatch(Hyprland.usingLua === true ? "hl.dsp.focus({ window = " + root.luaStr("address:" + addr) + " })" : "focuswindow address:" + addr)
      root.tagWindow(addr)
    }
  }

  // The window is Quickshell's (app id org.quickshell): a Hyprland tag,
  // "icon:<path>", names ours for the bar widgets that read it.
  readonly property string appIcon: root.pluginDir + "/assets/whatsapp.svg"
  function tagWindow(address) {
    var addr = String(address || "")
    if (!addr) return
    if (addr.indexOf("0x") !== 0) addr = "0x" + addr
    var tag = "+icon:" + root.appIcon
    Hyprland.dispatch(Hyprland.usingLua === true
                      ? "hl.dsp.window.tag({ tag = " + root.luaStr(tag) + ", window = " + root.luaStr("address:" + addr) + " })"
                      : "tagwindow " + tag + " address:" + addr)
  }

  function openChat(chat, msgId) {
    if (!chat) return
    root.showWindow()
    store.open(chat, { msg: msgId || "" })
  }
  function openDialog(name, args) { root.showWindow(); root.dialogRequested(name, args || {}) }

  Theme {
    id: themeObj
    zoom: root.zoom
    themeFont: root.setting("font", "theme") === "theme"
  }
  readonly property alias theme: themeObj

  // The window is made once the app is complete and its folders are in
  // place (views read it at birth).
  property bool ready: false
  LazyLoader {
    id: windowLoader
    active: root.ready && root.settingsLoaded
    AppWindow { app: root }
  }
  readonly property var appWindow: windowLoader.item

  // ---------------------------------------------------------------- notifications
  // As whatsapp-tui's widget notifies: one notification per new message,
  // except in muted chats, while paused, and for the chat open on screen.
  // The summary is the chat (the author · the group, in a group), the body
  // the message with its bold, italics and strikethrough (or only "New
  // message"), the icon the chat's picture. A click runs, in Omarchy's
  // notification center, the IPC call that opens the chat at that message,
  // so it still works after a shell restart. A message replayed by a
  // reconnect notifies once; one sent before WhatsApp started was waiting
  // already, and the badge has it.
  property real _lastSound: 0
  property var _notifiedIds: ({})
  property var _notifiedOrder: []

  function notifyAllowed(chat) {
    if (!root.notificationsOn || root.paused) return false
    var c = store.chat(chat)
    if (c && store.isMuted(c)) return false
    if (root.windowFocused && store.current === chat) return false
    return true
  }

  function firstNotice(chat, id) {
    var key = chat + "|" + id
    if (root._notifiedIds[key]) return false
    root._notifiedIds[key] = true
    root._notifiedOrder.push(key)
    while (root._notifiedOrder.length > 200) delete root._notifiedIds[root._notifiedOrder.shift()]
    return true
  }

  // A message as the notification's body: its text as markup, media by
  // their emoji and label.
  readonly property var _kindEmoji: ({ camera: "📷", video: "🎥", ptv: "🎥", gif: "🎞️", mic: "🎤", headphones: "🎧", document: "📄",
                                       sticker: "🏷️", location: "📍", liveLocation: "📍", contact: "👤", poll: "📊", event: "📅",
                                       call: "📞", callMissed: "📞" })
  function noticeBody(m) {
    var s = L.short(m, root.lang)
    var text = F.styled(s.text, m.mentions, root.tr("You", "Você"))
    var emoji = s.icon ? root._kindEmoji[s.icon] || "" : ""
    return (emoji ? emoji + " " : "") + text
  }

  function notifyMessage(m) {
    if (!m || m.from_me || (m.ts || 0) < root.startedAt - 5) return
    if (!root.notifyAllowed(m.chat) || !root.firstNotice(m.chat, m.id)) return
    var c = store.chat(m.chat)
    var group = c ? c.kind === "group" : String(m.chat).indexOf("@g.us") > 0
    var name = store.nameOf(m.chat)
    var who = String(m.name || "").replace(/^~/, "") || (m.sender ? store.nameOf(m.sender) : "")
    var title = group && who ? who + " · " + name : name
    var body = root.previewOn ? root.noticeBody(m) : ""
    root.notify(m.chat, m.id, title, body.length > 0 ? body : root.tr("New message", "Nova mensagem"))
  }

  function notifyReaction(ev) {
    if (!root.reactionNotices || !ev.emoji || !root.notifyAllowed(ev.chat)) return
    if (!root.firstNotice(ev.chat, "r:" + ev.id + ":" + (ev.who || "") + ":" + ev.emoji)) return
    var who = String(ev.who || "").replace(/^~/, "") || root.tr("Someone", "Alguém")
    var original = store.findMsg(ev.chat, ev.id)
    var quoted = original ? F.plain(L.short(original, root.lang).text, original.mentions).slice(0, 80) : ""
    var body = root.previewOn
      ? F.esc(root.tr(who + " reacted " + ev.emoji + " to: ", who + " reagiu com " + ev.emoji + " a: ") + "\u201c" + quoted + "\u201d")
      : root.tr("New reaction", "Nova reação")
    root.notify(ev.chat, ev.id, store.nameOf(ev.chat), body)
  }

  // Sent by the bridge over the session bus, not by notify-send: a command's
  // arguments can be read by any user of the machine, and these carry who
  // wrote and what.
  function notify(chat, msg, title, body) {
    var avatar = U.unfileUrl(String(store.avatar(chat)).replace(/\?.*$/, ""))
    var openArgv = ["omarchy-shell", "-q", "omawhats", "openAt", String(chat), String(msg || "")]
    store.send({ c: "notify", app: "WhatsApp", icon: avatar || root.appIcon, title: String(title), text: String(body),
                 exec: JSON.stringify(openArgv) })
    if (root.soundOn && Date.now() - root._lastSound > 1500) {
      root._lastSound = Date.now()
      Quickshell.execDetached(["sh", "-c", 'for f in "$1" /usr/share/sounds/freedesktop/stereo/message-new-instant.oga /usr/share/sounds/freedesktop/stereo/message.oga /usr/share/sounds/freedesktop/stereo/bell.oga; do [ -f "$f" ] && exec pw-play "$f"; done; exit 0', "sound", root.setting("soundFile", "")])
    }
  }

  // ---------------------------------------------------------------- utilities
  // The text goes to wl-copy on its stdin: as an argument it would stay
  // readable by any user of the machine while the clipboard holds it.
  function copy(text) { copyComponent.createObject(root, { text: String(text) }).running = true }
  Component {
    id: copyComponent
    Process {
      property string text: ""
      command: ["wl-copy"]
      stdinEnabled: true
      onStarted: { write(text); stdinEnabled = false }
      onExited: destroy()
    }
  }
  function copyImage(path) { Quickshell.execDetached(["sh", "-c", 'wl-copy < "$1"', "copy", path]) }
  // Only what a browser, the mail app or the dialer opens: a link that came
  // in a message could otherwise hand a file or a command to its handler.
  function openUrl(url) {
    var s = String(url || "").trim()
    if (/^(https?:\/\/|mailto:|tel:)/i.test(s)) Qt.openUrlExternally(s)
  }
  // A business's e-mail, when it is one address and nothing more.
  function openMail(address) {
    var s = String(address || "").trim()
    if (/^[^\s@?&#\/:;,<>"]+@[^\s@?&#\/:;,<>"]+\.[^\s@?&#\/:;,<>"]+$/.test(s)) Qt.openUrlExternally("mailto:" + s)
  }
  // A received file opens in its app only when it's a document, a picture,
  // audio, video or an archive. Anything else (a script, a launcher, a
  // program, a web page) is shown in its folder, where you decide.
  readonly property var _openable: ["pdf", "txt", "md", "csv", "tsv", "rtf", "odt", "ods", "odp", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "epub",
                                    "jpg", "jpeg", "png", "gif", "webp", "bmp", "tif", "tiff", "heic", "heif", "avif",
                                    "mp3", "m4a", "aac", "ogg", "oga", "opus", "wav", "flac", "amr",
                                    "mp4", "m4v", "mov", "mkv", "webm", "avi", "3gp",
                                    "zip", "rar", "7z", "tar", "gz", "xz", "bz2", "zst"]
  function openFile(path) {
    if (!path) return
    var p = U.unfileUrl(path)
    if (root._openable.indexOf(U.ext(p)) >= 0) { Quickshell.execDetached(["xdg-open", p]); return }
    root.showInFolder(p)
    if (root.appWindow) root.appWindow.toast(root.tr("This kind of file isn't opened directly: here's its folder",
                                                     "Esse tipo de arquivo não é aberto direto: aqui está a pasta dele"))
  }
  function showInFolder(path) { if (path) Quickshell.execDetached(["sh", "-c", 'nautilus --select "$1" 2>/dev/null || xdg-open "$(dirname "$1")"', "show", U.unfileUrl(path)]) }

  // A video plays in mpv (Omarchy's player), in a window of its own: only
  // the file, no youtube-dl and no playlist pointing elsewhere.
  function playVideo(path, loop) {
    if (!path) return
    var args = ["mpv", "--force-window=yes", "--title=WhatsApp", "--keep-open=no", "--ytdl=no", "--load-unsafe-playlists=no"]
    if (loop) args.push("--loop-file=inf", "--mute=yes")
    args.push(U.unfileUrl(path))
    Quickshell.execDetached(args)
  }

  // Saves a downloaded file to ~/Downloads under its own name (a number
  // added when one is there), then says where. The name came from whoever
  // sent it: only its last part, with no leading dot or dash, so it can't
  // reach another folder or hide; the script checks that once more.
  function safeName(name) {
    return U.basename(String(name || "").replace(/\\/g, "/")).replace(/[\x00-\x1f\x7f]/g, "").trim().replace(/^[.\-\s]+/, "")
  }
  function saveToDownloads(path, name, cb) {
    var src = U.unfileUrl(path)
    var base = root.safeName(name) || root.safeName(U.basename(src))
    saver.cb = cb || null
    saver.command = ["sh", "-c", 'dir="$1"; src="$2"; name="$3"; case "$name" in ""|*/*|.*|-*) exit 1;; esac; mkdir -p "$dir"; stem="${name%.*}"; ext="${name##*.}"; [ "$ext" = "$name" ] && ext="" || ext=".$ext"; out="$dir/$name"; n=1; while [ -e "$out" ] || [ -L "$out" ]; do out="$dir/$stem ($n)$ext"; n=$((n+1)); done; cp -- "$src" "$out" && echo "$out"',
                     "save", root.downloadsDir, src, base]
    saver.running = true
  }
  Process {
    id: saver
    property var cb: null
    stdout: StdioCollector {
      onStreamFinished: {
        var out = String(text).trim()
        if (saver.cb) saver.cb(out)
        if (out && root.appWindow) root.appWindow.toast(root.tr("Saved to ", "Salvo em ") + out.replace(root.home, "~"))
      }
    }
  }


  // What the clipboard has: a picture (saved to a file), files or text. A
  // picture comes first, as on WhatsApp Web, even when a browser puts its
  // HTML beside it. cb({image}|{files}|{text}).
  function readClipboard(cb) {
    var p = clipComponent.createObject(root, { cb: cb })
    var stamp = root.cacheDir + "/paste/" + Date.now()
    p.command = ["sh", "-c",
      'types=$(wl-paste --list-types 2>/dev/null); for m in image/png image/jpeg image/webp image/gif; do echo "$types" | grep -qx "$m" || continue; ext=${m#image/}; [ "$ext" = jpeg ] && ext=jpg; mkdir -p "$1"; wl-paste --type "$m" > "$2.$ext" && echo "IMAGE $2.$ext"; exit 0; done; '
      + 'uris=$(wl-paste --type text/uri-list 2>/dev/null); if [ -n "$uris" ]; then echo "FILES"; echo "$uris"; exit 0; fi; echo TEXT; wl-paste --no-newline --type text 2>/dev/null; exit 0',
      "paste", root.cacheDir + "/paste", stamp]
    p.running = true
  }
  Component {
    id: clipComponent
    // Called by its id: the collector has no parent of its own, and a bare
    // `parent` there is the Service's, so the answer never came back.
    Process {
      id: clip
      property var cb: null
      stdout: StdioCollector {
        onStreamFinished: {
          var s = String(text)
          if (!clip.cb) return
          if (s.indexOf("IMAGE ") === 0) clip.cb({ image: s.slice(6).trim() })
          else if (s.indexOf("FILES\n") === 0) clip.cb({ files: s.slice(6).split("\n").map(function(u) { return U.unfileUrl(u.trim()) }).filter(function(u) { return u.length > 0 && u.indexOf("#") !== 0 }) })
          else clip.cb({ text: s.indexOf("TEXT\n") === 0 ? s.slice(5) : s })
        }
      }
      onExited: destroy()
    }
  }

  // ---------------------------------------------------------------- lifecycle
  // The folders, made before anything reads or writes them. Omawhats was
  // whatsapp-claude: each of its old folders (the session, the settings,
  // the media) takes the new name once, by a rename, so nothing is copied
  // or split. `mv -T` renames it only while the new one is missing or
  // empty; one with something in it is left alone, and so is the old. The
  // settings, the window and the bridge wait for it (`ready`).
  Process {
    id: folders
    command: ["sh", "-c",
      'for d in "$@"; do old=${d%/*}/whatsapp-claude; [ -d "$old" ] && mv -T "$old" "$d"; done; mkdir -p -m 700 "$@"; chmod 700 "$@"; chmod 600 "$1/settings.json" 2>/dev/null; exit 0',
      "folders", root.configDir, root.cacheDir, root.dataDir]
    onExited: root.ready = true
  }

  Component.onCompleted: {
    folders.running = true
    Registry.service = root
    // Pasted pictures and voice notes recorded: a day is enough.
    Quickshell.execDetached(["sh", "-c", 'find "$1/paste" "$1/voice" -type f -mtime +1 -delete 2>/dev/null; exit 0', "clean", root.cacheDir])
  }

  Component.onDestruction: {
    if (Registry.service === root) Registry.service = null
    if (root.settingsLoaded) settingsFile.setText(JSON.stringify(root.settings, null, 2))
  }

  IpcHandler {
    target: "omawhats"
    function toggle(): void { root.toggleWindow() }
    function show(): void { root.showWindow() }
    function hide(): void { root.hideWindow() }
    function open(chat: string): void { root.openChat(chat, "") }
    function openAt(chat: string, msg: string): void { root.openChat(chat, msg) }
    function quit(): void { root.quit() }
    function pause(minutes: int): void { root.pause(minutes) }
    function resume(): void { root.resume() }
    function status(): string {
      return JSON.stringify({ running: root.running, state: store.conn, linked: store.linked, attention: store.attention, paused: root.paused,
                              me: store.me, open: root.windowOpen, current: store.current })
    }
  }
}
