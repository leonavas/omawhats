import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// WhatsApp Web's surfaces in the Omarchy theme's colors: the shell's base
// palette (it follows theme switches live) and the theme's colors.toml for
// the named colors. Sizes are WhatsApp Web's, scaled with the shell's type
// scale and the app's zoom.
QtObject {
  id: t

  property real zoom: 1.0
  property bool themeFont: true
  property var pal: ({})

  function mix(a, b, f) {
    return Qt.rgba(a.r * (1 - f) + b.r * f, a.g * (1 - f) + b.g * f, a.b * (1 - f) + b.b * f, a.a * (1 - f) + b.a * f)
  }
  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
  function hex(c) {
    function h(v) { var s = Math.round(Math.max(0, Math.min(1, v)) * 255).toString(16); return s.length < 2 ? "0" + s : s }
    return "#" + h(c.r) + h(c.g) + h(c.b)
  }
  function rgba(c, a) { return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + "," + a + ")" }
  function pick(key, fallback) { var v = t.pal[key]; return v ? v : fallback }
  function luma(c) { return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b }
  function onColor(c) { return t.luma(c) > 0.55 ? Qt.darker(t.bg, 1.6) : "#ffffff" }

  // ---------------------------------------------------------------- palette
  readonly property color bg: Color.background
  readonly property color fg: Color.foreground
  readonly property color accent: Color.accent
  readonly property color urgent: Color.urgent
  readonly property bool dark: luma(bg) < 0.5

  readonly property color bgDark: pick("dark_background", Qt.darker(bg, 1.18))
  readonly property color bgDarker: pick("darker_background", Qt.darker(bg, 1.4))
  readonly property color bgLight: pick("lighter_background", dark ? Qt.lighter(bg, 1.35) : Qt.darker(bg, 1.05))
  readonly property color red: pick("red", pick("color1", urgent))
  readonly property color green: pick("green", pick("color2", "#25d366"))
  readonly property color yellow: pick("yellow", pick("color3", "#ffd279"))
  readonly property color blue: pick("blue", pick("color4", "#53bdeb"))
  readonly property color magenta: pick("magenta", pick("color5", "#a791ff"))
  readonly property color cyan: pick("cyan", pick("color6", "#42c7b8"))
  readonly property color orange: pick("orange", pick("bright_red", "#fc9775"))

  // ---------------------------------------------------------------- surfaces
  // WhatsApp Web (dark): the rail a step above the panels, the panels the
  // page, the chat a shade under it with its doodles, bubbles raised from
  // it (yours tinted with the accent, as WhatsApp's are with its green).
  readonly property color rail: dark ? mix(bg, fg, 0.035) : mix(bg, fg, 0.03)
  readonly property color panel: bg
  readonly property color header: bg
  readonly property color chatBg: dark ? mix(bg, bgDarker, 0.35) : mix(bg, fg, 0.03)
  readonly property color doodle: fg
  readonly property real doodleAlpha: dark ? 0.055 : 0.07
  readonly property color bubbleIn: dark ? mix(bg, fg, 0.085) : Qt.lighter(bg, 1.06)
  readonly property color bubbleOut: dark ? mix(bg, accent, 0.30) : mix(bg, accent, 0.20)
  readonly property color bubbleOutText: fg
  readonly property color composer: dark ? mix(bg, fg, 0.085) : mix(bg, fg, 0.04)
  readonly property color field: dark ? mix(bg, fg, 0.08) : mix(bg, fg, 0.05)
  readonly property color chip: dark ? mix(bg, fg, 0.06) : mix(bg, fg, 0.04)
  readonly property color system: dark ? mix(chatBg, fg, 0.07) : alpha(Qt.lighter(bg, 1.05), 0.92)
  readonly property color popup: dark ? mix(bg, fg, 0.07) : Qt.lighter(bg, 1.04)
  readonly property color line: alpha(fg, 0.10)
  readonly property color lineStrong: alpha(fg, 0.17)
  readonly property color hover: alpha(fg, 0.06)
  readonly property color hoverStrong: alpha(fg, 0.10)
  readonly property color selected: alpha(fg, 0.11)
  readonly property color press: alpha(fg, 0.16)
  readonly property color scrim: alpha(bgDarker, 0.6)

  // ---------------------------------------------------------------- content
  readonly property color text: fg
  readonly property color textBright: pick("bright_foreground", fg)
  readonly property color dim: alpha(fg, 0.62)
  readonly property color faint: alpha(fg, 0.42)
  readonly property color icon: alpha(fg, 0.8)
  // WhatsApp's green, where the theme's accent stands in for it.
  readonly property color brand: accent
  readonly property color onBrand: onColor(accent)
  readonly property color badge: accent
  readonly property color badgeText: onColor(accent)
  readonly property color chipOn: alpha(accent, dark ? 0.22 : 0.18)
  readonly property color chipOnText: dark ? Qt.lighter(accent, 1.25) : Qt.darker(accent, 1.4)
  readonly property color read: blue
  readonly property color link: dark ? Qt.lighter(blue, 1.05) : Qt.darker(blue, 1.25)
  readonly property color mention: accent
  readonly property color danger: red
  readonly property color warning: yellow
  readonly property color online: green
  readonly property color code: orange
  readonly property color quoteBar: accent
  readonly property color quoteBg: alpha(fg, dark ? 0.07 : 0.05)
  readonly property color unreadBand: alpha(fg, dark ? 0.06 : 0.07)
  readonly property color flash: alpha(yellow, 0.22)

  // Group members' names, each in one of these, as WhatsApp colors them.
  readonly property var nameColors: [blue, magenta, cyan, orange, green, yellow, red,
    Qt.lighter(blue, 1.25), Qt.lighter(magenta, 1.2), Qt.lighter(cyan, 1.2), Qt.lighter(orange, 1.15), Qt.lighter(green, 1.2)]
  function nameColor(key) {
    var s = String(key || ""), h = 0
    for (var i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) | 0
    return nameColors[Math.abs(h) % nameColors.length]
  }
  // A default picture's colors: the initials in one of the palette's
  // colors over a deep shade of it.
  function avatarColors(key) {
    var c = nameColor(key)
    return { fg: dark ? Qt.lighter(c, 1.1) : Qt.darker(c, 1.3), bg: mix(bg, c, dark ? 0.22 : 0.2) }
  }

  // Colors as strings, for the rich text the renderer writes.
  readonly property var html: ({
    link: hex(link), mention: hex(mention), code: hex(code), codeBg: rgba(fg, dark ? 0.09 : 0.07),
    quote: hex(alpha(fg, 0.5)), quoteText: hex(mix(fg, bg, 0.25)), dim: hex(dim), text: hex(fg)
  })

  // ---------------------------------------------------------------- type
  readonly property string font: themeFont ? Style.font.family : "sans-serif"
  readonly property string emojiFont: "Noto Color Emoji"
  readonly property int base: Style.font.baseSize
  function px(n) { return Math.max(8, Math.round(n * t.zoom * (t.base / 12))) }
  readonly property int fsMsg: px(14.2)
  readonly property int fsMeta: px(11)
  readonly property int fsSmall: px(12)
  readonly property int fsText: px(14)
  readonly property int fsName: px(16)
  readonly property int fsTitle: px(16)
  readonly property int fsHeader: px(22)
  readonly property int fsHuge: px(28)
  readonly property int fsChip: px(13.5)

  // ---------------------------------------------------------------- shape
  function sp(n) { return Math.round(n * t.zoom) }
  readonly property int radius: Math.max(0, Style.cornerRadius)
  readonly property int bubbleRadius: sp(8)
  readonly property int railWidth: sp(64)
  readonly property int headerHeight: sp(60)
  readonly property int rowHeight: sp(72)
  readonly property int avatar: sp(49)
  readonly property int avatarHeader: sp(40)

  // ---------------------------------------------------------------- the theme file
  readonly property string themeDir: (Quickshell.env("HOME") || "") + "/.local/state/omarchy/current/theme"

  property FileView paletteFile: FileView {
    path: t.themeDir + "/colors.toml"
    printErrors: false
    onLoaded: t.parsePalette(text())
    onLoadFailed: t.pal = ({})
  }

  function parsePalette(raw) {
    var out = {}
    String(raw || "").split("\n").forEach(function(line) {
      var m = line.match(/^\s*([A-Za-z0-9_-]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
      if (m) out[m[1]] = m[2]
    })
    t.pal = out
  }

  // A theme switch pushes new colors into the shell: read the file again.
  property Connections themeWatch: Connections {
    target: Color
    function onBackgroundChanged() { t.paletteFile.reload() }
    function onAccentChanged() { t.paletteFile.reload() }
  }
}
