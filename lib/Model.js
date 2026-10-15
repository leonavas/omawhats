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

function cached(cache, key, row) {
  var hit = cache[key]
  if (hit && JSON.stringify(hit) === JSON.stringify(row)) return hit
  cache[key] = row
  return row
}

// The newest message of a chat that came from someone else, for marking
// where the unread ones start: the `n` newest of theirs, the first of them.
function firstUnread(msgs, n) {
  if (!n || n <= 0) return ""
  var seen = 0
  for (var i = msgs.length - 1; i >= 0; i--) {
    var m = msgs[i]
    if (m.from_me || isNotice(m)) continue
    seen++
    if (seen >= n) return m.id
  }
  return msgs.length ? msgs[0].id : ""
}
