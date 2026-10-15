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

var _ptFolded = null

// Up to `max` emoji whose names (or Portuguese keywords) have the query;
// the ones starting with it first.
function search(query, max) {
  var q = fold(query).trim()
  if (!q) return []
  if (!_ptFolded) {
    _ptFolded = {}
    for (var g in Pt.names) _ptFolded[g] = fold(Pt.names[g])
  }
  var first = [], rest = []
  for (var i = 0; i < Data.list.length; i++) {
    var e = Data.list[i]
    var names = e[1].replace(/_/g, " ") + " " + e[3]
    var pt = _ptFolded[e[0]] || _ptFolded[e[0].replace(/️/g, "")] || ""
    var words = (names + " | " + pt).toLowerCase()
    var at = words.indexOf(q)
    if (at < 0) continue
    var starts = at === 0 || /[\s|]/.test(words.charAt(at - 1))
    ;(starts ? first : rest).push(e[0])
    if (first.length >= (max || 60)) break
  }
  return first.concat(rest).slice(0, max || 60)
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
