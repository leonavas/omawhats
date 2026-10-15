import QtQuick
import QtQuick.Controls
import Quickshell
import "../lib/Util.js" as U
import "../lib/Labels.js" as L
import "../lib/Format.js" as F
import "../lib/Registry.js" as Reg

// The dialogs, over a dimmed window, as WhatsApp Web's: confirmations
// (log out, clear or delete a chat, delete messages), forwarding, the
// preview of files before they're sent, who reacted, the emoji picker for
// a reaction, the keyboard shortcuts, and from your menu (AccountMenu.qml)
// your profile and About, as whatsapp-tui's.
Item {
  id: host
  property var app: Reg.service
  property var win
  readonly property var t: app.theme
  readonly property var wa: app.wa
  property string name: ""
  property var args: ({})
  readonly property bool shown: name !== ""
  visible: shown
  z: 800

  // Closing (Close, a click outside, or opening something else from it)
  // keeps what's being typed in the profile's name or about, as a click
  // elsewhere in the card does; Esc in the field drops it.
  signal commitEdits()
  // The focus before the dialog: one with a field (the caption) takes it.
  function show(n, a) { host.args = a || {}; host.forceActiveFocus(); host.name = n }
  function hide() { host.commitEdits(); host.name = ""; host.args = ({}) }

  Keys.onEscapePressed: host.hide()

  Rectangle {
    anchors.fill: parent
    color: host.t.scrim
    MouseArea { anchors.fill: parent; onClicked: host.hide() }
  }

  Loader {
    id: body
    anchors.centerIn: parent
    active: host.shown
    sourceComponent: {
      switch (host.name) {
      case "logout": case "clearChat": case "deleteChat": case "removePhoto": return confirmC
      case "deleteMsgs": return deleteC
      case "forward": return forwardC
      case "sendFiles": return filesC
      case "reactions": return reactionsC
      case "emoji": return emojiC
      case "shortcuts": return shortcutsC
      case "profile": return profileC
      case "about": return aboutC
      }
      return null
    }
  }

  // ------------------------------------------------------------ the card
  component DFrame: Rectangle {
    id: fr
    default property alias content: inner.data
    property string title: ""
    property real cardWidth: host.t.sp(480)
    width: Math.min(cardWidth, host.width - host.t.sp(40))
    height: Math.min(inner.childrenRect.height + (title ? host.t.sp(64) : host.t.sp(24)) + host.t.sp(24), host.height - host.t.sp(40))
    radius: host.t.sp(20)
    color: host.t.popup
    border.width: 1
    border.color: host.t.line
    MouseArea { anchors.fill: parent; onPressed: host.commitEdits() }
    Text {
      textFormat: Text.PlainText
      visible: fr.title !== ""
      x: host.t.sp(24)
      y: host.t.sp(22)
      width: parent.width - host.t.sp(48)
      text: fr.title
      color: host.t.textBright
      font.family: host.t.font
      font.pixelSize: host.t.px(19)
      font.weight: Font.Medium
      wrapMode: Text.Wrap
    }
    Item {
      id: inner
      x: host.t.sp(24)
      y: fr.title ? host.t.sp(64) : host.t.sp(24)
      width: parent.width - host.t.sp(48)
      height: parent.height - y - host.t.sp(24)
    }
  }

  component Btn: Rectangle {
    id: bt
    property string label: ""
    property bool primary: false
    property bool danger: false
    property bool enabledState: true
    signal clicked()
    height: host.t.sp(40)
    width: lbl.implicitWidth + host.t.sp(40)
    radius: height / 2
    opacity: enabledState ? 1 : 0.45
    color: primary ? (danger ? host.t.danger : host.t.accent) : (bma.containsMouse ? host.t.hoverStrong : "transparent")
    border.width: primary ? 0 : 1
    border.color: host.t.lineStrong
    Text {
      id: lbl
      textFormat: Text.PlainText
      anchors.centerIn: parent
      text: bt.label
      color: bt.primary ? host.t.onColor(bt.danger ? host.t.danger : host.t.accent) : (bt.danger ? host.t.danger : host.t.accent)
      font.family: host.t.font
      font.pixelSize: host.t.fsText
      font.weight: Font.Medium
    }
    MouseArea { id: bma; anchors.fill: parent; hoverEnabled: true; enabled: bt.enabledState; cursorShape: Qt.PointingHandCursor; onClicked: bt.clicked() }
  }

  // ------------------------------------------------------------ confirm
  Component {
    id: confirmC
    DFrame {
      id: cfr
      readonly property var spec: {
        var tr = host.app.tr
        var name = host.args.chat ? host.wa.nameOf(host.args.chat) : ""
        if (host.name === "logout") return { title: tr("Log out?", "Desconectar?"), text: tr("This computer stops being a linked device. Your chats stay on your phone.", "Este computador deixa de ser um aparelho conectado. Suas conversas continuam no celular."), ok: tr("Log out", "Desconectar"), danger: true,
                                             run: function() { host.wa.logout() } }
        if (host.name === "removePhoto") return { title: tr("Remove your profile photo?", "Remover sua foto do perfil?"), text: tr("Everyone will see your initials in its place.", "Todos verão suas iniciais no lugar."), ok: tr("Remove", "Remover"), danger: true,
                                                  run: function() { host.wa.setMyPhoto(""); host.show("profile") } }
        if (host.name === "clearChat") return { title: tr("Clear this chat?", "Limpar esta conversa?"), text: tr("Messages will only be removed from this device and your devices on the newer versions of WhatsApp.", "As mensagens serão removidas apenas deste aparelho e dos seus aparelhos com as versões mais recentes do WhatsApp."), ok: tr("Clear chat", "Limpar conversa"), danger: true,
                                                run: function() { host.wa.chatAction(host.args.chat, "clear") } }
        return { title: tr("Delete this chat?", "Apagar esta conversa?"), text: tr("Messages will only be removed from this device and your devices on the newer versions of WhatsApp.", "As mensagens serão removidas apenas deste aparelho e dos seus aparelhos com as versões mais recentes do WhatsApp."), ok: tr("Delete chat", "Apagar conversa"), danger: true,
                 run: function() { if (host.wa.current === host.args.chat) host.wa.close(); host.wa.chatAction(host.args.chat, "delete") } }
      }
      title: spec.title
      cardWidth: host.t.sp(460)
      Column {
        width: parent.width
        spacing: host.t.sp(24)
        Text { textFormat: Text.PlainText; width: parent.width; text: cfr.spec.text; color: host.t.dim; font.family: host.t.font; font.pixelSize: host.t.fsText; wrapMode: Text.Wrap }
        Row {
          anchors.right: parent.right
          spacing: host.t.sp(10)
          Btn { label: host.app.tr("Cancel", "Cancelar"); onClicked: host.hide() }
          Btn { label: cfr.spec.ok; primary: true; danger: !!cfr.spec.danger; onClicked: { var f = cfr.spec.run; host.hide(); f() } }
        }
      }
    }
  }

  // ------------------------------------------------------------ delete messages
  Component {
    id: deleteC
    DFrame {
      id: df
      readonly property var msgs: host.args.msgs || []
      // For everyone: only yours, sent less than about two days ago, not deleted yet.
      readonly property bool everyone: msgs.length > 0 && msgs.every(function(m) { return m.from_me && m.kind !== "revoked" && Date.now() / 1000 - m.ts < 60 * 60 * 48 && m.status >= 0 })
      title: msgs.length > 1 ? host.app.tr("Delete messages?", "Deseja apagar as mensagens?") : host.app.tr("Delete message?", "Deseja apagar a mensagem?")
      cardWidth: host.t.sp(440)
      Column {
        width: parent.width
        spacing: host.t.sp(10)
        topPadding: host.t.sp(6)
        function done() { var d = host.args.done; host.hide(); if (d) d() }
        Btn {
          visible: df.everyone
          anchors.right: parent.right
          label: host.app.tr("Delete for everyone", "Apagar para todos")
          onClicked: { host.wa.deleteMsgs(host.args.chat, df.msgs.map(function(m) { return m.id }), true); parent.done() }
        }
        Btn {
          anchors.right: parent.right
          label: host.app.tr("Delete for me", "Apagar para mim")
          onClicked: { host.wa.deleteMsgs(host.args.chat, df.msgs.map(function(m) { return m.id }), false); parent.done() }
        }
        Btn {
          anchors.right: parent.right
          label: host.app.tr("Cancel", "Cancelar")
          onClicked: host.hide()
        }
      }
    }
  }

  // ------------------------------------------------------------ forward
  Component {
    id: forwardC
    DFrame {
      id: ff
      title: host.app.tr("Forward message to", "Encaminhar mensagem para")
      cardWidth: host.t.sp(480)
      property var picked: ({})
      property int pickedRev: 0
      readonly property var pickedList: { ff.pickedRev; return Object.keys(ff.picked) }
      Component.onCompleted: host.wa.loadChatSubs()
      readonly property var options: {
        var q = U.fold(search.text.trim())
        return host.wa.chatList.filter(function(c) { return !c.ro && (!q || U.fold(host.wa.chatName(c)).indexOf(q) >= 0) }).slice(0, 200)
      }
      Column {
        width: parent.width
        spacing: host.t.sp(10)
        SearchPill { id: search; app: host.app; width: parent.width; placeholder: host.app.tr("Search name or number", "Pesquisar nome ou número"); Component.onCompleted: focusInput() }
        ListView {
          width: parent.width + host.t.sp(24)
          x: -host.t.sp(12)
          height: Math.min(host.height * 0.5, host.t.sp(420))
          clip: true
          model: ff.options
          ScrollBar.vertical: ThinScroll { app: host.app }
          delegate: PersonRow {
            required property var modelData
            app: host.app
            jid: modelData.jid
            name: host.wa.chatName(modelData)
            group: modelData.kind === "group"
            sub: host.wa.chatSubs[modelData.jid] ? String(host.wa.chatSubs[modelData.jid]).replace("\u0000you", host.app.tr("You", "Você")) : ""
            checkable: true
            checked: { ff.pickedRev; return !!ff.picked[modelData.jid] }
            onClicked: { var p = ff.picked; if (p[modelData.jid]) delete p[modelData.jid]; else p[modelData.jid] = true; ff.pickedRev++ }
          }
        }
        Item {
          width: parent.width
          height: host.t.sp(44)
          Text {
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.right: sendFwd.left
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: ff.pickedList.map(function(j) { return host.wa.nameOf(j) }).join(", ")
            color: host.t.dim
            font.family: host.t.font
            font.pixelSize: host.t.fsSmall + 1
          }
          Rectangle {
            id: sendFwd
            anchors.right: parent.right
            width: host.t.sp(48); height: width; radius: width / 2
            color: host.t.accent
            opacity: ff.pickedList.length ? 1 : 0.4
            Icon { anchors.centerIn: parent; name: "send"; size: host.t.sp(24); color: host.t.onBrand }
            MouseArea {
              anchors.fill: parent
              enabled: ff.pickedList.length > 0
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                host.wa.forward(host.args.chat, (host.args.msgs || []).map(function(m) { return m.id }), ff.pickedList)
                var d = host.args.done
                host.hide()
                if (d) d()
              }
            }
          }
        }
      }
    }
  }

  // ------------------------------------------------------------ send files
  Component {
    id: filesC
    DFrame {
      id: sf
      // Ctrl+V in the caption adds what the clipboard has, as WhatsApp
      // Web's; a pasted picture is a copy of ours, gone once sent (temps).
      property var files: (host.args.files || []).slice()
      property var temps: ({})
      Component.onCompleted: { var o = {}; if (host.args.temp) sf.files.forEach(function(p) { o[p] = true }); sf.temps = o }
      property int at: 0
      readonly property string currentPath: files[at] || ""
      readonly property string kindOf: host.args.asDocument ? "document" : host.args.asAudio ? "audio" : U.kindOf(currentPath)
      title: sf.files.length > 1 ? host.app.tr(sf.files.length + " files", sf.files.length + " arquivos") : U.basename(sf.currentPath)
      cardWidth: host.t.sp(620)
      function send() {
        var caption = cap.text.trim()
        for (var i = 0; i < sf.files.length; i++) {
          var p = sf.files[i]
          var kind = host.args.asDocument ? "document" : host.args.asAudio ? "audio" : U.kindOf(p)
          host.wa.sendFile(host.args.chat, p, kind, i === sf.files.length - 1 ? caption : "", i === 0 ? (host.args.reply || "") : "", !!sf.temps[p])
        }
        host.hide()
      }
      function paste() {
        host.app.readClipboard(function(r) {
          var more = r.image ? [r.image] : (r.files || [])
          if (more.length && !host.args.asDocument && !host.args.asAudio) {
            var t = sf.temps
            if (r.image) { t[r.image] = true; sf.temps = t }
            sf.files = sf.files.concat(more)
            sf.at = sf.files.length - 1
          } else if (r.text) cap.insert(cap.cursorPosition, r.text)
        })
      }
      Column {
        width: parent.width
        spacing: host.t.sp(14)
        Rectangle {
          width: parent.width
          height: Math.min(host.height * 0.5, host.t.sp(380))
          radius: host.t.sp(10)
          color: host.t.alpha(host.t.fg, 0.05)
          Image {
            anchors.fill: parent
            anchors.margins: host.t.sp(8)
            visible: sf.kindOf === "image"
            source: sf.kindOf === "image" ? U.fileUrl(sf.currentPath) : ""
            sourceSize.width: 1200
            fillMode: Image.PreserveAspectFit
            asynchronous: true
          }
          Column {
            anchors.centerIn: parent
            visible: sf.kindOf !== "image"
            spacing: host.t.sp(12)
            Icon { anchors.horizontalCenter: parent.horizontalCenter; name: sf.kindOf === "video" ? "videoFilled" : sf.kindOf === "audio" ? "headphones" : "documentFilled"; size: host.t.sp(72); color: host.t.faint }
            Text { textFormat: Text.PlainText; anchors.horizontalCenter: parent.horizontalCenter; text: U.basename(sf.currentPath); color: host.t.text; font.family: host.t.font; font.pixelSize: host.t.fsText }
            Text { textFormat: Text.PlainText; anchors.horizontalCenter: parent.horizontalCenter; text: sf.kindOf === "document" ? host.app.tr("Sent as a document", "Enviado como documento") : ""; color: host.t.dim; font.family: host.t.font; font.pixelSize: host.t.fsSmall }
          }
        }
        // The files, when there are several.
        ListView {
          visible: sf.files.length > 1
          width: parent.width
          height: visible ? host.t.sp(58) : 0
          orientation: ListView.Horizontal
          spacing: host.t.sp(8)
          clip: true
          model: sf.files
          delegate: Rectangle {
            required property var modelData
            required property int index
            width: host.t.sp(56); height: width; radius: host.t.sp(8)
            color: host.t.hover
            border.width: index === sf.at ? 2 : 0
            border.color: host.t.accent
            Image { anchors.fill: parent; anchors.margins: 3; visible: U.kindOf(modelData) === "image"; source: U.kindOf(modelData) === "image" ? U.fileUrl(modelData) : ""; sourceSize.width: 120; fillMode: Image.PreserveAspectCrop; asynchronous: true }
            Icon { anchors.centerIn: parent; visible: U.kindOf(modelData) !== "image"; name: "documentFilled"; size: host.t.sp(26); color: host.t.faint }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: sf.at = index }
          }
        }
        Row {
          width: parent.width
          spacing: host.t.sp(12)
          // The caption, as the message box: it grows to a few lines,
          // Shift+Enter breaks one (Enter, when Enter doesn't send).
          Rectangle {
            width: parent.width - host.t.sp(60)
            height: Math.max(host.t.sp(46), capScroll.height + host.t.sp(24))
            radius: host.t.sp(23)
            color: host.t.field
            visible: sf.kindOf !== "audio"
            Flickable {
              id: capScroll
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.leftMargin: host.t.sp(18)
              anchors.rightMargin: host.t.sp(18)
              anchors.verticalCenter: parent.verticalCenter
              height: Math.min(contentHeight, host.t.sp(120))
              contentHeight: cap.implicitHeight
              contentWidth: width
              clip: true
              boundsBehavior: Flickable.StopAtBounds
              interactive: contentHeight > height
              function ensureVisible(r) {
                if (contentY >= r.y) contentY = r.y
                else if (contentY + height <= r.y + r.height) contentY = r.y + r.height - height
              }
              TextEdit {
                id: cap
                width: capScroll.width
                wrapMode: TextEdit.Wrap
                textFormat: TextEdit.PlainText
                color: host.t.text
                font.family: host.t.font
                font.pixelSize: host.t.fsText
                selectByMouse: true
                selectionColor: host.t.alpha(host.t.accent, 0.4)
                onCursorRectangleChanged: capScroll.ensureVisible(cursorRectangle)
                Component.onCompleted: forceActiveFocus()
                Keys.onPressed: event => {
                  var ctrl = event.modifiers & Qt.ControlModifier, shift = event.modifiers & Qt.ShiftModifier
                  if ((ctrl && event.key === Qt.Key_V) || event.matches(StandardKey.Paste)) { sf.paste(); event.accepted = true; return }
                  if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    if (host.app.enterSends ? !shift : ctrl) { sf.send(); event.accepted = true }
                    else if (!shift) { cap.insert(cap.cursorPosition, "\n"); event.accepted = true }
                  }
                }
                Text { textFormat: Text.PlainText; width: parent.width; visible: !cap.text; text: host.app.tr("Add a caption", "Adicione uma legenda"); color: host.t.faint; font: cap.font }
              }
            }
          }
          Rectangle {
            width: host.t.sp(48); height: width; radius: width / 2
            color: host.t.accent
            Icon { anchors.centerIn: parent; name: "send"; size: host.t.sp(24); color: host.t.onBrand }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: sf.send() }
          }
        }
      }
    }
  }

  // ------------------------------------------------------------ reactions
  Component {
    id: reactionsC
    DFrame {
      id: rf
      readonly property var m: host.args.msg
      readonly property var latest: { var x = host.wa.findMsg(m.chat, m.id); return x || m }
      property string only: ""
      title: host.app.tr("Reactions", "Reações")
      cardWidth: host.t.sp(400)
      readonly property var people: {
        var out = []
        ;(rf.latest.reactions || []).forEach(function(r) {
          if (rf.only && r.emoji !== rf.only) return
          ;(r.by || []).forEach(function(p) { out.push({ jid: p.jid, name: p.name, emoji: r.emoji, mine: r.mine && p.name === "" }) })
        })
        return out
      }
      Column {
        width: parent.width
        spacing: host.t.sp(8)
        Row {
          spacing: host.t.sp(6)
          Chip { app: host.app; label: host.app.tr("All", "Todas"); count: (rf.latest.reactions || []).reduce(function(s, r) { return s + r.count }, 0); on: rf.only === ""; onClicked: rf.only = "" }
          Repeater {
            model: rf.latest.reactions || []
            delegate: Chip { required property var modelData; app: host.app; label: modelData.emoji; count: modelData.count; on: rf.only === modelData.emoji; onClicked: rf.only = modelData.emoji }
          }
        }
        ListView {
          width: parent.width + host.t.sp(24)
          x: -host.t.sp(12)
          height: Math.min(contentHeight, host.t.sp(360))
          clip: true
          model: rf.people
          delegate: PersonRow {
            required property var modelData
            app: host.app
            jid: modelData.name === "" ? (host.wa.me ? host.wa.me.jid : "") : modelData.jid
            name: modelData.name === "" ? host.app.tr("You", "Você") : String(modelData.name).replace(/^~/, "")
            sub: modelData.name === "" ? host.app.tr("Click to remove", "Clique para remover") : ""
            badge: modelData.emoji
            onClicked: { if (modelData.name === "") host.wa.react(rf.m, ""); else host.win.showProfile(modelData.jid); host.hide() }
          }
        }
      }
    }
  }

  // ------------------------------------------------------------ emoji
  Component {
    id: emojiC
    Rectangle {
      width: Math.min(host.t.sp(420), host.width - host.t.sp(40))
      height: Math.min(host.t.sp(440), host.height - host.t.sp(40))
      radius: host.t.sp(16)
      color: host.t.panel
      border.width: 1
      border.color: host.t.line
      clip: true
      MouseArea { anchors.fill: parent }
      EmojiPanel {
        anchors.fill: parent
        anchors.margins: 2
        app: host.app
        pickOnly: true
        onPicked: glyph => { var f = host.args.onPick; host.hide(); if (f) f(glyph) }
      }
    }
  }

  // ------------------------------------------------------------ your profile
  // whatsapp-tui's "Perfil": your photo, your name over your number, and
  // your about. The name and the about edit in place, as on WhatsApp Web
  // (the pencil, then ✓ or Enter to save, Esc to leave it); a click on the
  // number copies it.
  component EditLine: Item {
    id: el
    property string value: ""
    property string display: value
    property bool dimmed: false
    property int limit: 25
    property bool wrap: false
    property bool editable: true
    property int pixelSize: host.t.fsName
    property int weight: Font.Normal
    property color textColor: host.t.text
    property bool editing: false
    signal saved(string text)
    height: editing ? box.height : shown.height
    Connections { target: host; function onCommitEdits() { if (el.editing) el.save() } }

    function start() {
      if (!el.editable) return
      host.commitEdits()
      input.text = el.value
      el.editing = true
      input.forceActiveFocus()
      input.cursorPosition = input.text.length
    }
    function cancel() { el.editing = false; host.forceActiveFocus() }
    function save() {
      var s = input.text.trim()
      if (s === "") return
      el.editing = false
      host.forceActiveFocus()
      if (s !== el.value) el.saved(s)
    }

    Item {
      id: shown
      visible: !el.editing
      width: parent.width
      height: Math.max(shownText.implicitHeight, host.t.sp(32))
      Text {
        id: shownText
        width: parent.width - (pen.visible ? pen.width + host.t.sp(8) : 0)
        anchors.verticalCenter: parent.verticalCenter
        text: el.display
        color: el.dimmed ? host.t.dim : el.textColor
        font.family: host.t.font
        font.pixelSize: el.pixelSize
        font.weight: el.weight
        wrapMode: el.wrap ? Text.Wrap : Text.NoWrap
        elide: el.wrap ? Text.ElideNone : Text.ElideRight
        textFormat: Text.PlainText
      }
      IconButton {
        id: pen
        visible: el.editable
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        implicitWidth: host.t.sp(32); implicitHeight: host.t.sp(32)
        icon: "edit"
        iconSize: host.t.sp(20)
        tip: host.app.tr("Edit", "Editar")
        onClicked: el.start()
      }
    }
    Item {
      id: box
      visible: el.editing
      width: parent.width
      height: Math.max(input.contentHeight, host.t.sp(24)) + host.t.sp(12)
      TextInput {
        id: input
        y: host.t.sp(4)
        width: parent.width - count.width - ok.width - host.t.sp(12)
        color: host.t.text
        font.family: host.t.font
        font.pixelSize: el.pixelSize
        font.weight: el.weight
        wrapMode: el.wrap ? TextInput.Wrap : TextInput.NoWrap
        clip: !el.wrap
        maximumLength: el.limit
        selectByMouse: true
        selectionColor: host.t.alpha(host.t.accent, 0.4)
        selectedTextColor: host.t.textBright
        Keys.onReturnPressed: event => { el.save(); event.accepted = true }
        Keys.onEnterPressed: event => { el.save(); event.accepted = true }
        Keys.onEscapePressed: event => { el.cancel(); event.accepted = true }
      }
      Text {
        id: count
        textFormat: Text.PlainText
        anchors.right: ok.left
        anchors.rightMargin: host.t.sp(4)
        y: input.y + Math.max(0, Math.round((host.t.sp(24) - height) / 2))
        text: String(el.limit - input.length)
        color: host.t.faint
        font.family: host.t.font
        font.pixelSize: host.t.fsSmall
      }
      IconButton {
        id: ok
        anchors.right: parent.right
        y: input.y + Math.round((host.t.sp(24) - height) / 2)
        implicitWidth: host.t.sp(32); implicitHeight: host.t.sp(32)
        icon: "check"
        iconSize: host.t.sp(20)
        enabledState: input.text.trim() !== ""
        tip: host.app.tr("Save", "Salvar")
        onClicked: el.save()
      }
      Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: 2
        color: host.t.accent
      }
    }
  }

  Component {
    id: profileC
    DFrame {
      id: pf
      readonly property string jid: host.wa.me ? host.wa.me.jid : ""
      readonly property var info: pf.jid ? host.wa.profile(pf.jid) : null
      readonly property string phone: host.wa.me ? U.phone(host.wa.me.phone) : ""
      title: host.app.tr("Profile", "Perfil")
      cardWidth: host.t.sp(460)
      Component.onCompleted: if (pf.jid) host.wa.askProfile(pf.jid)
      Column {
        width: parent.width
        spacing: host.t.sp(18)
        Row {
          width: parent.width
          spacing: host.t.sp(16)
          Avatar {
            id: pfPhoto
            app: host.app
            size: host.t.sp(72)
            jid: pf.jid
            name: host.wa.me ? host.wa.me.name : ""
            source: pf.info && pf.info.photo ? pf.info.photo : ""
            // While a new one goes (or the old one leaves).
            Rectangle {
              anchors.fill: parent
              radius: width / 2
              visible: host.wa.photoBusy
              color: host.t.alpha(host.t.bg, 0.6)
              Text { textFormat: Text.PlainText; anchors.centerIn: parent; text: "…"; color: host.t.textBright; font.family: host.t.font; font.pixelSize: host.t.fsName }
            }
            // WhatsApp Web's menu on your photo: see it, upload one, remove it.
            MouseArea {
              id: pfPhotoMa
              anchors.fill: parent
              enabled: !!host.wa.me && !host.wa.photoBusy
              hoverEnabled: true
              cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
              onClicked: {
                var tr = host.app.tr, has = !!pf.info && !!pf.info.photo
                var items = []
                if (has) items.push({ label: tr("View photo", "Ver foto"), icon: "eye", action: function() {
                  var p = pf.info.photo, n = host.wa.me ? host.wa.me.name : ""
                  host.hide()
                  host.win.viewMedia({ chat: pf.jid, id: "photo", kind: "image", media: { file: U.unfileUrl(p) }, ts: 0, name: n })
                } })
                items.push({ label: tr("Upload photo", "Carregar foto"), icon: "photo", action: function() {
                  host.win.pickFiles(tr("Profile photo", "Foto do perfil"), tr("Images", "Imagens") + " (*.jpg *.jpeg *.png *.webp *.gif *.bmp *.heic *.avif)",
                                     function(files) { if (files.length) host.wa.setMyPhoto(files[0]) }, true)
                } })
                if (has) items.push({ label: tr("Remove photo", "Remover foto"), icon: "delete", danger: true, action: function() { host.show("removePhoto") } })
                host.win.menuAt(pfPhoto, items, pfPhoto.width / 2, pfPhoto.height / 2)
              }
            }
            Tip { text: host.app.tr("Profile photo", "Foto do perfil"); shown: pfPhotoMa.containsMouse && pfPhotoMa.enabled; placement: "below" }
          }
          Column {
            width: parent.width - pfPhoto.width - host.t.sp(16)
            anchors.verticalCenter: parent.verticalCenter
            spacing: host.t.sp(2)
            // A business account's name is its business name, read-only
            // as on WhatsApp Web Business (it changes on the phone).
            Text {
              textFormat: Text.PlainText
              visible: !!host.wa.me && !!host.wa.me.business
              text: host.app.tr("Business name", "Nome comercial")
              color: host.t.dim
              font.family: host.t.font
              font.pixelSize: host.t.fsSmall
            }
            EditLine {
              width: parent.width
              value: host.wa.me ? (host.wa.me.business && host.wa.me.businessName ? host.wa.me.businessName : host.wa.me.name || "") : ""
              display: value || host.app.tr("You", "Você")
              limit: 25
              editable: !!host.wa.me && !host.wa.me.business
              textColor: host.t.textBright
              pixelSize: host.t.fsName + 2
              weight: Font.DemiBold
              onSaved: text => host.wa.setMyName(text)
            }
            Text {
              id: pfPhone
              textFormat: Text.PlainText
              text: pf.phone
              color: phMa.containsMouse ? host.t.text : host.t.dim
              font.family: host.t.font
              font.pixelSize: host.t.fsText
              font.underline: phMa.containsMouse
              MouseArea {
                id: phMa
                anchors.fill: parent
                hoverEnabled: true
                enabled: pf.phone !== ""
                cursorShape: Qt.PointingHandCursor
                onClicked: { host.app.copy(pf.phone); host.win.toast(host.app.tr("Number copied", "Número copiado")) }
              }
              Tip { text: host.app.tr("Copy number", "Copiar número"); shown: phMa.containsMouse; placement: "below" }
            }
          }
        }
        Column {
          width: parent.width
          spacing: host.t.sp(6)
          Text { textFormat: Text.PlainText; text: host.app.tr("About", "Recado"); color: host.t.accent; font.family: host.t.font; font.pixelSize: host.t.fsText; font.weight: Font.Medium }
          EditLine {
            width: parent.width
            value: pf.info && !pf.info.error ? (pf.info.about || "") : ""
            display: !pf.info ? host.app.tr("Loading…", "Carregando…")
                     : pf.info.error ? host.app.tr("Didn't load: ", "Não carregou: ") + pf.info.error
                     : value.trim() !== "" ? value : "—"
            dimmed: !pf.info || !!pf.info.error
            limit: 139
            wrap: true
            editable: !!pf.info && !pf.info.error
            onSaved: text => host.wa.setMyAbout(text)
          }
        }
        Btn { anchors.right: parent.right; label: host.app.tr("Close", "Fechar"); primary: true; onClicked: host.hide() }
      }
    }
  }

  // ------------------------------------------------------------ about
  // whatsapp-tui's "Sobre": the name, the version and where the code is,
  // with a newer version when there is one (core/Updater.qml).
  Component {
    id: aboutC
    DFrame {
      id: ab
      readonly property var up: host.app.updater || null
      readonly property string repo: ab.up && ab.up.repo ? ab.up.repo : "https://github.com/leonavas/omawhats"
      cardWidth: host.t.sp(440)
      Column {
        width: parent.width
        spacing: host.t.sp(8)
        Image {
          anchors.horizontalCenter: parent.horizontalCenter
          source: Qt.resolvedUrl("../assets/whatsapp.svg")
          width: host.t.sp(56); height: width
          sourceSize.width: width * 2; sourceSize.height: height * 2
        }
        Text {
          textFormat: Text.PlainText
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: host.app.windowTitleBase
          color: host.t.accent
          font.family: host.t.font
          font.pixelSize: host.t.px(22)
          font.weight: Font.Bold
        }
        Text {
          textFormat: Text.PlainText
          visible: !!ab.up && !!ab.up.version
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: ab.up ? host.app.tr("version ", "versão ") + ab.up.version : ""
          color: host.t.dim
          font.family: host.t.font
          font.pixelSize: host.t.fsSmall
        }
        Text {
          textFormat: Text.PlainText
          readonly property bool busy: !!ab.up && ab.up.phase === "updating"
          visible: !!ab.up && ab.up.phase !== ""
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: !ab.up ? "" : busy ? host.app.tr("Updating to ", "Atualizando para a versão ") + ab.up.latest + "…"
                : ab.up.phase === "updated" ? host.app.tr("Version ", "Versão ") + ab.up.latest + host.app.tr(" is installed · restart the shell", " instalada · reiniciar o shell")
                : host.app.tr("Version ", "Versão ") + ab.up.latest + host.app.tr(" is available · update", " disponível · atualizar")
          color: busy ? host.t.dim : host.t.green
          font.family: host.t.font
          font.pixelSize: host.t.fsSmall
          font.underline: !busy && abUp.containsMouse
          MouseArea { id: abUp; anchors.fill: parent; hoverEnabled: true; enabled: !parent.busy; cursorShape: Qt.PointingHandCursor; onClicked: ab.up.update() }
        }
        Item { width: 1; height: host.t.sp(4) }
        Text {
          textFormat: Text.PlainText
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: ab.repo.replace("https://", "")
          color: host.t.link
          font.family: host.t.font
          font.pixelSize: host.t.fsText
          font.underline: abLink.containsMouse
          MouseArea { id: abLink; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Qt.openUrlExternally(ab.repo) }
        }
        Text {
          textFormat: Text.PlainText
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.Wrap
          text: host.app.tr("An unofficial WhatsApp client for the Omarchy shell, linked to your phone as one more device. Not made or endorsed by WhatsApp.",
                            "Um cliente não oficial do WhatsApp para o shell do Omarchy, conectado ao seu celular como mais um aparelho. Não é feito nem endossado pelo WhatsApp.")
          color: host.t.dim
          font.family: host.t.font
          font.pixelSize: host.t.fsSmall
        }
        Item { width: 1; height: host.t.sp(8) }
        Row {
          anchors.right: parent.right
          spacing: host.t.sp(10)
          Btn { label: host.app.tr("Keyboard shortcuts", "Atalhos do teclado"); onClicked: host.show("shortcuts", {}) }
          Btn { label: host.app.tr("Close", "Fechar"); primary: true; onClicked: host.hide() }
        }
      }
    }
  }

  // ------------------------------------------------------------ shortcuts
  Component {
    id: shortcutsC
    DFrame {
      id: scf
      title: host.app.tr("Keyboard shortcuts", "Atalhos do teclado")
      cardWidth: host.t.sp(640)
      readonly property var keys: [
        ["Ctrl+Alt+N · Ctrl+N", host.app.tr("New chat", "Nova conversa")],
        ["Ctrl+Alt+/ · Ctrl+K", host.app.tr("Search", "Pesquisar")],
        ["Ctrl+Alt+Shift+F", host.app.tr("Search in chat", "Pesquisar na conversa")],
        ["Alt+↑ · Alt+↓", host.app.tr("Previous / next chat", "Conversa anterior / próxima")],
        ["Ctrl+Alt+E", host.app.tr("Archive chat", "Arquivar conversa")],
        ["Ctrl+Alt+Shift+M", host.app.tr("Mute chat", "Silenciar conversa")],
        ["Ctrl+Alt+Shift+U", host.app.tr("Mark as unread", "Marcar como não lida")],
        ["Ctrl+Alt+Shift+P", host.app.tr("Pin chat", "Fixar conversa")],
        ["Ctrl+Alt+Backspace", host.app.tr("Delete chat", "Apagar conversa")],
        ["Ctrl+Alt+I", host.app.tr("Contact info", "Dados do contato")],
        ["Alt+S", host.app.tr("Your menu", "Menu da conta")],
        ["Ctrl+Alt+P", host.app.tr("Profile", "Perfil")],
        ["Ctrl+Alt+,", host.app.tr("Settings", "Configurações")],
        ["Ctrl+/", host.app.tr("Keyboard shortcuts", "Atalhos do teclado")],
        ["↑ " + host.app.tr("(empty box)", "(caixa vazia)"), host.app.tr("Edit your last message", "Editar sua última mensagem")],
        ["Ctrl+B · Ctrl+I", host.app.tr("Bold / italic", "Negrito / itálico")],
        ["Ctrl+Shift+X", host.app.tr("Strikethrough", "Tachado")],
        ["Ctrl+Shift+M", host.app.tr("Monospace", "Monoespaçado")],
        ["Ctrl+V", host.app.tr("Paste a picture or files", "Colar imagem ou arquivos")],
        ["Ctrl+= · Ctrl+-", host.app.tr("Zoom in / out", "Aumentar / diminuir zoom")],
        ["Esc", host.app.tr("Close the chat, cancel", "Fechar a conversa, cancelar")],
        ["Ctrl+W", host.app.tr("Hide the window", "Esconder a janela")]
      ]
      Grid {
        width: parent.width
        columns: 2
        columnSpacing: host.t.sp(20)
        rowSpacing: host.t.sp(10)
        Repeater {
          model: scf.keys
          delegate: Row {
            required property var modelData
            width: (parent.width - host.t.sp(20)) / 2
            spacing: host.t.sp(10)
            Text { textFormat: Text.PlainText; width: parent.width * 0.55; text: modelData[1]; color: host.t.text; font.family: host.t.font; font.pixelSize: host.t.fsSmall + 1; wrapMode: Text.Wrap }
            Rectangle {
              width: kt.implicitWidth + host.t.sp(12); height: kt.implicitHeight + host.t.sp(6); radius: host.t.sp(5)
              color: host.t.hover
              border.width: 1
              border.color: host.t.line
              Text { id: kt; textFormat: Text.PlainText; anchors.centerIn: parent; text: modelData[0]; color: host.t.dim; font.family: host.t.font; font.pixelSize: host.t.fsSmall }
            }
          }
        }
      }
    }
  }
}
