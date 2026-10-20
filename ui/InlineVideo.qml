import QtQuick
import QtMultimedia
import "../lib/Util.js" as U
import "../lib/Registry.js" as Reg

// A video playing where it is, as WhatsApp Web's: in its bubble, or in the
// viewer. QtMultimedia plays it (Omarchy has it, for kdenlive and omacut);
// loaded apart, so where it's missing mpv plays it instead (`failed`). A
// click pauses or resumes; the bar (play, how far, the time, the sound,
// the viewer) shows on hover and while paused. A GIF just loops, silent,
// without it. One voice note or video plays at a time, and nothing goes on
// while the window is parked.
Item {
  id: iv
  property var app: Reg.service
  readonly property var t: app.theme
  property string file: ""
  property bool loop: false
  // The viewer's: the whole picture, bigger controls. A bubble's fills it.
  property bool fit: false
  property bool expandable: false
  // A round video note has no room for the bar: a click is all.
  property bool withBar: true
  // Where to begin, in ms (handed over from the bubble to the viewer).
  property real start: 0
  readonly property real position: mp.position
  readonly property bool paused: mp.playbackState !== MediaPlayer.PlayingState
  readonly property bool controlsShown: !iv.loop && iv.withBar && (hover.hovered || drag.pressed || iv.paused)
  signal ended()
  signal failed()
  signal expand()

  function play() {
    // A voice note playing stops for it.
    if (iv.app.wa.player && iv.app.wa.player.playing) iv.app.wa.send({ c: "pause" })
    mp.play()
  }
  function toggle() { if (iv.paused) iv.play(); else mp.pause() }
  function seekTo(frac) { if (mp.duration > 0) mp.setPosition(Math.max(0, Math.min(1, frac)) * mp.duration) }

  property bool _started: false
  MediaPlayer {
    id: mp
    source: iv.file ? U.fileUrl(iv.file) : ""
    videoOutput: out
    audioOutput: AudioOutput { muted: iv.loop || iv.app.videoMuted }
    loops: iv.loop ? MediaPlayer.Infinite : 1
    onMediaStatusChanged: {
      if (!iv._started && (mediaStatus === MediaPlayer.LoadedMedia || mediaStatus === MediaPlayer.BufferedMedia)) {
        iv._started = true
        if (iv.start > 0) mp.setPosition(iv.start)
        iv.play()
      }
      if (mediaStatus === MediaPlayer.EndOfMedia && !iv.loop) iv.ended()
    }
    onErrorOccurred: (error, message) => iv.failed()
  }
  Connections {
    target: iv.app.wa
    function onPlayerChanged() { if (iv.app.wa.player && iv.app.wa.player.playing) mp.pause() }
  }
  Connections {
    target: iv.app
    function onParkedChanged() { if (iv.app.parked) mp.pause() }
  }

  Rectangle { anchors.fill: parent; color: "black"; visible: !iv.fit }
  VideoOutput {
    id: out
    anchors.fill: parent
    fillMode: iv.fit ? VideoOutput.PreserveAspectFit : VideoOutput.PreserveAspectCrop
  }

  HoverHandler { id: hover }
  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: iv.loop ? iv.ended() : iv.toggle()
  }

  // Paused: the round play button, as on the thumbnail.
  Rectangle {
    visible: !iv.loop && iv.paused
    anchors.centerIn: parent
    width: iv.t.sp(iv.fit ? 72 : 52); height: width; radius: width / 2
    color: Qt.rgba(0, 0, 0, 0.5)
    Icon { anchors.centerIn: parent; name: "play"; size: iv.t.sp(iv.fit ? 40 : 30); color: "white" }
  }

  // ------------------------------------------------------------ the bar
  Rectangle {
    id: bar
    visible: iv.controlsShown
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    height: iv.t.sp(iv.fit ? 56 : 44)
    gradient: Gradient {
      GradientStop { position: 0.0; color: "transparent" }
      GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.6) }
    }
    // Clicks on the bar stay on it.
    MouseArea { anchors.fill: parent }
    Row {
      id: left
      anchors.left: parent.left
      anchors.leftMargin: iv.t.sp(6)
      anchors.bottom: parent.bottom
      anchors.bottomMargin: iv.t.sp(4)
      spacing: iv.t.sp(2)
      IconButton {
        width: iv.t.sp(32); height: width
        icon: iv.paused ? "play" : "pause"
        iconSize: iv.t.sp(22)
        color: "white"
        hoverColor: Qt.rgba(1, 1, 1, 0.15)
        tip: iv.paused ? iv.app.tr("Play", "Reproduzir") : iv.app.tr("Pause", "Pausar")
        onClicked: iv.toggle()
      }
      Text {
        textFormat: Text.PlainText
        anchors.verticalCenter: parent.verticalCenter
        text: U.duration(mp.position / 1000) + " / " + U.duration(mp.duration / 1000)
        color: "white"
        font.family: iv.t.font
        font.pixelSize: iv.t.fsMeta
      }
    }
    Row {
      id: right
      anchors.right: parent.right
      anchors.rightMargin: iv.t.sp(6)
      anchors.bottom: parent.bottom
      anchors.bottomMargin: iv.t.sp(4)
      spacing: iv.t.sp(2)
      IconButton {
        width: iv.t.sp(32); height: width
        icon: iv.app.videoMuted ? "soundOff" : "soundOn"
        iconSize: iv.t.sp(20)
        color: "white"
        hoverColor: Qt.rgba(1, 1, 1, 0.15)
        tip: iv.app.videoMuted ? iv.app.tr("Unmute", "Ativar som") : iv.app.tr("Mute", "Silenciar")
        onClicked: iv.app.videoMuted = !iv.app.videoMuted
      }
      IconButton {
        visible: iv.expandable
        width: iv.t.sp(32); height: width
        icon: "fullscreen"
        iconSize: iv.t.sp(20)
        color: "white"
        hoverColor: Qt.rgba(1, 1, 1, 0.15)
        tip: iv.app.tr("Open", "Abrir")
        onClicked: iv.expand()
      }
    }
    // How far it is: a click or a drag goes there.
    Item {
      id: track
      anchors.left: left.right
      anchors.right: right.left
      anchors.leftMargin: iv.t.sp(8)
      anchors.rightMargin: iv.t.sp(8)
      anchors.verticalCenter: left.verticalCenter
      height: iv.t.sp(16)
      readonly property real frac: mp.duration > 0 ? mp.position / mp.duration : 0
      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: iv.t.sp(4)
        radius: height / 2
        color: Qt.rgba(1, 1, 1, 0.35)
        Rectangle { width: parent.width * track.frac; height: parent.height; radius: parent.radius; color: "white" }
      }
      Rectangle {
        x: track.width * track.frac - width / 2
        anchors.verticalCenter: parent.verticalCenter
        width: iv.t.sp(12); height: width; radius: width / 2
        color: "white"
        visible: hover.hovered || drag.pressed
      }
      MouseArea {
        id: drag
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onPressed: mouse => iv.seekTo(mouse.x / width)
        onPositionChanged: mouse => { if (pressed) iv.seekTo(mouse.x / width) }
      }
    }
  }
}
