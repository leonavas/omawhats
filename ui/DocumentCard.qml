import QtQuick
import QtQuick.Controls
import "../lib/Util.js" as U
import "../lib/Registry.js" as Reg

// A document in its bubble: a PDF's first page when it came with one, then
// the file's badge, name, pages, type and size, and the download button.
// A click opens it (downloading it first).
Column {
  id: dc
  property var app: Reg.service
  readonly property var t: app.theme
  readonly property var wa: app.wa
  property var m
  property real maxWidth: 330
  readonly property var media: m.media || {}
  readonly property string name: media.name || app.tr("Document", "Documento")
  readonly property string ext: U.ext(name).toUpperCase() || String(media.mime || "").split("/").pop().toUpperCase()
  readonly property string state_: wa.downloadState(m)
  readonly property color badge: {
    var e = dc.ext.toLowerCase()
    if (e === "pdf") return dc.t.red
    if (["doc", "docx", "odt", "rtf", "txt"].indexOf(e) >= 0) return dc.t.blue
    if (["xls", "xlsx", "ods", "csv"].indexOf(e) >= 0) return dc.t.green
    if (["ppt", "pptx", "odp", "key"].indexOf(e) >= 0) return dc.t.orange
    if (["zip", "rar", "7z", "tar", "gz"].indexOf(e) >= 0) return dc.t.yellow
    return dc.t.alpha(dc.t.fg, 0.5)
  }

  property real natural: Math.min(maxWidth, t.sp(330))
  width: natural
  spacing: t.sp(3)

  function open() {
    if (dc.media.file) dc.app.openFile(dc.media.file)
    else dc.wa.whenDownloaded(dc.m, function(path) { dc.app.openFile(path) })
  }

  Clip {
    visible: !!dc.media.thumb && dc.ext === "PDF"
    width: parent.width
    height: dc.t.sp(130)
    radius: dc.t.sp(6)
    Image {
      anchors.fill: parent
      source: dc.media.thumb ? U.fileUrl(dc.media.thumb) : ""
      fillMode: Image.PreserveAspectCrop
      verticalAlignment: Image.AlignTop
      asynchronous: true
      smooth: true
    }
    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: dc.open() }
  }

  Rectangle {
    width: parent.width
    height: dc.t.sp(64)
    radius: dc.t.sp(7)
    color: Qt.rgba(0, 0, 0, dc.t.dark ? 0.2 : 0.06)

    Rectangle {
      id: icon
      x: dc.t.sp(10)
      anchors.verticalCenter: parent.verticalCenter
      width: dc.t.sp(30); height: dc.t.sp(38); radius: dc.t.sp(4)
      color: dc.badge
      Text {
        anchors.bottom: parent.bottom
        anchors.bottomMargin: dc.t.sp(4)
        anchors.horizontalCenter: parent.horizontalCenter
        text: dc.ext.slice(0, 4)
        color: "white"
        font.family: dc.t.font
        font.pixelSize: dc.t.sp(8)
        font.weight: Font.Bold
      }
    }
    Column {
      anchors.left: icon.right
      anchors.leftMargin: dc.t.sp(10)
      anchors.right: action.left
      anchors.rightMargin: dc.t.sp(8)
      anchors.verticalCenter: parent.verticalCenter
      spacing: dc.t.sp(2)
      Text {
        width: parent.width
        text: dc.name
        color: dc.t.text
        font.family: dc.t.font
        font.pixelSize: dc.t.fsText
        elide: Text.ElideMiddle
        textFormat: Text.PlainText
      }
      Text {
        width: parent.width
        text: [dc.media.pages ? (dc.media.pages === 1 ? dc.app.tr("1 page", "1 página") : dc.app.tr(dc.media.pages + " pages", dc.media.pages + " páginas")) : "",
               dc.ext, dc.media.size ? U.fileSize(dc.media.size, dc.app.lang) : ""].filter(function(s) { return s }).join(" • ")
        color: dc.t.faint
        font.family: dc.t.font
        font.pixelSize: dc.t.fsSmall
        elide: Text.ElideRight
      }
    }
    Item {
      id: action
      anchors.right: parent.right
      anchors.rightMargin: dc.t.sp(10)
      anchors.verticalCenter: parent.verticalCenter
      width: dc.t.sp(34); height: width
      visible: !dc.media.file
      Rectangle { anchors.fill: parent; radius: width / 2; color: "transparent"; border.width: 1.5; border.color: dc.t.faint }
      BusyIndicator { anchors.centerIn: parent; running: dc.state_ === "busy"; visible: running; width: dc.t.sp(30); height: width }
      Icon { anchors.centerIn: parent; visible: dc.state_ !== "busy"; name: dc.state_ === "failed" ? "refresh" : "download"; size: dc.t.sp(20); color: dc.t.dim }
    }
    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: dc.open() }
  }
}
