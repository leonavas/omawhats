import QtQuick
import "../lib/Util.js" as U
import "../lib/Labels.js" as L
import "../lib/Format.js" as F
import "../lib/Registry.js" as Reg

// One chat of the list, as WhatsApp Web draws it: the picture, the name and
// the time, then the last message (ticks, what it is, who wrote it in a
// group) or "typing…" or your draft, and on the right muted, pinned and
// the unread count. A right click (or the chevron on hover) opens its menu.
Item {
  id: row
  property var app: Reg.service
  property var win
  property var c: null
  readonly property var t: app.theme
  readonly property var wa: app.wa
  signal open()

  readonly property bool current: !!c && wa.current === c.jid
  readonly property bool unread: !!c && (c.unread > 0 || !!c.marked)
  readonly property bool muted: !!wa.isMuted(c)
  readonly property var typing: c ? wa.typingIn(c.jid) : null
  readonly property string draft: c && !current ? app.draft(c.jid) : ""
  readonly property var last: c ? c.last : null
  readonly property var shortLast: last ? L.short(last, app.lang) : null

  height: t.rowHeight

  Rectangle {
    anchors.fill: parent
    anchors.leftMargin: row.t.sp(10)
    anchors.rightMargin: row.t.sp(10)
    radius: row.t.sp(10)
    color: row.current ? row.t.selected : (ma.containsMouse ? row.t.hover : "transparent")
  }

  Avatar {
    id: pic
    x: row.t.sp(22)
    anchors.verticalCenter: parent.verticalCenter
    jid: row.c ? row.c.jid : ""
    name: row.c ? row.wa.chatName(row.c) : ""
    group: !!row.c && row.c.kind === "group"
  }

  Item {
    id: body
    anchors.left: pic.right
    anchors.leftMargin: row.t.sp(15)
    anchors.right: parent.right
    anchors.rightMargin: row.t.sp(24)
    anchors.verticalCenter: parent.verticalCenter
    height: row.t.sp(46)

    // ---------------------------------------------------------- top line
    Text {
      id: time
      textFormat: Text.PlainText
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.topMargin: row.t.sp(3)
      text: row.c ? U.listTime(row.c.ts, row.app.lang, row.app.clock24) : ""
      color: row.unread && !row.muted ? row.t.accent : row.t.dim
      font.family: row.t.font
      font.pixelSize: row.t.fsSmall
      font.weight: row.unread && !row.muted ? Font.Medium : Font.Normal
    }
    Row {
      anchors.left: parent.left
      anchors.right: time.left
      anchors.rightMargin: row.t.sp(8)
      anchors.top: parent.top
      spacing: row.t.sp(4)
      Text {
        id: nameText
        width: Math.min(implicitWidth, parent.width - (verified.visible ? verified.width + 4 : 0))
        text: row.c ? row.wa.chatName(row.c) : ""
        color: row.t.textBright
        font.family: row.t.font
        font.pixelSize: row.t.fsName
        font.weight: row.unread ? Font.Medium : Font.Normal
        elide: Text.ElideRight
        textFormat: Text.PlainText
      }
      Icon {
        id: verified
        visible: !!row.c && !!row.c.verified
        name: "verified"
        size: row.t.sp(16)
        color: row.t.blue
        anchors.verticalCenter: nameText.verticalCenter
      }
    }

    // ---------------------------------------------------------- bottom line
    Row {
      id: badges
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: row.t.sp(22)
      spacing: row.t.sp(5)
      Icon { visible: row.muted; name: "muted"; size: row.t.sp(18); color: row.t.faint; anchors.verticalCenter: parent.verticalCenter }
      Icon { visible: !!row.c && row.c.pin > 0; name: "pin"; size: row.t.sp(18); color: row.t.faint; anchors.verticalCenter: parent.verticalCenter }
      Rectangle {
        visible: row.unread
        anchors.verticalCenter: parent.verticalCenter
        height: row.t.sp(20)
        width: row.c && row.c.unread > 0 ? Math.max(height, count.implicitWidth + row.t.sp(10)) : height
        radius: height / 2
        color: row.muted ? row.t.faint : row.t.badge
        Text {
          id: count
          textFormat: Text.PlainText
          anchors.centerIn: parent
          visible: !!row.c && row.c.unread > 0
          text: row.c ? (row.c.unread > 999 ? "999+" : row.c.unread) : ""
          color: row.muted ? row.t.bg : row.t.badgeText
          font.family: row.t.font
          font.pixelSize: row.t.sp(12)
          font.weight: Font.DemiBold
        }
      }
      Item {
        width: chev.visible ? row.t.sp(22) : 0
        height: parent.height
        visible: ma.containsMouse || row.win.menusShown && row.menuOpen
        Icon {
          id: chev
          anchors.centerIn: parent
          visible: parent.visible
          name: "chevronDown"
          size: row.t.sp(22)
          color: row.t.dim
        }
      }
    }

    Row {
      id: preview
      anchors.left: parent.left
      anchors.right: badges.left
      anchors.rightMargin: row.t.sp(6)
      anchors.bottom: parent.bottom
      height: row.t.sp(22)
      spacing: row.t.sp(3)

      readonly property bool showTyping: !!row.typing
      readonly property bool showDraft: !showTyping && row.draft !== ""
      readonly property bool mine: !!row.last && row.last.from_me && !showTyping && !showDraft

      Ticks {
        visible: preview.mine && row.last.kind !== "revoked" && row.last.kind !== "system"
        status: row.last ? row.last.status : 0
        app: row.app
        anchors.verticalCenter: parent.verticalCenter
      }
      Icon {
        visible: !preview.showTyping && !preview.showDraft && !!row.shortLast && row.shortLast.icon !== ""
        name: row.shortLast ? row.shortLast.icon : ""
        size: row.t.sp(17)
        color: row.shortLast && row.shortLast.danger ? row.t.danger
             : (row.last && row.last.kind === "ptt" && row.last.status >= 4 ? row.t.read : row.t.dim)
        anchors.verticalCenter: parent.verticalCenter
      }
      Text {
        width: parent.width - x
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.StyledText
        elide: Text.ElideRight
        maximumLineCount: 1
        font.family: row.t.font
        font.pixelSize: row.t.fsText
        font.italic: !preview.showTyping && !preview.showDraft && !!row.shortLast && !!row.shortLast.italic
        color: preview.showTyping ? row.t.accent : (row.unread ? row.t.text : row.t.dim)
        text: {
          if (preview.showTyping) {
            var tp = row.typing
            var verb = tp.state === "recording" ? row.app.tr("recording audio…", "gravando áudio…") : row.app.tr("typing…", "digitando…")
            if (row.c.kind === "group" && tp.who) return F.esc(tp.who.replace(/^~/, "")) + row.app.tr(" is ", " está ") + verb
            return verb
          }
          if (preview.showDraft)
            return "<font color=\"" + row.t.hex(row.t.accent) + "\">" + row.app.tr("Draft: ", "Rascunho: ") + "</font>" + F.styled(row.draft)
          if (!row.last) return ""
          var s = row.shortLast
          var who = row.last.who ? F.esc(row.last.who.replace(/^~/, "")) + ": " : ""
          var body = s.icon !== "" || row.last.kind === "system" || row.last.kind === "revoked" ? F.esc(s.text) : F.styled(s.text, null, row.app.tr("You", "Você"))
          if (row.last.kind === "system") return body
          return who + body
        }
      }
    }
  }

  property bool menuOpen: false
  MouseArea {
    id: ma
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: Qt.PointingHandCursor
    onClicked: mouse => {
      var onChevron = mouse.x > body.x + body.width - row.t.sp(26) && mouse.y > body.y + body.height - row.t.sp(24)
      if (mouse.button === Qt.RightButton || onChevron) {
        var p = mapToItem(null, mouse.x, mouse.y)
        row.win.menuAt(row, row.win.chatMenu(row.c), mouse.x, mouse.y)
      } else row.open()
    }
  }
}
