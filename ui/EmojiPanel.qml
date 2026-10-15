import QtQuick
import QtQuick.Controls
import "../lib/Emoji.js" as Emoji
import "../lib/Util.js" as U
import "../lib/Registry.js" as Reg

// The panel over the message box, as WhatsApp Web's: Emoji (the recent
// ones, then by group, with a search) and Stickers (your favorites and the
// recent ones). Also the picker for a reaction (`pickOnly`).
Rectangle {
  id: ep
  property var app: Reg.service
  readonly property var t: app.theme
  readonly property var wa: app.wa
  property string chat: ""
  property bool pickOnly: false
  property string tab: "emoji"     // emoji, stickers
  signal picked(string glyph)
  signal sticker(var item)

  color: t.panel
  Rectangle { width: parent.width; height: 1; color: t.line }

  readonly property var recent: app.setting("recentEmoji", ["👍", "❤️", "😂", "😮", "😢", "🙏", "😊", "🎉"])
  function remember(g) {
    var r = ep.recent.filter(function(x) { return x !== g })
    r.unshift(g)
    ep.app.setSetting("recentEmoji", r.slice(0, 32))
  }
  function choose(g) { ep.remember(g); ep.picked(g) }

  readonly property string query: search.text.trim()
  readonly property var groups: {
    var cat = Emoji.catalogue(ep.app.lang)
    var out = [{ key: "recent", label: ep.app.tr("Recent", "Recentes"), icon: "recent", items: ep.recent }]
    return out.concat(cat)
  }
  readonly property var found: ep.query ? Emoji.search(ep.query, 120, ep.app.lang, ep.recent) : []

  onVisibleChanged: if (visible && ep.tab === "stickers") ep.wa.loadStickers()

  // ------------------------------------------------------------ tabs
  Row {
    id: tabs
    visible: !ep.pickOnly
    x: ep.t.sp(16)
    y: ep.t.sp(10)
    spacing: ep.t.sp(8)
    Repeater {
      model: [{ key: "emoji", label: ep.app.tr("Emoji", "Emojis") }, { key: "stickers", label: ep.app.tr("Stickers", "Figurinhas") }]
      delegate: Chip {
        required property var modelData
        app: ep.app
        label: modelData.label
        on: ep.tab === modelData.key
        onClicked: { ep.tab = modelData.key; if (ep.tab === "stickers") ep.wa.loadStickers() }
      }
    }
  }

  // ------------------------------------------------------------ emoji
  Item {
    id: emojiTab
    visible: ep.tab === "emoji" || ep.pickOnly
    anchors.fill: parent
    anchors.topMargin: ep.pickOnly ? ep.t.sp(10) : tabs.y + tabs.height + ep.t.sp(8)

    SearchPill {
      id: search
      x: ep.t.sp(14)
      width: parent.width - ep.t.sp(28)
      height: ep.t.sp(36)
      app: ep.app
      placeholder: ep.app.tr("Search emoji", "Pesquisar emoji")
      onAccepted: if (ep.found.length) ep.choose(ep.found[0])
    }

    // The groups, to jump to.
    Row {
      id: groupBar
      visible: !ep.query
      x: ep.t.sp(10)
      y: search.height + ep.t.sp(6)
      spacing: 0
      Repeater {
        model: ep.groups
        delegate: Item {
          required property var modelData
          required property int index
          width: Math.min(ep.t.sp(40), (emojiTab.width - ep.t.sp(20)) / ep.groups.length)
          height: ep.t.sp(34)
          Icon { anchors.centerIn: parent; name: modelData.icon; size: ep.t.sp(20); color: grid.currentGroup === index ? ep.t.accent : ep.t.faint }
          Rectangle { visible: grid.currentGroup === index; anchors.bottom: parent.bottom; width: parent.width; height: 2; color: ep.t.accent }
          MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: grid.showGroup(index) }
        }
      }
    }

    // One row of emoji per delegate (and one per group's title), so only
    // what's on screen is made.
    ListView {
      id: grid
      visible: !ep.query
      y: groupBar.y + groupBar.height + ep.t.sp(4)
      width: parent.width
      height: parent.height - y
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      cacheBuffer: ep.t.sp(400)
      ScrollBar.vertical: ThinScroll { app: ep.app }
      readonly property real cell: ep.t.sp(42)
      readonly property int cols: Math.max(6, Math.floor((width - ep.t.sp(20)) / cell))
      readonly property var rows: {
        var out = []
        for (var g = 0; g < ep.groups.length; g++) {
          out.push({ title: ep.groups[g].label, group: g })
          var items = ep.groups[g].items
          for (var i = 0; i < items.length; i += grid.cols) out.push({ items: items.slice(i, i + grid.cols), group: g })
        }
        return out
      }
      readonly property var groupStarts: {
        var starts = [], n = 0
        for (var g = 0; g < ep.groups.length; g++) { starts.push(n); n += 1 + Math.ceil(ep.groups[g].items.length / grid.cols) }
        return starts
      }
      readonly property int currentGroup: { var r = grid.rows[Math.max(0, grid.indexAt(10, grid.contentY + 10))]; return r ? r.group : 0 }
      function showGroup(g) { if (grid.groupStarts[g] !== undefined) grid.positionViewAtIndex(grid.groupStarts[g], ListView.Beginning) }
      model: rows
      delegate: Loader {
        required property var modelData
        width: grid.width
        sourceComponent: modelData.title !== undefined ? titleC : rowC
        property var r: modelData
      }
      Component {
        id: titleC
        Text {
          textFormat: Text.PlainText
          x: ep.t.sp(16)
          text: parent.r.title
          color: ep.t.dim
          font.family: ep.t.font
          font.pixelSize: ep.t.fsSmall
          topPadding: ep.t.sp(8)
          bottomPadding: ep.t.sp(6)
        }
      }
      Component {
        id: rowC
        Row {
          x: ep.t.sp(10)
          Repeater {
            model: parent.parent.r.items
            delegate: Rectangle {
              required property var modelData
              width: grid.cell; height: grid.cell; radius: ep.t.sp(8)
              color: ema.containsMouse ? ep.t.hoverStrong : "transparent"
              Text { textFormat: Text.PlainText; anchors.centerIn: parent; text: modelData; font.family: ep.t.emojiFont; font.pixelSize: ep.t.sp(26) }
              MouseArea { id: ema; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ep.choose(modelData) }
            }
          }
        }
      }
    }

    GridView {
      visible: !!ep.query
      y: search.height + ep.t.sp(10)
      x: ep.t.sp(10)
      width: parent.width - ep.t.sp(20)
      height: parent.height - y
      clip: true
      cellWidth: ep.t.sp(42)
      cellHeight: ep.t.sp(42)
      model: ep.found
      delegate: Rectangle {
        required property var modelData
        width: ep.t.sp(42); height: width; radius: ep.t.sp(8)
        color: fma.containsMouse ? ep.t.hoverStrong : "transparent"
        Text { textFormat: Text.PlainText; anchors.centerIn: parent; text: modelData; font.family: ep.t.emojiFont; font.pixelSize: ep.t.sp(26) }
        MouseArea { id: fma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ep.choose(modelData) }
      }
      Text {
        textFormat: Text.PlainText
        anchors.centerIn: parent
        visible: ep.found.length === 0
        text: ep.app.tr("No emoji found", "Nenhum emoji encontrado")
        color: ep.t.dim
        font.family: ep.t.font
        font.pixelSize: ep.t.fsText
      }
    }
  }

  // ------------------------------------------------------------ stickers
  Item {
    visible: ep.tab === "stickers" && !ep.pickOnly
    anchors.fill: parent
    anchors.topMargin: tabs.y + tabs.height + ep.t.sp(8)
    GridView {
      id: sgrid
      anchors.fill: parent
      anchors.leftMargin: ep.t.sp(10)
      clip: true
      readonly property real cell: Math.floor((width - ep.t.sp(10)) / Math.max(3, Math.floor(width / ep.t.sp(110))))
      cellWidth: cell
      cellHeight: cell
      model: ep.wa.stickers || []
      ScrollBar.vertical: ThinScroll { app: ep.app }
      delegate: Rectangle {
        required property var modelData
        width: sgrid.cell; height: width; radius: ep.t.sp(10)
        color: sma.containsMouse ? ep.t.hover : "transparent"
        AnimatedImage {
          anchors.fill: parent
          anchors.margins: ep.t.sp(8)
          source: U.fileUrl(modelData.path)
          fillMode: Image.PreserveAspectFit
          playing: sma.containsMouse
          asynchronous: true
        }
        Icon { visible: !!modelData.fav; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: ep.t.sp(4); name: "heartFilled"; size: ep.t.sp(14); color: ep.t.danger }
        MouseArea { id: sma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ep.sticker(modelData) }
      }
      Column {
        anchors.centerIn: parent
        visible: sgrid.count === 0
        spacing: ep.t.sp(10)
        BusyIndicator { anchors.horizontalCenter: parent.horizontalCenter; running: ep.wa.stickers === null; visible: running }
        Text {
          textFormat: Text.PlainText
          visible: ep.wa.stickers !== null
          text: ep.app.tr("Stickers you receive and favorite show up here", "As figurinhas que você recebe e favorita aparecem aqui")
          color: ep.t.dim
          font.family: ep.t.font
          font.pixelSize: ep.t.fsText
        }
      }
    }
  }
}
