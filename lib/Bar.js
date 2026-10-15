.pragma library

// The bar widget's helpers, as whatsapp-tui's widget has them: when a pause
// ends, the pause picker's day and time, how long ago, the badge's digits.
// `lang` is "pt-BR" or anything else for English.

function pt(lang) { return lang === "pt-BR" }

function pad(n) {
  return n < 10 ? "0" + n : String(n)
}

var WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
var WEEKDAYS_PT = ["dom", "seg", "ter", "qua", "qui", "sex", "sáb"]
var MONTHS_PT = ["jan", "fev", "mar", "abr", "mai", "jun", "jul", "ago", "set", "out", "nov", "dez"]

// Calendar days from now's day to when's day; DST days are 23 or 25 hours
// long, so the difference is rounded rather than floored.
function dayOffset(when, now) {
  var a = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime()
  var b = new Date(when.getFullYear(), when.getMonth(), when.getDate()).getTime()
  return Math.round((b - a) / 86400000)
}

// "Oct 20" ("20 out"), with the year only when it is not this one.
function dateLabel(when, now, lang) {
  var text = pt(lang) ? when.getDate() + " " + MONTHS_PT[when.getMonth()] : MONTHS[when.getMonth()] + " " + when.getDate()
  return when.getFullYear() !== now.getFullYear() ? text + " " + when.getFullYear() : text
}

// "14:30" today, "tomorrow 08:00", "Tue 08:00" within the coming week,
// otherwise "Oct 20, 08:00". A bare weekday further out would point at the
// wrong week.
function clockLabel(unixSec, nowSec, lang) {
  if (!unixSec) return ""
  var when = new Date(unixSec * 1000)
  var now = new Date(nowSec * 1000)
  var hm = pad(when.getHours()) + ":" + pad(when.getMinutes())
  var days = dayOffset(when, now)
  if (days === 0) return hm
  if (days === 1) return (pt(lang) ? "amanhã " : "tomorrow ") + hm
  if (days > 1 && days <= 6) return (pt(lang) ? WEEKDAYS_PT : WEEKDAYS)[when.getDay()] + " " + hm
  return dateLabel(when, now, lang) + ", " + hm
}

// The day picker's label for `offset` days from now: "Today", "Tomorrow",
// then "Wed, Oct 14".
function pickerDayLabel(offset, nowSec, lang) {
  if (offset === 0) return pt(lang) ? "Hoje" : "Today"
  if (offset === 1) return pt(lang) ? "Amanhã" : "Tomorrow"
  var now = new Date(nowSec * 1000)
  var day = new Date(now.getFullYear(), now.getMonth(), now.getDate() + offset)
  return (pt(lang) ? WEEKDAYS_PT : WEEKDAYS)[day.getDay()] + ", " + dateLabel(day, now, lang)
}

// Unix seconds of hour:minute, `offset` days from now's day. Built from the
// calendar date, so month ends and DST come out right.
function pickerTarget(offset, hour, minute, nowSec) {
  var now = new Date(nowSec * 1000)
  return new Date(now.getFullYear(), now.getMonth(), now.getDate() + offset, hour, minute, 0).getTime() / 1000
}

// Where the picker starts: the full hour after the next one (14:20 gives
// 16:00), rolling over into tomorrow when that passes midnight.
function pickerDefault(nowSec) {
  var now = new Date(nowSec * 1000)
  var hour = now.getHours() + 2
  return { day: hour >= 24 ? 1 : 0, hour: hour % 24, minute: 0 }
}

// Whole minutes from now to the target, rounded up so the pause never ends
// before the time picked. 0 when the target is not in the future.
function minutesUntil(targetSec, nowSec) {
  var delta = targetSec - nowSec
  return delta > 0 ? Math.ceil(delta / 60) : 0
}

// Minutes to 9 AM tomorrow, whatsapp-tui's "tomorrow".
function minutesToTomorrow(nowSec) {
  var now = new Date(nowSec * 1000)
  return minutesUntil(new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1, 9, 0, 0).getTime() / 1000, nowSec)
}

// Minutes to next Monday, 9 AM: whatsapp-tui's "next week".
function minutesToNextWeek(nowSec) {
  var now = new Date(nowSec * 1000)
  var days = 7 - (now.getDay() + 6) % 7
  return minutesUntil(new Date(now.getFullYear(), now.getMonth(), now.getDate() + days, 9, 0, 0).getTime() / 1000, nowSec)
}

function relativeTime(ts, nowSec, lang) {
  var then = Number(ts)
  if (!isFinite(then) || then <= 0) return ""
  var delta = Math.max(0, nowSec - then)
  if (delta < 60) return pt(lang) ? "agora" : "now"
  if (delta < 3600) return Math.floor(delta / 60) + "m"
  if (delta < 86400) return Math.floor(delta / 3600) + "h"
  return Math.floor(delta / 86400) + "d"
}

// Nerd Font glyphs: account, account-multiple.
function kindGlyph(kind) {
  return kind === "group" ? "󰀎" : "󰀄"
}

function badgeLabel(count) {
  return count > 99 ? "99+" : String(count)
}
