import QtQuick
import "../lib/Util.js" as U
import "../lib/Registry.js" as Reg

// A link's preview, over the message's text, as WhatsApp Web's: a wide
// picture across the top when the message brought one, a small one on the
// left otherwise; the title, description and site.
Item {
  id: lc
  property var app: Reg.service
  readonly property var t: app.theme
  property var link: ({})
  // The small picture inside the message (the x object's thumb).
  property string thumb: ""
  // Over the message box: no click, the box's own colors.
  property bool composer: false
  readonly property string host: String(link.url || "").replace(/^https?:\/\//, "").split("/")[0].replace(/^www\./, "")
  readonly property string image: link.image || ""
  readonly property bool big: !composer && !!image && (link.w || 0) >= 300 && (link.h || 0) > 0 && link.w / link.h >= 1.2
  readonly property string sideSrc: image || thumb
  readonly property bool hasSide: !big && !!sideSrc

  implicitWidth: big ? t.sp(400) : Math.min(t.sp(420), Math.max(titleText.implicitWidth, t.sp(240)) + t.sp(20) + (sideBox.visible ? sideBox.width : 0))
  height: (big ? bigBox.height + col.implicitHeight + t.sp(16) : Math.max(col.implicitHeight + t.sp(16), sideBox.visible ? sideBox.height : 0)) + t.sp(4)

  Clip {
    width: parent.width
    height: parent.height - lc.t.sp(4)
    radius: lc.t.sp(7)
    color: lc.composer ? lc.t.alpha(lc.t.fg, 0.07) : Qt.rgba(0, 0, 0, lc.t.dark ? 0.2 : 0.06)
    Image {
      id: bigBox
      visible: lc.big && status !== Image.Error
      width: parent.width
      height: visible ? Math.min(width * lc.link.h / lc.link.w, width * 0.75) : 0
      source: lc.big ? U.fileUrl(lc.image) : ""
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      smooth: true
      sourceSize.width: width * 2
    }
    Image {
      id: sideBox
      visible: lc.hasSide && status !== Image.Error
      width: lc.t.sp(84)
      height: Math.max(lc.t.sp(84), col.implicitHeight + lc.t.sp(16))
      source: lc.hasSide ? U.fileUrl(lc.sideSrc) : ""
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      smooth: true
    }
    Column {
      id: col
      x: (sideBox.visible ? sideBox.width : 0) + lc.t.sp(10)
      y: bigBox.height + lc.t.sp(8)
      width: parent.width - x - lc.t.sp(10)
      spacing: lc.t.sp(3)
      Text {
        id: titleText
        width: parent.width
        visible: !!lc.link.title
        text: lc.link.title || ""
        color: lc.t.textBright
        font.family: lc.t.font
        font.pixelSize: lc.t.fsText
        font.weight: Font.Medium
        wrapMode: Text.Wrap
        maximumLineCount: 2
        elide: Text.ElideRight
        textFormat: Text.PlainText
      }
      Text {
        width: parent.width
        visible: !!lc.link.desc
        text: lc.link.desc || ""
        color: lc.t.dim
        font.family: lc.t.font
        font.pixelSize: lc.t.fsSmall + 0.5
        wrapMode: Text.Wrap
        maximumLineCount: lc.big ? 3 : 2
        elide: Text.ElideRight
        textFormat: Text.PlainText
      }
      Text {
        textFormat: Text.PlainText
        width: parent.width
        text: lc.host
        color: lc.t.faint
        font.family: lc.t.font
        font.pixelSize: lc.t.fsSmall
        elide: Text.ElideRight
      }
    }
    MouseArea { enabled: !lc.composer; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: lc.app.openUrl(lc.link.url) }
  }
}
