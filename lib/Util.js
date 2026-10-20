.pragma library

// Small helpers: copies, the dates and times WhatsApp writes, phone
// numbers as it shows them, sizes and lengths.

function copy(o) {
  if (o === null || typeof o !== "object") return o
  if (Array.isArray(o)) return o.slice()
  var out = {}
  for (var k in o) out[k] = o[k]
  return out
}

function pad2(n) { return n < 10 ? "0" + n : String(n) }

function pt(lang) { return String(lang || "").indexOf("pt") === 0 }

// ---------------------------------------------------------------- time

function clock(ts, clock24) {
  var d = new Date(ts * 1000)
  if (clock24) return pad2(d.getHours()) + ":" + pad2(d.getMinutes())
  var h = d.getHours() % 12
  return (h === 0 ? 12 : h) + ":" + pad2(d.getMinutes()) + (d.getHours() < 12 ? " AM" : " PM")
}

function startOfDay(d) { return new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime() }

// Whole days between ts and today (0 today, 1 yesterday…).
function daysAgo(ts) {
  var now = new Date()
  return Math.round((startOfDay(now) - startOfDay(new Date(ts * 1000))) / 86400000)
}

var WEEKDAYS_PT = ["domingo", "segunda-feira", "terça-feira", "quarta-feira", "quinta-feira", "sexta-feira", "sábado"]
var WEEKDAYS_EN = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
var MONTHS_PT = ["janeiro", "fevereiro", "março", "abril", "maio", "junho", "julho", "agosto", "setembro", "outubro", "novembro", "dezembro"]
var MONTHS_EN = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]

function weekday(ts, lang) { return (pt(lang) ? WEEKDAYS_PT : WEEKDAYS_EN)[new Date(ts * 1000).getDay()] }

function shortDate(ts, lang) {
  var d = new Date(ts * 1000)
  return pt(lang) ? pad2(d.getDate()) + "/" + pad2(d.getMonth() + 1) + "/" + d.getFullYear()
                  : (d.getMonth() + 1) + "/" + d.getDate() + "/" + d.getFullYear()
}

// A chat row's time: the hour today, "Ontem", the weekday this week, the date before.
function listTime(ts, lang, clock24) {
  if (!ts) return ""
  var days = daysAgo(ts)
  if (days <= 0) return clock(ts, clock24)
  if (days === 1) return pt(lang) ? "Ontem" : "Yesterday"
  if (days < 7) return weekday(ts, lang)
  return shortDate(ts, lang)
}

// The chip between days: "Hoje", "Ontem", the weekday this week, the date before.
function dayLabel(ts, lang) {
  var days = daysAgo(ts)
  if (days <= 0) return pt(lang) ? "Hoje" : "Today"
  if (days === 1) return pt(lang) ? "Ontem" : "Yesterday"
  if (days < 7) return weekday(ts, lang)
  return shortDate(ts, lang)
}

// "Hoje às 19:20", as a message's info says when it was read.
function dayAt(ts, lang, clock24) {
  if (!ts) return ""
  return dayLabel(ts, lang) + (pt(lang) ? " às " : " at ") + clock(ts, clock24)
}

function longDate(ts, lang) {
  var d = new Date(ts * 1000)
  return pt(lang) ? d.getDate() + " de " + MONTHS_PT[d.getMonth()] + " de " + d.getFullYear()
                  : MONTHS_EN[d.getMonth()] + " " + d.getDate() + ", " + d.getFullYear()
}

// "visto por último hoje às 14:05".
function lastSeen(ts, lang, clock24) {
  if (!ts) return ""
  var days = daysAgo(ts)
  var at = clock(ts, clock24)
  if (pt(lang)) {
    if (days <= 0) return "visto por último hoje às " + at
    if (days === 1) return "visto por último ontem às " + at
    return "visto por último em " + shortDate(ts, lang) + " às " + at
  }
  if (days <= 0) return "last seen today at " + at
  if (days === 1) return "last seen yesterday at " + at
  return "last seen " + shortDate(ts, lang) + " at " + at
}

function ago(ts, lang) {
  var s = Math.max(0, Date.now() / 1000 - ts)
  var p = pt(lang)
  if (s < 60) return p ? "agora" : "now"
  if (s < 3600) return Math.floor(s / 60) + " min"
  if (s < 86400) return Math.floor(s / 3600) + " h"
  return Math.floor(s / 86400) + (p ? " d" : "d")
}

// ---------------------------------------------------------------- numbers

// m:ss, or h:mm:ss.
function duration(secs) {
  secs = Math.max(0, Math.round(secs || 0))
  var h = Math.floor(secs / 3600), m = Math.floor(secs % 3600 / 60), s = secs % 60
  return h > 0 ? h + ":" + pad2(m) + ":" + pad2(s) : m + ":" + pad2(s)
}

