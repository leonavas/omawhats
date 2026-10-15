import QtQuick
import "../lib/Bar.js" as Bar
import "../lib/Util.js" as U
import "../lib/Registry.js" as Reg

// Your menu, whatsapp-tui's account menu (your photo at the foot of the
// rail, Alt+S): a card that grows up beside the rail with you (photo, name,
// and the connection or the pause under it), Notifications (a submenu to
// pause or resume them), your profile, Settings, the shortcuts, new
// versions (when there's an updater: "Check for updates", and the update
// under it while there is one), About and Log out.
Item {
  id: d
  property var app: Reg.service
  property var win
  readonly property var t: app.theme
  readonly property var wa: app.wa
  signal closed()
  anchors.fill: parent
  z: 870

  // ---------------------------------------------------------------- state
  readonly property string myJid: d.wa.me ? d.wa.me.jid : ""
  readonly property string myName: d.wa.me && d.wa.me.name ? d.wa.me.name
                                   : (d.wa.me && d.wa.me.phone ? U.phone(d.wa.me.phone) : d.app.tr("You", "Você"))
  readonly property bool paused: d.app.paused
  readonly property string pausedLabel: d.paused ? Bar.clockLabel(d.app.pausedUntil, d.app.nowSec, d.app.lang) : ""
  // The line under your name, as the TUI's: the connection, or the pause.
  readonly property var line: {
    if (d.wa.conn !== "ready") return { text: d.app.tr("connecting…", "conectando…"), color: d.t.warning }
    if (d.wa.syncProgress >= 0 && d.wa.syncProgress < 100) return { text: d.app.tr("syncing ", "sincronizando ") + d.wa.syncProgress + "%", color: d.t.warning }
    if (d.paused) return { text: d.app.tr("notifications paused until ", "notificações pausadas até ") + d.pausedLabel, color: d.t.faint, muted: true }
    return { text: d.app.tr("connected", "conectado"), color: d.t.online }
  }
  // New versions, when the service has an updater ({phase: "" | available |
  // updating | updated, latest, checking, how, check(force), update()}).
  readonly property var up: d.app.updater || null
  readonly property string upPhase: d.up ? (d.up.phase || "") : ""

  property int hot: -1          // keyboard/hover row of the menu
  property bool subOpen: false  // the notifications submenu
  property int subHot: -1
  property bool subKeys: false  // the keyboard is in the submenu
  property Item notifRow: null  // where the submenu hangs

  readonly property var items: [
    { notif: true, icon: d.paused ? "muted" : "notifications", label: d.app.tr("Notifications", "Notificações") },
    { sep: true },
    { icon: "account", label: d.app.tr("Profile", "Perfil"), hint: "Ctrl+Alt+P", run: function() { d.open("profile") } },
    { icon: "settings", label: d.app.tr("Settings", "Configurações"), hint: "Ctrl+,", run: function() { var w = d.win; d.closed(); w.openSide("settings") } },
    { icon: "keyboard", label: d.app.tr("Keyboard shortcuts", "Atalhos do teclado"), hint: "Ctrl+/", run: function() { d.open("shortcuts") } },
    { sep: true },
    // Stays open on a check, so what it finds shows up under it.
    { hidden: !d.up, icon: d.upPhase === "updated" ? "refresh" : "sync", faded: !!d.up && !!d.up.checking,
      label: d.upPhase === "updated" ? d.app.tr("Restart the shell to update", "Reinicie o shell para atualizar")
             : d.up && d.up.checking ? d.app.tr("Checking for updates…", "Procurando atualizações…") : d.app.tr("Check for updates", "Procurar atualizações"),
      hint: d.upPhase === "updated" ? "↻" : "",
      run: function() { var u = d.up; if (d.upPhase === "updated") { d.closed(); u.update() } else u.check(true) } },
    // In green, as what's new; faded while it works; how to, when it isn't Omarchy's to update.
    { hidden: d.upPhase !== "available" && d.upPhase !== "updating", icon: "download",
      good: d.upPhase === "available", faded: d.upPhase === "updating",
      label: d.upPhase === "available" ? d.app.tr("Update to ", "Atualizar para a versão ") + d.up.latest : d.app.tr("Updating…", "Atualizando…"),
      hint: d.upPhase === "available" ? "↓" : "", sub2: d.upPhase === "available" && d.up.how ? d.up.how : "",
      run: function() { if (d.upPhase === "available") d.up.update() } },
    { icon: "info", label: d.app.tr("About ", "Sobre o ") + d.app.windowTitleBase, run: function() { d.open("about") } },
    { icon: "logout", danger: true, label: d.app.tr("Log out", "Desconectar"), run: function() { d.open("logout") } }
  ].filter(function(it) { return !it.hidden })

  // The TUI's: while paused, until when and the way back, then the pauses.
  readonly property var subItems: {
    var out = []
    var now = d.app.nowSec
    if (d.paused) {
      out.push({ head: d.app.tr("Paused until ", "Pausadas até ") + d.pausedLabel, warn: true })
      out.push({ sep: true })
      out.push({ label: d.app.tr("Resume notifications", "Retomar notificações"), run: function() { d.resume() } })
      out.push({ sep: true })
    }
    out.push({ head: d.app.tr("Pause notifications for…", "Pausar notificações por…") })
    out.push({ label: d.app.tr("30 minutes", "30 minutos"), run: function() { d.pause(30) } })
    out.push({ label: d.app.tr("1 hour", "1 hora"), run: function() { d.pause(60) } })
    out.push({ label: d.app.tr("2 hours", "2 horas"), run: function() { d.pause(120) } })
    out.push({ label: d.app.tr("Until tomorrow", "Até amanhã"), hint: Bar.clockLabel(now + Bar.minutesToTomorrow(now) * 60, now, d.app.lang),
               run: function() { d.pause(Bar.minutesToTomorrow(Date.now() / 1000)) } })
    out.push({ label: d.app.tr("Until next week", "Até a próxima semana"), hint: Bar.clockLabel(now + Bar.minutesToNextWeek(now) * 60, now, d.app.lang),
               run: function() { d.pause(Bar.minutesToNextWeek(Date.now() / 1000)) } })
    return out
  }

  // ---------------------------------------------------------------- actions
  function open(name) { var w = d.win; d.closed(); w.dialog(name, {}) }
  function pause(minutes) {
    var a = d.app, w = d.win
    d.closed()
    a.pause(minutes)
    w.toast(a.tr("Notifications paused until ", "Notificações pausadas até ") + Bar.clockLabel(a.pausedUntil, Date.now() / 1000, a.lang))
  }
  function resume() {
    var a = d.app, w = d.win
    d.closed()
    a.resume()
    w.toast(a.tr("Notifications resumed", "Notificações retomadas"))
  }
  function activate(i) {
    var it = d.items[i]
    if (!it) return
    if (it.notif) { d.openSub(true); return }
    if (it.faded) return
    if (it.run) it.run()
  }
  function selectable(list, i) { var it = list[i]; return !!it && !it.sep && it.head === undefined }
  function step(list, from, dir) {
    var n = list.length
    var i = from
    for (var k = 0; k < n; k++) {
      i = (i + dir + n) % n
      if (d.selectable(list, i)) return i
    }
    return from
  }
  function openSub(byKeys) {
    d.subOpen = true
    d.subKeys = byKeys
    d.subHot = byKeys ? d.step(d.subItems, -1, 1) : -1
  }
  function closeSub() { d.subOpen = false; d.subKeys = false; d.subHot = -1 }

  focus: true
  Component.onCompleted: d.forceActiveFocus()
  Keys.onPressed: event => {
    var k = event.key
    if (k === Qt.Key_Escape || (k === Qt.Key_S && (event.modifiers & Qt.AltModifier))) {
      if (d.subOpen && k === Qt.Key_Escape) d.closeSub(); else d.closed()
      event.accepted = true
      return
    }
    var up = k === Qt.Key_Up || k === Qt.Key_Backtab || k === Qt.Key_K
    var down = k === Qt.Key_Down || k === Qt.Key_Tab || k === Qt.Key_J
    var go = k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space
    if (d.subKeys) {
      if (up || down) d.subHot = d.step(d.subItems, d.subHot, up ? -1 : 1)
      else if (k === Qt.Key_Left || k === Qt.Key_H) d.closeSub()
      else if (go || k === Qt.Key_Right || k === Qt.Key_L) { var it = d.subItems[d.subHot]; if (it && it.run) it.run() }
      else return
      event.accepted = true
      return
    }
    if (up || down) {
      d.hot = d.step(d.items, d.hot < 0 && up ? d.items.length : d.hot, up ? -1 : 1)
      if (!d.items[d.hot].notif) d.closeSub()
    } else if (go) d.activate(d.hot)
    else if ((k === Qt.Key_Right || k === Qt.Key_L) && d.hot >= 0 && d.items[d.hot].notif) d.openSub(true)
    else return
    event.accepted = true
  }

  // Clicks outside close it, like any menu.
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.AllButtons
    onPressed: d.closed()
    onWheel: wheel => d.closed()
  }

  component Card: Item {
    id: cd
    default property alias content: body.data
    // A soft shadow, then the card, as MenuLayer's.
    Rectangle {
      anchors.fill: parent
      anchors.topMargin: d.t.sp(3)
      anchors.leftMargin: -d.t.sp(1)
      anchors.rightMargin: -d.t.sp(1)
      anchors.bottomMargin: -d.t.sp(5)
      radius: d.t.sp(16)
      color: Qt.rgba(0, 0, 0, d.t.dark ? 0.35 : 0.14)
    }
    Rectangle {
      anchors.fill: parent
      radius: d.t.sp(14)
      color: d.t.popup
      border.width: 1
      border.color: d.t.line
    }
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; hoverEnabled: true }
    Item { id: body; anchors.fill: parent }
  }

  component Sep: Item {
    height: d.t.sp(9)
    Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 1; color: d.t.line }
  }

  // ---------------------------------------------------------------- the card
  Card {
    id: card
    // Beside the rail, its foot level with your photo's.
    x: d.t.railWidth + d.t.sp(8)
    y: Math.max(d.t.sp(6), d.height - height - d.t.sp(10))
    width: d.t.sp(330)
    height: col.implicitHeight + d.t.sp(16)

    Column {
      id: col
      x: d.t.sp(8)
      y: d.t.sp(8)
      width: card.width - d.t.sp(16)

      // You: a click shows your profile.
      Rectangle {
        width: parent.width
        height: d.t.sp(64)
        radius: d.t.sp(8)
        color: meMa.containsMouse ? d.t.hover : "transparent"
        Avatar {
          id: photo
          app: d.app
          x: d.t.sp(8)
          anchors.verticalCenter: parent.verticalCenter
          size: d.t.sp(44)
          jid: d.myJid
          name: d.wa.me ? d.wa.me.name : ""
        }
        Column {
          anchors.left: photo.right
          anchors.leftMargin: d.t.sp(12)
          anchors.right: parent.right
          anchors.rightMargin: d.t.sp(10)
          anchors.verticalCenter: parent.verticalCenter
          spacing: d.t.sp(3)
          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: d.myName
            color: d.t.textBright
            font.family: d.t.font
            font.pixelSize: d.t.fsName
            font.weight: Font.DemiBold
            elide: Text.ElideRight
          }
          Row {
            width: parent.width
            spacing: d.t.sp(6)
            Rectangle {
              visible: !d.line.muted
              anchors.verticalCenter: parent.verticalCenter
              width: d.t.sp(8); height: width; radius: width / 2
              color: d.line.color
            }
            Icon {
              visible: !!d.line.muted
              anchors.verticalCenter: parent.verticalCenter
              name: "muted"
              size: d.t.sp(15)
              color: d.t.dim
            }
            Text {
              textFormat: Text.PlainText
              width: parent.width - d.t.sp(20)
              anchors.verticalCenter: parent.verticalCenter
              text: d.line.text
              color: d.t.dim
              font.family: d.t.font
              font.pixelSize: d.t.fsSmall
              elide: Text.ElideRight
            }
          }
        }
        MouseArea { id: meMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onEntered: d.closeSub(); onClicked: d.open("profile") }
      }
      Sep { width: parent.width }

      Repeater {
        model: d.items
        delegate: Loader {
          id: row
          required property var modelData
          required property int index
          width: col.width
          sourceComponent: modelData.sep ? sepC : itemC

          Component { id: sepC; Sep {} }
          Component {
            id: itemC
            Rectangle {
              id: ir
              readonly property var it: row.modelData
              readonly property bool hot: (d.hot === row.index || (!!ir.it.notif && d.subOpen)) && !ir.it.faded
              readonly property color ink: ir.it.danger ? d.t.danger : (ir.it.good ? d.t.green : (ir.it.faded ? d.t.faint : d.t.text))
              height: ir.it.sub2 ? d.t.sp(50) : d.t.sp(40)
              radius: d.t.sp(8)
              color: ir.hot ? d.t.hoverStrong : "transparent"
              Icon {
                id: ico
                x: d.t.sp(12)
                anchors.verticalCenter: parent.verticalCenter
                name: ir.it.icon || ""
                size: d.t.sp(22)
                color: ir.it.danger ? d.t.danger : (ir.it.good ? d.t.green : (ir.it.faded ? d.t.faint : d.t.icon))
              }
              Column {
                anchors.left: ico.right
                anchors.leftMargin: d.t.sp(14)
                anchors.right: tail.left
                anchors.rightMargin: d.t.sp(8)
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1
                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  text: ir.it.label
                  color: ir.ink
                  font.family: d.t.font
                  font.pixelSize: d.t.fsText
                  font.weight: ir.it.good ? Font.DemiBold : Font.Normal
                  elide: Text.ElideRight
                }
                Text {
                  textFormat: Text.PlainText
                  visible: !!ir.it.sub2
                  width: parent.width
                  text: ir.it.sub2 || ""
                  color: d.t.warning
                  font.family: d.t.font
                  font.pixelSize: d.t.fsSmall
                  elide: Text.ElideRight
                }
              }
              // At the right: the shortcut, or the submenu's arrow (with the
              // bell off while paused).
              Row {
                id: tail
                anchors.right: parent.right
                anchors.rightMargin: ir.it.notif ? d.t.sp(8) : d.t.sp(12)
                anchors.verticalCenter: parent.verticalCenter
                spacing: d.t.sp(4)
                Icon { visible: !!ir.it.notif && d.paused; anchors.verticalCenter: parent.verticalCenter; name: "muted"; size: d.t.sp(16); color: d.t.warning }
                Icon { visible: !!ir.it.notif; anchors.verticalCenter: parent.verticalCenter; name: "chevronRight"; size: d.t.sp(20); color: d.t.dim }
                Text {
                  textFormat: Text.PlainText
                  visible: !ir.it.notif && !!ir.it.hint
                  anchors.verticalCenter: parent.verticalCenter
                  text: ir.it.hint || ""
                  color: ir.it.good ? d.t.green : d.t.faint
                  font.family: d.t.font
                  font.pixelSize: d.t.fsSmall
                }
              }
              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: ir.it.faded ? Qt.ArrowCursor : Qt.PointingHandCursor
                onEntered: {
                  d.hot = row.index
                  if (ir.it.notif) { if (!d.subOpen) d.openSub(false) }
                  else d.closeSub()
                }
                onExited: if (d.hot === row.index && !ir.it.notif) d.hot = -1
                onClicked: d.activate(row.index)
              }
              Component.onCompleted: if (ir.it.notif) d.notifRow = ir
            }
          }
        }
      }
    }
  }

  // ---------------------------------------------------------------- the submenu
  Card {
    id: sub
    visible: d.subOpen
    readonly property point at: d.notifRow && d.subOpen ? d.notifRow.mapToItem(d, d.notifRow.width + d.t.sp(12), -d.t.sp(8)) : Qt.point(0, 0)
    x: Math.min(sub.at.x, d.width - width - d.t.sp(6))
    y: Math.max(d.t.sp(6), Math.min(sub.at.y, d.height - height - d.t.sp(6)))
    width: d.t.sp(290)
    height: subCol.implicitHeight + d.t.sp(16)

    Column {
      id: subCol
      x: d.t.sp(8)
      y: d.t.sp(8)
      width: sub.width - d.t.sp(16)
      Repeater {
        model: d.subOpen ? d.subItems : []
        delegate: Loader {
          id: srow
          required property var modelData
          required property int index
          width: subCol.width
          sourceComponent: modelData.sep ? ssepC : (modelData.head !== undefined ? sheadC : sitemC)
          Component { id: ssepC; Sep {} }
          Component {
            id: sheadC
            Row {
              spacing: d.t.sp(8)
              leftPadding: d.t.sp(12)
              topPadding: d.t.sp(6)
              bottomPadding: d.t.sp(6)
              Icon { visible: !!srow.modelData.warn; anchors.verticalCenter: parent.verticalCenter; name: "muted"; size: d.t.sp(16); color: d.t.warning }
              Text {
                textFormat: Text.PlainText
                anchors.verticalCenter: parent.verticalCenter
                text: srow.modelData.head
                color: srow.modelData.warn ? d.t.warning : d.t.dim
                font.family: d.t.font
                font.pixelSize: d.t.fsSmall
              }
            }
          }
          Component {
            id: sitemC
            Rectangle {
              id: sr
              readonly property bool hot: d.subHot === srow.index
              height: d.t.sp(40)
              radius: d.t.sp(8)
              color: sr.hot ? d.t.hoverStrong : "transparent"
              Text {
                textFormat: Text.PlainText
                anchors.left: parent.left
                anchors.leftMargin: d.t.sp(12)
                anchors.verticalCenter: parent.verticalCenter
                text: srow.modelData.label
                color: d.t.text
                font.family: d.t.font
                font.pixelSize: d.t.fsText
              }
              Text {
                textFormat: Text.PlainText
                anchors.right: parent.right
                anchors.rightMargin: d.t.sp(12)
                anchors.verticalCenter: parent.verticalCenter
                text: srow.modelData.hint || ""
                color: d.t.faint
                font.family: d.t.font
                font.pixelSize: d.t.fsSmall
              }
              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: { d.subHot = srow.index; d.hot = 0 }
                onExited: if (!d.subKeys && d.subHot === srow.index) d.subHot = -1
                onClicked: srow.modelData.run()
              }
            }
          }
        }
      }
    }
  }
}
