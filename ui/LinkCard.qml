import QtQuick
import "../lib/Util.js" as U
import "../lib/Registry.js" as Reg

// A link's preview, over the message's text: its picture, title,
// description and site.
Item {
  id: lc
  property var app: Reg.service
  readonly property var t: app.theme
  property var link: ({})
  readonly property string host: String(link.url || "").replace(/^https?:\/\//, "").split("/")[0].replace(/^www\./, "")
  readonly property bool hasThumb: !!link.thumb || false

  implicitWidth: Math.min(t.sp(420), Math.max(titleText.implicitWidth, t.sp(240)) + t.sp(20) + (thumbBox.visible ? thumbBox.width : 0))
  height: Math.max(col.implicitHeight + t.sp(16), thumbBox.visible ? thumbBox.height : 0) + t.sp(4)

  Clip {
    width: parent.width
    height: parent.height - lc.t.sp(4)
    radius: lc.t.sp(7)
    color: Qt.rgba(0, 0, 0, lc.t.dark ? 0.2 : 0.06)
    Image {
      id: thumbBox
      visible: lc.hasThumb && status !== Image.Error
      width: lc.t.sp(84)
      height: Math.max(lc.t.sp(84), col.implicitHeight + lc.t.sp(16))
      source: lc.link.thumb ? U.fileUrl(lc.link.thumb) : ""
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      smooth: true
    }
    Column {
      id: col
      x: (thumbBox.visible ? thumbBox.width : 0) + lc.t.sp(10)
      y: lc.t.sp(8)
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
        maximumLineCount: 2
        elide: Text.ElideRight
        textFormat: Text.PlainText
      }
      Text {
        width: parent.width
        text: lc.host
        color: lc.t.faint
        font.family: lc.t.font
        font.pixelSize: lc.t.fsSmall
        elide: Text.ElideRight
      }
    }
    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: lc.app.openUrl(lc.link.url) }
  }
}
