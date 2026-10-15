import QtQuick
import QtQuick.Controls
import Quickshell
import "../lib/Util.js" as U
import "../lib/Labels.js" as L
import "../lib/Format.js" as F
import "../lib/Registry.js" as Reg

// Starred messages, newest first, across every chat: who wrote it, in
// which chat, when; a click takes you to it.
Item {
  id: st
  property var app: Reg.service
  property var win
  readonly property var t: app.theme
  readonly property var wa: app.wa

  Component.onCompleted: st.wa.send({ c: "starred" })

  SubHeader {
    id: head
    title: st.app.tr("Starred messages", "Mensagens favoritas")
    onBack: st.win.sideView = "chats"
  }
  ListView {
    id: list
    y: head.height
    width: parent.width
    height: parent.height - y
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    model: ScriptModel { values: st.wa.starred || []; objectProp: "id" }
    ScrollBar.vertical: ThinScroll { app: st.app }
    spacing: st.t.sp(2)
    delegate: Item {
      required property var modelData
      readonly property var m: modelData
      width: list.width
      height: col.implicitHeight + st.t.sp(24)
      Rectangle { anchors.fill: parent; anchors.leftMargin: st.t.sp(10); anchors.rightMargin: st.t.sp(10); radius: st.t.sp(10); color: ma.containsMouse ? st.t.hover : "transparent" }
      Column {
        id: col
        x: st.t.sp(26)
        width: parent.width - st.t.sp(52)
        anchors.verticalCenter: parent.verticalCenter
        spacing: st.t.sp(6)
        Item {
          width: parent.width
          height: who.implicitHeight
          Text {
            id: who
            width: parent.width - when.width - st.t.sp(10)
            elide: Text.ElideRight
            text: (m.from_me ? st.app.tr("You", "Você") : (m.name || "").replace(/^~/, "")) + "  ›  " + st.wa.nameOf(m.chat)
            color: st.t.dim
            font.family: st.t.font
            font.pixelSize: st.t.fsSmall + 1
          }
          Text { id: when; anchors.right: parent.right; text: U.shortDate(m.ts, st.app.lang); color: st.t.faint; font.family: st.t.font; font.pixelSize: st.t.fsSmall }
        }
        Rectangle {
          width: Math.min(parent.width, body.implicitWidth + st.t.sp(20))
          height: body.implicitHeight + st.t.sp(14)
          radius: st.t.bubbleRadius
          color: m.from_me ? st.t.bubbleOut : st.t.bubbleIn
          Text {
            id: body
            x: st.t.sp(10)
            y: st.t.sp(7)
            width: Math.min(implicitWidth, parent.parent.width - st.t.sp(20))
            text: F.plain(L.short(m, st.app.lang).text, m.mentions)
            color: st.t.text
            font.family: st.t.font
            font.pixelSize: st.t.fsMsg
            wrapMode: Text.Wrap
            maximumLineCount: 6
            elide: Text.ElideRight
          }
        }
      }
      MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { st.win.sideView = "chats"; st.wa.open(m.chat, { msg: m.id }) } }
    }
    Column {
      anchors.centerIn: parent
      visible: list.count === 0
      spacing: st.t.sp(16)
      Icon { anchors.horizontalCenter: parent.horizontalCenter; name: "starFilled"; size: st.t.sp(56); color: st.t.faint }
      Text {
        width: list.width - st.t.sp(80)
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: st.app.tr("Tap and hold on any message to star it, so you can easily find it later.", "Toque e segure qualquer mensagem para favoritá-la e encontrá-la facilmente depois.")
        color: st.t.dim
        font.family: st.t.font
        font.pixelSize: st.t.fsText
      }
    }
  }
}