// A call's length, as WhatsApp words it: 19 seconds, 1 min 5 s, 1 h 2 min.
function callLength(secs, lang) {
  secs = Math.max(0, Math.round(secs || 0))
  var p = pt(lang)
  if (secs < 60) return secs + (p ? (secs === 1 ? " segundo" : " segundos") : (secs === 1 ? " second" : " seconds"))
  var h = Math.floor(secs / 3600), m = Math.floor(secs % 3600 / 60), s = secs % 60
  if (h > 0) return h + " h" + (m ? " " + m + " min" : "")
  return m + " min" + (s ? " " + s + " s" : "")
}

function fileSize(bytes, lang) {
  bytes = Number(bytes || 0)
  var units = ["B", "kB", "MB", "GB"]
  var i = 0
  while (bytes >= 1000 && i < units.length - 1) { bytes /= 1000; i++ }
  var n = i === 0 ? String(Math.round(bytes)) : bytes.toFixed(bytes < 10 ? 1 : 0)
  if (pt(lang)) n = n.replace(".", ",")
  return n + " " + units[i]
}

// Phone numbers as WhatsApp writes them: +55 11 91234-5678.
var CODES = ["1", "7", "20", "27", "30", "31", "32", "33", "34", "36", "39", "40", "41", "43", "44", "45", "46", "47", "48", "49", "51", "52",
             "53", "54", "55", "56", "57", "58", "60", "61", "62", "63", "64", "65", "66", "81", "82", "84", "86", "90", "91", "92", "93",
             "94", "95", "98", "212", "213", "216", "218", "220", "221", "233", "234", "244", "254", "255", "256", "258", "260", "263",
             "351", "352", "353", "354", "355", "356", "357", "358", "359", "370", "371", "372", "373", "374", "375", "376", "380", "381",
             "385", "386", "387", "389", "420", "421", "502", "503", "504", "505", "506", "507", "509", "591", "592", "593", "595", "597",
             "598", "852", "853", "855", "856", "880", "886", "960", "961", "962", "963", "964", "965", "966", "967", "968", "970", "971",
             "972", "973", "974", "975", "976", "977", "992", "993", "994", "995", "996", "998"]

function phone(digits) {
  var d = String(digits || "").replace(/\D/g, "")
  if (!d) return ""
  if (d.indexOf("55") === 0 && (d.length === 12 || d.length === 13)) {
    var area = d.slice(2, 4), rest = d.slice(4)
    return "+55 " + area + " " + rest.slice(0, rest.length - 4) + "-" + rest.slice(-4)
  }
  if (d.indexOf("1") === 0 && d.length === 11)
    return "+1 " + d.slice(1, 4) + "-" + d.slice(4, 7) + "-" + d.slice(7)
  var cc = ""
  for (var n = 3; n >= 1; n--) if (CODES.indexOf(d.slice(0, n)) >= 0) { cc = d.slice(0, n); break }
  if (!cc) return "+" + d
  var r = d.slice(cc.length)
  var groups = []
  while (r.length > 4) { groups.push(r.slice(0, r.length > 7 ? 3 : r.length - 4)); r = r.slice(groups[groups.length - 1].length) }
  groups.push(r)
  return "+" + cc + " " + groups.join(" ")
}

// ---------------------------------------------------------------- names

function initials(name) {
  var words = String(name || "").replace(/[~+]/g, "").trim().split(/\s+/).filter(function(w) {
    var c = Array.from(w)[0] || ""
    return c.toLowerCase() !== c.toUpperCase() || /[0-9]/.test(c)
  })
  if (words.length === 0) return ""
  var first = Array.from(words[0])[0] || ""
  var last = words.length > 1 ? (Array.from(words[words.length - 1])[0] || "") : ""
  return (first + last).toUpperCase()
}

// A stable small number for a string (a group member's color).
function hash(s) {
  s = String(s || "")
  var h = 0
  for (var i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) | 0
  return Math.abs(h)
}

function fold(s) {
  return String(s || "").toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "")
}

function basename(p) { var s = String(p || ""); var i = s.lastIndexOf("/"); return i >= 0 ? s.slice(i + 1) : s }

function ext(name) { var s = basename(name); var i = s.lastIndexOf("."); return i > 0 ? s.slice(i + 1).toLowerCase() : "" }

function fileUrl(path) {
  if (!path) return ""
  if (String(path).indexOf("file://") === 0) return path
  return "file://" + String(path).split("/").map(encodeURIComponent).join("/")
}

function unfileUrl(url) {
  var s = String(url || "")
  if (s.indexOf("file://") === 0) s = decodeURIComponent(s.slice(7))
  return s
}

// What a file goes as: image, video, audio or document, by its extension.
function kindOf(path) {
  var e = ext(path)
  if (["jpg", "jpeg", "png", "webp", "gif", "bmp"].indexOf(e) >= 0) return e === "gif" ? "video" : "image"
  if (["mp4", "mov", "m4v", "3gp", "webm", "mkv"].indexOf(e) >= 0) return "video"
  if (["mp3", "m4a", "aac", "ogg", "opus", "wav", "flac", "amr"].indexOf(e) >= 0) return "audio"
  return "document"
}
