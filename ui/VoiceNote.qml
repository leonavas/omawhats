import QtQuick
import QtQuick.Controls
import "../lib/Util.js" as U
import "../lib/Registry.js" as Reg

// A voice note (or an audio file) as WhatsApp Web plays it: the picture
// of who sent it with a microphone (or the orange headphones of a file),
// play/pause, the waveform you can click or drag through, the length (or
// where it is), the speed while it plays, and the time and ticks.
Item {
  id: vn
  property var app: Reg.service
  readonly property var t: app.theme
  readonly property var wa: app.wa
  property var m
  property real maxWidth: 320
  readonly property var media: m.media || {}
  readonly property bool ptt: m.kind === "ptt" || !!media.ptt
  readonly property var p: wa.player && wa.player.chat === m.chat && wa.player.id === m.id ? wa.player : null
  readonly property bool playing: !!p && p.playing
  readonly property real dur: p && p.dur > 0 ? p.dur : (media.secs || 0)
  readonly property real progress: p && dur > 0 ? Math.min(1, p.pos / dur) : 0
  readonly property bool busy: wa.downloadState(m) === "busy" || wa.pendingPlay === m.chat + "|" + m.id
  readonly property bool failed: wa.downloadState(m) === "failed"
  // Heard: yours, or played (blue mic) — the phone's "played" status.
  readonly property bool heard: m.from_me || m.status >= 4 || !!p

  implicitWidth: Math.min(maxWidth, t.sp(330))
  height: t.sp(62)

  // The picture side: the sender's photo with a mic, or the headphones.
  Item {
    id: face
    x: vn.m.from_me ? parent.width - width : 0
    width: vn.t.sp(55)
    height: parent.height
    visible: !vn.playing || !vn.ptt
    Avatar {
      visible: vn.ptt
      anchors.verticalCenter: parent.verticalCenter
      size: vn.t.sp(52)
      jid: vn.m.from_me ? (vn.wa.me ? vn.wa.me.jid : "") : vn.m.sender
      name: vn.m.from_me ? (vn.wa.me ? vn.wa.me.name : "") : String(vn.m.name || "").replace(/^~/, "")
    }
    Icon {
      visible: vn.ptt
      x: vn.m.from_me ? -vn.t.sp(4) : parent.width - width + vn.t.sp(2)
      y: parent.height - height - vn.t.sp(4)
      name: "micFilled"
      size: vn.t.sp(20)
      color: vn.heard ? vn.t.read : vn.t.accent
    }
    Rectangle {
      visible: !vn.ptt
      anchors.verticalCenter: parent.verticalCenter
      width: vn.t.sp(52); height: width; radius: width / 2
      color: vn.t.orange
      Icon { anchors.centerIn: parent; name: "headphones"; size: vn.t.sp(28); color: "white" }
    }
  }
  // While a voice note plays, the speed takes the picture's place.
  Rectangle {
    visible: vn.playing && vn.ptt
    anchors.verticalCenter: parent.verticalCenter
    x: vn.m.from_me ? parent.width - width - vn.t.sp(8) : vn.t.sp(8)
    width: vn.t.sp(42); height: vn.t.sp(26); radius: height / 2
    color: vn.t.alpha(vn.t.fg, 0.16)
    Text {
      textFormat: Text.PlainText
      anchors.centerIn: parent
      text: (vn.wa.speed === 1 ? "1" : vn.wa.speed === 1.5 ? (vn.app.lang === "pt-BR" ? "1,5" : "1.5") : "2") + "×"
      color: vn.t.text
      font.family: vn.t.font
      font.pixelSize: vn.t.fsSmall
      font.weight: Font.Medium
    }
    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: vn.wa.cycleSpeed() }
  }

  readonly property real sideX: vn.m.from_me ? 0 : face.width + vn.t.sp(6)
  readonly property real sideW: parent.width - face.width - vn.t.sp(6)

  Item {
    id: btn
    x: vn.sideX
    anchors.verticalCenter: parent.verticalCenter
    anchors.verticalCenterOffset: -vn.t.sp(6)
    width: vn.t.sp(36); height: width
    BusyIndicator { anchors.centerIn: parent; running: vn.busy; visible: running; width: vn.t.sp(30); height: width }
    Icon {
      anchors.centerIn: parent
      visible: !vn.busy
      name: vn.failed ? "refresh" : (vn.playing ? "pause" : "play")
      size: vn.t.sp(32)
      color: vn.t.icon
    }
    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: vn.wa.play(vn.m) }
  }

  // The waveform: 48 bars from the note's levels (a gentle line for an
  // audio file without them), the played part brighter, a dot where it is.
  Item {
    id: wave
    x: btn.x + btn.width + vn.t.sp(8)
    width: vn.sideX + vn.sideW - x - vn.t.sp(10)
    height: vn.t.sp(30)
    anchors.verticalCenter: parent.verticalCenter
    anchors.verticalCenterOffset: -vn.t.sp(6)
    readonly property var levels: {
      var w = vn.media.wave || []
      var out = []
      var n = 44
      for (var i = 0; i < n; i++) {
        if (w.length) {
          var a = Math.floor(i * w.length / n), b2 = Math.max(a + 1, Math.floor((i + 1) * w.length / n))
          var s = 0
          for (var j = a; j < b2; j++) s += w[j]
          out.push(s / (b2 - a) / 100)
        } else out.push(-1)
      }
      return out
    }
    Row {
      anchors.verticalCenter: parent.verticalCenter
      spacing: Math.max(1, (wave.width - wave.levels.length * vn.t.sp(3)) / Math.max(1, wave.levels.length - 1))
      visible: (vn.media.wave || []).length > 0
      Repeater {
        model: wave.levels
        delegate: Rectangle {
          required property var modelData
          required property int index
          width: vn.t.sp(3)
          height: Math.max(vn.t.sp(3), modelData * wave.height)
          radius: width / 2
          anchors.verticalCenter: parent ? parent.verticalCenter : undefined
          color: index / wave.levels.length < vn.progress ? (vn.heard ? vn.t.read : vn.t.accent) : vn.t.alpha(vn.t.fg, 0.38)
        }
      }
    }
    Rectangle {
      visible: (vn.media.wave || []).length === 0
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width
      height: vn.t.sp(4)
      radius: height / 2
      color: vn.t.alpha(vn.t.fg, 0.25)
      Rectangle { width: parent.width * vn.progress; height: parent.height; radius: parent.radius; color: vn.heard ? vn.t.read : vn.t.accent }
    }
    Rectangle {
      x: vn.progress * (parent.width - width)
      anchors.verticalCenter: parent.verticalCenter
      width: vn.t.sp(13); height: width; radius: width / 2
      color: vn.heard ? vn.t.read : vn.t.accent
    }
    MouseArea {
      anchors.fill: parent
      anchors.topMargin: -vn.t.sp(6)
      anchors.bottomMargin: -vn.t.sp(6)
      cursorShape: Qt.PointingHandCursor
      onPressed: mouse => vn.wa.seek(vn.m, Math.max(0, Math.min(1, mouse.x / width)))
      onPositionChanged: mouse => { if (pressed) vn.wa.seek(vn.m, Math.max(0, Math.min(1, mouse.x / width))) }
    }
  }

  Text {
    textFormat: Text.PlainText
    x: wave.x
    anchors.bottom: parent.bottom
    anchors.bottomMargin: vn.t.sp(2)
    text: U.duration(vn.p && (vn.p.playing || vn.p.pos > 0) ? vn.p.pos : vn.dur)
    color: vn.t.faint
    font.family: vn.t.font
    font.pixelSize: vn.t.fsMeta
  }
  Row {
    anchors.right: vn.m.from_me ? wave.right : parent.right
    anchors.rightMargin: vn.m.from_me ? 0 : vn.t.sp(2)
    anchors.bottom: parent.bottom
    anchors.bottomMargin: vn.t.sp(1)
    MetaContent { app: vn.app; m: vn.m }
  }
}
