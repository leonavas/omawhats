import QtQuick
import "../lib/Util.js" as U
import "../lib/Labels.js" as L
import "../lib/Registry.js" as Reg

// One row of a chat: a day chip, the unread band, the encryption note, a
// notice, or a message (its bubble, the sender's picture in groups, the
// reactions under it, the checkbox while selecting).
Item {
  id: r
  property var app: Reg.service
  property var win
  property var view
  property var list
  property var row: null
  readonly property var t: app.theme
  readonly property var wa: app.wa
  readonly property real pad: Math.round(Math.max(t.sp(14), Math.min(width * 0.055, t.sp(64))))

  height: loader.item ? loader.item.height : 0

  Loader {
    id: loader
    width: r.width
    sourceComponent: !r.row ? null : r.row.type === "day" ? dayC : r.row.type === "unread" ? unreadC : r.row.type === "e2e" ? e2eC
                   : r.row.type === "notice" ? noticeC : msgC
  }

  // ------------------------------------------------------------ chips
  component SysChip: Item {
    id: sc
    property string text: ""
    property string icon: ""
    property color fg: r.t.dim
    property real topGap: r.t.sp(12)
    width: r.width
    height: box.height + topGap
    Rectangle {
      id: box
      anchors.horizontalCenter: parent.horizontalCenter
      y: sc.topGap
      width: Math.min(label.implicitWidth + (sc.icon ? r.t.sp(22) : 0), r.width - r.pad * 2 - r.t.sp(40)) + r.t.sp(24)
      height: label.height + r.t.sp(10)
      radius: r.t.sp(8)
      color: r.t.system
      Icon { visible: sc.icon !== ""; x: r.t.sp(12); anchors.verticalCenter: parent.verticalCenter; name: sc.icon; size: r.t.sp(16); color: sc.fg }
      Text {
        id: label
        x: r.t.sp(12) + (sc.icon ? r.t.sp(22) : 0)
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, r.width - r.pad * 2 - r.t.sp(40) - (sc.icon ? r.t.sp(22) : 0))
        text: sc.text
        color: sc.fg
        font.family: r.t.font
        font.pixelSize: r.t.fsSmall + 0.5
        wrapMode: Text.Wrap
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
      }
    }
  }

  Component {
    id: dayC
    SysChip { text: U.dayLabel(r.row.ts, r.app.lang); topGap: r.t.sp(14) }
  }
  Component {
    id: unreadC
    Item {
      width: r.width
      height: r.t.sp(54)
      Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        y: r.t.sp(12)
        height: r.t.sp(32)
        color: r.t.unreadBand
        Rectangle {
          anchors.centerIn: parent
          width: ut.implicitWidth + r.t.sp(28)
          height: r.t.sp(26)
          radius: height / 2
          color: r.t.system
          Text {
            id: ut
            textFormat: Text.PlainText
            anchors.centerIn: parent
            text: r.row.count === 1 ? r.app.tr("1 unread message", "1 mensagem não lida") : r.app.tr(r.row.count + " unread messages", r.row.count + " mensagens não lidas")
            color: r.t.text
            font.family: r.t.font
            font.pixelSize: r.t.fsSmall + 0.5
          }
        }
      }
    }
  }
  Component {
    id: e2eC
    Item {
      width: r.width
      height: e2eBox.height + r.t.sp(16)
      Rectangle {
        id: e2eBox
        anchors.horizontalCenter: parent.horizontalCenter
        y: r.t.sp(8)
        width: Math.min(r.width - r.pad * 2, r.t.sp(560))
        height: e2eText.implicitHeight + r.t.sp(16)
        radius: r.t.sp(8)
        color: r.t.system
        Text {
          id: e2eText
          anchors.centerIn: parent
          width: parent.width - r.t.sp(28)
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.Wrap
          textFormat: Text.StyledText
          text: "🔒 " + r.app.tr("Messages and calls are end-to-end encrypted. Only people in this chat can read, listen to, or share them.",
                                "As mensagens e as chamadas são protegidas com a criptografia de ponta a ponta. Somente as pessoas que fazem parte da conversa podem ler, ouvir e compartilhar esse conteúdo.")
          color: r.t.warning
          font.family: r.t.font
          font.pixelSize: r.t.fsSmall + 0.5
        }
      }
    }
  }
  Component {
    id: noticeC
    SysChip { text: L.short(r.row.m, r.app.lang).text; topGap: r.t.sp(10) }
  }

  // ------------------------------------------------------------ a message
  Component {
    id: msgC
    Item {
      id: mi
      readonly property var m: r.row.m
      readonly property bool mine: m.from_me
      readonly property bool group: r.row.group
      readonly property bool showAvatar: group && !mine
      readonly property bool selecting: !!r.view && r.view.selecting
      readonly property bool isSelected: { if (!r.view) return false; r.view.selectedRev; return !!r.view.selected[m.id] }
      readonly property real topGap: r.row.first ? r.t.sp(12) : r.t.sp(2)
      readonly property bool hasReactions: !!m.reactions && m.reactions.length > 0
      readonly property real leftEdge: r.pad + (selecting ? r.t.sp(44) : 0) + (showAvatar ? r.t.sp(36) : 0)
      readonly property real maxWidth: Math.max(r.t.sp(180), (r.width - r.pad * 2 - (selecting ? r.t.sp(44) : 0) - (showAvatar ? r.t.sp(36) : 0)) * 0.72)

      width: r.width
      height: topGap + bubble.height + (hasReactions ? r.t.sp(22) : 0)

      // The highlight of a message you were taken to, or picked.
      Rectangle {
        anchors.fill: parent
        anchors.topMargin: mi.topGap - r.t.sp(2)
        color: r.list && r.list.flashId === mi.m.id ? r.t.flash : (mi.isSelected ? r.t.alpha(r.t.accent, 0.12) : "transparent")
        Behavior on color { ColorAnimation { duration: 300 } }
      }

      Icon {
        visible: mi.selecting
        x: r.pad
        y: mi.topGap + r.t.sp(6)
        name: mi.isSelected ? "checkboxOn" : "checkboxOff"
        size: r.t.sp(22)
        color: mi.isSelected ? r.t.accent : r.t.dim
      }

      Avatar {
        visible: mi.showAvatar && r.row.first
        x: r.pad + (mi.selecting ? r.t.sp(44) : 0)
        y: mi.topGap
        size: r.t.sp(28)
        jid: mi.m.sender
        name: String(mi.m.name || "").replace(/^~/, "")
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: r.win.showProfile(mi.m.sender) }
      }

      Bubble {
        id: bubble
        app: r.app
        win: r.win
        view: r.view
        list: r.list
        row: r.row
        m: mi.m
        maxWidth: mi.maxWidth
        x: mi.mine ? r.width - r.pad - width : mi.leftEdge
        y: mi.topGap
        hovered: hover.hovered
      }

      // Reactions, overlapping the bubble's bottom edge.
      Rectangle {
        visible: mi.hasReactions
        x: mi.mine ? bubble.x + bubble.width - width - r.t.sp(10) : bubble.x + r.t.sp(10)
        y: bubble.y + bubble.height - r.t.sp(5)
        height: r.t.sp(26)
        width: reacRow.implicitWidth + r.t.sp(12)
        radius: height / 2
        color: mi.mine ? r.t.bubbleOut : r.t.bubbleIn
        border.width: 2
        border.color: r.t.chatBg
        Row {
          id: reacRow
          anchors.centerIn: parent
          spacing: r.t.sp(2)
          Repeater {
            model: (mi.m.reactions || []).slice(0, 3)
            delegate: Text { textFormat: Text.PlainText; required property var modelData; text: modelData.emoji; font.family: r.t.emojiFont; font.pixelSize: r.t.sp(14) }
          }
          Text {
            textFormat: Text.PlainText
            readonly property int total: (mi.m.reactions || []).reduce(function(s, x) { return s + x.count }, 0)
            visible: total > 1
            text: total
            color: r.t.dim
            font.family: r.t.font
            font.pixelSize: r.t.fsSmall
            anchors.verticalCenter: parent.verticalCenter
            leftPadding: r.t.sp(2)
          }
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: r.win.dialog("reactions", { msg: mi.m }) }
      }

      // The quick react button beside the bubble, on hover.
      Rectangle {
        visible: hover.hovered && !mi.selecting && bubble.canReact
        x: mi.mine ? bubble.x - width - r.t.sp(8) : bubble.x + bubble.width + r.t.sp(8)
        y: bubble.y + bubble.height / 2 - height / 2
        width: r.t.sp(30); height: width; radius: width / 2
        color: rma.containsMouse ? r.t.popup : r.t.alpha(r.t.popup, 0.85)
        Icon { anchors.centerIn: parent; name: "react"; size: r.t.sp(20); color: r.t.icon }
        MouseArea {
          id: rma
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: bubble.openReactions(parent)
        }
      }

      HoverHandler { id: hover }
      // While selecting, a click anywhere on the row picks it or lets it go,
      // over the bubble's own links, media and text.
      MouseArea {
        anchors.fill: parent
        anchors.topMargin: mi.topGap - r.t.sp(2)
        visible: mi.selecting
        cursorShape: Qt.PointingHandCursor
        onClicked: r.view.toggleSelect(mi.m)
      }
    }
  }
}
