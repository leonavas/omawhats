.pragma library
.import "EmojiData.js" as Data
.import "EmojiPt.js" as Pt

// The emoji panel's catalogue and search (English names and Portuguese
// keywords), and the count WhatsApp uses to draw a message of only one to
// three emoji large.

var GROUP_LABELS = {
  smileys: ["Smileys & people", "Carinhas e pessoas"], people: ["People & body", "Pessoas e corpo"],
  nature: ["Animals & nature", "Animais e natureza"], food: ["Food & drink", "Comidas e bebidas"],
  travel: ["Travel & places", "Viagens e lugares"], activities: ["Activities", "Atividades"],
  objects: ["Objects", "Objetos"], symbols: ["Symbols", "Símbolos"], flags: ["Flags", "Bandeiras"]
}
var GROUP_ICONS = { smileys: "smiley", people: "person", nature: "emojiNature", food: "emojiFood", travel: "car",
                    activities: "sports", objects: "emojiObjects", symbols: "emojiSymbols", flags: "flag" }

var _cat = null
var _catLang = ""

// [{key, label, icon, items: [glyph]}], WhatsApp's groups in its order.
function catalogue(lang) {
  if (_cat && _catLang === lang) return _cat
  var p = String(lang).indexOf("pt") === 0
  var groups = Data.groups.map(function(g) { return { key: g, label: GROUP_LABELS[g][p ? 1 : 0], icon: GROUP_ICONS[g], items: [] } })
  for (var i = 0; i < Data.list.length; i++) groups[Data.list[i][2]].items.push(Data.list[i][0])
  _cat = groups
  _catLang = lang
  return groups
}

// The skin-tone variants of an emoji, light to dark; [] when it has none.
function tones(glyph) {
  for (var i = 0; i < Data.list.length; i++) if (Data.list[i][0] === glyph) return Data.list[i][4] || []
  return []
}

function fold(s) { return String(s || "").toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "") }

// The words of a name, lowercase and without accents ("coração verde" →
// ["coracao", "verde"]).
function words(s) { return fold(s).split(/[^a-z0-9]+/).filter(function(w) { return w !== "" }) }

var _index = {}

// Each emoji's names as searched, made once per language: its phrases (the
// Portuguese keywords, then the English names; English only for an English
// `lang`), each as its words and run together ("coracaoverde").
function index(lang) {
  var pt = lang === undefined || String(lang).indexOf("pt") === 0
  var key = pt ? "pt" : "en"
  if (_index[key]) return _index[key]
  var out = []
  for (var i = 0; i < Data.list.length; i++) {
    var e = Data.list[i]
    var phrases = [e[1].replace(/_/g, " "), e[3]]
    if (pt) {
      var p = Pt.names[e[0]] || Pt.names[e[0].replace(/\uFE0F/g, "")] || ""
      if (p) phrases = p.split("|").concat(phrases)
    }
    var ph = [], seen = {}
    for (var j = 0; j < phrases.length; j++) {
      var w = words(phrases[j])
      if (!w.length) continue
      var joined = w.join("")
      if (seen[joined]) continue
      seen[joined] = true
      ph.push({ words: w, joined: joined })
    }
    out.push({ g: e[0], ph: ph })
  }
  _index[key] = out
  return out
}

// How well an emoji's phrases answer the query's words (0: not at all).
// Every word has to start one of its words. The query as one of its
// phrases first, then all the words in one phrase (its main name, the
// first, and phrases starting with the first word ahead; exact words up,
// extra words down), then the words spread over its phrases, then the
// query run together as the start of a phrase ("coracaoverde"), then
// anywhere in one.
function score(ph, qw, qj) {
  var best = 0
  for (var j = 0; j < ph.length; j++) {
    var p = ph[j]
    var main = j === 0 ? 40 : 0
    var s = 0
    if (p.joined === qj) s = 1000 + main
    else {
      var hit = 0, exact = 0
      for (var k = 0; k < qw.length; k++) {
        for (var x = 0; x < p.words.length; x++) {
          if (p.words[x].indexOf(qw[k]) === 0) { hit++; if (p.words[x] === qw[k]) exact++; break }
        }
      }
      if (hit === qw.length) s = 600 + main + (p.words[0].indexOf(qw[0]) === 0 ? 30 : 0) + exact * 10 - Math.min(5, Math.max(0, p.words.length - qw.length - 1)) * 5
      else if (p.joined.indexOf(qj) === 0) s = 400
      else if (qj.length >= 3 && p.joined.indexOf(qj) > 0) s = 100
    }
    if (s > best) best = s
  }
  if (best < 450 && qw.length > 1) {
    for (var k2 = 0; k2 < qw.length; k2++) {
      var found = false
      for (var j2 = 0; j2 < ph.length && !found; j2++) {
        var ws = ph[j2].words
        for (var x2 = 0; x2 < ws.length; x2++) if (ws[x2].indexOf(qw[k2]) === 0) { found = true; break }
      }
      if (!found) return best
    }
    best = 450
  }
  return best
}

