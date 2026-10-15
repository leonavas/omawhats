import QtQuick
import "../lib/Registry.js" as Reg

// Context menus over the whole window, as WhatsApp Web's: a rounded card
// of rows with an icon each, submenus beside their row. Items: {label,
// icon, action(), danger, checked, enabled, sub: [items], hint},
// {separator: true}, {header: "…"}, {reactions: ["👍", …], action(emoji),
// more()} (the quick reactions on top of a message's menu).
Item {
  id: menuLayer
  property var app: Reg.service
  readonly property var t: app.theme
  property var stack: []        // [{items, x, y}]
  property int hot: -1          // keyboard row in the last card
  readonly property bool shown: stack.length > 0
  visible: shown
  z: 900

  function open(items, x, y) {
    menuLayer.stack = [{ items: items, x: x, y: y }]
    menuLayer.hot = -1
    menuLayer.forceActiveFocus()
  }
  function close() { menuLayer.stack = []; menuLayer.hot = -1 }
  function openSub(level, items, x, y) {
    var s = menuLayer.stack.slice(0, level + 1)
    s.push({ items: items, x: x, y: y })
    menuLayer.stack = s
  }
  function trim(level) { if (menuLayer.stack.length > level + 1) menuLayer.stack = menuLayer.stack.slice(0, level + 1) }
  function run(item) {
    if (!item || item.enabled === false || item.sub) return
    menuLayer.close()
    if (item.action) Qt.callLater(item.action)
  }

  FontMetrics { id: labelMetrics; font.family: menuLayer.t.font; font.pixelSize: menuLayer.t.fsText }
  function measure(items) {
    var w = menuLayer.t.sp(180)
    for (var i = 0; i < items.length; i++) {
      var it = items[i]
      if (it.reactions) { w = Math.max(w, (it.reactions.length + (it.more ? 1 : 0)) * menuLayer.t.sp(44) + menuLayer.t.sp(16)); continue }
      var label = labelMetrics.advanceWidth(it.label || it.header || "")
      var extra = (it.icon || it.checked !== undefined ? menuLayer.t.sp(40) : 0) + (it.sub ? menuLayer.t.sp(24) : 0) + (it.hint ? labelMetrics.advanceWidth(it.hint) + menuLayer.t.sp(16) : 0)
      w = Math.max(w, label + extra + menuLayer.t.sp(40))
    }
    return Math.min(Math.round(w), menuLayer.t.sp(420))
  }

  Keys.onEscapePressed: menuLayer.close()
  Keys.onUpPressed: menuLayer.move(-1)
  Keys.onDownPressed: menuLayer.move(1)
  Keys.onReturnPressed: { var s = menuLayer.stack[menuLayer.stack.length - 1]; if (s && menuLayer.hot >= 0) menuLayer.run(s.items[menuLayer.hot]) }
  function move(d) {
    var s = menuLayer.stack[menuLayer.stack.length - 1]
    if (!s) return
    var n = s.items.length
    for (var k = 0; k < n; k++) {
      menuLayer.hot = (menuLayer.hot + d + n) % n
      var it = s.items[menuLayer.hot]
      if (!it.separator && it.header === undefined && !it.reactions && it.enabled !== false) return
    }
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.AllButtons
    onPressed: menuLayer.close()
    onWheel: wheel => menuLayer.close()
  }

  Repeater {
    model: menuLayer.stack
    delegate: Item {
      id: card
      required property var modelData
      required property int index
      readonly property int level: index
      width: menuLayer.measure(modelData.items)
      height: col.implicitHeight + menuLayer.t.sp(16)
      x: Math.max(6, Math.min(modelData.x, menuLayer.width - width - 6))
      y: Math.max(6, Math.min(modelData.y, menuLayer.height - height - 6))

      // A soft shadow, then the card.
      Rectangle {
        anchors.fill: parent
        anchors.topMargin: menuLayer.t.sp(3)
        anchors.leftMargin: -menuLayer.t.sp(1)
        anchors.rightMargin: -menuLayer.t.sp(1)
        anchors.bottomMargin: -menuLayer.t.sp(5)
        radius: menuLayer.t.sp(16)
        color: Qt.rgba(0, 0, 0, menuLayer.t.dark ? 0.35 : 0.14)
      }
      Rectangle {
        anchors.fill: parent
        radius: menuLayer.t.sp(14)
        color: menuLayer.t.popup
        border.width: 1
        border.color: menuLayer.t.line
      }

      MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; hoverEnabled: true }

      Column {
        id: col
        x: menuLayer.t.sp(8)
        y: menuLayer.t.sp(8)
        width: card.width - menuLayer.t.sp(16)

        Repeater {
          model: card.modelData.items
          delegate: Loader {
            id: row
            required property var modelData
            required property int index
            width: col.width
            sourceComponent: modelData.separator ? sepC : (modelData.header !== undefined ? headC : (modelData.reactions ? reactC : itemC))

            Component {
              id: sepC
              Item { height: menuLayer.t.sp(9); Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 1; color: menuLayer.t.line } }
            }
            Component {
              id: headC
              Text {
                textFormat: Text.PlainText
                text: row.modelData.header
                color: menuLayer.t.dim
                font.family: menuLayer.t.font
                font.pixelSize: menuLayer.t.fsSmall
                leftPadding: menuLayer.t.sp(12)
                topPadding: menuLayer.t.sp(6)
                bottomPadding: menuLayer.t.sp(6)
                elide: Text.ElideRight
                width: col.width
              }
            }
            Component {
              id: reactC
              Row {
                spacing: menuLayer.t.sp(2)
                bottomPadding: menuLayer.t.sp(4)
                Repeater {
                  model: row.modelData.reactions
                  delegate: Rectangle {
                    required property var modelData
                    width: menuLayer.t.sp(42); height: width; radius: width / 2
                    color: rma.containsMouse ? menuLayer.t.hoverStrong : (row.modelData.mine === modelData ? menuLayer.t.selected : "transparent")
                    Text { textFormat: Text.PlainText; anchors.centerIn: parent; text: parent.modelData; font.family: menuLayer.t.emojiFont; font.pixelSize: menuLayer.t.sp(26) }
                    MouseArea { id: rma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                      onClicked: { var f = row.modelData.action; var n = parent.modelData; menuLayer.close(); Qt.callLater(function() { f(n) }) } }
                  }
                }
                Rectangle {
                  visible: !!row.modelData.more
                  width: menuLayer.t.sp(42); height: width; radius: width / 2
                  color: pma.containsMouse ? menuLayer.t.hoverStrong : menuLayer.t.hover
                  Icon { anchors.centerIn: parent; name: "add"; size: menuLayer.t.sp(22); color: menuLayer.t.icon }
                  MouseArea { id: pma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: { var f = row.modelData.more; menuLayer.close(); Qt.callLater(f) } }
                }
              }
            }
            Component {
              id: itemC
              Rectangle {
                readonly property var it: row.modelData
                readonly property bool hot: ima.containsMouse || (menuLayer.hot === row.index && card.level === menuLayer.stack.length - 1)
                readonly property bool on: it.enabled !== false
                height: menuLayer.t.sp(40)
                radius: menuLayer.t.sp(8)
                color: hot && on ? menuLayer.t.hoverStrong : "transparent"
                readonly property color ink: it.danger ? menuLayer.t.danger : menuLayer.t.text
                opacity: on ? 1 : 0.45
                Row {
                  anchors.left: parent.left
                  anchors.leftMargin: menuLayer.t.sp(12)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: menuLayer.t.sp(14)
                  Icon {
                    visible: !!parent.parent.it.icon || parent.parent.it.checked !== undefined
                    name: parent.parent.it.checked !== undefined ? (parent.parent.it.checked ? "check" : "") : (parent.parent.it.icon || "")
                    size: menuLayer.t.sp(22)
                    color: parent.parent.it.danger ? menuLayer.t.danger : menuLayer.t.icon
                    anchors.verticalCenter: parent.verticalCenter
                  }
                  Text {
                    textFormat: Text.PlainText
                    text: parent.parent.it.label
                    color: parent.parent.ink
                    font.family: menuLayer.t.font
                    font.pixelSize: menuLayer.t.fsText
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }
                Text {
                  textFormat: Text.PlainText
                  anchors.right: parent.right
                  anchors.rightMargin: menuLayer.t.sp(12)
                  anchors.verticalCenter: parent.verticalCenter
                  visible: !!parent.it.hint && !parent.it.sub
                  text: parent.it.hint || ""
                  color: menuLayer.t.faint
                  font.family: menuLayer.t.font
                  font.pixelSize: menuLayer.t.fsSmall
                }
                Icon {
                  anchors.right: parent.right
                  anchors.rightMargin: menuLayer.t.sp(8)
                  anchors.verticalCenter: parent.verticalCenter
                  visible: !!parent.it.sub
                  name: "chevronRight"
                  size: menuLayer.t.sp(20)
                  color: menuLayer.t.dim
                }
                MouseArea {
                  id: ima
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: parent.on ? Qt.PointingHandCursor : Qt.ArrowCursor
                  onEntered: {
                    menuLayer.hot = -1
                    if (parent.it.sub && parent.on) {
                      var p = parent.mapToItem(menuLayer, parent.width + menuLayer.t.sp(12), -menuLayer.t.sp(8))
                      menuLayer.openSub(card.level, parent.it.sub, p.x, p.y)
                    } else menuLayer.trim(card.level)
                  }
                  onClicked: menuLayer.run(parent.it)
                }
              }
            }
          }
        }
      }
    }
  }
}
