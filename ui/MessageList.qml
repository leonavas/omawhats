import QtQuick
import QtQuick.Controls
import Quickshell
import "../lib/Model.js" as Model
import "../lib/Util.js" as U
import "../lib/Registry.js" as Reg

// A chat's messages, newest at the bottom. Scrolling up loads older pages
// (and, past what's here, asks the phone). On open it sits on the unread
// band when there is one; the round button brings you back down; the day
// of what's on top floats while you scroll.
Item {
  id: root
  property var app: Reg.service
  property var win
  property var view               // the Conversation
  property string chat: ""
  readonly property var t: app.theme
  readonly property var wa: app.wa

  // The history object is mutated in place: whatever reads it reads
  // historyRev too, so it follows.
  readonly property int rev: wa.historyRev
  readonly property var hist: { root.rev; return root.wa.histories[root.chat] || null }
  readonly property bool group: chat.indexOf("@g.us") > 0
  property var rowCache: ({})
  property string unreadFrom: ""
  property int unreadCount: 0
  property bool opened: false
  // Messages that arrived while you were scrolled up.
  property int newBelow: 0
  property string flashId: ""

  onChatChanged: {
    root.rowCache = ({})
    root.opened = false
    root.unreadFrom = ""
    root.newBelow = 0
    root.flashId = ""
  }

  // The band goes over the first of the unread ones, once, at open.
  onRevChanged: {
    var h = root.wa.histories[root.chat]
    if (root.opened || !h || !h.loaded || root.unreadFrom) return
    var n = root.wa.unreadMarks[root.chat] || 0
    if (n > 0) { root.unreadCount = n; root.unreadFrom = Model.firstUnread(h.msgs, n) }
  }

  readonly property var rows: {
    root.rev
    var h = root.wa.histories[root.chat]
    if (!h) return []
    var atStart = h.loaded && !h.more && (h.olderDone || h.msgs.length === 0)
    var list = Model.rows(h.msgs, { unreadFrom: root.unreadFrom, unread: root.unreadCount, group: root.group, atStart: atStart }, root.rowCache)
    return list.reverse()
  }

  // Pinned to the newest message unless you scrolled up.
  readonly property bool atBottom: list.atYEnd || list.contentHeight <= list.height
  property bool _prevAtBottom: true
  property int _prevCount: 0
  onRowsChanged: Qt.callLater(root.settle)
  function settle() {
    var h = root.hist
    if (!h || !h.loaded) return
    if (!root.opened) {
      root.opened = true
      root._prevCount = h.msgs.length
      if (root.unreadFrom) {
        var at = root.indexOfKey("unread")
        if (at >= 0) { list.positionViewAtIndex(at, ListView.Contain); return }
      }
      list.positionViewAtBeginning()
      root.tryJump()
      return
    }
    var n = h.msgs.length
    if (n > root._prevCount && root._prevAtBottom) list.positionViewAtBeginning()
    else if (n > root._prevCount && !root._prevAtBottom) {
      var last = h.msgs[n - 1]
      if (last && !last.from_me) root.newBelow += n - root._prevCount
      if (last && last.from_me) list.positionViewAtBeginning()
    }
    root._prevCount = n
    root.tryJump()
  }
  Connections {
    target: list
    function onContentYChanged() {
      root._prevAtBottom = root.atBottom
      if (root.atBottom) root.newBelow = 0
      // Near the top: the page before.
      if (list.contentY - list.originY < root.t.sp(600) && root.opened) root.wa.loadOlder(root.chat)
      dayChip.show()
    }
  }

  function indexOfKey(key) {
    var r = root.rows
    for (var i = 0; i < r.length; i++) if (r[i].key === key) return i
    return -1
  }

  // Going to a message: a quote's, a search result's. Older pages load
  // until it's here (a few at most).
  property var _jump: null
  property int _jumpTries: 0
  Connections {
    target: root.wa
    function onJumpToChanged() {
      var j = root.wa.jumpTo
      if (j && j.chat === root.chat) { root._jump = j; root._jumpTries = 0; root.tryJump() }
    }
  }
  function jumpTo(id) { root._jump = { chat: root.chat, id: id }; root._jumpTries = 0; root.tryJump() }
  function tryJump() {
    var j = root._jump
    if (!j || !root.opened) return
    var at = root.indexOfKey(j.id)
    if (at >= 0) {
      root._jump = null
      list.positionViewAtIndex(at, ListView.Center)
      root.flashId = j.id
      flashTimer.restart()
      return
    }
    if (root._jumpTries++ < 25) root.wa.loadOlder(root.chat)
    else root._jump = null
  }
  Timer { id: flashTimer; interval: 1600; onTriggered: root.flashId = "" }

  ListView {
    id: list
    anchors.fill: parent
    verticalLayoutDirection: ListView.BottomToTop
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    cacheBuffer: root.t.sp(1400)
    reuseItems: false
    topMargin: root.t.sp(12)
    bottomMargin: root.t.sp(10)
    model: ScriptModel { values: root.rows; objectProp: "key" }
    ScrollBar.vertical: ThinScroll { app: root.app }
    flickDeceleration: 4000
    maximumFlickVelocity: 6000

    delegate: MessageRow {
      required property var modelData
      width: list.width
      app: root.app
      win: root.win
      view: root.view
      list: root
      row: modelData
    }

    footer: Item {
      width: list.width
      height: { root.rev; return root.hist && root.hist.loading && root.opened ? root.t.sp(56) : 0 }
      BusyIndicator {
        anchors.centerIn: parent
        running: parent.height > 0
        visible: running
        width: root.t.sp(32); height: width
      }
    }
  }

  // The day of what's on top, while scrolling.
  Rectangle {
    id: dayChip
    property string label: ""
    function show() {
      var it = list.itemAt(list.width / 2, list.contentY + root.t.sp(30))
      if (it && it.row && (it.row.ts || (it.row.m && it.row.m.ts))) label = U.dayLabel(it.row.ts || it.row.m.ts, root.app.lang)
      if (!list.moving && !list.dragging) return
      opacity = 1
      hideChip.restart()
    }
    anchors.horizontalCenter: parent.horizontalCenter
    y: root.t.sp(10)
    width: chipText.implicitWidth + root.t.sp(24)
    height: root.t.sp(28)
    radius: root.t.sp(8)
    color: root.t.system
    opacity: 0
    visible: opacity > 0 && label !== ""
    Behavior on opacity { NumberAnimation { duration: 200 } }
    Text { id: chipText; anchors.centerIn: parent; text: dayChip.label; color: root.t.dim; font.family: root.t.font; font.pixelSize: root.t.fsSmall; font.weight: Font.Medium }
    Timer { id: hideChip; interval: 1300; onTriggered: dayChip.opacity = 0 }
  }

  // Back to the newest, with how many came meanwhile.
  Rectangle {
    id: down
    visible: !root.atBottom && root.opened
    anchors.right: parent.right
    anchors.rightMargin: root.t.sp(20)
    anchors.bottom: parent.bottom
    anchors.bottomMargin: root.t.sp(16)
    width: root.t.sp(42); height: width; radius: width / 2
    color: root.t.popup
    border.width: 1
    border.color: root.t.line
    Icon { anchors.centerIn: parent; name: "chevronDown"; size: root.t.sp(26); color: root.t.icon }
    Rectangle {
      visible: root.newBelow > 0
      anchors.right: parent.right
      anchors.rightMargin: -root.t.sp(4)
      y: -root.t.sp(8)
      height: root.t.sp(20)
      width: Math.max(height, nb.implicitWidth + root.t.sp(10))
      radius: height / 2
      color: root.t.badge
      Text { id: nb; anchors.centerIn: parent; text: root.newBelow; color: root.t.badgeText; font.family: root.t.font; font.pixelSize: root.t.sp(11); font.weight: Font.DemiBold }
    }
    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { list.positionViewAtBeginning(); root.newBelow = 0 } }
  }

  // Empty chat: WhatsApp's note, centered.
  Text {
    anchors.centerIn: parent
    visible: { root.rev; return !!root.hist && root.hist.loaded && root.hist.msgs.length === 0 && !root.hist.loading }
    width: Math.min(parent.width - root.t.sp(60), root.t.sp(420))
    horizontalAlignment: Text.AlignHCenter
    wrapMode: Text.Wrap
    text: root.app.tr("No messages here yet. Say hi!", "Nenhuma mensagem aqui ainda. Diga oi!")
    color: root.t.dim
    font.family: root.t.font
    font.pixelSize: root.t.fsText
  }
}
