import QtQuick
import QtQuick.Controls
import "../lib/Util.js" as U
import "../lib/Format.js" as F
import "../lib/Labels.js" as L
import "../lib/Registry.js" as Reg

// A message's bubble, as WhatsApp Web draws it: the tail on the first of
// a run, "Forwarded", the sender's name in groups, the message it
// answers, then what it is (photo, video, sticker, voice note, document,
// place, contact, poll…) and its text, with the time, "Edited" and the
// ticks in its bottom corner. Stickers and messages of a few emoji have no
// bubble. On hover a chevron opens its menu.
Item {
  id: b
  property var app: Reg.service
  property var win
  property var view
  property var list
  property var row
  property var m
  property real maxWidth: 400
  property bool hovered: false
  readonly property var t: app.theme
  readonly property var wa: app.wa

  readonly property bool mine: m.from_me
  readonly property string kind: m.kind || "text"
  readonly property var x_: L.parseX(m.x)
  readonly property var media: m.media || null
  readonly property bool sticker: kind === "sticker"
  readonly property bool jumbo: row.jumbo > 0
  readonly property bool bare: sticker || jumbo
  readonly property bool visual: kind === "image" || kind === "video" || kind === "gif" || kind === "ptv" || (kind === "card" && !!media && media.kind !== "document")
  readonly property bool showText: m.text !== undefined && m.text !== "" && kind !== "poll" && kind !== "event" && kind !== "system"
  readonly property bool metaOver: visual && !showText && !m.card
  readonly property bool tail: row.first && !bare
  readonly property bool group: row.group
  readonly property bool showName: group && !mine && row.first && !bare
  readonly property color bg: mine ? t.bubbleOut : t.bubbleIn
  readonly property bool canReact: ["revoked", "placeholder", "system", "unsupported"].indexOf(kind) < 0
  readonly property real padX: visual ? t.sp(3) : t.sp(8)
  readonly property real padTop: visual && !showName && !m.fwd && !m.quote ? t.sp(3) : t.sp(6)
  readonly property real padBottom: visual && metaOver ? t.sp(3) : t.sp(8)

  // The widest of the parts, within what the row allows.
  readonly property real innerMax: maxWidth - padX * 2
  // A part's own width: `natural` where a column or row can't be told
  // its implicit width.
  function nat(it) { return !it ? 0 : (it.natural !== undefined ? it.natural : it.implicitWidth) }
  readonly property real natural: {
    var w = 0
    w = Math.max(w, nat(nameLoader.item))
    w = Math.max(w, nat(fwdLoader.item))
    w = Math.max(w, nat(quoteLoader.item))
    w = Math.max(w, nat(partLoader.item))
    w = Math.max(w, nat(linkLoader.item))
    w = Math.max(w, nat(textLoader.item))
    w = Math.max(w, nat(cardLoader.item))
    if (!textLoader.item || metaOver) w = Math.max(w, meta.implicitWidth + (partLoader.item && !visual ? 0 : 0))
    return w
  }
  readonly property real inner: Math.min(innerMax, Math.max(natural, t.sp(40)))

  width: bare ? Math.max(jumbo ? jumboText.width : (partLoader.item ? partLoader.item.width : 0), metaPill.width) : inner + padX * 2
  height: bare ? (jumbo ? jumboText.height : col.height) + metaPill.height + t.sp(4)
               : col.height + padTop + padBottom + (metaRowNeeded ? meta.height : 0)

  // A part with no text under it (a document, a place) keeps a line of its
  // own for the time; a voice note has it inside; a deleted one beside it.
  readonly property bool inlineMeta: kind === "ptt" || kind === "audio"
  readonly property bool sideMeta: kind === "revoked" || kind === "placeholder"
  readonly property bool metaRowNeeded: !bare && !metaOver && !textLoader.item && !inlineMeta && !sideMeta

  // ------------------------------------------------------------ the bubble
  Rectangle {
    visible: !b.bare
    anchors.fill: parent
    anchors.topMargin: 1
    anchors.bottomMargin: -1
    radius: b.t.bubbleRadius
    topLeftRadius: b.tail && !b.mine ? 0 : b.t.bubbleRadius
    topRightRadius: b.tail && b.mine ? 0 : b.t.bubbleRadius
    color: Qt.rgba(0, 0, 0, b.t.dark ? 0.18 : 0.10)
  }
  Rectangle {
    id: shape
    visible: !b.bare
    anchors.fill: parent
    radius: b.t.bubbleRadius
    topLeftRadius: b.tail && !b.mine ? 0 : b.t.bubbleRadius
    topRightRadius: b.tail && b.mine ? 0 : b.t.bubbleRadius
    color: b.bg
  }
  Image {
    visible: b.tail
    x: b.mine ? parent.width : -width
    y: 0
    width: b.t.sp(8)
    height: b.t.sp(13)
    sourceSize.width: 16
    sourceSize.height: 26
    source: "data:image/svg+xml;utf8," + encodeURIComponent(b.mine
      ? "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 8 13'><path fill='" + b.t.hex(b.bg) + "' d='M5.188 0H0v11.193l6.467-8.625C7.526 1.156 6.958 0 5.188 0z'/></svg>"
      : "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 8 13'><path fill='" + b.t.hex(b.bg) + "' d='M1.533 2.568 8 11.193V0H2.812C1.042 0 .474 1.156 1.533 2.568z'/></svg>")
  }

  // ------------------------------------------------------------ the parts
  Column {
    id: col
    visible: !b.jumbo
    x: b.bare ? 0 : b.padX
    y: b.bare ? 0 : b.padTop
    width: b.bare ? b.width : b.inner
    spacing: b.t.sp(3)

    Loader {
      id: fwdLoader
      active: !!b.m.fwd && !b.bare
      width: parent.width
      sourceComponent: Row {
        spacing: b.t.sp(4)
        leftPadding: b.visual ? b.t.sp(4) : 0
        topPadding: b.visual ? b.t.sp(2) : 0
        Icon { name: "forward"; size: b.t.sp(15); color: b.t.faint; anchors.verticalCenter: parent.verticalCenter }
        Text {
          text: b.m.fwd >= 5 ? b.app.tr("Forwarded many times", "Encaminhada com frequência") : b.app.tr("Forwarded", "Encaminhada")
          color: b.t.faint
          font.family: b.t.font
          font.pixelSize: b.t.fsSmall + 0.5
          font.italic: true
        }
      }
    }

    Loader {
      id: nameLoader
      active: b.showName
      width: parent.width
      sourceComponent: Row {
        spacing: b.t.sp(8)
        leftPadding: b.visual ? b.t.sp(4) : 0
        topPadding: b.visual ? b.t.sp(2) : 0
        readonly property bool unsaved: String(b.m.name || "").indexOf("~") === 0 || String(b.m.name || "") === ""
        Text {
          id: who
          text: parent.unsaved ? U.phone(String(b.m.sender).split("@")[0]) : b.m.name
          color: b.t.nameColor(b.m.sender)
          font.family: b.t.font
          font.pixelSize: b.t.fsSmall + 1
          font.weight: Font.Medium
          textFormat: Text.PlainText
          MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: b.win.showProfile(b.m.sender) }
        }
        Text {
          visible: parent.unsaved && String(b.m.name || "").indexOf("~") === 0
          text: String(b.m.name || "").replace(/^~/, "~ ")
          color: b.t.faint
          font.family: b.t.font
          font.pixelSize: b.t.fsSmall
          anchors.baseline: who.baseline
          textFormat: Text.PlainText
        }
      }
    }

    Loader {
      id: quoteLoader
      active: !!b.m.quote && !b.sticker
      width: parent.width
      sourceComponent: Quote { app: b.app; quote: b.m.quote; chat: b.m.chat; onClicked: if (b.list) b.list.jumpTo(b.m.quote.id) }
    }

    Loader {
      id: partLoader
      active: b.kind !== "text" || b.jumbo
      width: b.bare ? undefined : parent.width
      sourceComponent: {
        switch (b.kind) {
        case "image": case "video": case "gif": case "ptv": return visualC
        case "sticker": return stickerC
        case "ptt": case "audio": return audioC
        case "document": return documentC
        case "location": case "live_location": return locationC
        case "contact": return contactC
        case "poll": return pollC
        case "event": return eventC
        case "call": return callC
        case "invite": return inviteC
        case "revoked": case "placeholder": case "unsupported": case "view_once": return noteC
        case "card": return b.media ? (b.media.kind === "document" ? documentC : visualC) : null
        }
        return null
      }
    }

    Loader {
      id: linkLoader
      active: !!b.x_.link && (b.x_.link.title || b.x_.link.desc) && b.kind === "text"
      width: parent.width
      sourceComponent: LinkCard { app: b.app; link: b.x_.link }
    }

    Loader {
      id: textLoader
      active: b.showText && !b.jumbo
      width: parent.width
      sourceComponent: textC
    }

    Loader {
      id: cardLoader
      active: !!b.m.card
      width: parent.width
      sourceComponent: cardC
    }
  }

  // Messages of one to three emoji: large, no bubble.
  Text {
    id: jumboText
    visible: b.jumbo
    text: b.m.text || ""
    font.family: b.t.emojiFont
    font.pixelSize: b.row.jumbo === 1 ? b.t.sp(50) : b.row.jumbo === 2 ? b.t.sp(42) : b.t.sp(36)
    x: b.mine ? b.width - width : 0
    y: 0
  }

  // ------------------------------------------------------------ the time
  Row {
    id: meta
    visible: !b.bare && !b.metaOver && !b.inlineMeta
    anchors.right: parent.right
    anchors.rightMargin: b.t.sp(7)
    anchors.bottom: parent.bottom
    anchors.bottomMargin: b.t.sp(4)
    spacing: b.t.sp(3)
    height: b.t.sp(15)
    MetaContent { app: b.app; m: b.m; over: false }
  }
  // Over a photo or video without caption: white, on a shade.
  Rectangle {
    visible: b.metaOver
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.margins: b.t.sp(3)
    width: overMeta.implicitWidth + b.t.sp(16)
    height: b.t.sp(28)
    radius: b.t.sp(6)
    gradient: Gradient {
      GradientStop { position: 0.0; color: "transparent" }
      GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.45) }
    }
    Row {
      id: overMeta
      anchors.right: parent.right
      anchors.rightMargin: b.t.sp(6)
      anchors.bottom: parent.bottom
      anchors.bottomMargin: b.t.sp(4)
      spacing: b.t.sp(3)
      MetaContent { app: b.app; m: b.m; over: true }
    }
  }
  // Under a sticker or big emoji: a small pill.
  Rectangle {
    id: metaPill
    visible: b.bare
    anchors.right: b.mine ? parent.right : undefined
    anchors.left: b.mine ? undefined : parent.left
    anchors.bottom: parent.bottom
    width: pillMeta.implicitWidth + b.t.sp(12)
    height: b.t.sp(20)
    radius: height / 2
    color: b.t.system
    Row {
      id: pillMeta
      anchors.centerIn: parent
      spacing: b.t.sp(3)
      MetaContent { app: b.app; m: b.m; over: false }
    }
  }

  // ------------------------------------------------------------ the menu
  Rectangle {
    id: chevron
    visible: b.hovered && !(b.view && b.view.selecting) && b.kind !== "system"
    anchors.top: parent.top
    anchors.right: parent.right
    anchors.topMargin: b.t.sp(2)
    anchors.rightMargin: b.t.sp(2)
    width: b.t.sp(30)
    height: b.t.sp(24)
    radius: b.t.sp(10)
    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop { position: 0.0; color: b.t.alpha(b.bare ? b.t.system : b.bg, 0) }
      GradientStop { position: 0.45; color: b.bare ? b.t.system : b.bg }
    }
    Icon { anchors.right: parent.right; anchors.rightMargin: b.t.sp(2); anchors.verticalCenter: parent.verticalCenter; name: "chevronDown"; size: b.t.sp(22); color: b.visual && b.metaOver ? "white" : b.t.dim }
    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: b.openMenu(chevron, 0, chevron.height) }
  }
  TapHandler {
    acceptedButtons: Qt.RightButton
    enabled: !(b.view && b.view.selecting)
    onTapped: (point) => b.openMenu(b, point.position.x, point.position.y)
  }

  readonly property var quick: ["👍", "❤️", "😂", "😮", "😢", "🙏"]
  function myReaction() {
    var rs = b.m.reactions || []
    for (var i = 0; i < rs.length; i++) if (rs[i].mine) return rs[i].emoji
    return ""
  }
  function react(emoji) { b.wa.react(b.m, b.myReaction() === emoji ? "" : emoji) }
  function openReactions(anchor) {
    b.win.menuAt(anchor, [{ reactions: b.quick, mine: b.myReaction(), action: b.react,
                            more: function() { b.win.dialog("emoji", { onPick: function(e) { b.react(e) } }) } }], 0, -b.t.sp(70))
  }

  function openMenu(anchor, dx, dy) {
    var tr = b.app.tr
    var m = b.m
    var items = []
    if (b.canReact) items.push({ reactions: b.quick, mine: b.myReaction(), action: b.react, more: function() { b.win.dialog("emoji", { onPick: function(e) { b.react(e) } }) } })
    var c = b.wa.chat(m.chat)
    var canSend = !(c && c.ro)
    if (canSend && b.canReact) items.push({ label: tr("Reply", "Responder"), icon: "reply", action: function() { b.view.reply(m) } })
    var plain = F.plain(m.text, m.mentions)
    if (plain) items.push({ label: tr("Copy", "Copiar"), icon: "copy", action: function() { b.app.copy(plain) } })
    if (b.media && b.media.file && (b.kind === "image" || b.kind === "sticker")) items.push({ label: tr("Copy image", "Copiar imagem"), icon: "image", action: function() { b.app.copyImage(b.media.file) } })
    if (b.canReact && b.kind !== "view_once") items.push({ label: tr("Forward", "Encaminhar"), icon: "forward", action: function() { b.win.dialog("forward", { chat: m.chat, msgs: [m] }) } })
    if (b.canReact) items.push(m.star ? { label: tr("Unstar", "Desfavoritar"), icon: "starFilled", action: function() { b.wa.star(m.chat, [m.id], false) } }
                                      : { label: tr("Star", "Favoritar"), icon: "star", action: function() { b.wa.star(m.chat, [m.id], true) } })
    if (b.media && b.kind !== "sticker" && b.kind !== "view_once") items.push({ label: tr("Download", "Baixar"), icon: "download", action: function() { b.save() } })
    if (b.sticker) items.push({ label: tr("Add to favorites", "Adicionar às favoritas"), icon: "heart", action: function() { b.wa.stickerFav(m, "favorite") } })
    var editable = m.from_me && (b.kind === "text" || ((b.kind === "image" || b.kind === "video") && m.text)) && (Date.now() / 1000 - m.ts) < 15 * 60
    if (editable && canSend) items.push({ label: tr("Edit", "Editar"), icon: "edit", action: function() { b.view.startEdit(m) } })
    items.push({ label: tr("Select", "Selecionar"), icon: "select", action: function() { b.view.toggleSelect(m) } })
    items.push({ separator: true })
    items.push({ label: tr("Delete", "Apagar"), icon: "delete", danger: true, action: function() { b.win.dialog("deleteMsgs", { chat: m.chat, msgs: [m] }) } })
    b.win.menuAt(anchor, items, dx, dy)
  }

  // Downloads first when needed, then copies to ~/Downloads.
  function save() {
    var name = b.media.name || ""
    if (b.media.file) { b.app.saveToDownloads(b.media.file, name || U.basename(b.media.file)); return }
    b.wa.whenDownloaded(b.m, function(path) { b.app.saveToDownloads(path, name || U.basename(path)) })
  }

  // ------------------------------------------------------------ components
  Component {
    id: textC
    TextEdit {
      id: te
      readonly property real spacerWidth: (b.metaOver ? 0 : meta.implicitWidth + b.t.sp(10))
      property bool expanded: false
      width: Math.min(implicitWidth, parent ? parent.width : implicitWidth)
      leftPadding: b.visual ? b.t.sp(4) : 0
      rightPadding: b.visual ? b.t.sp(4) : 0
      topPadding: b.visual ? b.t.sp(3) : 0
      textFormat: TextEdit.RichText
      readOnly: true
      selectByMouse: true
      wrapMode: TextEdit.Wrap
      color: b.t.text
      font.family: b.t.font
      font.pixelSize: b.t.fsMsg
      selectionColor: b.t.alpha(b.t.accent, 0.4)
      selectedTextColor: b.t.textBright
      activeFocusOnPress: false
      text: F.render(b.m.text, {
        link: b.t.html.link, mention: b.t.html.mention, code: b.t.html.code, codeBg: b.t.html.codeBg,
        quote: b.t.html.quote, quoteText: b.t.html.quoteText, mentions: b.m.mentions, you: b.app.tr("You", "Você"),
        limit: te.expanded ? 0 : 2000, moreLabel: b.app.tr("Read more", "Ler mais"),
        spacer: te.spacerWidth > 0 ? "&#8203;<img src=\"" + Qt.resolvedUrl("../assets/spacer.png") + "\" width=\"" + Math.round(te.spacerWidth) + "\" height=\"1\">" : ""
      })
      onLinkActivated: url => {
        if (url.indexOf("mention:") === 0) b.win.showProfile(url.slice(8))
        else if (url === "more:") te.expanded = true
        else b.app.openUrl(url)
      }
      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        cursorShape: te.hoveredLink ? Qt.PointingHandCursor : Qt.IBeamCursor
      }
    }
  }

  Component {
    id: visualC
    VisualMedia { app: b.app; win: b.win; m: b.m; maxWidth: b.innerMax; caption: b.showText }
  }

  Component {
    id: stickerC
    Item {
      readonly property real side: b.t.sp(160)
      width: side
      height: side
      implicitWidth: side
      Component.onCompleted: if (b.media && !b.media.file) b.wa.download(b.m, true)
      AnimatedImage {
        anchors.fill: parent
        source: b.media && b.media.file ? U.fileUrl(b.media.file) : ""
        fillMode: Image.PreserveAspectFit
        playing: !!b.media && !!b.media.animated && !!b.app.windowFocused
        asynchronous: true
        smooth: true
        cache: true
      }
      Rectangle {
        anchors.centerIn: parent
        visible: !b.media || !b.media.file
        width: parent.width * 0.6; height: width; radius: b.t.sp(16)
        color: b.t.alpha(b.t.fg, 0.06)
        Icon { anchors.centerIn: parent; name: "sticker"; size: b.t.sp(40); color: b.t.faint }
      }
    }
  }

  Component {
    id: audioC
    VoiceNote { app: b.app; m: b.m; maxWidth: b.innerMax }
  }

  Component {
    id: documentC
    DocumentCard { app: b.app; m: b.m; maxWidth: b.innerMax }
  }

  Component {
    id: locationC
    Column {
      readonly property var loc: b.x_.loc || {}
      readonly property string url: loc.url || ("https://maps.google.com/?q=" + loc.lat + "," + loc.lon)
      property real natural: Math.min(b.innerMax, b.t.sp(270))
      spacing: b.t.sp(4)
      Clip {
        width: parent.width
        height: b.t.sp(150)
        radius: b.t.sp(6)
        color: b.t.alpha(b.t.fg, 0.08)
        Image {
          anchors.fill: parent
          source: b.x_.thumb ? U.fileUrl(b.x_.thumb) : ""
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          smooth: true
        }
        Icon { anchors.centerIn: parent; name: "location"; size: b.t.sp(40); color: b.t.danger }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: b.app.openUrl(parent.parent.url) }
      }
      Text {
        visible: !!parent.loc.name || b.kind === "live_location"
        width: parent.width
        text: b.kind === "live_location" ? b.app.tr("Live location", "Localização em tempo real") : (parent.loc.name || "")
        color: b.t.text
        font.family: b.t.font
        font.pixelSize: b.t.fsMsg
        wrapMode: Text.Wrap
      }
      Text {
        visible: !!parent.loc.addr
        width: parent.width
        text: parent.loc.addr || ""
        color: b.t.dim
        font.family: b.t.font
        font.pixelSize: b.t.fsSmall + 0.5
        wrapMode: Text.Wrap
      }
      Item { width: 1; height: b.t.sp(10) }
    }
  }

  Component {
    id: contactC
    Column {
      readonly property var cs: b.x_.contacts || []
      readonly property var first: cs.length ? cs[0] : { name: "", phones: [] }
      readonly property var waPhone: { var ps = first.phones || []; for (var i = 0; i < ps.length; i++) if (ps[i].wa) return ps[i].wa; return "" }
      property real natural: Math.min(b.innerMax, b.t.sp(280))
      Row {
        spacing: b.t.sp(12)
        topPadding: b.t.sp(6)
        bottomPadding: b.t.sp(10)
        Avatar { size: b.t.sp(46); jid: parent.parent.waPhone ? parent.parent.waPhone + "@s.whatsapp.net" : ""; name: parent.parent.first.name }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: b.t.sp(200)
          text: parent.parent.cs.length > 1 ? b.app.tr(parent.parent.first.name + " and " + (parent.parent.cs.length - 1) + " other contacts", parent.parent.first.name + " e mais " + (parent.parent.cs.length - 1) + " contatos") : parent.parent.first.name
          color: b.t.textBright
          font.family: b.t.font
          font.pixelSize: b.t.fsName - 1
          font.weight: Font.Medium
          wrapMode: Text.Wrap
        }
      }
      Rectangle { width: parent.width; height: 1; color: b.t.line }
      Item {
        width: parent.width
        height: b.t.sp(40)
        Text {
          anchors.centerIn: parent
          text: parent.parent.waPhone ? b.app.tr("Message", "Conversar") : (parent.parent.first.phones.length ? U.phone(parent.parent.first.phones[0].number) : "")
          color: b.t.accent
          font.family: b.t.font
          font.pixelSize: b.t.fsText
          font.weight: Font.Medium
        }
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          enabled: !!parent.parent.waPhone
          onClicked: b.wa.open(parent.parent.waPhone + "@s.whatsapp.net")
        }
      }
    }
  }

  Component {
    id: pollC
    Column {
      readonly property var poll: b.x_.poll || { options: [] }
      property real natural: Math.min(b.innerMax, b.t.sp(320))
      spacing: b.t.sp(6)
      Text { width: parent.width; text: b.m.text; color: b.t.textBright; font.family: b.t.font; font.pixelSize: b.t.fsMsg + 1; font.weight: Font.Medium; wrapMode: Text.Wrap; topPadding: b.t.sp(4) }
      Row {
        spacing: b.t.sp(4)
        Icon { name: parent.parent.poll.multi ? "checklist" : "check"; size: b.t.sp(14); color: b.t.faint; anchors.verticalCenter: parent.verticalCenter }
        Text { text: parent.parent.poll.multi ? b.app.tr("Select one or more", "Selecione uma ou mais opções") : b.app.tr("Select one", "Selecione uma opção"); color: b.t.faint; font.family: b.t.font; font.pixelSize: b.t.fsSmall }
      }
      Repeater {
        model: parent.poll.options
        delegate: Row {
          required property var modelData
          spacing: b.t.sp(10)
          topPadding: b.t.sp(4)
          bottomPadding: b.t.sp(4)
          Rectangle { width: b.t.sp(20); height: width; radius: parent.parent.poll.multi ? b.t.sp(4) : width / 2; color: "transparent"; border.width: 2; border.color: b.t.faint; anchors.verticalCenter: parent.verticalCenter }
          Text { width: b.t.sp(250); text: modelData; color: b.t.text; font.family: b.t.font; font.pixelSize: b.t.fsMsg; wrapMode: Text.Wrap; anchors.verticalCenter: parent.verticalCenter }
        }
      }
      Rectangle { width: parent.width; height: 1; color: b.t.line }
      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: b.app.tr("Vote on your phone", "Vote pelo celular")
        color: b.t.faint
        font.family: b.t.font
        font.pixelSize: b.t.fsSmall + 0.5
        bottomPadding: b.t.sp(14)
      }
    }
  }

  Component {
    id: eventC
    Row {
      readonly property var ev: b.x_.event || {}
      spacing: b.t.sp(12)
      property real natural: Math.min(b.innerMax, b.t.sp(300))
      topPadding: b.t.sp(4)
      bottomPadding: b.t.sp(12)
      Rectangle {
        width: b.t.sp(44); height: width; radius: b.t.sp(8)
        color: b.t.alpha(b.t.accent, 0.2)
        Icon { anchors.centerIn: parent; name: "event"; size: b.t.sp(24); color: b.t.accent }
      }
      Column {
        width: b.t.sp(220)
        spacing: b.t.sp(2)
        Text { width: parent.width; text: parent.parent.ev.name || b.m.text; color: b.t.textBright; font.family: b.t.font; font.pixelSize: b.t.fsMsg; font.weight: Font.Medium; wrapMode: Text.Wrap; font.strikeout: !!parent.parent.ev.canceled }
        Text { width: parent.width; visible: !!parent.parent.ev.start; text: parent.parent.ev.start ? U.longDate(parent.parent.ev.start, b.app.lang) + ", " + U.clock(parent.parent.ev.start, b.app.clock24) : ""; color: b.t.dim; font.family: b.t.font; font.pixelSize: b.t.fsSmall + 0.5 }
        Text { width: parent.width; visible: !!parent.parent.ev.place; text: parent.parent.ev.place || ""; color: b.t.dim; font.family: b.t.font; font.pixelSize: b.t.fsSmall + 0.5; wrapMode: Text.Wrap }
      }
    }
  }

  Component {
    id: callC
    Row {
      readonly property var s: L.short(b.m, b.app.lang)
      spacing: b.t.sp(12)
      topPadding: b.t.sp(2)
      bottomPadding: b.t.sp(10)
      property real natural: b.t.sp(240)
      Rectangle {
        width: b.t.sp(40); height: width; radius: width / 2
        color: b.t.alpha(parent.s.danger ? b.t.danger : b.t.fg, 0.12)
        Icon { anchors.centerIn: parent; name: parent.parent.s.icon; size: b.t.sp(22); color: parent.parent.s.danger ? b.t.danger : b.t.icon }
      }
      Column {
        anchors.verticalCenter: parent.verticalCenter
        Text { text: parent.parent.s.text; color: b.t.text; font.family: b.t.font; font.pixelSize: b.t.fsMsg }
        Text {
          readonly property var c: b.x_.call || {}
          visible: !!c.secs
          text: U.duration(c.secs || 0)
          color: b.t.dim; font.family: b.t.font; font.pixelSize: b.t.fsSmall
        }
      }
    }
  }

  Component {
    id: inviteC
    Row {
      readonly property var inv: b.x_.invite || {}
      spacing: b.t.sp(12)
      property real natural: Math.min(b.innerMax, b.t.sp(300))
      topPadding: b.t.sp(4)
      bottomPadding: b.t.sp(6)
      Avatar { size: b.t.sp(48); group: true; jid: parent.inv.jid || ""; name: parent.inv.group || ""; source: b.x_.thumb ? U.fileUrl(b.x_.thumb) : "" }
      Column {
        anchors.verticalCenter: parent.verticalCenter
        width: b.t.sp(220)
        Text { width: parent.width; text: parent.parent.inv.group || ""; color: b.t.textBright; font.family: b.t.font; font.pixelSize: b.t.fsMsg; font.weight: Font.Medium; elide: Text.ElideRight }
        Text { width: parent.width; text: b.app.tr("WhatsApp group invite", "Convite para grupo do WhatsApp"); color: b.t.dim; font.family: b.t.font; font.pixelSize: b.t.fsSmall + 0.5 }
      }
    }
  }

  Component {
    id: noteC
    Row {
      readonly property var s: L.short(b.m, b.app.lang)
      spacing: b.t.sp(6)
      property real natural: noteText.implicitWidth + b.t.sp(24) + b.t.sp(6) + (b.sideMeta ? meta.implicitWidth + b.t.sp(12) : 0)
      bottomPadding: b.kind === "revoked" ? 0 : b.t.sp(2)
      Icon { name: b.kind === "view_once" ? "camera" : (parent.s.icon || "info"); size: b.t.sp(18); color: b.t.faint; anchors.verticalCenter: noteText.verticalCenter }
      Text {
        id: noteText
        width: Math.min(implicitWidth, b.innerMax - b.t.sp(30) - (b.sideMeta ? meta.implicitWidth + b.t.sp(12) : 0))
        text: parent.s.text + (b.kind === "placeholder" ? b.app.tr(". This may take a while.", ". Isso pode levar alguns instantes.") : b.kind === "view_once" ? b.app.tr(" · open it on your phone", " · abra no seu celular") : b.kind === "unsupported" ? b.app.tr(" · see it on your phone", " · veja no seu celular") : "")
        color: b.t.dim
        font.family: b.t.font
        font.pixelSize: b.t.fsMsg
        font.italic: true
        wrapMode: Text.Wrap
      }
    }
  }

  Component {
    id: cardC
    Column {
      readonly property var card: b.m.card || {}
      property real natural: Math.min(b.innerMax, Math.max(titleText.implicitWidth, b.t.sp(220)))
      spacing: b.t.sp(4)
      Text {
        id: titleText
        visible: !!parent.card.title
        width: parent.width
        text: parent.card.title || ""
        color: b.t.textBright
        font.family: b.t.font
        font.pixelSize: b.t.fsMsg
        font.weight: Font.DemiBold
        wrapMode: Text.Wrap
      }
      Text {
        visible: !!parent.card.footer
        width: parent.width
        text: parent.card.footer || ""
        color: b.t.faint
        font.family: b.t.font
        font.pixelSize: b.t.fsSmall
        wrapMode: Text.Wrap
        bottomPadding: b.t.sp(14)
      }
      Repeater {
        model: parent.card.buttons || []
        delegate: Column {
          required property var modelData
          width: parent.width
          Rectangle { width: parent.width; height: 1; color: b.t.line }
          Item {
            width: parent.width
            height: b.t.sp(40)
            Row {
              anchors.centerIn: parent
              spacing: b.t.sp(6)
              Icon {
                name: modelData.kind === "url" ? "openNew" : modelData.kind === "call" ? "call" : modelData.kind === "copy" ? "copy" : modelData.kind === "list" ? "listBullet" : "reply"
                size: b.t.sp(18); color: b.t.accent; anchors.verticalCenter: parent.verticalCenter
              }
              Text { text: modelData.text; color: b.t.accent; font.family: b.t.font; font.pixelSize: b.t.fsText; font.weight: Font.Medium; anchors.verticalCenter: parent.verticalCenter }
            }
            MouseArea { anchors.fill: parent; enabled: !!modelData.url; cursorShape: Qt.PointingHandCursor; onClicked: b.app.openUrl(modelData.url) }
          }
        }
      }
    }
  }
}
