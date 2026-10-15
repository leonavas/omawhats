import QtQuick
import QtQuick.Controls
import "../lib/Util.js" as U
import "../lib/Format.js" as F
import "../lib/Registry.js" as Reg

// A photo over the whole window, as WhatsApp Web's viewer: who sent it and
// when on top with download, forward and close, the picture in the middle
// (← → for the chat's others), its caption, and the strip of the chat's
// photos and videos at the bottom.
Rectangle {
  id: mv
  property var app: Reg.service
  property var win
  property var msg: null
  readonly property var t: app.theme
  readonly property var wa: app.wa
  signal closed()

  color: t.alpha(t.dark ? t.bgDarker : t.bg, 0.97)
  focus: true
  Component.onCompleted: { mv.forceActiveFocus(); mv.current = mv.msg; mv.fetch() }

  property var current: null
  // The chat's photos and videos, oldest first, from what's loaded.
  readonly property var all: {
    if (!mv.msg || mv.msg.id === "photo") return mv.msg ? [mv.msg] : []
    var h = mv.wa.history(mv.msg.chat)
    if (!h) return [mv.msg]
    var out = h.msgs.filter(function(m) { return m.kind === "image" || m.kind === "video" || m.kind === "gif" })
    return out.length ? out : [mv.msg]
  }
  readonly property int index: {
    if (!mv.current) return -1
    for (var i = 0; i < mv.all.length; i++) if (mv.all[i].id === mv.current.id) return i
    return -1
  }
  // The newest copy of the shown message (a download lands there).
  readonly property var shown: mv.index >= 0 ? mv.all[mv.index] : mv.current
  function go(d) {
    var i = mv.index + d
    if (i < 0 || i >= mv.all.length) return
    mv.current = mv.all[i]
    mv.fetch()
  }
  function fetch() {
    var m = mv.shown
    if (m && m.media && !m.media.file && m.kind === "image") mv.wa.download(m, false)
  }

  Keys.onEscapePressed: mv.closed()
  Keys.onLeftPressed: mv.go(-1)
  Keys.onRightPressed: mv.go(1)

  MouseArea { anchors.fill: parent; onClicked: mv.closed(); onWheel: wheel => { if (wheel.angleDelta.y > 0) mv.go(-1); else mv.go(1) } }

  // ------------------------------------------------------------ top
  Item {
    id: top
    width: parent.width
    height: mv.t.sp(64)
    Avatar {
      id: who
      x: mv.t.sp(18)
      anchors.verticalCenter: parent.verticalCenter
      size: mv.t.sp(40)
      jid: mv.shown ? (mv.shown.from_me ? (mv.wa.me ? mv.wa.me.jid : "") : (mv.shown.sender || mv.shown.chat)) : ""
      name: mv.shown ? String(mv.shown.name || "").replace(/^~/, "") : ""
    }
    Column {
      anchors.left: who.right
      anchors.leftMargin: mv.t.sp(14)
      anchors.verticalCenter: parent.verticalCenter
      Text {
        textFormat: Text.PlainText
        text: !mv.shown ? "" : mv.shown.from_me ? mv.app.tr("You", "Você") : (String(mv.shown.name || "").replace(/^~/, "") || mv.wa.nameOf(mv.shown.chat))
        color: mv.t.textBright
        font.family: mv.t.font
        font.pixelSize: mv.t.fsName
      }
      Text {
        textFormat: Text.PlainText
        visible: !!mv.shown && mv.shown.ts > 0
        text: mv.shown && mv.shown.ts ? U.dayLabel(mv.shown.ts, mv.app.lang) + mv.app.tr(" at ", " às ") + U.clock(mv.shown.ts, mv.app.clock24) : ""
        color: mv.t.dim
        font.family: mv.t.font
        font.pixelSize: mv.t.fsSmall + 1
      }
    }
    Row {
      anchors.right: parent.right
      anchors.rightMargin: mv.t.sp(16)
      anchors.verticalCenter: parent.verticalCenter
      spacing: mv.t.sp(8)
      IconButton {
        visible: !!mv.shown && mv.shown.id !== "photo"
        icon: mv.shown && mv.shown.star ? "starFilled" : "star"
        tip: mv.app.tr("Star", "Favoritar")
        onClicked: mv.wa.star(mv.shown.chat, [mv.shown.id], !mv.shown.star)
      }
      IconButton {
        visible: !!mv.shown && mv.shown.id !== "photo"
        icon: "forward"
        tip: mv.app.tr("Forward", "Encaminhar")
        onClicked: { var m = mv.shown; mv.closed(); mv.win.dialog("forward", { chat: m.chat, msgs: [m] }) }
      }
      IconButton {
        icon: "download"
        tip: mv.app.tr("Download", "Baixar")
        onClicked: {
          var m = mv.shown
          if (m.media.file) mv.app.saveToDownloads(m.media.file, "")
          else mv.wa.whenDownloaded(m, function(p) { mv.app.saveToDownloads(p, "") })
        }
      }
      IconButton {
        icon: "openNew"
        tip: mv.app.tr("Open with…", "Abrir com…")
        visible: !!mv.shown && !!mv.shown.media && !!mv.shown.media.file
        onClicked: mv.app.openFile(mv.shown.media.file)
      }
      IconButton { icon: "close"; tip: mv.app.tr("Close", "Fechar"); onClicked: mv.closed() }
    }
  }

  // ------------------------------------------------------------ the picture
  Item {
    id: stage
    anchors.top: top.bottom
    anchors.bottom: caption.top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.margins: mv.t.sp(20)
    Image {
      id: low
      anchors.fill: parent
      source: mv.shown && mv.shown.media && mv.shown.media.thumb ? U.fileUrl(mv.shown.media.thumb) : ""
      fillMode: Image.PreserveAspectFit
      visible: high.status !== Image.Ready
      smooth: true
      opacity: 0.6
    }
    Image {
      id: high
      anchors.fill: parent
      source: mv.shown && mv.shown.media && mv.shown.media.file && mv.shown.kind === "image" ? U.fileUrl(mv.shown.media.file) : ""
      fillMode: Image.PreserveAspectFit
      asynchronous: true
      smooth: true
      mipmap: true
      sourceSize.width: Math.ceil(stage.width * 1.5)
      sourceSize.height: Math.ceil(stage.height * 1.5)
      MouseArea { anchors.centerIn: parent; width: high.paintedWidth; height: high.paintedHeight; onClicked: {} }
    }
    BusyIndicator { anchors.centerIn: parent; running: !!mv.shown && mv.shown.kind === "image" && high.status !== Image.Ready && mv.wa.downloadState(mv.shown) === "busy" }
    // A video: play it in mpv.
    Rectangle {
      visible: !!mv.shown && mv.shown.kind !== "image"
      anchors.centerIn: parent
      width: mv.t.sp(72); height: width; radius: width / 2
      color: Qt.rgba(0, 0, 0, 0.55)
      Icon { anchors.centerIn: parent; name: "play"; size: mv.t.sp(40); color: "white" }
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: { var m = mv.shown; mv.wa.whenDownloaded(m, function(p) { mv.app.playVideo(p, m.kind === "gif") }) }
      }
    }
  }

  // Previous and next.
  Rectangle {
    visible: mv.index > 0
    x: mv.t.sp(20)
    anchors.verticalCenter: stage.verticalCenter
    width: mv.t.sp(46); height: width; radius: width / 2
    color: pma.containsMouse ? mv.t.hoverStrong : mv.t.hover
    Icon { anchors.centerIn: parent; name: "chevronLeft"; size: mv.t.sp(30); color: mv.t.text }
    MouseArea { id: pma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: mv.go(-1) }
  }
  Rectangle {
    visible: mv.index >= 0 && mv.index < mv.all.length - 1
    anchors.right: parent.right
    anchors.rightMargin: mv.t.sp(20)
    anchors.verticalCenter: stage.verticalCenter
    width: mv.t.sp(46); height: width; radius: width / 2
    color: nma.containsMouse ? mv.t.hoverStrong : mv.t.hover
    Icon { anchors.centerIn: parent; name: "chevronRight"; size: mv.t.sp(30); color: mv.t.text }
    MouseArea { id: nma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: mv.go(1) }
  }

  Text {
    id: caption
    textFormat: Text.PlainText
    anchors.bottom: strip.top
    anchors.bottomMargin: mv.t.sp(14)
    anchors.horizontalCenter: parent.horizontalCenter
    width: Math.min(implicitWidth, parent.width - mv.t.sp(120))
    height: text ? implicitHeight : 0
    text: mv.shown && mv.shown.text ? F.plain(mv.shown.text, mv.shown.mentions) : ""
    color: mv.t.text
    font.family: mv.t.font
    font.pixelSize: mv.t.fsMsg
    wrapMode: Text.Wrap
    maximumLineCount: 4
    elide: Text.ElideRight
    horizontalAlignment: Text.AlignHCenter
  }

  // ------------------------------------------------------------ strip
  ListView {
    id: strip
    anchors.bottom: parent.bottom
    anchors.bottomMargin: mv.t.sp(16)
    anchors.horizontalCenter: parent.horizontalCenter
    width: Math.min(parent.width - mv.t.sp(40), count * mv.t.sp(66))
    height: mv.all.length > 1 ? mv.t.sp(62) : 0
    visible: mv.all.length > 1
    orientation: ListView.Horizontal
    spacing: mv.t.sp(6)
    clip: true
    model: mv.all
    currentIndex: mv.index
    highlightRangeMode: ListView.ApplyRange
    preferredHighlightBegin: width / 2 - mv.t.sp(30)
    preferredHighlightEnd: width / 2 + mv.t.sp(30)
    delegate: Item {
      required property var modelData
      required property int index
      width: mv.t.sp(60); height: width
      Clip {
        anchors.fill: parent
        radius: mv.t.sp(6)
        color: mv.t.hover
        Image {
          anchors.fill: parent
          source: modelData.media ? U.fileUrl(modelData.media.thumb || (modelData.kind === "image" ? modelData.media.file : "")) : ""
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
        }
      }
      Rectangle {
        anchors.fill: parent
        radius: mv.t.sp(6)
        color: "transparent"
        border.width: index === mv.index ? 3 : 0
        border.color: mv.t.accent
      }
      MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { mv.current = modelData; mv.fetch() } }
    }
  }
}
