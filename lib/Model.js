.pragma library
.import "Util.js" as U
.import "Emoji.js" as Emoji

// A chat's messages as the rows its list draws: the day chips, the unread
// band, the notices, and each message knowing whether it starts a run of
// the same sender's (it gets the tail, and in groups the name) or ends one.

// Kinds drawn as centered notices rather than bubbles.
var NOTICE = { system: true }

function isNotice(m) { return !!NOTICE[m.kind] }

function sameRun(a, b) {
  if (!a || !b) return false
  if (isNotice(a) || isNotice(b)) return false
  if (a.from_me !== b.from_me) return false
  if (!a.from_me && a.sender !== b.sender) return false
  return U.daysAgo(a.ts) === U.daysAgo(b.ts)
}

// msgs oldest first; opts: {unreadFrom: id of the first unread, unread:
// how many, group, lang, atStart (no older messages anywhere: the
// encryption notice goes on top)}. Rows keep their object while nothing
// about them changed, so their delegates stay.
function rows(msgs, opts, cache) {
  var out = []
  var lastDay = null
  if (opts.atStart) out.push(cached(cache, "e2e", { key: "e2e", type: "e2e" }))
  for (var i = 0; i < msgs.length; i++) {
    var m = msgs[i]
    var day = U.startOfDay(new Date(m.ts * 1000))
    if (day !== lastDay) {
      out.push(cached(cache, "day:" + day, { key: "day:" + day, type: "day", ts: m.ts }))
      lastDay = day
    }
    if (opts.unreadFrom && m.id === opts.unreadFrom)
      out.push(cached(cache, "unread:" + m.id + ":" + opts.unread, { key: "unread", type: "unread", count: opts.unread }))
    var prev = i > 0 ? msgs[i - 1] : null
    // Four or more photos and videos in a row: one album.
    var end = albumEnd(msgs, i, opts.unreadFrom)
    if (end - i >= ALBUM_MIN) {
      out.push(album(msgs, i, end, prev, opts, cache))
      i = end - 1
      continue
    }
    var next = i + 1 < msgs.length ? msgs[i + 1] : null
    var first = !sameRun(prev, m) || (opts.unreadFrom && m.id === opts.unreadFrom)
    var last = !sameRun(m, next) || (opts.unreadFrom && next && next.id === opts.unreadFrom)
    var type = isNotice(m) ? "notice" : "msg"
    var jumbo = m.kind === "text" && !m.quote && !m.fwd ? Emoji.count(m.text) : 0
    if (jumbo > 3) jumbo = 0
    var sig = type + (first ? "F" : "") + (last ? "L" : "") + (opts.group ? "G" : "") + jumbo
    var hit = cache[m.id]
    if (hit && hit.m === m && hit.sig === sig) { out.push(hit); continue }
    var row = { key: m.id, type: type, m: m, first: first, last: last, group: !!opts.group, jumbo: jumbo, sig: sig }
    cache[m.id] = row
    out.push(row)
  }
  return out
}

// WhatsApp Web's albums: photos and videos sent one after the other by the
// same person, without a caption, a reply or "Forwarded", drawn as one
// bubble of four tiles, the fourth with "+N" over it when there are more.
var ALBUM_MIN = 4
var ALBUM_GAP = 60

function albumable(m) {
  return !!m && (m.kind === "image" || m.kind === "video") && !!m.media && !m.text && !m.quote && !m.fwd
}

// Where the album starting at `i` ends (exclusive): `i + 1` when none does.
// The unread band cuts one.
function albumEnd(msgs, i, unreadFrom) {
  if (!albumable(msgs[i])) return i + 1
  var j = i + 1
  while (j < msgs.length && albumable(msgs[j]) && sameRun(msgs[j - 1], msgs[j])
         && msgs[j].ts - msgs[j - 1].ts <= ALBUM_GAP && msgs[j].id !== unreadFrom) j++
  return j
}

function album(msgs, i, end, prev, opts, cache) {
  var items = msgs.slice(i, end)
  var head = items[0]
  var next = end < msgs.length ? msgs[end] : null
  var first = !sameRun(prev, head) || (opts.unreadFrom && head.id === opts.unreadFrom)
  var last = !sameRun(items[items.length - 1], next) || (opts.unreadFrom && next && next.id === opts.unreadFrom)
  var sig = "album" + (first ? "F" : "") + (last ? "L" : "") + (opts.group ? "G" : "")
  var key = "album:" + head.id
  var hit = cache[key]
  if (hit && hit.sig === sig && hit.items.length === items.length
      && items.every(function(m, k) { return hit.items[k] === m })) return hit
  // The reactions of all of them, on the album's pill.
  var reactions = []
  var at = {}
  items.forEach(function(m) {
    (m.reactions || []).forEach(function(r) {
      if (at[r.emoji] === undefined) { at[r.emoji] = reactions.length; reactions.push({ emoji: r.emoji, count: 0, mine: false }) }
      var x = reactions[at[r.emoji]]
      x.count += r.count
      x.mine = x.mine || !!r.mine
    })
  })
  reactions.sort(function(a, b) { return b.count - a.count })
  // `m` is the newest: its time and ticks go in the corner.
  var row = { key: key, type: "album", m: items[items.length - 1], items: items, reactions: reactions,
              first: first, last: last, group: !!opts.group, jumbo: 0, sig: sig }
  cache[key] = row
  return row
}

// The row holding message `id`: its own, or the album it's in.
function holds(row, id) {
  if (row.key === id) return true
  if (!row.items) return false
  for (var i = 0; i < row.items.length; i++) if (row.items[i].id === id) return true
  return false
}

function cached(cache, key, row) {
  var hit = cache[key]
  if (hit && JSON.stringify(hit) === JSON.stringify(row)) return hit
  cache[key] = row
  return row
}

// Only a missed call counts as unread; the others are no news.
function quietCall(m) {
  if (m.kind !== "call") return false
  var x = m.x
  if (typeof x === "string") { try { x = JSON.parse(x) } catch (e) { x = null } }
  return !(x && x.call && x.call.outcome === "missed")
}

// The newest message of a chat that came from someone else, for marking
// where the unread ones start: the `n` newest of theirs, the first of them.
function firstUnread(msgs, n) {
  if (!n || n <= 0) return ""
  var seen = 0
  for (var i = msgs.length - 1; i >= 0; i--) {
    var m = msgs[i]
    if (m.from_me || isNotice(m) || quietCall(m)) continue
    seen++
    if (seen >= n) return m.id
  }
  return msgs.length ? msgs[0].id : ""
}
