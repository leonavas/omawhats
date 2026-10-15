import QtQuick
import QtQuick.Effects
import QtQuick.Window
import Quickshell
import qs.Commons
import qs.Ui
import "lib/Registry.js" as Registry
import "lib/Util.js" as U
import "lib/Labels.js" as L
import "lib/Format.js" as F

// The bar's door into WhatsApp: the mark (white and tinted like the bar's
// glyphs, the green one, or a Nerd Font glyph), a red badge for unread
// direct chats and a blue one for groups (muted chats count in neither), a
// preview of what's unread on hover, and a menu on right click. The app is
// the plugin's service (Service.qml).
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
  readonly property bool dimWhenUnlinked: setting("dimWhenClosed", true) !== false
  readonly property bool closeOnMiddle: setting("middleClickCloses", true) !== false
  readonly property bool hoverPreview: setting("hoverPreview", true) !== false
  readonly property int previewRows: Math.max(1, Number(setting("previewRows", 6)))
  readonly property int previewMessages: Math.max(1, Math.min(5, Number(setting("previewMessages", 3))))
  readonly property string mutedIndicator: String(setting("mutedIndicator", "Bell"))

  // ------------------------------------------------------------------- theme
  readonly property color foreground: bar ? bar.barForeground : Color.foreground
  readonly property color urgentColor: bar ? bar.urgent : Color.urgent
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

  // ------------------------------------------------------------------ window
  readonly property bool running: !!root.service && root.service.windowOpen
  readonly property bool focused: !!root.service && root.service.windowFocused
  readonly property bool parked: !!root.service && root.service.parked
  readonly property bool specialShown: !!root.service && root.service.specialShown
  readonly property var windowOptions: ({ specialName: root.specialName, openInSpecial: root.openInSpecial,
                                          hideMode: root.hideMode, launchForeground: root.launchForeground })
  onWindowOptionsChanged: root.pushOptions()
  onServiceChanged: root.pushOptions()
  function pushOptions() { if (root.service) root.service.barOptions = root.windowOptions }

  readonly property bool linked: !!root.wa && root.wa.linked
  readonly property bool paused: !!root.service && root.service.paused

  // ------------------------------------------------------------------- counts
  readonly property var att: root.service ? root.service.attention : ({ chats: 0, direct: 0, groups: 0, messages: 0, muted: 0, archived: 0 })
  readonly property bool badgesOn: !root.paused && root.badgeStyle !== "None" && root.linked
  readonly property int directCount: root.badgesOn ? root.att.direct : 0
  readonly property int groupCount: root.badgesOn ? root.att.groups : 0
  readonly property bool anyBadge: root.directCount > 0 || root.groupCount > 0
  readonly property int combinedCount: root.directCount + root.groupCount

  function badgeLabel(n) { return n > 99 ? "99+" : String(n) }

  // ----------------------------------------------------------------- actions
  function toggle() { if (root.service) root.service.toggleWindow() }
  function close() { root.popupOpen = false; root.menuOpen = false }

  function writeSetting(key, value) {
    var shell = root.bar ? root.bar.shell : null
    if (!shell || typeof shell.updateEntryInline !== "function") return
    var merged = JSON.parse(JSON.stringify(root.settings || {}))
    merged[key] = value
    shell.updateEntryInline(root.moduleName, merged)
  }

  function isPrimaryInstance() {
    var peers = root.bar && typeof root.bar.moduleWidgets === "function" ? root.bar.moduleWidgets(root.moduleName) : []
    return peers.length === 0 || peers[0] === root
  }

  // Launch on Login: the window opens once the shell is up, once per shell.
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
  onMenuOpenChanged: if (menuOpen) root.popupOpen = false

  readonly property bool previewAvailable: root.hoverPreview && !!root.wa && !root.menuOpen
  readonly property bool previewHovered: button.tooltipHovered || popup.containsMouse
  onPreviewAvailableChanged: if (!previewAvailable) root.popupOpen = false
  onPreviewHoveredChanged: {
    if (root.previewHovered && root.previewAvailable) { closePreviewTimer.stop(); if (!root.popupOpen) openPreviewTimer.restart() }
    else { openPreviewTimer.stop(); if (root.popupOpen) closePreviewTimer.restart() }
  }
  Timer { id: openPreviewTimer; interval: 350; onTriggered: if (root.previewHovered && root.previewAvailable) root.popupOpen = true }
  Timer { id: closePreviewTimer; interval: 250; onTriggered: if (!root.previewHovered) root.popupOpen = false }

  // The unread chats the card lists, newest first, muted and archived aside.
  readonly property var unreadChats: {
    if (!root.wa) return []
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
  onPopupOpenChanged: if (popupOpen) root.askPreviews()
  onUnreadChatsChanged: if (popupOpen) root.askPreviews()
  function askPreviews() {
    var list = root.unreadChats.slice(0, root.previewRows)
    for (var i = 0; i < list.length; i++) root.wa.askUnread(list[i].jid, root.previewMessages)
  }

  // ------------------------------------------------------------------ layout
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  readonly property string tooltip: {
    if (!root.service) return "WhatsApp"
    if (!root.linked) return root.tr("WhatsApp: click to link your phone", "WhatsApp: clique para conectar o celular")
    var text = "WhatsApp"
    if (root.att.chats > 0) text += ": " + root.att.chats + root.tr(" unread", " não lidas")
    if (root.paused) text += root.tr(" (notifications paused)", " (notificações pausadas)")
    return text
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    iconComponent: root.iconStyle === "Glyph" ? glyphIcon : root.iconStyle === "Color" ? colorIcon : monoIcon
    active: root.anyBadge
    useActiveColor: root.tintWhenUnread
    dimmed: (!root.linked && root.dimWhenUnlinked) || (root.paused && root.mutedIndicator === "Dim")
    tooltipText: root.previewAvailable ? "" : root.tooltip
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.MiddleButton) { if (root.closeOnMiddle && root.service) root.service.hideWindow() }
      else if (mouseButton === Qt.RightButton) root.menuOpen = !root.menuOpen
      else { root.menuOpen = false; root.popupOpen = false; root.toggle() }
    }
  }

  // ------------------------------------------------------------------- icons
  readonly property url monoIconSource: Qt.resolvedUrl("assets/whatsapp-white.svg")
  readonly property url colorIconSource: Qt.resolvedUrl("assets/whatsapp.svg")
  readonly property color tintColor: root.directCount > 0 || root.combinedBadge ? root.directColor : root.groupColor
  readonly property color glyphColor: root.anyBadge && root.tintWhenUnread ? root.tintColor : root.foreground
  readonly property int glyphPixelSize: root.glyphSize > 0 ? root.glyphSize : Math.max(8, Style.bar.iconFont)
  readonly property real markOpacity: root.paused && root.mutedIndicator === "Bell" ? 0.45 : 1

  Component {
    id: glyphIcon
    Item {
      opacity: root.markOpacity
      Text {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: root.glyphOffsetY
        textFormat: Text.PlainText
        text: root.glyph
        color: root.glyphColor
        font.family: root.fontFamily
        font.pixelSize: root.glyphPixelSize
        renderType: Text.NativeRendering
      }
    }
  }
  Component {
    id: colorIcon
    Image {
      anchors.fill: parent
      anchors.margins: parent ? Math.round(parent.width * 0.04) : 0
      fillMode: Image.PreserveAspectFit
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
        anchors.margins: Math.round(parent.width * 0.04)
        fillMode: Image.PreserveAspectFit
        sourceSize.width: Math.round(width * Screen.devicePixelRatio)
        sourceSize.height: Math.round(height * Screen.devicePixelRatio)
        source: root.monoIconSource
        smooth: true
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

  // A count pill on a corner of the icon.
  component CornerBadge: Rectangle {
    id: cb
    property int count: 0
    property string corner: "bottom-right"
    readonly property bool dotOnly: root.badgeStyle === "Dot"
    readonly property int sx: corner.indexOf("left") >= 0 ? -1 : 1
    readonly property int sy: corner.indexOf("top") === 0 ? -1 : 1
    visible: count > 0
    z: 2
    height: dotOnly ? Math.round(Style.bar.iconCanvas * root.badgeScale) : Math.round(digits.implicitHeight + Style.space(1))
    width: dotOnly ? height : Math.max(height, Math.round(digits.implicitWidth + Style.space(5)))
    radius: height / 2
    readonly property int reachX: dotOnly ? Math.round((Style.bar.iconCanvas - height) / 2) : Math.round(Style.bar.iconCanvas / 2)
    readonly property int reachY: dotOnly ? reachX : Math.round(Style.bar.iconCanvas / 2 + 1)
    readonly property int maxX: Math.max(0, Math.round((root.width - width) / 2))
    readonly property int maxY: Math.max(0, Math.round((root.height - height) / 2))
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.horizontalCenterOffset: sx * Math.min(reachX, maxX)
    anchors.verticalCenter: parent.verticalCenter
    anchors.verticalCenterOffset: sy * Math.min(reachY, maxY)
    Text {
      id: digits
      anchors.centerIn: parent
      visible: !cb.dotOnly
      textFormat: Text.PlainText
      text: root.badgeLabel(cb.count)
      color: root.badgeDigitColor
      font.family: root.fontFamily
      font.pixelSize: Math.max(7, Math.round(Style.font.caption * 0.85))
      font.bold: true
      renderType: Text.NativeRendering
    }
  }
  CornerBadge {
    count: root.combinedBadge ? root.combinedCount : root.directCount
    corner: "bottom-right"
    color: root.combinedBadge && root.directCount === 0 ? root.groupColor : root.directColor
  }
  CornerBadge {
    count: root.combinedBadge ? 0 : root.groupCount
    corner: "top-right"
    color: root.groupColor
  }
  // Paused: the mark fades under a bell-off.
  Text {
    readonly property int size: Math.max(8, Math.round(Style.bar.iconCanvas * 0.6))
    readonly property int corner: Math.round(Style.bar.iconCanvas / 2 - 1)
    visible: root.paused && root.mutedIndicator === "Bell"
    z: 2
    textFormat: Text.PlainText
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
    contentWidth: popup.fittedContentWidth(Style.space(380))
    contentHeight: popup.fittedContentHeight(previewColumn.implicitHeight)
    readonly property color fg: root.bar ? root.bar.foreground : Color.foreground
    readonly property color dim: Qt.rgba(popup.fg.r, popup.fg.g, popup.fg.b, 0.6)

    Column {
      id: previewColumn
      anchors.fill: parent
      spacing: Style.space(6)
      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: !root.linked ? root.tr("WhatsApp · not linked", "WhatsApp · não conectado")
            : root.att.chats > 0 ? "WhatsApp · " + root.att.chats + root.tr(" unread", " não lidas") : "WhatsApp"
        color: popup.fg
        elide: Text.ElideRight
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
      }
      Row {
        visible: root.paused
        spacing: Style.space(6)
        Text { textFormat: Text.PlainText; text: "󰂛 " + root.tr("Notifications paused until ", "Notificações pausadas até ") + (root.service ? U.clock(root.service.pausedUntil, root.service.clock24) : "") + " ·"; color: popup.dim; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall }
        Text {
          textFormat: Text.PlainText
          text: root.tr("Resume", "Reativar")
          color: popup.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
          font.underline: resumeArea.containsMouse
          MouseArea { id: resumeArea; anchors.fill: parent; anchors.margins: -Style.space(3); hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.service.resume() }
        }
      }
      PanelSeparator { foreground: popup.fg }
      Text {
        textFormat: Text.PlainText
        visible: root.unreadChats.length === 0
        text: !root.linked ? root.tr("Click the icon to link your phone.", "Clique no ícone para conectar o celular.") : root.tr("No unread messages", "Nenhuma mensagem não lida")
        color: popup.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
      Repeater {
        model: root.unreadChats.slice(0, root.previewRows)
        Rectangle {
          id: convRow
          required property var modelData
          readonly property bool isGroup: modelData.kind === "group"
          readonly property var msgs: { root.previewsRev; return (root.previews[modelData.jid] || []).slice(-root.previewMessages) }
          width: previewColumn.width
          height: inner.implicitHeight + Style.space(12)
          radius: Style.spacing.labelGap
          color: rowArea.containsMouse ? Qt.rgba(popup.fg.r, popup.fg.g, popup.fg.b, 0.08) : "transparent"
          Column {
            id: inner
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.space(6)
            anchors.rightMargin: Style.space(6)
            spacing: Style.space(3)
            Item {
              width: parent.width
              height: nameText.implicitHeight
              Rectangle {
                id: dot
                width: Math.round(Style.font.bodySmall * 0.5); height: width; radius: width / 2
                color: convRow.isGroup ? root.groupColor : root.directColor
                anchors.verticalCenter: nameText.verticalCenter
              }
              Text {
                id: nameText
                anchors.left: dot.right
                anchors.leftMargin: Style.space(6)
                anchors.right: countText.left
                anchors.rightMargin: Style.space(8)
                textFormat: Text.PlainText
                text: root.wa ? root.wa.chatName(convRow.modelData) : ""
                color: popup.fg
                elide: Text.ElideRight
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
              }
              Text {
                id: countText
                anchors.right: timeText.left
                anchors.rightMargin: Style.space(8)
                anchors.baseline: nameText.baseline
                textFormat: Text.PlainText
                text: convRow.modelData.unread > 0 ? String(convRow.modelData.unread) : ""
                color: convRow.isGroup ? root.groupColor : root.directColor
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
              Text {
                id: timeText
                anchors.right: parent.right
                anchors.baseline: nameText.baseline
                textFormat: Text.PlainText
                text: U.ago(convRow.modelData.ts, root.lang)
                color: popup.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
            Repeater {
              // The newest unread messages, or the chat's last one until they come.
              model: convRow.msgs.length ? convRow.msgs : (convRow.modelData.last ? [convRow.modelData.last] : [])
              Text {
                required property var modelData
                x: Style.space(6) + Math.round(Style.font.bodySmall * 0.5)
                width: inner.width - x
                textFormat: Text.StyledText
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                color: Qt.darker(popup.fg, 1.25)
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                text: {
                  var m = modelData
                  var s = L.short(m, root.lang)
                  var who = convRow.isGroup && (m.name || m.who) && !m.from_me ? F.esc(String(m.name || m.who).replace(/^~/, "")) + ": " : ""
                  return who + (s.icon || m.kind === "system" ? F.esc(s.text) : F.styled(s.text, m.mentions))
                }
              }
            }
          }
          MouseArea {
            id: rowArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { root.popupOpen = false; root.service.openChat(convRow.modelData.jid, "") }
          }
        }
      }
      Text {
        textFormat: Text.PlainText
        visible: root.unreadChats.length > root.previewRows
        text: "+" + (root.unreadChats.length - root.previewRows) + root.tr(" more", " mais")
        color: popup.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
      Text {
        textFormat: Text.PlainText
        visible: root.att.muted > 0 || root.att.archived > 0
        text: [root.att.muted > 0 ? (root.att.muted === 1 ? root.tr("1 muted chat unread", "1 conversa silenciada não lida") : root.tr(root.att.muted + " muted chats unread", root.att.muted + " conversas silenciadas não lidas")) : "",
               root.att.archived > 0 ? (root.att.archived === 1 ? root.tr("1 archived", "1 arquivada") : root.tr(root.att.archived + " archived", root.att.archived + " arquivadas")) : ""].filter(function(s) { return s }).join(" · ")
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
    contentWidth: menu.fittedContentWidth(Style.space(230))
    contentHeight: menu.fittedContentHeight(menuColumn.implicitHeight)
    readonly property color fg: root.bar ? root.bar.foreground : Color.foreground

    component MenuEntry: Rectangle {
      id: entry
      property string label: ""
      property bool showCheck: false
      property bool checked: false
      property int indent: 0
      signal activated()
      width: menuColumn.width
      height: entryText.implicitHeight + Style.space(12)
      radius: Style.spacing.labelGap
      color: entryArea.containsMouse ? Qt.rgba(menu.fg.r, menu.fg.g, menu.fg.b, 0.08) : "transparent"
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
      MouseArea { id: entryArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: entry.activated() }
    }

    Column {
      id: menuColumn
      anchors.fill: parent
      spacing: Style.space(2)

      MenuEntry {
        label: !root.running ? root.tr("Open WhatsApp", "Abrir o WhatsApp")
             : root.parked && !root.specialShown ? root.tr("Show WhatsApp", "Mostrar o WhatsApp")
             : (root.focused && root.hideMode === "Special workspace") ? root.tr("Hide WhatsApp", "Esconder o WhatsApp")
             : root.tr("Focus WhatsApp", "Focar o WhatsApp")
        onActivated: { root.close(); root.toggle() }
      }
      PanelSeparator { foreground: menu.fg }
      MenuEntry {
        label: root.tr("Launch on Login", "Abrir ao iniciar a sessão")
        showCheck: true
        checked: root.autoStart
        onActivated: { root.close(); root.writeSetting("autoStart", !root.autoStart) }
      }
      MenuEntry {
        label: root.tr("Launch in Foreground", "Abrir em primeiro plano")
        showCheck: true
        checked: root.launchForeground
        onActivated: { root.close(); root.writeSetting("launchForeground", !root.launchForeground) }
      }
      MenuEntry {
        label: root.tr("Open in Scratchpad", "Abrir no Scratchpad")
        showCheck: true
        checked: root.openInSpecial
        onActivated: { root.close(); root.writeSetting("openInSpecial", !root.openInSpecial) }
      }
      MenuEntry {
        label: root.tr("Group notifications", "Agrupar notificações")
        showCheck: true
        checked: root.combinedBadge
        onActivated: { root.close(); root.writeSetting("badgeLayout", root.combinedBadge ? "Split" : "Combined") }
      }
      MenuEntry {
        label: root.tr("Desktop notifications", "Notificações na área de trabalho")
        showCheck: true
        checked: !!root.service && root.service.notificationsOn
        onActivated: { root.close(); if (root.service) root.service.setSetting("notifications", !root.service.notificationsOn) }
      }
      PanelSeparator { foreground: menu.fg }
      MenuEntry {
        visible: root.paused
        label: root.tr("Resume notifications", "Reativar notificações")
        onActivated: { root.close(); root.service.resume() }
      }
      Column {
        width: parent.width
        visible: !root.paused
        spacing: Style.space(2)
        Text {
          leftPadding: Style.space(8)
          topPadding: Style.space(4)
          textFormat: Text.PlainText
          text: root.tr("Pause notifications", "Pausar notificações")
          color: Qt.rgba(menu.fg.r, menu.fg.g, menu.fg.b, 0.6)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
        MenuEntry { indent: Style.space(8); label: root.tr("For 30 minutes", "Por 30 minutos"); onActivated: { root.close(); root.service.pause(30) } }
        MenuEntry { indent: Style.space(8); label: root.tr("For 1 hour", "Por 1 hora"); onActivated: { root.close(); root.service.pause(60) } }
        MenuEntry { indent: Style.space(8); label: root.tr("For 8 hours", "Por 8 horas"); onActivated: { root.close(); root.service.pause(480) } }
        MenuEntry {
          indent: Style.space(8)
          label: root.tr("Until tomorrow", "Até amanhã")
          onActivated: {
            root.close()
            var d = new Date(); d.setDate(d.getDate() + 1); d.setHours(9, 0, 0, 0)
            root.service.pause(Math.max(1, (d.getTime() - Date.now()) / 60000))
          }
        }
      }
      PanelSeparator { foreground: menu.fg }
      MenuEntry {
        label: root.tr("Quit (close the window)", "Fechar a janela")
        onActivated: { root.close(); if (root.service) root.service.hideWindow() }
      }
    }
  }
}
