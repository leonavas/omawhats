import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../lib/Util.js" as U
import "../lib/Labels.js" as L
import "../lib/Emoji.js" as Emoji
import "../lib/Registry.js" as Reg

// The message box, as WhatsApp Web's: the + (documents, photos and videos,
// audio), the emoji and sticker panel, the text (growing to a few lines,
// with your draft kept per chat), and the microphone, or send once there's
// text. Over it: the message you're answering, or editing. Recording a
// voice note turns it into the recorder.
Item {
  id: box
  property var app: Reg.service
  property var win
  property var view
  property string chat: ""
  readonly property var t: app.theme
  readonly property var wa: app.wa
  readonly property var c: wa.chat(chat)
  readonly property bool group: chat.indexOf("@g.us") > 0
  readonly property bool hasText: input.text.trim().length > 0
  readonly property var replyTo: view ? view.replyTo : null
  readonly property var editing: view ? view.editing : null

  height: pill.height + top.height + t.sp(10) + t.sp(8) + (panel.visible ? panel.height : 0) + (mentions.visible ? mentions.height : 0)

  function focusInput() { input.forceActiveFocus() }
  function startEdit(m) {
    input.text = m.text || ""
    input.cursorPosition = input.length
    input.forceActiveFocus()
  }
  function insert(s) {
    var at = input.cursorPosition
    input.insert(at, s)
    input.cursorPosition = at + s.length
    input.forceActiveFocus()
  }

  // ------------------------------------------------------------ drafts
  property bool _loading: false
  onChatChanged: box.loadDraft()
  Component.onCompleted: box.loadDraft()
  function loadDraft() {
    box._loading = true
    input.text = box.app.draft(box.chat)
    input.cursorPosition = input.length
    box._loading = false
    box.mentionNames = ({})
    box.emojiAt = -1
    box.emojiDismissed = -1
    panel.visible = false
  }
  Timer { id: draftSave; interval: 700; property string chat: ""; property string text: ""; onTriggered: box.app.setDraft(chat, text) }

  // ------------------------------------------------------------ typing
  property real _lastTyping: 0
  Timer { id: pausedSoon; interval: 4000; onTriggered: box.wa.typingState(box.chat, "paused") }
  function typed() {
    if (box._loading || box.editing) return
    draftSave.chat = box.chat
    draftSave.text = input.text
    draftSave.restart()
    if (!input.text) { pausedSoon.stop(); if (box._lastTyping) { box.wa.typingState(box.chat, "paused"); box._lastTyping = 0 } return }
    if (Date.now() - box._lastTyping > 3000) { box._lastTyping = Date.now(); box.wa.typingState(box.chat, "composing") }
    pausedSoon.restart()
  }

  // ------------------------------------------------------------ mentions
  // "@Name" in the box stands for "@number" in what's sent.
  property var mentionNames: ({})
  property string mentionQuery: ""
  property int mentionAt: -1
  readonly property var members: {
    var p = box.wa.profile(box.chat)
    return p && p.members ? p.members.filter(function(x) { return !x.me }) : []
  }
  readonly property var mentionMatches: {
    if (box.mentionAt < 0) return []
    var q = U.fold(box.mentionQuery)
    return box.members.filter(function(x) {
      var n = x.name || x.push || x.phone
      return !q || U.fold(n).indexOf(q) >= 0 || String(x.phone).indexOf(q) >= 0
    }).slice(0, 8)
  }
  function checkMention() {
    if (!box.group) { box.mentionAt = -1; return }
    var upto = input.text.slice(0, input.cursorPosition)
    var m = upto.match(/(^|\s)@([^\s@]{0,30})$/)
    if (m) { box.mentionAt = upto.length - m[2].length - 1; box.mentionQuery = m[2] }
    else box.mentionAt = -1
  }
  function pickMention(x) {
    var name = x.name || (x.push ? x.push : U.phone(x.phone))
    var label = "@" + name
    var start = box.mentionAt
    var end = input.cursorPosition
    input.remove(start, end)
    input.insert(start, label + " ")
    input.cursorPosition = start + label.length + 1
    var map = box.mentionNames
    map[label] = "@" + x.phone
    box.mentionNames = map
    box.mentionAt = -1
  }
  function withMentions(text) {
    var map = box.mentionNames
    var keys = Object.keys(map).sort(function(a, b) { return b.length - a.length })
    for (var i = 0; i < keys.length; i++) text = text.split(keys[i]).join(map[keys[i]])
    return text
  }

  // ------------------------------------------------------------ emoji by name
  // ":cora" (a colon and two letters or more) offers the emoji whose names
  // have them in a strip over the box, as WhatsApp Web's. Once open it goes
  // on over single spaces (":cora verde") while it still finds some.
  property string emojiQuery: ""
  property int emojiAt: -1
  property int emojiDismissed: -1
  property int emojiIndex: 0
  readonly property var emojiMatches: {
    if (box.emojiAt < 0) return []
    return Emoji.search(box.emojiQuery, 40, box.app.lang, panel.recent)
  }
  onEmojiQueryChanged: box.emojiIndex = 0
  onEmojiIndexChanged: stripList.positionViewAtIndex(box.emojiIndex, ListView.Contain)
  function checkEmoji() {
    var tk = Emoji.token(input.text.slice(0, input.cursorPosition), box.emojiAt, box.app.lang)
    var at = tk ? tk.at : -1
    if (tk && tk.end) box.emojiDismissed = at
    else if (at !== box.emojiDismissed) box.emojiDismissed = -1
    if (at < 0 || at === box.emojiDismissed) { box.emojiAt = -1; return }
    box.emojiQuery = tk.query
    box.emojiAt = at
  }
  function pickEmoji(g) {
    var start = box.emojiAt
    var end = input.cursorPosition
    box.emojiAt = -1
    input.remove(start, end)
    input.insert(start, g)
    input.cursorPosition = start + g.length
    panel.remember(g)
    input.forceActiveFocus()
  }

  // ------------------------------------------------------------ send
  function send() {
    var text = input.text.trim()
    if (!text) return
    if (box.editing) {
      box.wa.edit(box.editing, box.withMentions(text))
      box.view.editing = null
    } else {
      box.wa.sendText(box.chat, box.withMentions(text), box.replyTo ? box.replyTo.id : "")
      box.view.replyTo = null
    }
    box._loading = true
    input.text = ""
    box._loading = false
    box.mentionNames = ({})
    draftSave.stop()
    box.app.setDraft(box.chat, "")
    pausedSoon.stop()
    if (box._lastTyping) { box.wa.typingState(box.chat, "paused"); box._lastTyping = 0 }
  }

  // Your last message, to edit with ↑ in an empty box.
  function editLast() {
    var h = box.wa.history(box.chat)
    if (!h) return false
    for (var i = h.msgs.length - 1; i >= 0; i--) {
      var m = h.msgs[i]
      if (!m.from_me) continue
      if (m.kind === "text" && Date.now() / 1000 - m.ts < 15 * 60) { box.view.startEdit(m); return true }
      return false
    }
    return false
  }

  function wrap(mark) {
    var a = input.selectionStart, b = input.selectionEnd
    if (a === b) { input.insert(a, mark + mark); input.cursorPosition = a + mark.length; return }
    var sel = input.selectedText
    input.remove(a, b)
    input.insert(a, mark + sel + mark)
    input.select(a, a + sel.length + mark.length * 2)
  }

  function paste() {
    box.app.readClipboard(function(r) {
      // A picture (a screenshot, say) goes to the preview, its caption and
      // the reply with it, as one attached or dropped does.
      if (r.image || (r.files && r.files.length)) {
        box.win.dialog("sendFiles", { chat: box.chat, files: r.image ? [r.image] : r.files, temp: !!r.image, reply: box.replyTo ? box.replyTo.id : "" })
        if (box.view) box.view.replyTo = null
      } else if (r.text) box.insert(r.text)
    })
  }

  function attach(kind) {
    var tr = box.app.tr
    var filter = kind === "media" ? tr("Photos and videos", "Fotos e vídeos") + " (*.jpg *.jpeg *.png *.webp *.gif *.mp4 *.mov *.m4v *.3gp *.webm *.mkv)"
               : kind === "audio" ? tr("Audio", "Áudio") + " (*.mp3 *.m4a *.ogg *.opus *.aac *.wav *.flac *.amr)" : ""
    box.win.pickFiles(kind === "document" ? tr("Send documents", "Enviar documentos") : kind === "audio" ? tr("Send audio", "Enviar áudio") : tr("Send photos and videos", "Enviar fotos e vídeos"),
                      filter, function(files) {
      box.win.dialog("sendFiles", { chat: box.chat, files: files, asDocument: kind === "document", asAudio: kind === "audio", reply: box.replyTo ? box.replyTo.id : "" })
      if (box.view) box.view.replyTo = null
    })
  }

  // ------------------------------------------------------------ voice notes
  property bool recording: false
  property real recStart: 0
  property real recNow: 0
  property string recPath: ""
  property bool recSend: false
  Process {
    id: recorder
    onExited: (code, status) => {
      var path = box.recPath
      var send = box.recSend
      box.recording = false
      box.wa.typingState(box.chat, "paused")
      if (send && path && (box.recNow - box.recStart) > 700) box.wa.sendFile(box.chat, path, "ptt", "", box.replyTo ? box.replyTo.id : "", true)
      else if (path) Quickshell.execDetached(["rm", "-f", path])
      if (send && box.view) box.view.replyTo = null
    }
  }
  Timer { interval: 200; repeat: true; running: box.recording; onTriggered: box.recNow = Date.now() }
  // "recording audio…" for the other side, every few seconds.
  Timer { interval: 5000; repeat: true; running: box.recording; onTriggered: box.wa.typingState(box.chat, "recording") }
  function startRecording() {
    if (box.recording) return
    box.recPath = box.app.cacheDir + "/voice/" + Date.now() + ".ogg"
    box.recSend = false
    recorder.command = ["sh", "-c", 'mkdir -p "$(dirname "$1")" && exec ffmpeg -hide_banner -loglevel error -nostdin -f pulse -i default -ac 1 -ar 48000 -c:a libopus -b:a 32k -application voip -y "$1"', "rec", box.recPath]
    recorder.running = true
    box.recording = true
    box.recStart = Date.now()
    box.recNow = box.recStart
    box.wa.typingState(box.chat, "recording")
  }
  function stopRecording(send) {
    if (!box.recording) return
    box.recSend = send
    recorder.signal(2)
  }

  // ------------------------------------------------------------ the emoji panel
  EmojiPanel {
    id: panel
    visible: false
    app: box.app
    width: parent.width
    height: Math.min(box.t.sp(380), box.view ? box.view.height * 0.5 : box.t.sp(380))
    y: 0
    chat: box.chat
    onPicked: glyph => box.insert(glyph)
    onSticker: item => { box.wa.sendSticker(box.chat, item, box.replyTo ? box.replyTo.id : ""); if (box.view) box.view.replyTo = null; panel.visible = false }
  }

  // ------------------------------------------------------------ mention list
  Rectangle {
    id: mentions
    visible: box.mentionAt >= 0 && box.mentionMatches.length > 0
    y: panel.visible ? panel.height : 0
    x: box.t.sp(16)
    width: Math.min(parent.width - box.t.sp(32), box.t.sp(420))
    height: visible ? mcol.implicitHeight + box.t.sp(12) : 0
    radius: box.t.sp(12)
    color: box.t.popup
    border.width: 1
    border.color: box.t.line
    Column {
      id: mcol
      y: box.t.sp(6)
      width: parent.width
      Repeater {
        model: box.mentionMatches
        delegate: PersonRow {
          required property var modelData
          app: box.app
          height: box.t.sp(54)
          jid: modelData.jid
          name: modelData.name || ("~" + (modelData.push || U.phone(modelData.phone)))
          sub: modelData.name ? (modelData.push ? "~" + modelData.push : "") : U.phone(modelData.phone)
          onClicked: box.pickMention(modelData)
        }
      }
    }
  }

  // ------------------------------------------------------------ the bar
  Column {
    id: top
    x: box.t.sp(16)
    y: (panel.visible ? panel.height : 0) + (mentions.visible ? mentions.height : 0) + box.t.sp(6)
    width: parent.width - box.t.sp(32)
    spacing: box.t.sp(4)
    // The message being answered, or edited.
    Item {
      visible: !!box.replyTo || !!box.editing
      width: parent.width
      height: visible ? Math.max(quoteBox.height, editBox.height) + box.t.sp(4) : 0
      Quote {
        id: quoteBox
        visible: !!box.replyTo
        app: box.app
        composer: true
        width: parent.width - box.t.sp(48)
        quote: box.replyTo ? { id: box.replyTo.id, from: box.replyTo.sender, name: box.replyTo.from_me ? "" : box.replyTo.name, kind: box.replyTo.kind,
                               text: box.replyTo.text || L.short(box.replyTo, box.app.lang).text, thumb: box.replyTo.media ? box.replyTo.media.thumb || "" : "" } : null
        onClicked: {}
      }
      Rectangle {
        id: editBox
        visible: !!box.editing
        width: parent.width - box.t.sp(48)
        height: visible ? box.t.sp(46) : 0
        radius: box.t.sp(7)
        color: box.t.alpha(box.t.fg, 0.07)
        Rectangle { width: box.t.sp(4); height: parent.height; radius: 2; color: box.t.accent }
        Row {
          x: box.t.sp(14)
          anchors.verticalCenter: parent.verticalCenter
          spacing: box.t.sp(8)
          Icon { name: "edit"; size: box.t.sp(18); color: box.t.accent; anchors.verticalCenter: parent.verticalCenter }
          Text { textFormat: Text.PlainText; text: box.app.tr("Editing message", "Editando mensagem"); color: box.t.accent; font.family: box.t.font; font.pixelSize: box.t.fsText; anchors.verticalCenter: parent.verticalCenter }
        }
      }
      IconButton {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        icon: "close"
        onClicked: {
          if (box.editing) { box.view.editing = null; box.loadDraft() }
          box.view.replyTo = null
        }
      }
    }
  }

  Rectangle {
    id: pill
    x: box.t.sp(12)
    y: top.y + top.height + box.t.sp(2)
    width: parent.width - box.t.sp(24)
    height: Math.max(box.t.sp(52), Math.min(scroller.contentHeight, box.t.sp(160)) + box.t.sp(26))
    radius: box.t.sp(26)
    color: box.t.composer

    // ---------------------------------------------------------- typing
    Row {
      id: leftTools
      visible: !box.recording
      x: box.t.sp(6)
      anchors.bottom: parent.bottom
      anchors.bottomMargin: box.t.sp(6)
      spacing: box.t.sp(2)
      IconButton {
        id: attachBtn
        icon: "add"
        tip: box.app.tr("Attach", "Anexar")
        onClicked: box.win.menuAt(attachBtn, [
          { label: box.app.tr("Document", "Documento"), icon: "documentFilled", action: function() { box.attach("document") } },
          { label: box.app.tr("Photos & videos", "Fotos e vídeos"), icon: "image", action: function() { box.attach("media") } },
          { label: box.app.tr("Audio", "Áudio"), icon: "headphones", action: function() { box.attach("audio") } },
          { label: box.app.tr("Paste from clipboard", "Colar da área de transferência"), icon: "copy", hint: "Ctrl+V", action: function() { box.paste() } }
        ], 0, -box.t.sp(210))
      }
      IconButton {
        icon: panel.visible ? "keyboard" : "smiley"
        tip: box.app.tr("Emoji, stickers", "Emojis, figurinhas")
        active: panel.visible
        onClicked: { panel.visible = !panel.visible; input.forceActiveFocus() }
      }
    }

    Flickable {
      id: scroller
      visible: !box.recording
      anchors.left: leftTools.right
      anchors.leftMargin: box.t.sp(8)
      anchors.right: sendBtn.left
      anchors.rightMargin: box.t.sp(6)
      anchors.verticalCenter: parent.verticalCenter
      height: Math.min(contentHeight, box.t.sp(160))
      contentHeight: input.implicitHeight
      contentWidth: width
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height
      function ensureVisible(r) {
        if (contentY >= r.y) contentY = r.y
        else if (contentY + height <= r.y + r.height) contentY = r.y + r.height - height
      }
      ScrollBar.vertical: ThinScroll { app: box.app }

      TextEdit {
        id: input
        width: scroller.width
        wrapMode: TextEdit.Wrap
        textFormat: TextEdit.PlainText
        color: box.t.text
        font.family: box.t.font
        font.pixelSize: box.t.fsMsg + 1
        selectByMouse: true
        persistentSelection: true
        selectionColor: box.t.alpha(box.t.accent, 0.4)
        selectedTextColor: box.t.textBright
        onCursorRectangleChanged: scroller.ensureVisible(cursorRectangle)
        onTextChanged: { box.typed(); box.checkMention(); box.checkEmoji() }
        onCursorPositionChanged: { box.checkMention(); box.checkEmoji() }

        Text {
          textFormat: Text.PlainText
          visible: input.length === 0 && !input.preeditText
          anchors.fill: parent
          verticalAlignment: Text.AlignVCenter
          text: box.app.tr("Type a message", "Digite uma mensagem")
          color: box.t.faint
          font: input.font
          elide: Text.ElideRight
        }

        Keys.onPressed: event => {
          var ctrl = event.modifiers & Qt.ControlModifier, shift = event.modifiers & Qt.ShiftModifier
          if (strip.visible) {
            var plain = !(event.modifiers & (Qt.ShiftModifier | Qt.ControlModifier | Qt.AltModifier))
            if (plain && event.key === Qt.Key_Left) { box.emojiIndex = Math.max(0, box.emojiIndex - 1); event.accepted = true; return }
            if (plain && event.key === Qt.Key_Right) { box.emojiIndex = Math.min(box.emojiMatches.length - 1, box.emojiIndex + 1); event.accepted = true; return }
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Tab) {
              box.pickEmoji(box.emojiMatches[Math.min(box.emojiIndex, box.emojiMatches.length - 1)])
              event.accepted = true
              return
            }
            if (event.key === Qt.Key_Escape) { box.emojiDismissed = box.emojiAt; box.emojiAt = -1; event.accepted = true; return }
          }
          if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
            if (box.mentionAt >= 0 && box.mentionMatches.length) { box.pickMention(box.mentionMatches[0]); event.accepted = true; return }
            if (box.app.enterSends ? !shift : ctrl) { box.send(); event.accepted = true }
            return
          }
          if (event.key === Qt.Key_Escape) {
            if (box.mentionAt >= 0) { box.mentionAt = -1; event.accepted = true; return }
            if (panel.visible) { panel.visible = false; event.accepted = true; return }
            if (box.editing) { box.view.editing = null; box.loadDraft(); event.accepted = true; return }
            if (box.replyTo) { box.view.replyTo = null; event.accepted = true; return }
            return
          }
          if (event.key === Qt.Key_Up && input.length === 0 && !box.editing) { if (box.editLast()) event.accepted = true; return }
          // Shift+Insert too: the box's own paste would take text only.
          if ((ctrl && event.key === Qt.Key_V) || event.matches(StandardKey.Paste)) { box.paste(); event.accepted = true; return }
          if (ctrl && !shift && event.key === Qt.Key_B) { box.wrap("*"); event.accepted = true; return }
          if (ctrl && !shift && event.key === Qt.Key_I) { box.wrap("_"); event.accepted = true; return }
          if (ctrl && shift && event.key === Qt.Key_X) { box.wrap("~"); event.accepted = true; return }
          if (ctrl && shift && event.key === Qt.Key_M) { box.wrap("```"); event.accepted = true; return }
          if (ctrl && shift && event.key === Qt.Key_C) { box.wrap("`"); event.accepted = true; return }
        }
      }
    }

    // ---------------------------------------------------------- recording
    Row {
      visible: box.recording
      anchors.left: parent.left
      anchors.leftMargin: box.t.sp(10)
      anchors.verticalCenter: parent.verticalCenter
      spacing: box.t.sp(14)
      IconButton {
        icon: "delete"
        tip: box.app.tr("Discard", "Descartar")
        color: box.t.danger
        onClicked: box.stopRecording(false)
      }
      Rectangle {
        width: box.t.sp(10); height: width; radius: width / 2
        color: box.t.danger
        anchors.verticalCenter: parent.verticalCenter
        SequentialAnimation on opacity {
          running: box.recording
          loops: Animation.Infinite
          NumberAnimation { to: 0.2; duration: 600 }
          NumberAnimation { to: 1; duration: 600 }
        }
      }
      Text {
        textFormat: Text.PlainText
        text: U.duration((box.recNow - box.recStart) / 1000)
        color: box.t.text
        font.family: box.t.font
        font.pixelSize: box.t.fsName
        anchors.verticalCenter: parent.verticalCenter
      }
      Text {
        textFormat: Text.PlainText
        text: box.app.tr("Recording…", "Gravando…")
        color: box.t.dim
        font.family: box.t.font
        font.pixelSize: box.t.fsText
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    // ---------------------------------------------------------- send / mic
    Item {
      id: sendBtn
      anchors.right: parent.right
      anchors.rightMargin: box.t.sp(6)
      anchors.bottom: parent.bottom
      anchors.bottomMargin: box.t.sp(6)
      width: box.t.sp(40); height: width
      readonly property bool sendMode: box.hasText || box.recording
      Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: sendBtn.sendMode ? box.t.accent : (sma.containsMouse ? box.t.hoverStrong : "transparent")
        Behavior on color { ColorAnimation { duration: 120 } }
      }
      Icon {
        anchors.centerIn: parent
        name: sendBtn.sendMode ? (box.editing ? "check" : "send") : "micFilled"
        size: box.t.sp(22)
        color: sendBtn.sendMode ? box.t.onBrand : box.t.icon
      }
      MouseArea {
        id: sma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
          if (box.recording) box.stopRecording(true)
          else if (box.hasText) box.send()
          else box.startRecording()
        }
      }
      Tip { text: box.recording ? box.app.tr("Send", "Enviar") : box.hasText ? box.app.tr("Send", "Enviar") : box.app.tr("Voice message", "Mensagem de voz"); shown: sma.containsMouse; placement: "above" }
    }
  }

  // ------------------------------------------------------------ emoji strip
  // Floats over the conversation, above the box, from where the text starts.
  Item {
    id: strip
    z: 10
    visible: box.emojiAt >= 0 && box.mentionAt < 0 && box.emojiMatches.length > 0 && input.activeFocus && !box.recording
    readonly property real cell: box.t.sp(60)
    readonly property real pad: box.t.sp(10)
    x: pill.x + scroller.x
    y: (panel.visible ? 0 : (top.height > 0 ? top.y : pill.y + box.t.sp(4))) - height
    width: Math.min(box.emojiMatches.length * cell + pad * 2, box.width - x - box.t.sp(16))
    height: box.t.sp(80)

    // A soft shadow, then the card.
    Rectangle {
      anchors.fill: parent
      anchors.topMargin: box.t.sp(3)
      anchors.leftMargin: -box.t.sp(1)
      anchors.rightMargin: -box.t.sp(1)
      anchors.bottomMargin: -box.t.sp(5)
      radius: box.t.sp(14)
      color: Qt.rgba(0, 0, 0, box.t.dark ? 0.35 : 0.14)
    }
    Rectangle {
      anchors.fill: parent
      radius: box.t.sp(12)
      color: box.t.popup
      border.width: 1
      border.color: box.t.line
    }

    ListView {
      id: stripList
      x: strip.pad
      y: box.t.sp(8)
      width: parent.width - strip.pad * 2
      height: box.t.sp(56)
      orientation: ListView.Horizontal
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      model: box.emojiMatches
      delegate: Item {
        id: cellItem
        required property var modelData
        required property int index
        readonly property bool on: index === box.emojiIndex
        width: strip.cell
        height: stripList.height
        Rectangle {
          anchors.centerIn: parent
          width: box.t.sp(52); height: width
          radius: box.t.sp(10)
          color: cellItem.on ? box.t.selected : "transparent"
          border.width: cellItem.on ? box.t.sp(2) : 0
          border.color: box.t.accent
        }
        Text {
          textFormat: Text.PlainText
          anchors.centerIn: parent
          text: cellItem.modelData
          font.family: box.t.emojiFont
          font.pixelSize: box.t.sp(32)
        }
        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onEntered: box.emojiIndex = cellItem.index
          onClicked: box.pickEmoji(cellItem.modelData)
        }
      }
    }
    // The thin bar under it when there are more than fit.
    Rectangle {
      visible: stripList.visibleArea.widthRatio < 1
      x: stripList.x + stripList.visibleArea.xPosition * stripList.width
      y: stripList.y + stripList.height + box.t.sp(6)
      width: stripList.visibleArea.widthRatio * stripList.width
      height: box.t.sp(4)
      radius: height / 2
      color: box.t.alpha(box.t.fg, 0.3)
    }
  }
}
