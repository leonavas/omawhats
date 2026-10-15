import QtQuick
import "../lib/Util.js" as U
import "../lib/Labels.js" as L
import "../lib/Format.js" as F
import "../lib/Registry.js" as Reg

// The message a reply answers, inside its bubble (or over the message box):
// a colored bar, who wrote it, a line or two of it, its picture on the right.
Item {
  id: qb
  property var app: Reg.service
  readonly property var t: app.theme
  property var quote: null      // {id, from, name, kind, text, thumb}
  property string chat: ""
  property bool composer: false
  signal clicked()
  readonly property bool you: !!quote && (quote.name === "" || (!!app.wa.me && String(quote.from).split("@")[0] === app.wa.me.phone))
  readonly property color barColor: you ? t.accent : t.nameColor(quote ? quote.from : "")
  readonly property var s: quote ? L.short({ kind: quote.kind, text: quote.text, from_me: you }, app.lang) : { icon: "", text: "" }

  implicitWidth: Math.min(t.sp(420), Math.max(nameText.implicitWidth, Math.min(bodyText.implicitWidth, t.sp(360))) + t.sp(28) + (thumb.visible ? thumb.width : 0))
  height: Math.max(col.implicitHeight + t.sp(14), thumb.visible ? thumb.height : 0)

  Clip {
    anchors.fill: parent
    radius: qb.t.sp(7)
    color: qb.composer ? qb.t.alpha(qb.t.fg, 0.07) : Qt.rgba(0, 0, 0, qb.t.dark ? 0.2 : 0.06)
    Rectangle { width: qb.t.sp(4); height: parent.height; color: qb.barColor }
    Column {
      id: col
      x: qb.t.sp(12)
      y: qb.t.sp(7)
      width: qb.width - x - qb.t.sp(8) - (thumb.visible ? thumb.width : 0)
      spacing: qb.t.sp(2)
      Text {
        id: nameText
        width: parent.width
        text: qb.you ? qb.app.tr("You", "Você") : String(qb.quote ? qb.quote.name : "").replace(/^~/, "") || qb.app.wa.nameOf(qb.quote ? qb.quote.from : "")
        color: qb.barColor
        font.family: qb.t.font
        font.pixelSize: qb.t.fsSmall + 1
        font.weight: Font.Medium
        elide: Text.ElideRight
        textFormat: Text.PlainText
      }
      Row {
        width: parent.width
        spacing: qb.t.sp(3)
        Icon { visible: qb.s.icon !== ""; name: qb.s.icon; size: qb.t.sp(16); color: qb.t.dim; anchors.top: parent.top; anchors.topMargin: qb.t.sp(1) }
        Text {
          id: bodyText
          width: parent.width - (qb.s.icon !== "" ? qb.t.sp(19) : 0)
          text: F.plain(qb.s.text, null)
          color: qb.t.dim
          font.family: qb.t.font
          font.pixelSize: qb.t.fsSmall + 1
          wrapMode: Text.Wrap
          maximumLineCount: 3
          elide: Text.ElideRight
          textFormat: Text.PlainText
        }
      }
    }
    Image {
      id: thumb
      visible: !!qb.quote && !!qb.quote.thumb && status !== Image.Error
      anchors.right: parent.right
      width: qb.t.sp(56)
      height: Math.max(qb.t.sp(56), col.implicitHeight + qb.t.sp(14))
      source: qb.quote && qb.quote.thumb ? U.fileUrl(qb.quote.thumb) : ""
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      smooth: true
    }
  }
  MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: qb.clicked() }
}