// The most used emoji, most first: among equal matches, after your recent
// ones.
var POPULAR = ["😂", "❤️", "🤣", "👍", "😭", "🙏", "😘", "🥰", "😍", "😊", "🎉", "😁", "💕", "🥺", "😅", "🔥", "☺️", "🤦", "♥️", "🤷",
               "🙄", "😆", "🤗", "😉", "🎂", "🤔", "👏", "🙂", "😳", "🥳", "😎", "👌", "💜", "😔", "💪", "✨", "💖", "👀", "😋", "😏",
               "😢", "👉", "💗", "😩", "💯", "🌹", "💞", "🎈", "💙", "😃", "😡", "💐", "😜", "🙈", "🤞", "😄", "🤤", "🙌", "🤪", "❣️",
               "😀", "💋", "💀", "👇", "💔", "😌", "💓", "🤩", "🙃", "😬", "😱", "😴", "🤭", "😐", "🌞", "😒", "😇", "🌸", "😈", "🎶",
               "✌️", "🎊", "🥵", "😞", "💚", "☀️", "🖤", "💰", "😚", "👑", "🎁", "💥", "🙋", "☹️", "😑", "🥴", "👈", "💩", "✅", "🧡", "💛"]
var _popular = null

// Up to `max` emoji for the query ("cora", "cora verde", "coracaoverde"),
// best first; among equals, the `recent` ones, then the popular ones, then
// WhatsApp's order.
function search(query, max, lang, recent) {
  var qw = words(query)
  if (!qw.length) return []
  var qj = qw.join("")
  var idx = index(lang)
  if (!_popular) {
    _popular = {}
    for (var m = 0; m < POPULAR.length; m++) _popular[POPULAR[m]] = 1000 + m
  }
  var rank = {}
  var r = recent || []
  for (var n = 0; n < r.length; n++) if (rank[r[n]] === undefined) rank[r[n]] = n
  var hits = []
  for (var i = 0; i < idx.length; i++) {
    var s = score(idx[i].ph, qw, qj)
    if (s <= 0) continue
    var g = idx[i].g
    hits.push({ g: g, s: s, r: rank[g] !== undefined ? rank[g] : _popular[g] !== undefined ? _popular[g] : 1e6, i: i })
  }
  hits.sort(function(a, b) { return b.s - a.s || a.r - b.r || a.i - b.i })
  return hits.slice(0, max || 60).map(function(h) { return h.g })
}

// The ":query" being typed for the emoji strip, from the text before the
// cursor: {at, query, end} or null. A colon (at the start or after a space)
// and two letters or more opens one; `open`, where the open one starts (-1:
// none), goes on over single spaces ("cora verde"). A second space ends it,
// and so does a space after words that find nothing (`end`).
function token(upto, open, lang) {
  var m = upto.match(/(^|\s):([^\s:]{2,30})$/)
  if (m) return { at: upto.length - m[2].length - 1, query: m[2], end: false }
  if (open < 0 || open >= upto.length) return null
  var tok = upto.slice(open)
  if (tok.length > 60 || !/^:[^\s:]{2,}( [^\s:]+)* ?$/.test(tok)) return null
  var q = tok.slice(1)
  return { at: open, query: q, end: / $/.test(q) && search(q, 1, lang).length === 0 }
}

function emojiStart(cp) {
  return (cp >= 0x1f000 && cp <= 0x1faff) || (cp >= 0x2600 && cp <= 0x27bf) || (cp >= 0x2300 && cp <= 0x23ff) ||
         (cp >= 0x2b00 && cp <= 0x2bff) || (cp >= 0x2190 && cp <= 0x21ff) || cp === 0x3030 || cp === 0x303d ||
         cp === 0x3297 || cp === 0x3299 || cp === 0xa9 || cp === 0xae || cp === 0x203c || cp === 0x2049 ||
         cp === 0x2122 || cp === 0x2139 || cp === 0x24c2 || (cp >= 0x25aa && cp <= 0x25fe) || (cp >= 0x2934 && cp <= 0x2935)
}

// How many emoji the text is, when it's only emoji (spaces aside); 0 when
// it has anything else.
function count(text) {
  var s = String(text || "").replace(/\s+/g, "")
  if (!s || s.length > 80) return 0
  var n = 0
  var i = 0
  while (i < s.length) {
    var cp = s.codePointAt(i)
    var len = cp > 0xffff ? 2 : 1
    var keycap = (cp === 0x23 || cp === 0x2a || (cp >= 0x30 && cp <= 0x39)) && s.charCodeAt(i + 1) === 0xfe0f && s.charCodeAt(i + 2) === 0x20e3
    if (!emojiStart(cp) && !keycap) return 0
    var j = i + len
    for (;;) {
      if (j >= s.length) break
      var c = s.codePointAt(j)
      if (c === 0xfe0f || c === 0x20e3 || (c >= 0x1f3fb && c <= 0x1f3ff) || (c >= 0xe0020 && c <= 0xe007f)) { j += c > 0xffff ? 2 : 1; continue }
      if (c === 0x200d && j + 1 < s.length) { var nx = s.codePointAt(j + 1); j += 1 + (nx > 0xffff ? 2 : 1); continue }
      if (cp >= 0x1f1e6 && cp <= 0x1f1ff && c >= 0x1f1e6 && c <= 0x1f1ff && j === i + 2) { j += 2; continue }
      break
    }
    n++
    i = j
  }
  return n
}
