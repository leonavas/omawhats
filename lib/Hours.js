.pragma library

// A business's opening hours, as WhatsApp Web's contact info puts them:
// whether it's open now and the next change ("Aberta até às 17:00"), and
// each day's hours. `hours` are the bridge's: day 0 is Monday, times in
// minutes after midnight, mode specific_hours, open_24h or appointment_only;
// `tz` the business's UTC offset in seconds, when it set a time zone.

var DAYS_PT = ["segunda-feira", "terça-feira", "quarta-feira", "quinta-feira", "sexta-feira", "sábado", "domingo"]
var DAYS_EN = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

function pt(lang) { return String(lang || "").indexOf("pt") === 0 }
function pad2(n) { return n < 10 ? "0" + n : String(n) }
function clock(minutes) { return pad2(Math.floor(minutes / 60) % 24) + ":" + pad2(minutes % 60) }

// "Segunda-feira", for the week's list.
function dayName(day, lang) {
  var s = (pt(lang) ? DAYS_PT : DAYS_EN)[day]
  return s.charAt(0).toUpperCase() + s.slice(1)
}

// A day's hours as WhatsApp Web lists them: "08:00 - 17:00", "Fechada".
function dayHours(hours, day, lang) {
  var spans = []
  ;(hours || []).forEach(function(h) {
    if (h.day !== day) return
    if (h.mode === "open_24h") spans.push(pt(lang) ? "Aberta 24 horas" : "Open 24 hours")
    else if (h.mode === "appointment_only") spans.push(pt(lang) ? "Com agendamento" : "By appointment only")
    else spans.push(clock(h.open) + " - " + clock(h.close))
  })
  return spans.length ? spans.join(", ") : (pt(lang) ? "Fechada" : "Closed")
}

// Where the week stands now, on the business's clock: {open, always (every
// hour of every day), next ("até às 17:00", "abre amanhã às 08:00"), day}.
function opening(hours, tz, lang) {
  hours = hours || []
  var now = new Date()
  if (tz !== undefined && tz !== null) now = new Date(now.getTime() + now.getTimezoneOffset() * 60000 + tz * 1000)
  var day = (now.getDay() + 6) % 7
  var min = now.getHours() * 60 + now.getMinutes()
  var p = pt(lang)
  function allDay(d) { return hours.some(function(h) { return h.day === d && h.mode === "open_24h" }) }
  if ([0, 1, 2, 3, 4, 5, 6].every(allDay)) return { open: true, always: true, next: "", day: day }
  if (allDay(day)) return { open: true, always: false, next: p ? "24 horas hoje" : "24 hours today", day: day }
  // Hours past midnight close the next day.
  function end(h) { return h.close <= h.open ? h.close + 1440 : h.close }
  for (var i = 0; i < hours.length; i++) {
    var h = hours[i]
    if (h.mode === "open_24h" || h.mode === "appointment_only") continue
    var today = h.day === day && min >= h.open && min < end(h)
    var fromYesterday = h.day === (day + 6) % 7 && end(h) > 1440 && min < end(h) - 1440
    if (today || fromYesterday) return { open: true, always: false, next: (p ? "até às " : "until ") + clock(h.close), day: day }
  }
  // Closed: when it opens next, later today or on a coming day.
  for (var k = 0; k < 8; k++) {
    var d = (day + k) % 7
    var starts = hours.filter(function(x) { return x.day === d && x.mode !== "appointment_only" })
                      .map(function(x) { return x.mode === "open_24h" ? 0 : x.open })
                      .filter(function(o) { return k > 0 || o > min })
    if (starts.length) {
      var o = Math.min.apply(null, starts)
      var when = k === 0 ? "" : k === 1 ? (p ? "amanhã " : "tomorrow ") : (p ? DAYS_PT : DAYS_EN)[d] + " "
      return { open: false, always: false, next: (p ? "abre " + when + "às " : "opens " + when + "at ") + clock(o), day: day }
    }
  }
  return { open: false, always: false, next: "", day: day }
}
