import QtQuick
import QtQuick.Effects
import QtQuick.Window
import Quickshell
import qs.Commons
import qs.Ui
import "lib/Registry.js" as Registry
import "lib/Bar.js" as Bar
import "lib/Labels.js" as L
import "lib/Format.js" as F

// The bar's door into WhatsApp, as whatsapp-tui's widget is to it: the mark
// (white and tinted like the bar's glyphs, outlined, green, or a Nerd Font
// glyph), a red badge for unread direct chats and a blue one for groups
// (muted chats count in neither), a preview of them on hover, the menu on a
// right click, pauses. The app itself is the plugin's service
// (Service.qml): it runs WhatsApp, the window and the notifications.
BarWidget {
  id: root
  moduleName: "leonavas.whatsapp-claude"

  // ---------------------------------------------------------------- settings
  readonly property string iconStyle: String(setting("iconStyle", "Mono"))
  readonly property string glyph: String(setting("glyph", "󰖣"))
  readonly property int glyphSize: Math.max(0, Number(setting("glyphSize", 0)))
  readonly property real glyphOffsetY: Number(setting("glyphOffsetY", -0.5))
  readonly property string badgeStyle: String(setting("badge", "Count"))
  readonly property bool combinedBadge: String(setting("badgeLayout", "Split")) === "Combined"
  readonly property string directColorSetting: String(setting("directColor", "#b65f4e"))
  readonly property string groupColorSetting: String(setting("groupColor", "#467996"))
  readonly property real badgeScale: Math.max(0.2, Math.min(0.9, Number(setting("badgeScale", 0.45))))
  readonly property bool tintWhenUnread: setting("tintWhenUnread", false) === true
  readonly property string hideMode: String(setting("hideMode", "Special workspace"))
  readonly property string specialName: String(setting("specialWorkspace", "scratchpad"))
  readonly property bool openInSpecial: setting("openInSpecial", true) !== false
  readonly property bool autoStart: setting("autoStart", false) === true
  readonly property bool launchForeground: setting("launchForeground", true) !== false
  readonly property bool dimWhenClosed: setting("dimWhenClosed", true) !== false
  readonly property bool hideWhenNotRunning: setting("hideWhenNotRunning", false) === true
  readonly property bool closeOnMiddle: setting("middleClickCloses", true) !== false
  readonly property bool hoverPreview: setting("hoverPreview", true) !== false
  readonly property int previewRows: Math.max(1, Number(setting("previewRows", 6)))
  readonly property int previewMessages: Math.max(1, Math.min(5, Number(setting("previewMessages", 3))))
  readonly property bool desktopNotifications: setting("notifications", true) !== false
  readonly property bool notificationText: setting("notificationText", true) !== false
  readonly property string mutedIndicator: String(setting("mutedIndicator", "Bell"))

  // ------------------------------------------------------------------- theme
  readonly property color foreground: bar ? bar.barForeground : Color.foreground
  readonly property color urgentColor: bar ? bar.urgent : Color.urgent
  // Direct chats in one color, groups in the other. An empty setting falls
  // back to the theme's urgent color.
  readonly property color directColor: root.directColorSetting.length > 0 ? root.directColorSetting : root.urgentColor
  readonly property color groupColor: root.groupColorSetting.length > 0 ? root.groupColorSetting : root.directColor
  readonly property color badgeDigitColor: "#ffffff"
  readonly property color badgeTextColor: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 1)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // ---------------------------------------------------------------- service
  property var service: null
  function findService() {
    var s = null
    try { if (root.bar && root.bar.shell && typeof root.bar.shell.serviceFor === "function") s = root.bar.shell.serviceFor("leonavas.whatsapp-claude") } catch (e) { s = null }
    if (!s) s = Registry.service
    root.service = s
  }
  Timer { interval: 400; repeat: true; running: !root.service; triggeredOnStart: true; onTriggered: root.findService() }
  Connections {
    target: root.service
    ignoreUnknownSignals: true
    function onDestroyed() { root.service = null }
  }
  readonly property var wa: root.service ? root.service.wa : null

  function tr(en, pt) { return root.service ? root.service.tr(en, pt) : en }
  readonly property string lang: root.service ? root.service.lang : "en"

  // The window's options and the notifications' go to the service, which
  // acts on them; the first widget (one per monitor) also takes the app's
  // toggles of the notifications into its settings.
  readonly property var barOptions: ({ specialName: root.specialName, openInSpecial: root.openInSpecial,
                                       hideMode: root.hideMode, launchForeground: root.launchForeground,
                                       notifications: root.desktopNotifications, notificationText: root.notificationText })
  onBarOptionsChanged: root.pushOptions()
  onServiceChanged: root.pushOptions()
  function pushOptions() {
    if (!root.service || !root.isPrimaryInstance()) return
    root.service.barOptions = root.barOptions
    root.service.barWriter = function(key, value) { root.writeSetting(key, value) }
  }
  Component.onDestruction: {
    if (root.service && root.isPrimaryInstance()) root.service.barWriter = null
  }

  // ------------------------------------------------------------------ window
  readonly property bool running: !!root.service && root.service.running
  readonly property bool windowOpen: !!root.service && root.service.windowOpen
  readonly property bool focused: !!root.service && root.service.windowFocused
  readonly property bool parked: !!root.service && root.service.parked
  readonly property bool specialShown: !!root.service && root.service.specialShown

  // ------------------------------------------------------- whatsapp's state
  // Gated on running: stopped, the last counts are not a badge.
  readonly property bool linked: root.running && !!root.wa && root.wa.linked
  readonly property bool stateLive: root.linked
  // Not linked yet: the widget is the way to link it, as whatsapp-tui's is
  // to install it.
  readonly property bool notLinked: root.running && !!root.wa && (root.wa.conn === "pairing" || root.wa.conn === "logged_out")

  // Wall clock for relative times and pause expiry, coarse on purpose.
  property real nowSec: Date.now() / 1000
  Timer { interval: 20000; repeat: true; running: true; onTriggered: root.nowSec = Date.now() / 1000 }

  readonly property var att: root.stateLive && root.service ? root.service.attention : ({ chats: 0, direct: 0, groups: 0, messages: 0, muted: 0, archived: 0 })
  readonly property int attention: root.att.chats
  readonly property bool muted: !!root.service && root.service.paused
  // A new version on GitHub (core/Updater.qml): a line in the preview and
  // a row in the menu; a click updates.
  readonly property var updater: root.service ? root.service.updater : null
  readonly property string updatePhase: root.updater ? root.updater.phase : ""
  readonly property string updateLabel: !root.updater ? ""
    : root.updatePhase === "updating" ? root.tr("Updating to ", "Atualizando para a versão ") + root.updater.latest + "…"
    : root.updatePhase === "updated" ? root.tr("Restart the shell to use ", "Reinicie o shell para usar a versão ") + root.updater.latest
    : root.tr("Update to ", "Atualizar para a versão ") + root.updater.latest
  function runUpdate() { if (root.updater) root.updater.update() }

  // ------------------------------------------------------------------- icons
  // Mono (default) is the white WhatsApp mark tinted like the bar's glyphs;
  // Outline is the white mark with a faint dark edge, readable on light and
  // dark bars; Color is the green mark as WhatsApp ships it; Glyph is any
  // Nerd Font character.
  readonly property url outlineIconSource: Qt.resolvedUrl("assets/whatsapp-outline.svg")
  readonly property url colorIconSource: Qt.resolvedUrl("assets/whatsapp.svg")
  readonly property url monoIconSource: Qt.resolvedUrl("assets/whatsapp-white.svg")
  // Tinted: red while a direct chat waits, blue while only groups do.
  readonly property color tintColor: root.directCount > 0 ? root.directColor : root.groupColor
  readonly property color glyphColor: root.anyBadge && root.tintWhenUnread ? root.tintColor : root.foreground
  readonly property int glyphPixelSize: root.glyphSize > 0 ? root.glyphSize : Math.max(8, Style.bar.iconFont)
  // A pause you set fades the mark under the bell-off.
  readonly property real markOpacity: root.muted && root.mutedIndicator === "Bell" ? 0.45 : 1

  // Two counts, two corners. A pause hides both.
  readonly property bool badgesOn: !root.muted && root.badgeStyle !== "None" && root.stateLive
  readonly property int directCount: root.badgesOn ? root.att.direct : 0
  readonly property int groupCount: root.badgesOn ? root.att.groups : 0
  readonly property bool anyBadge: root.directCount > 0 || root.groupCount > 0
  // "Combined" folds both into one badge: red while a direct chat waits, blue
  // when only groups do.
  readonly property int combinedCount: root.directCount + root.groupCount
  readonly property color combinedColor: root.directCount > 0 ? root.directColor : root.groupColor

  // Which corner each badge takes. Change these two to move them.
  readonly property string directCorner: "bottom-right"
  readonly property string groupCorner: "top-right"

  // ----------------------------------------------------------------- actions
  // Left click: open it, bring it back, put it away.
  function toggle() { if (root.service) root.service.toggleWindow() }
  function open() { if (root.service) root.service.showWindow() }
  function quit() { if (root.service) root.service.quit() }

  function openConversation(row) {
    root.popupOpen = false
    if (root.service) root.service.openChat(row.jid, row.msgId || "")
  }

  function pause(minutes) { if (root.service) root.service.pause(minutes) }
  function resume() { if (root.service) root.service.resume() }

  // "Until a date and time…": a day and an hour:minute picked in the menu,
  // `pickerDay` days from today. The pause is the minutes from the moment of
  // the click to that time, rounded up.
  readonly property int pickerMaxDays: 30
  readonly property int pickerMinuteStep: 15
  property bool pickerOpen: false
  property int pickerDay: 0
  property int pickerHour: 0
  property int pickerMinute: 0
  readonly property real pickerTarget: Bar.pickerTarget(root.pickerDay, root.pickerHour, root.pickerMinute, root.nowSec)
  readonly property bool pickerValid: Bar.minutesUntil(root.pickerTarget, root.nowSec) > 0

  function resetPicker() {
    root.nowSec = Date.now() / 1000
    var start = Bar.pickerDefault(root.nowSec)
    root.pickerDay = start.day
    root.pickerHour = start.hour
    root.pickerMinute = start.minute
  }
  function stepPickerDay(delta) { root.pickerDay = Math.max(0, Math.min(root.pickerMaxDays, root.pickerDay + delta)) }
  function stepPickerHour(delta) { root.pickerHour = (root.pickerHour + delta + 24) % 24 }
  function stepPickerMinute(delta) { root.pickerMinute = (root.pickerMinute + delta * root.pickerMinuteStep + 60) % 60 }

  // Measured again at the click: the clock the label follows ticks every 20 s.
  function pauseUntilPicked() {
    var now = Date.now() / 1000
    var minutes = Bar.minutesUntil(Bar.pickerTarget(root.pickerDay, root.pickerHour, root.pickerMinute, now), now)
    if (minutes <= 0) { root.nowSec = now; return }
    root.close()
    root.pause(minutes)
  }

  function writeSetting(key, value) {
    var shell = root.bar ? root.bar.shell : null
    if (!shell || typeof shell.updateEntryInline !== "function") return
    var merged = JSON.parse(JSON.stringify(root.settings || {}))
    merged[key] = value
    shell.updateEntryInline(root.moduleName, merged)
  }

  // One bar surface per monitor means N copies of this widget; only the first
  // may act on the session as a whole (launching at login).
  function isPrimaryInstance() {
    var peers = root.bar && typeof root.bar.moduleWidgets === "function" ? root.bar.moduleWidgets(root.moduleName) : []
    return peers.length === 0 || peers[0] === root
  }

  // Launch on Login: WhatsApp starts once the shell is up, once per shell,
  // its window shown or parked as Launch in Foreground says.
  Timer {
    interval: 2500
    running: root.autoStart
    onTriggered: {
      var s = root.service
      if (!s || s.autoStarted || !root.isPrimaryInstance()) return
      s.autoStarted = true
      if (!s.windowOpen) s.launchWindow(root.launchForeground)
    }
  }

  // ----------------------------------------------------------- hover preview
  property bool popupOpen: false
  property bool menuOpen: false
  function close() {
    root.popupOpen = false
    root.menuOpen = false
  }

  onMenuOpenChanged: {
    if (!menuOpen) return
    root.popupOpen = false
    root.pickerOpen = false
    root.nowSec = Date.now() / 1000
  }

  // Available whenever WhatsApp runs, empty or not, paused or not: "nothing
  // waiting" is an answer worth hovering for.
  readonly property bool previewAvailable: ((root.hoverPreview && root.stateLive) || root.notLinked) && !root.menuOpen
  readonly property bool previewHovered: button.tooltipHovered || popup.containsMouse

  onPreviewAvailableChanged: if (!previewAvailable) root.popupOpen = false
  onPreviewHoveredChanged: {
    if (root.previewHovered && root.previewAvailable) {
      closePreviewTimer.stop()
      if (!root.popupOpen) openPreviewTimer.restart()
    } else {
      openPreviewTimer.stop()
      if (root.popupOpen) closePreviewTimer.restart()
    }
  }
  onPopupOpenChanged: {
    if (!popupOpen) return
    root.nowSec = Date.now() / 1000
    root.askPreviews()
  }
  Timer { id: openPreviewTimer; interval: 350; onTriggered: if (root.previewHovered && root.previewAvailable) root.popupOpen = true }
  Timer { id: closePreviewTimer; interval: 250; onTriggered: if (!root.previewHovered) root.popupOpen = false }

  // The unread chats the card lists, newest first, muted and archived aside.
  readonly property var unreadChats: {
    if (!root.stateLive) return []
    root.wa.chatsRev
    var list = root.wa.chatList.filter(function(c) { return (c.unread > 0 || c.marked) && !c.archived && !root.wa.isMuted(c) })
    list.sort(function(a, b) { return b.ts - a.ts })
    return list
  }
  // Their newest unread messages, asked for while the card is open.
  property var previews: ({})
  property int previewsRev: 0
  Connections {
    target: root.wa
    ignoreUnknownSignals: true
    function onUnreadPreview(chat, msgs) { root.previews[chat] = msgs; root.previewsRev++ }
  }
  onUnreadChatsChanged: if (popupOpen) root.askPreviews()
  function askPreviews() {
    if (!root.stateLive) return
    var list = root.unreadChats.slice(0, root.previewRows)
    for (var i = 0; i < list.length; i++) root.wa.askUnread(list[i].jid, root.previewMessages)
  }

  // The rows the card renders, as whatsapp-tui's widget builds them: the
  // newest unread messages, oldest first, the author only in groups and only
  // where it changes; `hidden` counts the chats past the cap.
  readonly property var preview: {
    root.previewsRev
    var out = { rows: [], hidden: Math.max(0, root.unreadChats.length - root.previewRows) }
    var list = root.unreadChats.slice(0, root.previewRows)
    var you = root.tr("You", "Você")
    for (var i = 0; i < list.length; i++) {
      var c = list[i]
      var group = c.kind === "group"
      var msgs = (root.previews[c.jid] || []).slice(-root.previewMessages)
      if (!msgs.length && c.last) msgs = [c.last]
      var lines = []
      var lastAuthor = ""
      for (var m = 0; m < msgs.length; m++) {
        var msg = msgs[m]
        var s = L.short(msg, root.lang)
        var html = s.icon || msg.kind === "system" ? F.esc(s.text) : F.styled(s.text, msg.mentions, you)
        if (!html.length) continue
        var by = msg.from_me ? you : String(msg.name || msg.who || "").replace(/^~/, "").trim()
        var prefixed = group && by.length > 0 && by !== lastAuthor
        lines.push(prefixed ? "<b>" + F.esc(by) + ":</b> " + html : html)
        lastAuthor = by
      }
      var newest = msgs.length ? msgs[msgs.length - 1] : null
      out.rows.push({
        jid: c.jid,
        kind: group ? "group" : "dm",
        glyph: Bar.kindGlyph(group ? "group" : "dm"),
        name: root.wa.chatName(c),
        count: Math.max(1, c.unread || 0),
        latest: c.ts || 0,
        lines: lines,
        msgId: newest && newest.id ? String(newest.id) : ""
      })
    }
    return out
  }

  // ------------------------------------------------------------------ layout
  visible: root.running || !root.hideWhenNotRunning
  implicitWidth: root.visible ? button.implicitWidth : 0
  implicitHeight: root.visible ? button.implicitHeight : 0

  readonly property string pauseLabel: {
    var until = root.service ? Bar.clockLabel(root.service.pausedUntil, root.nowSec, root.lang) : ""
    return until.length > 0 ? root.tr("Notifications paused until ", "Notificações pausadas até ") + until
                            : root.tr("Notifications paused", "Notificações pausadas")
  }

  readonly property string tooltip: {
    if (!root.running) return root.tr("WhatsApp: click to open", "WhatsApp: clique para abrir")
    if (root.notLinked) return root.tr("WhatsApp: click to link your phone", "WhatsApp: clique para conectar o celular")
    var text = "WhatsApp"
    if (root.attention > 0) text += ": " + root.attention + root.tr(" waiting", " aguardando")
    if (root.muted) text += root.tr(" (notifications paused)", " (notificações pausadas)")
    else if (root.parked) text += root.attention > 0 ? "" : root.tr(", hidden", ", escondido")
    return text
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    iconComponent: root.iconStyle === "Glyph" ? glyphIcon
      : root.iconStyle === "Outline" ? outlineIcon
      : root.iconStyle === "Color" ? colorIcon : monoIcon
    active: root.anyBadge
    useActiveColor: root.tintWhenUnread
    dimmed: root.notLinked || (!root.running && root.dimWhenClosed)
      || (root.muted && root.mutedIndicator === "Dim")
    tooltipText: root.previewAvailable ? "" : root.tooltip
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.MiddleButton) {
        if (root.closeOnMiddle) root.quit()
      } else if (mouseButton === Qt.RightButton) {
        root.menuOpen = !root.menuOpen
      } else {
        root.close()
        root.toggle()
      }
    }
  }

  Component {
    id: glyphIcon

    Item {
      opacity: root.markOpacity

      TextMetrics {
        id: metrics
        font.family: root.fontFamily
        font.pixelSize: root.glyphPixelSize
        text: root.glyph
      }

      Text {
        id: painted
        textFormat: Text.PlainText
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: painted.implicitWidth / 2
          - (metrics.tightBoundingRect.x + Math.max(1, metrics.tightBoundingRect.width) / 2)
        anchors.verticalCenterOffset: root.glyphOffsetY
        text: root.glyph
        color: root.glyphColor
        font.family: root.fontFamily
        font.pixelSize: root.glyphPixelSize
        renderType: Text.NativeRendering

        Behavior on color {
          enabled: !root.bar || root.bar.foregroundAnimationEnabled
          ColorAnimation { duration: 160 }
        }
      }
    }
  }

  Component {
    id: outlineIcon

    Image {
      anchors.fill: parent
      fillMode: Image.PreserveAspectFit
      sourceSize.width: Math.round(width * Screen.devicePixelRatio)
      sourceSize.height: Math.round(height * Screen.devicePixelRatio)
      source: root.outlineIconSource
      opacity: root.markOpacity
      smooth: true
    }
  }

  Component {
    id: colorIcon

    Image {
      anchors.fill: parent
      fillMode: Image.PreserveAspectFit
      // Decode at physical pixels: the logical size leaves it blurry on HiDPI.
      sourceSize.width: Math.round(width * Screen.devicePixelRatio)
      sourceSize.height: Math.round(height * Screen.devicePixelRatio)
      source: root.colorIconSource
      opacity: root.markOpacity
      smooth: true
    }
  }

  Component {
    id: monoIcon

    Item {
      opacity: root.markOpacity

      Image {
        id: monoImage
        anchors.fill: parent
        fillMode: Image.PreserveAspectFit
        sourceSize.width: Math.round(width * Screen.devicePixelRatio)
        sourceSize.height: Math.round(height * Screen.devicePixelRatio)
        source: root.monoIconSource
        smooth: true
        // Hidden layer so the effect can sample it, the way the tray tints
        // symbolic icons.
        visible: false
        layer.enabled: true
      }

      MultiEffect {
        anchors.fill: monoImage
        source: monoImage
        colorization: 1.0
        colorizationColor: root.glyphColor
      }
    }
  }

  // A small count pill on one corner of the icon canvas. A dot fits inside
  // the canvas; a count is nearly as tall as the canvas, so it is centred on
  // the corner instead, out into the slot's padding, like a tray badge.
  component CornerBadge: Rectangle {
    id: cornerBadge

    property int count: 0
    property string corner: "bottom-right"
    readonly property bool dotOnly: root.badgeStyle === "Dot"
    readonly property int sx: corner.indexOf("left") >= 0 ? -1 : 1
    readonly property int sy: corner.indexOf("top") === 0 ? -1 : 1

    visible: count > 0
    z: 2
    height: dotOnly ? Math.round(Style.bar.iconCanvas * root.badgeScale)
                    : Math.round(digits.contentHeight + Style.space(1))
    width: dotOnly ? height : Math.max(height, Math.round(digits.contentWidth + Style.space(5)))
    radius: height / 2

    // Vertically a little past the corner: with a badge on each right-hand
    // corner, that keeps the two off each other and off most of the mark.
    readonly property int reachX: dotOnly ? Math.round((Style.bar.iconCanvas - height) / 2)
                                          : Math.round(Style.bar.iconCanvas / 2)
    readonly property int reachY: dotOnly ? reachX : Math.round(Style.bar.iconCanvas / 2 + 1)
    readonly property int maxX: Math.max(0, Math.round((root.width - width) / 2))
    readonly property int maxY: Math.max(0, Math.round((root.height - height) / 2))

    anchors.horizontalCenter: parent.horizontalCenter
    anchors.horizontalCenterOffset: sx * Math.min(reachX, maxX)
    anchors.verticalCenter: parent.verticalCenter
    anchors.verticalCenterOffset: sy * Math.min(reachY, maxY)

    Text {
      id: digits
      textFormat: Text.PlainText
      // Aligned over the whole badge: centerIn left the digit off to the right.
      anchors.fill: parent
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
      visible: !cornerBadge.dotOnly
      text: Bar.badgeLabel(cornerBadge.count)
      color: root.badgeDigitColor
      font.family: root.fontFamily
      font.pixelSize: Math.max(7, Math.round(Style.font.caption * 0.85))
      font.bold: true
      renderType: Text.NativeRendering
    }
  }

  CornerBadge {
    count: root.combinedBadge ? root.combinedCount : root.directCount
    corner: root.directCorner
    color: root.combinedBadge ? root.combinedColor : root.directColor
  }

  CornerBadge {
    count: root.combinedBadge ? 0 : root.groupCount
    corner: root.groupCorner
    color: root.groupColor
  }

  // Paused: no badge. The mark fades and a bell-off takes the badge's
  // corner, outlined in the background color so it stays its own shape where
  // it overlaps the mark.
  Text {
    id: mutedMark
    textFormat: Text.PlainText
    readonly property int size: Math.max(8, Math.round(Style.bar.iconCanvas * 0.6))
    readonly property int corner: Math.round(Style.bar.iconCanvas / 2 - 1)
    visible: root.muted && root.mutedIndicator === "Bell"
    z: 2
    text: "󰂛"
    color: root.foreground
    style: Text.Outline
    styleColor: root.badgeTextColor
    font.family: root.fontFamily
    font.pixelSize: size
    renderType: Text.NativeRendering
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.horizontalCenterOffset: Math.min(corner, Math.max(0, Math.round((root.width - implicitWidth) / 2)))
    anchors.verticalCenter: parent.verticalCenter
    anchors.verticalCenterOffset: Math.min(corner, Math.max(0, Math.round((root.height - implicitHeight) / 2)))
  }

  // ----------------------------------------------------------- preview card
  PopupCard {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    triggerMode: "hover"
    contentWidth: popup.fittedContentWidth(Style.space(400))
    contentHeight: popup.fittedContentHeight(root.notLinked ? linkColumn.implicitHeight
                                                            : previewColumn.implicitHeight)

    readonly property color fg: root.bar ? root.bar.foreground : Color.foreground
    readonly property color dim: Qt.rgba(popup.fg.r, popup.fg.g, popup.fg.b, 0.6)

    // Not linked yet: what to do.
    Column {
      id: linkColumn
      anchors.fill: parent
      spacing: Style.space(8)
      visible: root.notLinked

      Text {
        textFormat: Text.PlainText
        text: root.tr("WhatsApp is not linked", "WhatsApp não conectado")
        color: popup.fg
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
      }

      Text {
        textFormat: Text.PlainText
        width: parent.width
        text: root.tr("Click the icon and scan the QR code with your phone (WhatsApp → Linked devices).",
                      "Clique no ícone e escaneie o QR code com o celular (WhatsApp → Dispositivos conectados).")
        color: popup.dim
        wrapMode: Text.Wrap
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }

    Column {
      id: previewColumn
      anchors.fill: parent
      spacing: Style.space(6)
      visible: !root.notLinked

      Row {
        width: parent.width
        spacing: Style.space(6)

        Image {
          readonly property int box: Math.round(Style.font.bodySmall * 1.2)
          width: box
          height: box
          anchors.verticalCenter: parent.verticalCenter
          source: root.colorIconSource
          sourceSize.width: Math.round(box * Screen.devicePixelRatio)
          sourceSize.height: Math.round(box * Screen.devicePixelRatio)
          fillMode: Image.PreserveAspectFit
          smooth: true
        }

        Text {
          textFormat: Text.PlainText
          // Not online: reconnecting, the counts are the last known.
          text: (root.attention > 0 ? "WhatsApp · " + root.attention + root.tr(" waiting", " aguardando") : "WhatsApp")
            + (root.wa && !root.wa.online ? root.tr(" · connecting…", " · conectando…") : "")
          color: popup.fg
          elide: Text.ElideRight
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
        }
      }

      // A new version: what it is, and a way in.
      Row {
        visible: root.updatePhase !== ""
        spacing: Style.space(6)

        Text {
          textFormat: Text.PlainText
          text: "󰚰"
          color: popup.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
        Text {
          textFormat: Text.PlainText
          text: root.updatePhase === "updating" ? root.updateLabel
              : root.tr("Version ", "Versão ") + (root.updater ? root.updater.latest : "")
                + (root.updatePhase === "updated" ? root.tr(" installed ·", " instalada ·") : root.tr(" available ·", " disponível ·"))
          color: popup.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
        Text {
          visible: root.updatePhase === "available" || root.updatePhase === "updated"
          textFormat: Text.PlainText
          text: root.updatePhase === "updated" ? root.tr("Restart", "Reiniciar") : root.tr("Update", "Atualizar")
          color: popup.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
          font.underline: updateArea.containsMouse

          MouseArea {
            id: updateArea
            anchors.fill: parent
            anchors.margins: -Style.space(3)
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.runUpdate()
          }
        }
      }

      // Paused: when it ends, and a way out.
      Row {
        visible: root.muted
        spacing: Style.space(6)

        Text {
          textFormat: Text.PlainText
          text: "󰂛"
          color: popup.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
        Text {
          textFormat: Text.PlainText
          text: root.pauseLabel + " ·"
          color: popup.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
        Text {
          textFormat: Text.PlainText
          text: root.tr("Resume", "Reativar")
          color: popup.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
          font.underline: resumeArea.containsMouse

          MouseArea {
            id: resumeArea
            anchors.fill: parent
            anchors.margins: -Style.space(3)
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.resume()
          }
        }
      }

      PanelSeparator {
        foreground: popup.fg
      }

      Text {
        textFormat: Text.PlainText
        visible: root.preview.rows.length === 0
        text: root.att.muted > 0 ? root.tr("Nothing that notifies you", "Nada que te notifique")
                                 : root.tr("No unread messages", "Nenhuma mensagem não lida")
        color: popup.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Repeater {
        model: root.preview.rows

        Rectangle {
          id: chatRow
          required property var modelData

          readonly property bool isGroup: chatRow.modelData.kind === "group"
          readonly property color kindColor: chatRow.isGroup ? root.groupColor : root.directColor
          readonly property int indent: Math.round(Style.font.bodySmall * 1.5)

          width: previewColumn.width
          height: chatInner.implicitHeight + Style.space(12)
          radius: Style.spacing.labelGap
          color: rowArea.containsMouse
            ? Qt.rgba(popup.fg.r, popup.fg.g, popup.fg.b, 0.08) : "transparent"

          Column {
            id: chatInner
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.space(6)
            anchors.rightMargin: Style.space(6)
            spacing: Style.space(3)

            Item {
              width: parent.width
              height: nameText.implicitHeight

              Text {
                id: kindText
                textFormat: Text.PlainText
                width: chatRow.indent
                text: chatRow.modelData.glyph
                color: chatRow.kindColor
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
                anchors.left: parent.left
                anchors.baseline: nameText.baseline
              }

              Text {
                id: nameText
                textFormat: Text.PlainText
                text: chatRow.modelData.name
                color: popup.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
                elide: Text.ElideRight
                anchors.left: kindText.right
                anchors.right: marker.left
                anchors.rightMargin: Style.space(8)
              }

              // Unread count as a pill, in the badge's color for the kind.
              Rectangle {
                id: marker
                // Whole pixels: a fractional box puts the digit off center.
                width: Math.max(height, Math.round(countText.contentWidth + Style.space(8)))
                height: Math.round(countText.contentHeight + Style.space(2))
                radius: height / 2
                color: chatRow.kindColor
                anchors.right: timeText.left
                anchors.rightMargin: timeText.text !== "" ? Style.space(8) : 0
                anchors.verticalCenter: nameText.verticalCenter

                Text {
                  id: countText
                  textFormat: Text.PlainText
                  // Centered by the text's own alignment over the whole pill,
                  // not by centerIn, which rounds the text box's position.
                  anchors.fill: parent
                  horizontalAlignment: Text.AlignHCenter
                  verticalAlignment: Text.AlignVCenter
                  text: Bar.badgeLabel(chatRow.modelData.count)
                  color: root.badgeDigitColor
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
              }

              Text {
                id: timeText
                textFormat: Text.PlainText
                text: Bar.relativeTime(chatRow.modelData.latest, root.nowSec, root.lang)
                color: popup.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                anchors.right: parent.right
                anchors.baseline: nameText.baseline
              }
            }

            // The newest unread messages, oldest first, up to two lines each,
            // with WhatsApp's bold, italic and strikethrough. Escaped:
            // nothing a message says becomes markup of its own.
            Repeater {
              model: chatRow.modelData.lines

              Text {
                required property var modelData
                x: chatRow.indent
                width: chatInner.width - x
                text: modelData
                textFormat: Text.StyledText
                color: Qt.darker(popup.fg, 1.3)
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }
          }

          MouseArea {
            id: rowArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.openConversation(chatRow.modelData)
          }
        }
      }

      Text {
        textFormat: Text.PlainText
        visible: root.preview.hidden > 0
        text: "+" + root.preview.hidden + (root.preview.hidden === 1 ? root.tr(" more chat", " outra conversa")
                                                                     : root.tr(" more chats", " outras conversas"))
        color: popup.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      // Muted chats with unread messages: counted, not listed.
      Text {
        textFormat: Text.PlainText
        visible: root.att.muted > 0
        text: "+" + root.att.muted
          + (root.att.muted === 1 ? root.tr(" muted chat unread", " conversa silenciada não lida")
                                  : root.tr(" muted chats unread", " conversas silenciadas não lidas"))
        color: popup.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  // ------------------------------------------------------------------- menu
  PopupCard {
    id: menu
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.menuOpen
    contentWidth: menu.fittedContentWidth(Style.space(root.lang === "pt-BR" ? 250 : 210))
    contentHeight: menu.fittedContentHeight(menuColumn.implicitHeight)

    readonly property color fg: root.bar ? root.bar.foreground : Color.foreground

    component MenuEntry: Rectangle {
      id: entry

      property string label: ""
      property bool showCheck: false
      property bool checked: false
      property bool clickable: true
      property int indent: 0

      signal activated()

      width: menuColumn.width
      height: entryText.implicitHeight + Style.space(12)
      radius: Style.spacing.labelGap
      color: entry.clickable && entryArea.containsMouse && entry.enabled
        ? Qt.rgba(menu.fg.r, menu.fg.g, menu.fg.b, 0.08) : "transparent"
      opacity: !entry.enabled ? 0.4 : (entry.clickable ? 1 : 0.6)

      Text {
        id: entryText
        textFormat: Text.PlainText
        anchors.left: parent.left
        anchors.leftMargin: Style.space(8) + entry.indent
        anchors.verticalCenter: parent.verticalCenter
        text: entry.label
        color: menu.fg
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Text {
        textFormat: Text.PlainText
        visible: entry.showCheck
        anchors.right: parent.right
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        text: entry.checked ? "✓" : ""
        color: menu.fg
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
      }

      MouseArea {
        id: entryArea
        anchors.fill: parent
        enabled: entry.clickable
        hoverEnabled: true
        cursorShape: entry.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: entry.activated()
      }
    }

    // ‹ value ›, for the pause picker. Clicks on the chevrons or the wheel
    // over it step the value.
    component Stepper: Item {
      id: stepper

      property string label: ""
      property int valueWidth: 0
      property bool canBack: true
      property bool canForward: true

      signal stepped(int delta)

      implicitWidth: backChevron.implicitWidth + stepper.valueWidth + forwardChevron.implicitWidth + Style.space(8)
      implicitHeight: valueText.implicitHeight + Style.space(8)

      WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: function (event) {
          if (event.angleDelta.y > 0 && stepper.canForward) stepper.stepped(1)
          else if (event.angleDelta.y < 0 && stepper.canBack) stepper.stepped(-1)
        }
      }

      Text {
        id: backChevron
        textFormat: Text.PlainText
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: "󰅁"
        color: menu.fg
        opacity: !stepper.canBack ? 0.25 : backArea.containsMouse ? 1 : 0.6
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall

        MouseArea {
          id: backArea
          anchors.fill: parent
          anchors.margins: -Style.space(4)
          hoverEnabled: true
          enabled: stepper.canBack
          cursorShape: Qt.PointingHandCursor
          onClicked: stepper.stepped(-1)
        }
      }

      Text {
        id: valueText
        textFormat: Text.PlainText
        anchors.left: backChevron.right
        anchors.right: forwardChevron.left
        anchors.verticalCenter: parent.verticalCenter
        horizontalAlignment: Text.AlignHCenter
        text: stepper.label
        color: menu.fg
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
      }

      Text {
        id: forwardChevron
        textFormat: Text.PlainText
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: "󰅂"
        color: menu.fg
        opacity: !stepper.canForward ? 0.25 : forwardArea.containsMouse ? 1 : 0.6
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall

        MouseArea {
          id: forwardArea
          anchors.fill: parent
          anchors.margins: -Style.space(4)
          hoverEnabled: true
          enabled: stepper.canForward
          cursorShape: Qt.PointingHandCursor
          onClicked: stepper.stepped(1)
        }
      }
    }

    Column {
      id: menuColumn
      anchors.fill: parent
      spacing: Style.space(2)

      MenuEntry {
        label: !root.running || !root.windowOpen ? root.tr("Open WhatsApp", "Abrir o WhatsApp")
          : root.parked && !root.specialShown ? root.tr("Show WhatsApp", "Mostrar o WhatsApp")
          : (root.focused && root.hideMode === "Special workspace") ? root.tr("Hide WhatsApp", "Esconder o WhatsApp")
          : root.tr("Focus WhatsApp", "Focar o WhatsApp")
        onActivated: {
          root.close()
          root.toggle()
        }
      }

      MenuEntry {
        visible: root.updatePhase !== ""
        enabled: root.updatePhase !== "updating"
        label: root.updateLabel
        onActivated: {
          root.close()
          root.runUpdate()
        }
      }

      PanelSeparator { foreground: menu.fg }

      // Closed before the write: saving shell.json can rebuild the bar's
      // widgets, and a menu owned by a destroyed widget dies mid-click.
      MenuEntry {
        label: root.tr("Launch on Login", "Abrir ao iniciar a sessão")
        showCheck: true
        checked: root.autoStart
        onActivated: {
          root.close()
          root.writeSetting("autoStart", !root.autoStart)
        }
      }

      MenuEntry {
        label: root.tr("Launch in Foreground", "Abrir em primeiro plano")
        showCheck: true
        checked: root.launchForeground
        onActivated: {
          root.close()
          root.writeSetting("launchForeground", !root.launchForeground)
        }
      }

      MenuEntry {
        label: root.tr("Open in Scratchpad", "Abrir no Scratchpad")
        showCheck: true
        checked: root.openInSpecial
        onActivated: {
          root.close()
          root.writeSetting("openInSpecial", !root.openInSpecial)
        }
      }

      MenuEntry {
        label: root.tr("Group notifications", "Agrupar notificações")
        showCheck: true
        checked: root.combinedBadge
        onActivated: {
          root.close()
          root.writeSetting("badgeLayout", root.combinedBadge ? "Split" : "Combined")
        }
      }

      MenuEntry {
        label: root.tr("Desktop notifications", "Notificações na área de trabalho")
        showCheck: true
        checked: root.desktopNotifications
        onActivated: {
          root.close()
          root.writeSetting("notifications", !root.desktopNotifications)
        }
      }

      PanelSeparator { foreground: menu.fg }

      MenuEntry {
        visible: root.muted
        label: root.tr("Resume notifications", "Reativar notificações")
        onActivated: {
          root.close()
          root.resume()
        }
      }

      MenuEntry {
        label: root.tr("Pause notifications", "Pausar notificações")
        clickable: false
      }

      Repeater {
        model: [
          { en: "30 minutes", pt: "30 minutos", minutes: 30 },
          { en: "1 hour", pt: "1 hora", minutes: 60 },
          { en: "2 hours", pt: "2 horas", minutes: 120 },
          { en: "Until tomorrow", pt: "Até amanhã", minutes: -1 },
        ]

        MenuEntry {
          required property var modelData
          label: root.tr(modelData.en, modelData.pt)
          indent: Style.space(10)
          onActivated: {
            root.close()
            root.pause(modelData.minutes > 0 ? modelData.minutes : Bar.minutesToTomorrow(Date.now() / 1000))
          }
        }
      }

      MenuEntry {
        label: root.tr("Until a date and time…", "Até uma data e hora…")
        indent: Style.space(10)
        onActivated: {
          if (!root.pickerOpen) root.resetPicker()
          root.pickerOpen = !root.pickerOpen
        }
      }

      // The picker: a day, an hour and a minute, then the pause itself,
      // labelled with when it would end.
      Column {
        visible: root.pickerOpen
        width: parent.width
        spacing: Style.space(2)

        Stepper {
          x: Style.space(18)
          width: parent.width - x - Style.space(8)
          label: Bar.pickerDayLabel(root.pickerDay, root.nowSec, root.lang)
          canBack: root.pickerDay > 0
          canForward: root.pickerDay < root.pickerMaxDays
          onStepped: function (delta) { root.stepPickerDay(delta) }
        }

        Row {
          x: Style.space(18)
          spacing: Style.space(4)

          Stepper {
            valueWidth: Math.round(Style.font.bodySmall * 2)
            label: Bar.pad(root.pickerHour)
            onStepped: function (delta) { root.stepPickerHour(delta) }
          }
          Text {
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            text: ":"
            color: menu.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: true
          }
          Stepper {
            valueWidth: Math.round(Style.font.bodySmall * 2)
            label: Bar.pad(root.pickerMinute)
            onStepped: function (delta) { root.stepPickerMinute(delta) }
          }
        }

        MenuEntry {
          indent: Style.space(10)
          enabled: root.pickerValid
          label: root.pickerValid ? root.tr("Pause until ", "Pausar até ") + Bar.clockLabel(root.pickerTarget, root.nowSec, root.lang)
                                  : root.tr("Pick a time in the future", "Escolha um horário no futuro")
          onActivated: root.pauseUntilPicked()
        }
      }

      PanelSeparator { foreground: menu.fg }

      MenuEntry {
        label: root.tr("Quit WhatsApp", "Sair do WhatsApp")
        enabled: root.running
        onActivated: {
          root.close()
          root.quit()
        }
      }
    }
  }
}
