.pragma library

// WhatsApp's text formatting, as the bubbles draw it (rich text for a
// TextEdit): *bold*, _italic_, ~strikethrough~, `inline code`, ```mono```
// blocks, "> " quotes, "- " and "1. " lists, links (http, www, bare
// domains, e-mail) and @mentions shown by name.

function esc(s) {
  return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;")
}

var TLDS = "com|net|org|br|io|app|dev|me|co|info|gov|edu|tv|ly|gl|gg|ai|xyz|online|site|store|shop|link|us|uk|pt|de|fr|es|it|jp|ru|cn|in|ca|au|mx|ar|cl|biz|news|blog|tech|cloud|page|sh"
var LINK_RE = new RegExp("([A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\\.[A-Za-z0-9-]+)*\\.[A-Za-z]{2,})" +
                         "|((?:https?:\\/\\/|www\\.)[^\\s<>\"]+)" +
                         "|((?:[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?\\.)+(?:" + TLDS + ")(?![A-Za-z0-9])(?:[\\/?#][^\\s<>\"]*)?)", "g")
var MENTION_RE = /@(\d{5,})/g

// A link's end, without what usually follows it in a sentence.
function trimUrl(u) {
  var s = u
  for (;;) {
    var last = s.charAt(s.length - 1)
    if (".,;:!?'\"*_~".indexOf(last) >= 0) { s = s.slice(0, -1); continue }
    if (last === ")" && (s.split("(").length - 1) < (s.split(")").length - 1)) { s = s.slice(0, -1); continue }
    break
  }
  return s
}

