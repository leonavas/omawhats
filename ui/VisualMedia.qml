import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import "../lib/Util.js" as U
import "../lib/Registry.js" as Reg

// A photo, video or GIF in its bubble: the thumbnail at once, the picture
// once downloaded (photos download by themselves when the setting says
// so), a play button on videos with their length, GIF on GIFs. A click
// opens the viewer, or plays the video right here (InlineVideo), fetching
// it first; its bar's button takes it on to the viewer.
Item {
  id: vm
  property var app: Reg.service
  property var win
  readonly property var t: app.theme
  readonly property var wa: app.wa
  property var m
  property real maxWidth: 330
  property bool caption: false
  readonly property var media: m.media || {}
  readonly property string kind: m.kind === "card" ? (media.kind || "image") : m.kind
  readonly property bool isVideo: kind === "video" || kind === "gif" || kind === "ptv" || media.kind === "video"
  readonly property bool gif: kind === "gif" || !!media.gif
  readonly property string state_: wa.downloadState(m)
  readonly property bool hasFile: !!media.file
  // The thumbnail the message carries is tiny: blurred, as WhatsApp Web
  // has it, rather than stretched into blocks. A downloaded video's frame
  // (bridge's "frame") is sharp and stays so.
  readonly property bool blurred: !!media.thumb && !/\.frame\.jpg$/.test(media.thumb)
  // Playing here: asked for, and once the file is here. Without
  // QtMultimedia (`inlineFailed`), mpv plays it as before.
  readonly property bool playing: isVideo && app.video === vm
  property bool inlineFailed: false
  readonly property bool controlsShown: !!inline.item && inline.item.controlsShown

  // WhatsApp's sizes: as wide as 330 points and as tall as 400, in the
  // picture's shape (a tall one narrower, down to 150), cropped past that.
  readonly property real fullWidth: Math.min(maxWidth, t.sp(kind === "ptv" ? 240 : 330))
  readonly property real ratio: media.w > 0 && media.h > 0 ? media.h / media.w : 0.75
  readonly property real boxWidth: kind === "ptv" ? fullWidth : Math.min(fullWidth, Math.max(t.sp(150), t.sp(400) / ratio))
  readonly property real boxHeight: kind === "ptv" ? boxWidth : Math.max(t.sp(110), Math.min(boxWidth * ratio, t.sp(400)))

  implicitWidth: boxWidth
  implicitHeight: boxHeight
  height: boxHeight

  Component.onCompleted: {
    if (!vm.hasFile && !vm.isVideo && vm.app.autoPhotos) vm.wa.download(vm.m, true)
  }
  Component.onDestruction: if (vm.app.video === vm) vm.app.video = null

  function play() {
    if (vm.inlineFailed) {
      if (vm.hasFile) vm.app.playVideo(vm.media.file, vm.gif)
      else vm.wa.whenDownloaded(vm.m, function(path) { vm.app.playVideo(path, vm.gif) })
      return
    }
    vm.app.video = vm
    if (!vm.hasFile && vm.state_ !== "busy") vm.wa.download(vm.m, false)
  }

  Clip {
    anchors.fill: parent
    radius: vm.kind === "ptv" ? width / 2 : vm.t.sp(6)
    color: vm.t.alpha(vm.t.fg, 0.06)
    Image {
      id: thumb
      // Past the edges by the blur's reach, where it fades out: the clip
      // cuts that off.
      anchors.fill: parent
      anchors.margins: vm.blurred ? -vm.t.sp(40) : 0
      source: vm.media.thumb ? U.fileUrl(vm.media.thumb) : ""
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      smooth: true
      visible: full.status !== Image.Ready
      layer.enabled: vm.blurred && GraphicsInfo.api !== GraphicsInfo.Software
      layer.effect: MultiEffect {
        blurEnabled: true
        blur: 1.0
        blurMax: 48
        autoPaddingEnabled: false
      }
    }
    Image {
      id: full
      anchors.fill: parent
      source: vm.hasFile && !vm.isVideo ? U.fileUrl(vm.media.file) : ""
      sourceSize.width: Math.ceil(vm.boxWidth * 2)
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      smooth: true
      mipmap: true
    }
    Loader {
      id: inline
      anchors.fill: parent
      readonly property bool want: vm.playing && vm.hasFile && !vm.inlineFailed
      onWantChanged: inline.load()
      Component.onCompleted: inline.load()
      function load() {
        if (!inline.want) { inline.source = ""; return }
        inline.setSource(Qt.resolvedUrl("InlineVideo.qml"), { file: vm.media.file, loop: vm.gif, expandable: true, withBar: vm.kind !== "ptv" })
      }
      onStatusChanged: if (status === Loader.Error) inline.fail()
      function fail() {
        vm.inlineFailed = true
        vm.app.video = null
        vm.play()
      }
    }
    Connections {
      target: inline.item
      ignoreUnknownSignals: true
      function onEnded() { vm.app.video = null }
      function onFailed() { inline.fail() }
      function onExpand() {
        vm.app.videoResume = { chat: vm.m.chat, id: vm.m.id, pos: inline.item.position }
        vm.app.video = null
        vm.win.viewMedia(vm.m)
      }
    }
  }

  // Not here yet and not on its way: a click fetches it.
  Rectangle {
    visible: !vm.isVideo && !vm.hasFile
    anchors.centerIn: parent
    width: vm.t.sp(52); height: width; radius: width / 2
    color: Qt.rgba(0, 0, 0, 0.5)
    BusyIndicator { anchors.centerIn: parent; running: vm.state_ === "busy"; visible: running; width: vm.t.sp(40); height: width }
    Icon { anchors.centerIn: parent; visible: vm.state_ !== "busy"; name: vm.state_ === "failed" ? "refresh" : "download"; size: vm.t.sp(26); color: "white" }
  }

  // A video: the play button and its length.
  Rectangle {
    visible: vm.isVideo && !inline.item
    anchors.centerIn: parent
    width: vm.t.sp(52); height: width; radius: width / 2
    color: Qt.rgba(0, 0, 0, 0.5)
    BusyIndicator { anchors.centerIn: parent; running: vm.state_ === "busy"; visible: running; width: vm.t.sp(40); height: width }
    Icon { anchors.centerIn: parent; visible: vm.state_ !== "busy" && !vm.gif; name: vm.state_ === "failed" ? "refresh" : "play"; size: vm.t.sp(30); color: "white" }
    Text { textFormat: Text.PlainText; anchors.centerIn: parent; visible: vm.state_ !== "busy" && vm.gif; text: "GIF"; color: "white"; font.family: vm.t.font; font.pixelSize: vm.t.fsSmall + 1; font.weight: Font.Bold }
  }
  Row {
    visible: vm.isVideo && !vm.gif && (vm.media.secs || 0) > 0 && !inline.item
    anchors.left: parent.left
    anchors.bottom: parent.bottom
    anchors.margins: vm.t.sp(8)
    spacing: vm.t.sp(4)
    Icon { name: "videoFilled"; size: vm.t.sp(16); color: "white"; anchors.verticalCenter: parent.verticalCenter }
    Text { textFormat: Text.PlainText; text: U.duration(vm.media.secs); color: "white"; font.family: vm.t.font; font.pixelSize: vm.t.fsMeta; anchors.verticalCenter: parent.verticalCenter; style: Text.Raised; styleColor: Qt.rgba(0, 0, 0, 0.4) }
  }

  // Once the player is there, the clicks are its own.
  MouseArea {
    anchors.fill: parent
    visible: !inline.item
    cursorShape: Qt.PointingHandCursor
    onClicked: {
      if (vm.isVideo) {
        // A second click while it's still coming: never mind.
        if (vm.playing) vm.app.video = null
        else vm.play()
        return
      }
      if (!vm.hasFile && vm.state_ !== "busy") vm.wa.download(vm.m, false)
      vm.win.viewMedia(vm.m)
    }
  }
}
