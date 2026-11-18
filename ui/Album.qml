import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import "../lib/Util.js" as U
import "../lib/Registry.js" as Reg

// Photos and videos sent together, as WhatsApp Web's album: four square
// tiles, two by two; past four, the last one dark with "+N" over it. A tile
// opens the viewer on its own (← → go through the rest).
Item {
  id: al
  property var app: Reg.service
  property var win
  readonly property var t: app.theme
  readonly property var wa: app.wa
  property var items: []
  property real maxWidth: 330
  // Bubble asks the visual part whether a video's bar is showing.
  readonly property bool controlsShown: false

  readonly property real gap: t.sp(3)
  readonly property real tile: Math.floor((Math.min(maxWidth, t.sp(330)) - gap) / 2)
  readonly property int more: items.length - 4

  implicitWidth: tile * 2 + gap
  implicitHeight: implicitWidth
  height: implicitHeight

  Grid {
    columns: 2
    spacing: al.gap
    Repeater {
      model: al.items.slice(0, 4)
      delegate: Item {
        id: cell
        required property var modelData
        required property int index
        readonly property var m: modelData
        readonly property var media: m.media || {}
        readonly property bool isVideo: m.kind === "video"
        readonly property bool hasFile: !!media.file
        readonly property string state_: al.wa.downloadState(m)
        readonly property bool blurred: !!media.thumb && !/\.frame\.jpg$/.test(media.thumb)
        readonly property bool plus: index === 3 && al.more > 0
        width: al.tile
        height: al.tile

        Component.onCompleted: if (!cell.hasFile && !cell.isVideo && al.app.autoPhotos) al.wa.download(cell.m, true)

        Clip {
          anchors.fill: parent
          radius: al.t.sp(6)
          color: al.t.alpha(al.t.fg, 0.06)
          Image {
            anchors.fill: parent
            anchors.margins: cell.blurred ? -al.t.sp(30) : 0
            source: cell.media.thumb ? U.fileUrl(cell.media.thumb) : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            smooth: true
            visible: full.status !== Image.Ready
            layer.enabled: cell.blurred && GraphicsInfo.api !== GraphicsInfo.Software
            layer.effect: MultiEffect { blurEnabled: true; blur: 1.0; blurMax: 40; autoPaddingEnabled: false }
          }
          Image {
            id: full
            anchors.fill: parent
            source: cell.hasFile && !cell.isVideo ? U.fileUrl(cell.media.file) : ""
            sourceSize.width: Math.ceil(al.tile * 2)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            smooth: true
            mipmap: true
          }
          // The rest of them, counted.
          Rectangle {
            visible: cell.plus
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.5)
            Text {
              textFormat: Text.PlainText
              anchors.centerIn: parent
              text: "+" + al.more
              color: "white"
              font.family: al.t.font
              font.pixelSize: al.t.sp(30)
            }
          }
        }

        // A photo not here yet and not coming: the download button; a
        // video: the play button.
        Rectangle {
          visible: !cell.plus && (cell.isVideo || !cell.hasFile)
          anchors.centerIn: parent
          width: al.t.sp(44); height: width; radius: width / 2
          color: Qt.rgba(0, 0, 0, 0.5)
          BusyIndicator { anchors.centerIn: parent; running: cell.state_ === "busy"; visible: running; width: al.t.sp(34); height: width }
          Icon {
            anchors.centerIn: parent
            visible: cell.state_ !== "busy"
            name: cell.state_ === "failed" ? "refresh" : cell.isVideo ? "play" : "download"
            size: al.t.sp(cell.isVideo ? 26 : 22)
            color: "white"
          }
        }
        Row {
          visible: cell.isVideo && !cell.plus && (cell.media.secs || 0) > 0
          anchors.left: parent.left
          anchors.bottom: parent.bottom
          anchors.margins: al.t.sp(6)
          spacing: al.t.sp(4)
          Icon { name: "videoFilled"; size: al.t.sp(14); color: "white"; anchors.verticalCenter: parent.verticalCenter }
          Text { textFormat: Text.PlainText; text: U.duration(cell.media.secs); color: "white"; font.family: al.t.font; font.pixelSize: al.t.fsMeta; anchors.verticalCenter: parent.verticalCenter; style: Text.Raised; styleColor: Qt.rgba(0, 0, 0, 0.4) }
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            if (!cell.isVideo && !cell.hasFile && cell.state_ !== "busy") al.wa.download(cell.m, false)
            al.win.viewMedia(cell.m)
          }
        }
      }
    }
  }
}