// The links and @mentions in text, as [{at, len, html, plain}].
function spans(text, ctx) {
  var out = []
  var m
  LINK_RE.lastIndex = 0
  while ((m = LINK_RE.exec(text)) !== null) {
    var raw = m[0]
    var url = trimUrl(raw)
    if (!url) continue
    var href = m[1] ? "mailto:" + url : (/^https?:\/\//i.test(url) ? url : "https://" + url)
    out.push({ at: m.index, len: url.length,
               html: "<a href=\"" + esc(href) + "\" style=\"color:" + ctx.link + ";text-decoration:none\">" + esc(url) + "</a>" })
    LINK_RE.lastIndex = m.index + Math.max(1, url.length)
  }
  var byUser = {}
  ;(ctx.mentions || []).forEach(function(x) { byUser[x.user] = x })
  MENTION_RE.lastIndex = 0
  while ((m = MENTION_RE.exec(text)) !== null) {
    var who = byUser[m[1]]
    if (!who) continue
    if (m.index > 0 && /[A-Za-z0-9_]/.test(text.charAt(m.index - 1))) continue
    var clash = out.some(function(o) { return m.index < o.at + o.len && o.at < m.index + m[0].length })
    if (clash) continue
    out.push({ at: m.index, len: m[0].length,
               html: "<a href=\"mention:" + esc(who.jid) + "\" style=\"color:" + ctx.mention + ";text-decoration:none\">@" + esc(who.me ? (ctx.you || who.name) : who.name) + "</a>" })
  }
  out.sort(function(a, b) { return a.at - b.at })
  return out
}

var B = "[\\s.,;:!?()\\[\\]{}'\"“”‘’«»…\\-–—/|<>]"
var FMT = [
  [new RegExp("(^|" + B + ")\\*(?=\\S)([^*\\n]*?\\S)\\*(?=$|" + B + ")", "g"), "<b>", "</b>"],
  [new RegExp("(^|" + B + ")_(?=\\S)([^_\\n]*?\\S)_(?=$|" + B + ")", "g"), "<i>", "</i>"],
  [new RegExp("(^|" + B + ")~(?=\\S)([^~\\n]*?\\S)~(?=$|" + B + ")", "g"), "<s>", "</s>"]
]
var CODE_RE = new RegExp("(^|" + B + ")`(?=\\S)([^`\\n]*?\\S)`(?=$|" + B + ")", "g")

// One line's inline formatting (escaped text in, HTML out). Placeholders
// (n) stand for links and code, which formatting doesn't touch.
function inline(s, ctx, keep) {
  s = s.replace(CODE_RE, function(all, pre, inner) {
    keep.push("<span style=\"font-family:monospace;background-color:" + ctx.codeBg + ";color:" + ctx.code + "\">&#8201;" + inner + "&#8201;</span>")
    return pre + "" + (keep.length - 1) + ""
  })
  for (var pass = 0; pass < 2; pass++)
    for (var i = 0; i < FMT.length; i++) s = s.replace(FMT[i][0], "$1" + FMT[i][1] + "$2" + FMT[i][2])
  return s
}

function restore(s, keep) {
  for (var round = 0; round < 3 && s.indexOf("") >= 0; round++)
    s = s.replace(/(\d+)/g, function(all, n) { return keep[Number(n)] })
  return s
}

// The message's text as rich text. ctx: {link, mention, code, codeBg,
// quote, mentions, you, spacer (HTML put at the very end), limit}.
function render(text, ctx) {
  text = String(text || "")
  var more = false
  if (ctx.limit && text.length > ctx.limit) {
    var cutAt = text.lastIndexOf(" ", ctx.limit)
    text = text.slice(0, cutAt > ctx.limit * 0.7 ? cutAt : ctx.limit) + "…"
    more = true
  }
  var keep = []
  // ``` blocks first: nothing inside them is formatting.
  var parts = text.split(/```/)
  var html = ""
  for (var p = 0; p < parts.length; p++) {
    var part = parts[p]
    if (p % 2 === 1 && p < parts.length - 1) {
      keep.push("<span style=\"font-family:monospace\">" + esc(part).replace(/\n/g, "<br>") + "</span>")
      html += "" + (keep.length - 1) + ""
      continue
    }
    if (p % 2 === 1) part = "```" + part
    // Links and mentions become placeholders before escaping.
    var sp = spans(part, ctx)
    var buf = ""
    var at = 0
    for (var k = 0; k < sp.length; k++) {
      buf += esc(part.slice(at, sp[k].at))
      keep.push(sp[k].html)
      buf += "" + (keep.length - 1) + ""
      at = sp[k].at + sp[k].len
    }
    buf += esc(part.slice(at))
    var lines = buf.split("\n")
    for (var l = 0; l < lines.length; l++) {
      var line = lines[l]
      var m
      if ((m = line.match(/^&gt; ?(.*)$/))) {
        line = "<span style=\"color:" + ctx.quote + "\">▎</span><span style=\"color:" + ctx.quoteText + "\">" + inline(m[1], ctx, keep) + "</span>"
      } else if ((m = line.match(/^\s*[-*•] (.*)$/))) {
        line = "&nbsp;&nbsp;•&nbsp;&nbsp;" + inline(m[1], ctx, keep)
      } else if ((m = line.match(/^\s*(\d{1,3})\. (.*)$/))) {
        line = "&nbsp;&nbsp;" + m[1] + ".&nbsp;" + inline(m[2], ctx, keep)
      } else {
        line = inline(line, ctx, keep)
      }
      lines[l] = line
    }
    html += lines.join("<br>")
  }
  html = restore(html, keep)
  if (more) html += " <a href=\"more:\" style=\"color:" + ctx.link + ";text-decoration:none\"><b>" + (ctx.moreLabel || "Read more") + "</b></a>"
  return "<span style=\"white-space:pre-wrap\">" + html + (ctx.spacer || "") + "</span>"
}

// The text without its formatting marks, mentions by name, on one line:
// for previews, quotes and notifications.
function plain(text, mentions, you) {
  var s = String(text || "")
  var byUser = {}
  ;(mentions || []).forEach(function(x) { byUser[x.user] = x })
  s = s.replace(MENTION_RE, function(all, user) { var w = byUser[user]; return w ? "@" + (w.me ? (you || w.name) : w.name) : all })
  s = s.replace(/```/g, "")
  for (var i = 0; i < FMT.length; i++) s = s.replace(FMT[i][0], "$1$2")
  s = s.replace(CODE_RE, "$1$2")
  return s.replace(/\s*\n+\s*/g, " ")
}

// The same, as styled text with its bold, italics and strikethrough
// kept (the chat list and the bar's preview).
function styled(text, mentions, you) {
  var s = String(text || "")
  var byUser = {}
  ;(mentions || []).forEach(function(x) { byUser[x.user] = x })
  s = s.replace(MENTION_RE, function(all, user) { var w = byUser[user]; return w ? "@" + (w.me ? (you || w.name) : w.name) : all })
  s = esc(s.replace(/```/g, "").replace(/\s*\n+\s*/g, " "))
  for (var i = 0; i < FMT.length; i++) s = s.replace(FMT[i][0], "$1" + FMT[i][1] + "$2" + FMT[i][2])
  return s.replace(CODE_RE, "$1$2")
}

// The first link in the text, for a preview card; "" when none.
function firstLink(text) {
  LINK_RE.lastIndex = 0
  var m = LINK_RE.exec(String(text || ""))
  if (!m || m[1]) return ""
  var u = trimUrl(m[0])
  return /^https?:\/\//i.test(u) ? u : "https://" + u
}
