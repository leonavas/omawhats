import QtQuick
import Quickshell
import "../lib/Util.js" as U
import "../lib/Model.js" as Model
import "../lib/Labels.js" as L

// Everything WhatsApp: the link's state, the chats, the open chat's
// messages, pictures, who's online or typing, the voice note playing. The
// bridge's events land here; the views read from here and act through
// the functions below. Plain maps with revision counters: a view that
// reads `chatsRev` (or `historyRev`…) follows the changes.
Item {
  id: wa

  property var app: null
  property string dataDir: ""
  property string cacheDir: ""
  property bool enabled: true

  // ---------------------------------------------------------------- link
  // starting, pairing, connecting, ready, offline, logged_out, replaced
  property string conn: "starting"
  readonly property bool linked: me !== null && conn !== "pairing" && conn !== "logged_out"
  readonly property bool online: conn === "ready"
  property var me: null
  property var qr: null
  property string pairCode: ""
  property string pairError: ""
  property int syncProgress: -1
  property bool everReady: false

  Bridge {
    id: bridge
    dataDir: wa.dataDir
    cacheDir: wa.cacheDir
    enabled: wa.enabled
    onEvent: ev => wa.handle(ev)
    // Downloads it had under way won't be answered: asked again when shown.
    onExited: code => {
      if (wa.conn === "ready") wa.conn = "offline"
      wa.downloads = ({})
      wa._onDownloaded = ({})
      wa.downloadsRev++
    }
  }
  readonly property alias bridge: bridge
  readonly property string build: bridge.build

  function send(obj) { bridge.send(obj) }

  // ---------------------------------------------------------------- chats
  property var chatMap: ({})
  property int chatsRev: 0
  // Pinned first (the newest pin on top), then the newest message.
  readonly property var chatList: {
    wa.chatsRev
    var list = []
    for (var k in wa.chatMap) list.push(wa.chatMap[k])
    list.sort(function(a, b) {
      if ((a.pin || 0) !== (b.pin || 0)) return (b.pin || 0) - (a.pin || 0)
      return (b.ts || 0) - (a.ts || 0)
    })
    return list
  }
  function chat(jid) { wa.chatsRev; return wa.chatMap[jid] || null }

  function isMuted(c) { return !!c && (c.mute === -1 || (c.mute || 0) > Date.now() / 1000) }

  // What waits: unread chats (archived and muted ones aside), as WhatsApp
  // counts them on its Chats tab, and the messages in them.
  readonly property var attention: {
    wa.chatsRev
    var out = { chats: 0, direct: 0, groups: 0, messages: 0, archived: 0, muted: 0 }
    for (var k in wa.chatMap) {
      var c = wa.chatMap[k]
      if (!(c.unread > 0 || c.marked)) continue
      if (c.archived) { out.archived++; continue }
      if (wa.isMuted(c)) { out.muted++; continue }
      // The badges count chats, one each however many messages wait in it,
      // as WhatsApp does.
      out.chats++
      out.messages += Math.max(c.unread || 0, 1)
      if (c.kind === "group") out.groups++
      else out.direct++
    }
    return out
  }

  // The name a chat goes by: a group's subject, the saved name, the
  // business's, else the number.
  function chatName(c) {
    if (!c) return ""
    if (c.kind === "self") return (wa.me && wa.me.name ? wa.me.name : U.phone(c.phone)) + wa.app.tr(" (You)", " (você)")
    if (c.name) return c.name
    if (c.kind === "group") return wa.app.tr("Group", "Grupo")
    return U.phone(c.phone || String(c.jid || "").split("@")[0])
  }
  function nameOf(jid) {
    var c = wa.chat(jid)
    if (c) return wa.chatName(c)
    var p = wa.profiles[jid]
    if (p && p.name) return p.name
    return U.phone(String(jid || "").split("@")[0])
  }

  // ---------------------------------------------------------------- pictures
  property var avatars: ({})
  property int avatarsRev: 0
  property var _avatarAsked: ({})
  property var _avatarQueue: []
  function avatar(jid) {
    if (!jid) return ""
    wa.avatarsRev
    var p = wa.avatars[jid]
    if (p === undefined) { wa.askAvatar(jid); return "" }
    return p
  }
  function askAvatar(jid) {
    if (wa._avatarAsked[jid]) return
    wa._avatarAsked[jid] = true
    wa._avatarQueue.push(jid)
    avatarTimer.start()
  }
  Timer {
    id: avatarTimer
    interval: 60
    onTriggered: {
      var q = wa._avatarQueue
      wa._avatarQueue = []
      for (var i = 0; i < q.length; i++) wa.send({ c: "avatar", chat: q[i] })
    }
  }

  // ---------------------------------------------------------------- presence
  property var presence: ({})
  property int presenceRev: 0
  property var typing: ({})
  property int typingRev: 0
  function typingIn(chat) {
    wa.typingRev
    var t = wa.typing[chat]
    if (!t) return null
    return t.until > Date.now() ? t : null
  }
  Timer {
    // WhatsApp sends "paused" but not always: typing fades on its own.
    interval: 5000
    repeat: true
    running: Object.keys(wa.typing).length > 0
    onTriggered: {
      var now = Date.now(), changed = false
      for (var k in wa.typing) if (wa.typing[k].until <= now) { delete wa.typing[k]; changed = true }
      if (changed) wa.typingRev++
    }
  }

  // ---------------------------------------------------------------- history
  // chat -> {msgs (oldest first), more (older here), loading, olderAsked,
  // olderDone (the phone has none either)}
  property var histories: ({})
  property int historyRev: 0
  function history(chat) { wa.historyRev; return wa.histories[chat] || null }

  function openHistory(chat) {
    var h = wa.histories[chat]
    if (h && h.loaded) {
      // Kept from before: fresh again in the background.
      wa.send({ c: "history", chat: chat, limit: Math.max(60, h.msgs.length) })
      return
    }
    wa.histories[chat] = { msgs: [], more: false, loading: true, loaded: false, olderAsked: false, olderDone: false }
    wa.historyRev++
    wa.send({ c: "history", chat: chat, limit: 60 })
  }

  function loadOlder(chat) {
    var h = wa.histories[chat]
    if (!h || h.loading || !h.loaded) return
    if (h.more && h.msgs.length) {
      h.loading = true
      wa.historyRev++
      var oldest = h.msgs[0]
      wa.send({ c: "history", chat: chat, limit: 60, before: oldest.ts, before_id: oldest.id })
    } else if (!h.olderAsked && !h.olderDone) {
      // Nothing older here: the phone may have it, as WhatsApp Web asks.
      h.olderAsked = true
      h.loading = true
      wa.historyRev++
      wa.send({ c: "older", chat: chat })
      olderGiveUp.chat = chat
      olderGiveUp.restart()
    }
  }
  Timer {
    id: olderGiveUp
    property string chat: ""
    interval: 15000
    onTriggered: {
      var h = wa.histories[chat]
      if (h && h.olderAsked && h.loading) { h.loading = false; h.olderDone = true; wa.historyRev++ }
    }
  }

  function _indexOf(msgs, id) {
    for (var i = msgs.length - 1; i >= 0; i--) if (msgs[i].id === id) return i
    return -1
  }

  function upsert(m) {
    var h = wa.histories[m.chat]
    if (!h || !h.loaded) return
    var i = wa._indexOf(h.msgs, m.id)
    var msgs = h.msgs.slice()
    if (i >= 0) {
      // A download or a frame kept: the new copy keeps them.
      var old = msgs[i]
      if (old.media && m.media) {
        if (!m.media.file && old.media.file) m.media.file = old.media.file
        if (!m.media.thumb && old.media.thumb) m.media.thumb = old.media.thumb
      }
      msgs[i] = m
    } else {
      // In time order; ours sent just now go last.
      var at = msgs.length
      while (at > 0 && msgs[at - 1].ts > m.ts) at--
      msgs.splice(at, 0, m)
    }
    h.msgs = msgs
    wa.historyRev++
  }

  function patchMsg(chat, id, fn) {
    var h = wa.histories[chat]
    if (!h) return
    var i = wa._indexOf(h.msgs, id)
    if (i < 0) return
    var m = U.copy(h.msgs[i])
    fn(m)
    var msgs = h.msgs.slice()
    msgs[i] = m
    h.msgs = msgs
    wa.historyRev++
  }

  function findMsg(chat, id) {
    var h = wa.histories[chat]
    if (!h) return null
    var i = wa._indexOf(h.msgs, id)
    return i >= 0 ? h.msgs[i] : null
  }

  // ---------------------------------------------------------------- the open chat
  property string current: ""
  // At open: how many were unread, for the band over the first of them.
  property var unreadMarks: ({})
  property int marksRev: 0

  function open(chat, opts) {
    if (!chat) return
    opts = opts || {}
    var c = wa.chat(chat)
    if (wa.current !== chat) {
      var marks = wa.unreadMarks
      marks[chat] = c && c.unread > 0 ? c.unread : 0
      wa.marksRev++
      wa.current = chat
      wa.openHistory(chat)
      wa.send({ c: "subscribe", chat: chat })
    }
    if (opts.msg) wa.jumpTo = { chat: chat, id: opts.msg, serial: Date.now() }
    wa.readSoon()
  }
  function close() { wa.current = "" }

  // Where the list should go (a quote's message, a search result): the
  // view looks and scrolls.
  property var jumpTo: null

  // Read when you can see it: the window in front and the chat open.
  function readSoon() { readTimer.restart() }
  Timer {
    id: readTimer
    interval: 350
    onTriggered: {
      var c = wa.chat(wa.current)
      if (!c || !wa.app.windowFocused || !(c.unread > 0 || c.marked)) return
      wa.send({ c: "read", chat: wa.current, quiet: !wa.app.setting("readReceipts", true) })
    }
  }
  Connections {
    target: wa.app
    function onWindowFocusedChanged() {
      wa.send({ c: "presence", state: wa.app.windowFocused ? "available" : "unavailable" })
      if (wa.app.windowFocused) wa.readSoon()
    }
  }

  // ---------------------------------------------------------------- profiles
  property var profiles: ({})
  property int profilesRev: 0
  function profile(jid) { wa.profilesRev; return wa.profiles[jid] || null }
  function askProfile(jid) { wa.send({ c: "profile", chat: jid }) }

  // Your name and about, changed from the profile: shown at once, and put
  // back if WhatsApp refuses.
  property var undoName: null
  property var undoAbout: null
  function setMyName(text) {
    text = String(text || "").trim()
    if (!wa.me || text === "" || text === wa.me.name) return
    wa.undoName = wa.me.name || ""
    wa.me = Object.assign({}, wa.me, { name: text })
    wa.send({ c: "set_name", text: text })
  }
  function setMyAbout(text) {
    text = String(text || "").trim()
    var p = wa.me ? wa.profiles[wa.me.jid] || {} : null
    if (!p || text === "" || text === (p.about || "")) return
    wa.undoAbout = p.about || ""
    wa.setMyAboutLocal(text)
    wa.send({ c: "set_about", text: text })
  }
  // Your photo: a picture file (cropped and sent by the bridge), or "" to
  // remove it. photoBusy while it goes.
  property bool photoBusy: false
  function setMyPhoto(path) {
    if (!wa.me || wa.photoBusy) return
    wa.photoBusy = true
    wa.send({ c: "set_photo", text: String(path || "") })
  }
  function setMyAboutLocal(text) {
    if (!wa.me) return
    wa.profiles[wa.me.jid] = Object.assign({}, wa.profiles[wa.me.jid] || {}, { about: text })
    wa.profilesRev++
  }

  // ---------------------------------------------------------------- media
  // Downloads under way, by chat + id; failures, the same way.
  property var downloads: ({})
  property int downloadsRev: 0
  function download(m, auto) {
    if (!m || !m.media) return
    var key = m.chat + "|" + m.id
    if (wa.downloads[key] === "busy") return
    wa.downloads[key] = "busy"
    wa.downloadsRev++
    wa.send({ c: "download", chat: m.chat, id: m.id, auto: !!auto })
  }
  function downloadState(m) { wa.downloadsRev; return m ? (wa.downloads[m.chat + "|" + m.id] || "") : "" }
  // Something to do with the file once it's here (open it, save it, play it).
  property var _onDownloaded: ({})
  function whenDownloaded(m, cb) {
    if (!m || !m.media) return
    if (m.media.file) { cb(m.media.file); return }
    wa._onDownloaded[m.chat + "|" + m.id] = cb
    wa.download(m, false)
  }

  // The voice note or audio playing: {chat, id, pos, dur, playing}.
  property var player: null
  property real speed: 1
  function play(m) {
    if (!m || !m.media) return
    if (!m.media.file) { wa.pendingPlay = m.chat + "|" + m.id; wa.download(m, false); return }
    var p = wa.player
    if (p && p.chat === m.chat && p.id === m.id) {
      wa.send({ c: p.playing ? "pause" : "resume" })
      return
    }
    var start = p && p.chat === m.chat && p.id === m.id ? p.pos : 0
    wa.player = { chat: m.chat, id: m.id, pos: start, dur: m.media.secs || 0, playing: true }
    wa.send({ c: "play", chat: m.chat, id: m.id, path: m.media.file, pos: start, speed: wa.speed })
  }
  property string pendingPlay: ""
  function seek(m, frac) {
    var p = wa.player
    var dur = p && p.id === m.id && p.dur > 0 ? p.dur : (m.media ? m.media.secs : 0)
    if (!p || p.id !== m.id) { wa.play(m); return }
    wa.send({ c: "seek", pos: Math.max(0, frac * dur) })
  }
  function cycleSpeed() {
    wa.speed = wa.speed >= 2 ? 1 : wa.speed >= 1.5 ? 2 : 1.5
    wa.send({ c: "speed", speed: wa.speed })
  }
  function stopPlayer() { wa.send({ c: "stop" }); wa.player = null }

  // ---------------------------------------------------------------- the rest
  property var search: null
  property var chatSearch: null
  property var mediaList: null
  property var starred: null
  property var contacts: null
  property var stickers: null
  property var chatSubs: ({})
  property var stickerFavs: ({})

  // ---------------------------------------------------------------- events
  signal incoming(var msg)
  signal reacted(var ev)
  signal failed(string text)

  function handle(ev) {
    switch (ev.t) {
    case "state":
      if (ev.me) wa.me = ev.me
      if (ev.state === "paired") { wa.qr = null; wa.pairCode = ""; wa.conn = "connecting"; break }
      if (ev.state === "pairing") { wa.me = null; wa.chatMap = ({}); wa.chatsRev++ }
      if (ev.state === "logged_out") { wa.me = null; wa.chatMap = ({}); wa.histories = ({}); wa.chatsRev++; wa.historyRev++; wa.current = "" }
      if (ev.state === "qr_timeout") break
      wa.conn = ev.state
      if (ev.state === "ready") {
        wa.everReady = true
        wa.send({ c: "presence", state: wa.app.windowFocused ? "available" : "unavailable" })
        if (wa.current) { wa.send({ c: "subscribe", chat: wa.current }); wa.openHistory(wa.current) }
      }
      break
    case "me":
      if (ev.me) wa.me = ev.me
      // The presence carries your name: the others see the new one at once.
      if (wa.undoName !== null) {
        wa.send({ c: "presence", state: wa.app.windowFocused ? "available" : "unavailable" })
        wa.failed(wa.app.tr("Name changed", "Nome alterado"))
      }
      wa.undoName = null
      break
    case "photo_set":
      wa.photoBusy = false
      wa.failed(ev.removed ? wa.app.tr("Profile photo removed", "Foto do perfil removida") : wa.app.tr("Profile photo changed", "Foto do perfil alterada"))
      break
    case "about":
      if (wa.undoAbout !== null) wa.failed(wa.app.tr("About changed", "Recado alterado"))
      wa.undoAbout = null
      wa.setMyAboutLocal(ev.about || "")
      break
    case "qr":
      wa.qr = { rows: ev.rows || [], code: ev.code || "" }
      if (wa.conn !== "pairing") wa.conn = "pairing"
      break
    case "pair_code":
      wa.pairCode = ev.code || ""
      wa.pairError = ""
      break
    case "sync":
      wa.syncProgress = ev.progress || 0
      break
    case "chats": {
      var map = ev.full ? {} : wa.chatMap
      var list = ev.chats || []
      for (var i = 0; i < list.length; i++) map[list[i].jid] = list[i]
      var gone = ev.gone || []
      for (var g = 0; g < gone.length; g++) delete map[gone[g]]
      wa.chatMap = map
      wa.chatsRev++
      if (wa.current && map[wa.current] && (map[wa.current].unread > 0 || map[wa.current].marked)) wa.readSoon()
      break
    }
    case "message": {
      var m = ev.msg
      if (!m) break
      wa.upsert(m)
      if (wa.pendingPlay === m.chat + "|" + m.id && m.media && m.media.file) { wa.pendingPlay = ""; wa.play(m) }
      if (ev["new"]) {
        if (m.chat === wa.current) wa.readSoon()
        wa.incoming(m)
      }
      break
    }
    case "history": {
      var h = wa.histories[ev.chat]
      if (!h) { h = { msgs: [], olderAsked: false, olderDone: false }; wa.histories[ev.chat] = h }
      var msgs = ev.msgs || []
      if (ev.page) {
        // Older ones, before what's here.
        var have = {}
        for (var a = 0; a < h.msgs.length; a++) have[h.msgs[a].id] = true
        h.msgs = msgs.filter(function(x) { return !have[x.id] }).concat(h.msgs)
        h.more = ev.more
      } else {
        // The newest page: what's older than it stays when we had it.
        if (h.loaded && h.msgs.length > msgs.length && msgs.length > 0) {
          var firstNew = msgs[0]
          var keep = h.msgs.filter(function(x) { return x.ts < firstNew.ts })
          h.msgs = keep.concat(msgs)
        } else {
          h.msgs = msgs
          h.more = ev.more
        }
      }
      h.loading = false
      h.loaded = true
      wa.historyRev++
      break
    }
    case "older": {
      var ho = wa.histories[ev.chat]
      if (ho && !ev.asked) { ho.loading = false; ho.olderDone = true; wa.historyRev++ }
      break
    }
    case "refresh": {
      var hr = wa.histories[ev.chat]
      if (!hr || !hr.loaded) break
      if (ev.older) {
        hr.olderAsked = false
        hr.loading = false
        olderGiveUp.stop()
        // What the phone sent is older than what's here.
        if (hr.msgs.length) { hr.loading = true; wa.send({ c: "history", chat: ev.chat, limit: 60, before: hr.msgs[0].ts, before_id: hr.msgs[0].id }) }
        wa.historyRev++
      } else {
        wa.send({ c: "history", chat: ev.chat, limit: Math.max(60, hr.msgs.length) })
      }
      break
    }
    case "removed": {
      var hd = wa.histories[ev.chat]
      if (!hd) break
      var ids = ev.ids || []
      hd.msgs = hd.msgs.filter(function(x) { return ids.indexOf(x.id) < 0 })
      wa.historyRev++
      break
    }
    case "cleared":
      if (wa.histories[ev.chat]) { wa.histories[ev.chat].msgs = []; wa.historyRev++ }
      break
    case "status": {
      var hs = wa.histories[ev.chat]
      if (!hs) break
      var sids = ev.ids || []
      var changed = false
      var arr = hs.msgs.slice()
      for (var s = arr.length - 1; s >= 0 && sids.length; s--) {
        var at = sids.indexOf(arr[s].id)
        if (at < 0) continue
        if (ev.status < 0 || arr[s].status < ev.status) {
          var cp = U.copy(arr[s])
          cp.status = ev.status
          arr[s] = cp
          changed = true
        }
      }
      if (changed) { hs.msgs = arr; wa.historyRev++ }
      break
    }
    case "typing": {
      if (ev.state === "paused" || ev.state === "available") delete wa.typing[ev.chat]
      else wa.typing[ev.chat] = { who: ev.who || "", jid: ev.jid || "", state: ev.state, until: Date.now() + 25000 }
      wa.typingRev++
      break
    }
    case "presence": {
      wa.presence[ev.jid] = { online: !!ev.online, last_seen: ev.last_seen || (wa.presence[ev.jid] ? wa.presence[ev.jid].last_seen : 0) }
      if (!ev.online) {
        for (var tk in wa.typing) if (tk === ev.jid) delete wa.typing[tk]
        wa.typingRev++
      }
      wa.presenceRev++
      break
    }
    case "avatar":
      wa.avatars[ev.jid] = ev.path ? U.fileUrl(ev.path) + (ev.changed ? "?" + Date.now() : "") : ""
      wa.avatarsRev++
      break
    case "profile": {
      var prev = wa.profiles[ev.chat] || {}
      var p = ev
      if (prev.photo !== undefined) p.photo = prev.photo
      wa.profiles[ev.chat] = p
      wa.profilesRev++
      break
    }
    case "photo": {
      var pp = U.copy(wa.profiles[ev.chat] || {})
      pp.photo = ev.path ? U.fileUrl(ev.path) : ""
      wa.profiles[ev.chat] = pp
      wa.profilesRev++
      break
    }
    case "media": {
      var key = ev.chat + "|" + ev.id
      // An auto download given up: its button again, not a failure.
      if (ev.skipped) {
        delete wa.downloads[key]
        wa.downloadsRev++
        break
      }
      if (ev.error) {
        wa.downloads[key] = "failed"
        wa.downloadsRev++
        if (wa.pendingPlay === key) wa.pendingPlay = ""
        if (wa._onDownloaded[key]) { delete wa._onDownloaded[key]; wa.failed(wa.app.tr("This media is no longer available", "Esta mídia não está mais disponível")) }
        break
      }
      delete wa.downloads[key]
      wa.downloadsRev++
      wa.patchMsg(ev.chat, ev.id, function(x) { if (x.media) { x.media = U.copy(x.media); x.media.file = ev.path } })
      if (wa.pendingPlay === key) { wa.pendingPlay = ""; var pm = wa.findMsg(ev.chat, ev.id); if (pm) wa.play(pm) }
      var after = wa._onDownloaded[key]
      if (after) { delete wa._onDownloaded[key]; after(ev.path) }
      wa.mediaReady(ev.chat, ev.id, ev.path)
      break
    }
    case "thumb":
      wa.patchMsg(ev.chat, ev.id, function(x) { if (x.media) { x.media = U.copy(x.media); x.media.thumb = ev.path } })
      break
    case "player":
      if (ev.error) { wa.player = null; break }
      wa.player = { chat: ev.chat, id: ev.id, pos: ev.pos || 0, dur: ev.dur || 0, playing: !!ev.playing, ended: !!ev.ended }
      if (ev.ended) wa.playNextVoice(ev.chat, ev.id)
      break
    case "search":
      if (ev.chat) wa.chatSearch = ev
      else wa.search = ev
      break
    case "media_list":
      wa.mediaList = ev
      break
    case "contacts":
      wa.contacts = ev.contacts || []
      break
    case "starred":
      wa.starred = ev.msgs || []
      break
    case "stickers":
      wa.stickers = ev.stickers || []
      break
    case "chat_subs":
      wa.chatSubs = ev.subs || {}
      break
    case "sticker_fav": {
      var f = wa.stickerFavs
      f[ev.chat + "|" + ev.id] = !!ev.fav
      wa.stickerFavs = U.copy(f)
      break
    }
    case "reaction":
      wa.reacted(ev)
      break
    case "unread":
      wa.unreadPreview(ev.chat, ev.msgs || [])
      break
    case "error":
      if (ev.code === "set_name" && wa.undoName !== null && wa.me) { wa.me = Object.assign({}, wa.me, { name: wa.undoName }); wa.undoName = null }
      if (ev.code === "set_about" && wa.undoAbout !== null) { wa.setMyAboutLocal(wa.undoAbout); wa.undoAbout = null }
      if (ev.code === "set_photo") wa.photoBusy = false
      if (ev.code === "pair_phone" || ev.code === "pair_phone_number") wa.pairError = L.error(ev.code, wa.app.lang)
      wa.failed(L.error(ev.code, wa.app.lang) + (ev.text && ev.code !== "pair_phone_number" ? "" : ""))
      if (ev.text) console.warn("whatsapp-claude:", ev.code, ev.text)
      break
    }
  }

  signal mediaReady(string chat, string id, string path)
  signal unreadPreview(string chat, var msgs)

  // After a voice note ends, the next unplayed one of the same chat plays,
  // as on the phone.
  function playNextVoice(chat, id) {
    var h = wa.histories[chat]
    if (!h) return
    var i = wa._indexOf(h.msgs, id)
    if (i < 0) return
    var ended = h.msgs[i]
    if (ended.kind !== "ptt" || ended.from_me) return
    for (var j = i + 1; j < h.msgs.length; j++) {
      var n = h.msgs[j]
      if (n.kind === "ptt" && !n.from_me && n.sender === ended.sender) { wa.play(n); return }
      if (n.kind !== "ptt") return
    }
  }

  // ---------------------------------------------------------------- actions
  function sendText(chat, text, reply) {
    text = String(text || "").trim()
    if (!chat || !text) return
    wa.send({ c: "send", chat: chat, text: text, reply: reply || "" })
  }
  function sendFile(chat, path, kind, caption, reply, temp) {
    wa.send({ c: "send_file", chat: chat, path: path, kind: kind || U.kindOf(path), caption: caption || "", reply: reply || "", temp: !!temp })
  }
  function react(m, emoji) { wa.send({ c: "react", chat: m.chat, id: m.id, text: emoji }) }
  function edit(m, text) { wa.send({ c: "edit", chat: m.chat, id: m.id, text: text }) }
  function deleteMsgs(chat, ids, everyone) { wa.send({ c: "delete_msgs", chat: chat, ids: ids, everyone: !!everyone }) }
  function star(chat, ids, on) { wa.send({ c: "star", chat: chat, ids: ids, action: on ? "star" : "unstar" }) }
  function forward(chat, ids, to) { wa.send({ c: "forward", chat: chat, ids: ids, to: to }) }
  function chatAction(chat, action, secs) { wa.send({ c: "chat_action", chat: chat, action: action, secs: secs || 0 }) }
  function typingState(chat, state) { if (chat) wa.send({ c: "typing", chat: chat, state: state }) }
  function doSearch(q) { wa.send({ c: "search", text: q }) }
  function searchIn(chat, q) { wa.send({ c: "search", text: q, chat: chat }) }
  function loadMediaList(chat, kind) { wa.mediaList = null; wa.send({ c: "media_list", chat: chat, kind: kind || "media" }) }
  function loadContacts() { wa.send({ c: "contacts" }) }
  function loadStickers() { wa.send({ c: "stickers" }) }
  function sendSticker(chat, item, reply) {
    if (item.hash) wa.send({ c: "send_sticker", chat: chat, name: item.hash, reply: reply || "" })
    else wa.send({ c: "send_sticker", chat: chat, from: item.chat, id: item.id, reply: reply || "" })
  }
  function stickerFav(m, action) { wa.send({ c: "sticker_fav", chat: m.chat, id: m.id, action: action || "" }) }
  function loadChatSubs() { wa.send({ c: "chat_subs" }) }
  function askUnread(chat, n) { wa.send({ c: "unread", chat: chat, limit: n || 3 }) }
  function pairPhone(phone) { wa.pairCode = ""; wa.pairError = ""; wa.send({ c: "pair_phone", phone: phone }) }
  function logout() { wa.send({ c: "logout" }) }
}
