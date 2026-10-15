import QtQuick
import QtQuick.Controls
import Quickshell
import "../lib/Util.js" as U
import "../lib/Format.js" as F
import "../lib/Labels.js" as L
import "../lib/Hours.js" as H
import "../lib/Registry.js" as Reg

// The right side panel, as WhatsApp Web's: the contact's or group's info
// (photo, name, about, a business's details and hours, media, members,
// groups in common, mute, starred, delete), the search in the chat, or its
// media, links and docs. The open chat's, or of someone picked in it.
Rectangle {
  id: ip
  property var app: Reg.service
  property var win
  property string chat: ""
  readonly property var t: app.theme
  readonly property var wa: app.wa
  readonly property var c: wa.chat(chat)
  readonly property var p: wa.profile(chat)
  readonly property bool group: chat.indexOf("@g.us") > 0
  readonly property string view: win.infoView
  // Someone picked in the conversation, not the open chat.
  readonly property bool other: chat !== "" && chat !== wa.current
  color: t.panel

  Component.onCompleted: ip.wa.askProfile(ip.chat)
  onChatChanged: { ip.week = false; if (ip.chat) ip.wa.askProfile(ip.chat) }

  // ------------------------------------------------------------ header
  Item {
    id: head
    width: parent.width
    height: ip.t.sp(64)
    IconButton {
      id: closeBtn
      x: ip.t.sp(10)
      anchors.verticalCenter: parent.verticalCenter
      icon: ip.view === "media" ? "back" : "close"
      color: ip.t.text
      onClicked: { if (ip.view === "media") ip.win.infoView = ""; else ip.win.infoOpen = false }
    }
    Text {
      textFormat: Text.PlainText
      anchors.left: closeBtn.right
      anchors.leftMargin: ip.t.sp(14)
      anchors.verticalCenter: parent.verticalCenter
      text: ip.view === "search" ? ip.app.tr("Search messages", "Pesquisar mensagens")
          : ip.view === "media" ? ip.app.tr("Media, links and docs", "Mídia, links e docs")
          : ip.group ? ip.app.tr("Group info", "Dados do grupo") : ip.app.tr("Contact info", "Dados do contato")
      color: ip.t.textBright
      font.family: ip.t.font
      font.pixelSize: ip.t.px(17)
      font.weight: Font.Medium
    }
  }

  Loader {
    y: head.height
    width: parent.width
    height: parent.height - y
    sourceComponent: ip.view === "search" ? searchC : ip.view === "media" ? mediaC : infoC
  }

  // ------------------------------------------------------------ info
  component Row2: Item {
    id: r2
    property string icon: ""
    property string label: ""
    property string value: ""
    property bool danger: false
    property bool chevron: false
    signal clicked()
    width: parent ? parent.width : 0
    height: ip.t.sp(54)
    Rectangle { anchors.fill: parent; anchors.leftMargin: ip.t.sp(10); anchors.rightMargin: ip.t.sp(10); radius: ip.t.sp(10); color: rma.containsMouse ? ip.t.hover : "transparent" }
    Icon { x: ip.t.sp(28); anchors.verticalCenter: parent.verticalCenter; name: r2.icon; size: ip.t.sp(22); color: r2.danger ? ip.t.danger : ip.t.icon }
    Text {
      textFormat: Text.PlainText
      x: ip.t.sp(70)
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - x - ip.t.sp(90)
      text: r2.label
      color: r2.danger ? ip.t.danger : ip.t.text
      font.family: ip.t.font
      font.pixelSize: ip.t.fsName - 1
      elide: Text.ElideRight
    }
    Row {
      anchors.right: parent.right
      anchors.rightMargin: ip.t.sp(24)
      anchors.verticalCenter: parent.verticalCenter
      spacing: ip.t.sp(4)
      Text { textFormat: Text.PlainText; text: r2.value; color: ip.t.dim; font.family: ip.t.font; font.pixelSize: ip.t.fsText; anchors.verticalCenter: parent.verticalCenter }
      Icon { visible: r2.chevron; name: "chevronRight"; size: ip.t.sp(20); color: ip.t.dim; anchors.verticalCenter: parent.verticalCenter }
    }
    MouseArea { id: rma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: r2.clicked() }
  }
  component Gap: Rectangle { width: parent ? parent.width : 0; height: ip.t.sp(10); color: ip.t.alpha(ip.t.fg, ip.t.dark ? 0.03 : 0.04) }
  // A section's dim title, with an icon at its right end.
  component Title: Item {
    id: tt
    property string text: ""
    property string icon: ""
    width: parent ? parent.width - parent.leftPadding - parent.rightPadding : 0
    height: ip.t.sp(22)
    Text { textFormat: Text.PlainText; anchors.verticalCenter: parent.verticalCenter; text: tt.text; color: ip.t.dim; font.family: ip.t.font; font.pixelSize: ip.t.fsText }
    Icon { visible: tt.icon !== ""; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; name: tt.icon; size: ip.t.sp(18); color: ip.t.dim }
  }
  // A square button under the name: search, message.
  component Action: Rectangle {
    id: act
    property string icon: ""
    property string label: ""
    signal clicked()
    width: ip.t.sp(110); height: ip.t.sp(64); radius: ip.t.sp(12)
    color: ama.containsMouse ? ip.t.hoverStrong : "transparent"
    border.width: 1
    border.color: ip.t.lineStrong
    Column {
      anchors.centerIn: parent
      spacing: ip.t.sp(4)
      Icon { anchors.horizontalCenter: parent.horizontalCenter; name: act.icon; size: ip.t.sp(22); color: ip.t.accent }
      Text { textFormat: Text.PlainText; anchors.horizontalCenter: parent.horizontalCenter; text: act.label; color: ip.t.text; font.family: ip.t.font; font.pixelSize: ip.t.fsSmall + 1 }
    }
    MouseArea { id: ama; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: act.clicked() }
  }

  // The name the panel shows, and whether the number is worth a line under it.
  readonly property string title: c ? wa.chatName(c) : (p && p.name ? p.name : wa.nameOf(chat))
  readonly property string number: group ? "" : (p && p.phone ? U.phone(p.phone) : (c && c.phone ? U.phone(c.phone) : ""))
  // A business's week, where it stands now.
  readonly property var op: p && p.hours && p.hours.length ? H.opening(p.hours, p.tz, app.lang) : null
  property bool week: false

  Component {
    id: infoC
    Flickable {
      contentHeight: col.implicitHeight + ip.t.sp(30)
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      ScrollBar.vertical: ThinScroll { app: ip.app }
      Column {
        id: col
        width: parent.width

        // The picture, the name and number (or the members), the name
        // they set, a business's category and whether it's open.
        Column {
          width: parent.width
          spacing: ip.t.sp(6)
          bottomPadding: ip.t.sp(20)
          topPadding: ip.t.sp(10)
          Avatar {
            anchors.horizontalCenter: parent.horizontalCenter
            size: ip.t.sp(200)
            jid: ip.chat
            name: ip.title
            group: ip.group
            source: ip.p && ip.p.photo ? ip.p.photo : ""
            // Big over everything; a word when there's none, or not yet.
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                if (ip.p && ip.p.photo) ip.win.viewMedia({ chat: ip.chat, id: "photo", kind: "image", media: { file: U.unfileUrl(ip.p.photo) }, ts: 0, name: ip.title })
                else if (ip.p && ip.p.photo === "") ip.win.toast(ip.app.tr("No profile photo", "Sem foto do perfil"))
                else ip.win.toast(ip.app.tr("Loading the photo…", "Carregando a foto…"))
              }
            }
          }
          Item { width: 1; height: ip.t.sp(6) }
          Text {
            width: parent.width - ip.t.sp(40)
            anchors.horizontalCenter: parent.horizontalCenter
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: ip.title
            color: ip.t.textBright
            font.family: ip.t.font
            font.pixelSize: ip.t.px(22)
            textFormat: Text.PlainText
          }
          Text {
            textFormat: Text.PlainText
            width: parent.width - ip.t.sp(40)
            anchors.horizontalCenter: parent.horizontalCenter
            horizontalAlignment: Text.AlignHCenter
            visible: text !== ""
            text: ip.group ? (ip.p && ip.p.members ? ip.app.tr("Group · " + ip.p.members.length + " members", "Grupo · " + ip.p.members.length + " membros") : "")
                           : (ip.number !== ip.title ? ip.number : "")
            color: ip.t.dim
            font.family: ip.t.font
            font.pixelSize: ip.t.fsName - 1
          }
          Text {
            textFormat: Text.PlainText
            width: parent.width - ip.t.sp(40)
            anchors.horizontalCenter: parent.horizontalCenter
            horizontalAlignment: Text.AlignHCenter
            visible: !ip.group && !!ip.p && !!ip.p.push && !ip.p.biz && ip.title.indexOf(ip.p.push) < 0
            text: "~" + (ip.p ? ip.p.push || "" : "")
            color: ip.t.faint
            font.family: ip.t.font
            font.pixelSize: ip.t.fsText
          }
          Text {
            textFormat: Text.PlainText
            width: parent.width - ip.t.sp(40)
            anchors.horizontalCenter: parent.horizontalCenter
            horizontalAlignment: Text.AlignHCenter
            visible: !!ip.p && !!ip.p.category
            text: ip.p ? ip.p.category || "" : ""
            wrapMode: Text.Wrap
            color: ip.t.dim
            font.family: ip.t.font
            font.pixelSize: ip.t.fsText
          }
          // "Aberta até às 17:00", "Fechada abre amanhã às 08:00".
          Row {
            visible: !!ip.op
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: ip.t.sp(5)
            Text { textFormat: Text.PlainText; text: ip.op && ip.op.open ? ip.app.tr("Open", "Aberta") : ip.app.tr("Closed", "Fechada"); color: ip.op && ip.op.open ? ip.t.online : ip.t.danger; font.family: ip.t.font; font.pixelSize: ip.t.fsText }
            Text { textFormat: Text.PlainText; visible: text !== ""; text: ip.op ? ip.op.next : ""; color: ip.t.dim; font.family: ip.t.font; font.pixelSize: ip.t.fsText }
          }
          Text {
            textFormat: Text.PlainText
            width: parent.width - ip.t.sp(40)
            anchors.horizontalCenter: parent.horizontalCenter
            horizontalAlignment: Text.AlignHCenter
            visible: !ip.p || !!ip.p.error
            text: !ip.p ? ip.app.tr("Loading…", "Carregando…") : ip.app.tr("Didn't load: ", "Não carregou: ") + ip.p.error
            wrapMode: Text.Wrap
            color: !ip.p ? ip.t.dim : ip.t.danger
            font.family: ip.t.font
            font.pixelSize: ip.t.fsText
          }
          Row {
            anchors.horizontalCenter: parent.horizontalCenter
            topPadding: ip.t.sp(12)
            spacing: ip.t.sp(12)
            // Someone picked in the conversation: a chat with them.
            Action {
              visible: ip.other
              icon: "chat"
              label: ip.app.tr("Message", "Conversar")
              onClicked: ip.wa.open(ip.chat)
            }
            Action {
              icon: "search"
              label: ip.app.tr("Search", "Pesquisar")
              onClicked: ip.win.infoView = "search"
            }
          }
        }
        Gap {}

        // A group's description, and when it was made.
        Column {
          width: parent.width
          visible: ip.group && !!ip.p && !ip.p.error
          leftPadding: ip.t.sp(30)
          rightPadding: ip.t.sp(30)
          topPadding: ip.t.sp(16)
          bottomPadding: ip.t.sp(16)
          spacing: ip.t.sp(6)
          Title { text: ip.app.tr("Description", "Descrição") }
          TextEdit {
            visible: !!ip.p && !!ip.p.about && ip.p.about.trim() !== ""
            width: parent.width - ip.t.sp(60)
            readOnly: true
            selectByMouse: true
            wrapMode: TextEdit.Wrap
            textFormat: TextEdit.RichText
            text: ip.group && ip.p && ip.p.about ? F.render(ip.p.about, { link: ip.t.html.link, mention: ip.t.html.mention, code: ip.t.html.code, codeBg: ip.t.html.codeBg, quote: ip.t.html.quote, quoteText: ip.t.html.quoteText }) : ""
            color: ip.t.text
            font.family: ip.t.font
            font.pixelSize: ip.t.fsName - 1
            onLinkActivated: url => ip.app.openUrl(url)
          }
          Text {
            textFormat: Text.PlainText
            visible: !ip.p || !ip.p.about || ip.p.about.trim() === ""
            text: ip.app.tr("No description", "Sem descrição")
            color: ip.t.faint
            font.family: ip.t.font
            font.pixelSize: ip.t.fsName - 1
          }
          Text {
            textFormat: Text.PlainText
            visible: !!ip.p && !!ip.p.created
            width: parent.width - ip.t.sp(60)
            wrapMode: Text.Wrap
            text: ip.p && ip.p.created ? ip.app.tr("Created ", "Criado ") + (ip.p.owner ? ip.app.tr("by " + ip.p.owner + " ", "por " + ip.p.owner + " ") : "")
                                         + ip.app.tr("on ", "em ") + U.shortDate(ip.p.created, ip.app.lang) + ip.app.tr(" at ", " às ") + U.clock(ip.p.created, ip.app.clock24) : ""
            color: ip.t.faint
            font.family: ip.t.font
            font.pixelSize: ip.t.fsSmall
          }
        }
        Gap { visible: ip.group && !!ip.p && !ip.p.error }

        // A business's details: what it does, its hours today (a click
        // opens the week), the address with Google Maps, e-mail, sites.
        Column {
          id: biz
          width: parent.width
          visible: !ip.group && !!ip.p && !!ip.p.biz
          leftPadding: ip.t.sp(30)
          rightPadding: ip.t.sp(30)
          topPadding: ip.t.sp(14)
          bottomPadding: ip.t.sp(14)
          spacing: ip.t.sp(10)
          readonly property real inner: width - leftPadding - rightPadding
          readonly property bool empty: !!ip.p && !ip.p.description && !ip.op && !ip.p.address && !ip.p.maps && !ip.p.email && !(ip.p.website && ip.p.website.length)
          Title { text: ip.app.tr("Business account", "Conta comercial"); icon: "info" }
          Text { textFormat: Text.PlainText; visible: !!ip.p && !!ip.p.description; width: biz.inner; text: ip.p ? ip.p.description || "" : ""; color: ip.t.text; font.family: ip.t.font; font.pixelSize: ip.t.fsText; wrapMode: Text.Wrap }
          Item {
            visible: !!ip.op
            width: biz.inner
            height: ip.t.sp(24)
            Text {
              textFormat: Text.PlainText
              anchors.verticalCenter: parent.verticalCenter
              text: !ip.op ? "" : ip.op.always ? ip.app.tr("Open 24 hours", "Aberta 24 horas") : ip.op.open ? ip.app.tr("Open now", "Aberta agora") : ip.app.tr("Closed now", "Fechada agora")
              color: ip.op && ip.op.open ? ip.t.online : ip.t.danger
              font.family: ip.t.font
              font.pixelSize: ip.t.fsText
            }
            Row {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: ip.t.sp(4)
              Text { textFormat: Text.PlainText; anchors.verticalCenter: parent.verticalCenter; text: ip.op && !ip.op.always ? H.dayHours(ip.p.hours, ip.op.day, ip.app.lang) : ""; color: ip.t.dim; font.family: ip.t.font; font.pixelSize: ip.t.fsText }
              Icon { anchors.verticalCenter: parent.verticalCenter; name: ip.week ? "chevronUp" : "chevronDown"; size: ip.t.sp(20); color: ip.t.dim }
            }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: ip.week = !ip.week }
          }
          Column {
            visible: !!ip.op && ip.week
            width: biz.inner
            spacing: ip.t.sp(4)
            Repeater {
              model: 7
              delegate: Item {
                id: day
                required property int index
                readonly property bool today: !!ip.op && ip.op.day === day.index
                width: parent.width
                height: ip.t.sp(20)
                Text { textFormat: Text.PlainText; text: H.dayName(day.index, ip.app.lang); color: day.today ? ip.t.text : ip.t.dim; font.family: ip.t.font; font.pixelSize: ip.t.fsText; font.weight: day.today ? Font.Medium : Font.Normal }
                Text { textFormat: Text.PlainText; anchors.right: parent.right; text: ip.p && ip.p.hours ? H.dayHours(ip.p.hours, day.index, ip.app.lang) : ""; color: day.today ? ip.t.text : ip.t.dim; font.family: ip.t.font; font.pixelSize: ip.t.fsText; font.weight: day.today ? Font.Medium : Font.Normal }
              }
            }
          }
          Column {
            visible: !!ip.p && (!!ip.p.address || !!ip.p.maps)
            width: biz.inner
            spacing: ip.t.sp(4)
            Text {
              textFormat: Text.PlainText
              visible: !!ip.p && !!ip.p.address
              width: parent.width
              text: ip.p ? (ip.p.address || "").trim() : ""
              color: ip.t.text
              font.family: ip.t.font
              font.pixelSize: ip.t.fsText
              wrapMode: Text.Wrap
              MouseArea { anchors.fill: parent; enabled: !!ip.p && !!ip.p.maps; cursorShape: Qt.PointingHandCursor; onClicked: ip.app.openUrl(ip.p.maps) }
            }
            Row {
              visible: !!ip.p && !!ip.p.maps
              spacing: ip.t.sp(4)
              Icon { anchors.verticalCenter: parent.verticalCenter; name: "location"; size: ip.t.sp(16); color: ip.t.link }
              Text {
                textFormat: Text.PlainText
                text: ip.app.tr("Open in Google Maps", "Abrir no Google Maps")
                color: ip.t.link
                font.family: ip.t.font
                font.pixelSize: ip.t.fsText
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: ip.app.openUrl(ip.p.maps) }
              }
            }
          }
          Text { textFormat: Text.PlainText; visible: !!ip.p && !!ip.p.email; text: ip.p ? ip.p.email || "" : ""; color: ip.t.link; font.family: ip.t.font; font.pixelSize: ip.t.fsText
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: ip.app.openMail(ip.p.email) } }
          Repeater {
            model: ip.p && ip.p.website ? ip.p.website : []
            delegate: Text { textFormat: Text.PlainText; required property var modelData; width: Math.min(implicitWidth, biz.inner); elide: Text.ElideRight; text: modelData; color: ip.t.link; font.family: ip.t.font; font.pixelSize: ip.t.fsText
              MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: ip.app.openUrl(/^https?:\/\//.test(modelData) ? modelData : "https://" + modelData) } }
          }
          Text { textFormat: Text.PlainText; visible: biz.empty; text: ip.app.tr("This is a business account.", "Esta é uma conta comercial."); color: ip.t.dim; font.family: ip.t.font; font.pixelSize: ip.t.fsText }
        }
        Gap { visible: biz.visible }

        // Their about.
        Column {
          id: about
          width: parent.width
          visible: !ip.group && !!ip.p && !!ip.p.about && ip.p.about.trim() !== ""
          leftPadding: ip.t.sp(30)
          rightPadding: ip.t.sp(30)
          topPadding: ip.t.sp(16)
          bottomPadding: ip.t.sp(16)
          spacing: ip.t.sp(6)
          Title { text: ip.app.tr("About", "Recado") }
          TextEdit {
            width: parent.width - ip.t.sp(60)
            readOnly: true
            selectByMouse: true
            wrapMode: TextEdit.Wrap
            textFormat: TextEdit.RichText
            text: !ip.group && ip.p && ip.p.about ? F.render(ip.p.about, { link: ip.t.html.link, mention: ip.t.html.mention, code: ip.t.html.code, codeBg: ip.t.html.codeBg, quote: ip.t.html.quote, quoteText: ip.t.html.quoteText }) : ""
            color: ip.t.text
            font.family: ip.t.font
            font.pixelSize: ip.t.fsName - 1
            onLinkActivated: url => ip.app.openUrl(url)
          }
        }
        Gap { visible: about.visible }

        Row2 {
          icon: "mediaGallery"
          label: ip.app.tr("Media, links and docs", "Mídia, links e docs")
          value: ip.p && ip.p.counts ? String((ip.p.counts.media || 0) + (ip.p.counts.docs || 0) + (ip.p.counts.links || 0)) : ""
          chevron: true
          onClicked: ip.win.infoView = "media"
        }
        Row2 {
          icon: "star"
          label: ip.app.tr("Starred messages", "Mensagens favoritas")
          value: ip.p && ip.p.starred ? String(ip.p.starred) : ""
          chevron: true
          onClicked: ip.win.openSide("starred")
        }
        Row2 {
          id: muteRow
          visible: !!ip.c
          readonly property bool muted: !!ip.wa.isMuted(ip.c)
          icon: muted ? "muted" : "bell"
          label: muted ? ip.app.tr("Unmute notifications", "Reativar notificações") : ip.app.tr("Mute notifications", "Silenciar notificações")
          onClicked: {
            if (muted) { ip.wa.chatAction(ip.chat, "unmute"); return }
            ip.win.menuAt(muteRow, [
              { label: ip.app.tr("8 hours", "8 horas"), action: function() { ip.wa.chatAction(ip.chat, "mute", 8 * 3600) } },
              { label: ip.app.tr("1 week", "1 semana"), action: function() { ip.wa.chatAction(ip.chat, "mute", 7 * 86400) } },
              { label: ip.app.tr("Always", "Sempre"), action: function() { ip.wa.chatAction(ip.chat, "mute", 0) } }
            ], ip.t.sp(70), height)
          }
        }
        Row2 {
          icon: "lock"
          label: ip.app.tr("Encryption", "Criptografia")
          value: ""
          onClicked: ip.win.toast(ip.app.tr("Messages are end-to-end encrypted.", "As mensagens são protegidas com a criptografia de ponta a ponta."))
        }
        Gap {}

        // A group's members, all of them: you first, then the admins; a
        // click opens a chat with one.
        Column {
          width: parent.width
          visible: ip.group && !!ip.p && !!ip.p.members
          Text {
            textFormat: Text.PlainText
            leftPadding: ip.t.sp(30)
            topPadding: ip.t.sp(16)
            bottomPadding: ip.t.sp(8)
            text: ip.p && ip.p.members ? ip.app.tr(ip.p.members.length + " members", ip.p.members.length + " membros") : ""
            color: ip.t.dim
            font.family: ip.t.font
            font.pixelSize: ip.t.fsText
          }
          Repeater {
            model: ip.group && ip.p && ip.p.members ? ip.p.members : []
            delegate: PersonRow {
              id: member
              required property var modelData
              readonly property string number: member.modelData.phone ? U.phone(member.modelData.phone) : ""
              app: ip.app
              jid: member.modelData.jid
              name: member.modelData.me ? ip.app.tr("You", "Você") : (member.modelData.name || member.number || U.phone(String(member.modelData.jid).split("@")[0]))
              // The number under a saved name; the name they set under a number.
              sub: member.modelData.me ? "" : (member.modelData.name ? member.number : (member.modelData.push ? "~" + member.modelData.push : ""))
              badge: member.modelData.admin ? ip.app.tr("Group admin", "Admin do grupo") : ""
              onClicked: if (!member.modelData.me) ip.wa.open(member.modelData.jid)
            }
          }
        }
        Gap { visible: ip.group && !!ip.p && !!ip.p.members }

        // Groups in common.
        Column {
          width: parent.width
          visible: !ip.group && !!ip.p && !!ip.p.common && ip.p.common.length > 0
          Text {
            textFormat: Text.PlainText
            leftPadding: ip.t.sp(30)
            topPadding: ip.t.sp(16)
            bottomPadding: ip.t.sp(8)
            text: ip.p && ip.p.common ? ip.app.tr(ip.p.common.length + " groups in common", ip.p.common.length + " grupos em comum") : ""
            color: ip.t.dim
            font.family: ip.t.font
            font.pixelSize: ip.t.fsText
          }
          Repeater {
            model: ip.p && ip.p.common ? ip.p.common : []
            delegate: PersonRow {
              required property var modelData
              app: ip.app
              jid: modelData.jid
              name: modelData.name
              group: true
              onClicked: ip.wa.open(modelData.jid)
            }
          }
        }
        Gap { visible: !ip.group && !!ip.p && !!ip.p.common && ip.p.common.length > 0 }

        Row2 { visible: !!ip.c; icon: "nosign"; label: ip.app.tr("Clear chat", "Limpar conversa"); danger: true; onClicked: ip.win.dialog("clearChat", { chat: ip.chat }) }
        Row2 { visible: !!ip.c; icon: "delete"; label: ip.app.tr("Delete chat", "Apagar conversa"); danger: true; onClicked: ip.win.dialog("deleteChat", { chat: ip.chat }) }
      }
    }
  }

  // ------------------------------------------------------------ search
  Component {
    id: searchC
    Item {
      SearchPill {
        id: sf
        x: ip.t.sp(14)
        width: parent.width - ip.t.sp(28)
        app: ip.app
        placeholder: ip.app.tr("Search…", "Pesquisar…")
        Component.onCompleted: sf.focusInput()
        onTextChanged: searchSoon.restart()
        onEscaped: ip.win.infoView = ""
      }
      Timer { id: searchSoon; interval: 250; onTriggered: if (sf.text.trim()) ip.wa.searchIn(ip.chat, sf.text.trim()); else ip.wa.chatSearch = null }
      readonly property var results: ip.wa.chatSearch && ip.wa.chatSearch.chat === ip.chat && ip.wa.chatSearch.query === sf.text.trim() ? ip.wa.chatSearch.messages : []
      ListView {
        y: sf.height + ip.t.sp(10)
        width: parent.width
        height: parent.height - y
        clip: true
        model: parent.results
        ScrollBar.vertical: ThinScroll { app: ip.app }
        delegate: Item {
          required property var modelData
          width: ListView.view.width
          height: ip.t.sp(70)
          Rectangle { anchors.fill: parent; anchors.leftMargin: ip.t.sp(10); anchors.rightMargin: ip.t.sp(10); radius: ip.t.sp(10); color: rma2.containsMouse ? ip.t.hover : "transparent" }
          Column {
            x: ip.t.sp(26)
            width: parent.width - ip.t.sp(52)
            anchors.verticalCenter: parent.verticalCenter
            spacing: ip.t.sp(3)
            Text { textFormat: Text.PlainText; text: U.listTime(modelData.ts, ip.app.lang, ip.app.clock24); color: ip.t.dim; font.family: ip.t.font; font.pixelSize: ip.t.fsSmall }
            Text {
              width: parent.width
              elide: Text.ElideRight
              textFormat: Text.StyledText
              color: ip.t.text
              font.family: ip.t.font
              font.pixelSize: ip.t.fsText
              text: (modelData.from_me ? "" : (ip.group && modelData.name ? F.esc(modelData.name.replace(/^~/, "")) + ": " : "")) + F.esc(F.plain(modelData.text, modelData.mentions))
            }
          }
          MouseArea { id: rma2; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ip.wa.open(ip.chat, { msg: modelData.id }) }
        }
        Text {
          textFormat: Text.PlainText
          anchors.centerIn: parent
          visible: parent.count === 0
          width: parent.width - ip.t.sp(60)
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.Wrap
          text: sf.text.trim() ? ip.app.tr("No messages found", "Nenhuma mensagem encontrada") : ip.app.tr("Search for messages with " + ip.wa.nameOf(ip.chat) + ".", "Pesquise mensagens com " + ip.wa.nameOf(ip.chat) + ".")
          color: ip.t.dim
          font.family: ip.t.font
          font.pixelSize: ip.t.fsText
        }
      }
    }
  }

  // ------------------------------------------------------------ media, links, docs
  Component {
    id: mediaC
    Item {
      id: mv
      property string tab: "media"
      Component.onCompleted: ip.wa.loadMediaList(ip.chat, "media")
      readonly property var items: ip.wa.mediaList && ip.wa.mediaList.chat === ip.chat && ip.wa.mediaList.kind === mv.tab ? ip.wa.mediaList.msgs : null
      Row {
        id: mtabs
        x: ip.t.sp(16)
        spacing: ip.t.sp(8)
        Repeater {
          model: [{ k: "media", l: ip.app.tr("Media", "Mídia") }, { k: "docs", l: ip.app.tr("Docs", "Docs") }, { k: "links", l: ip.app.tr("Links", "Links") }]
          delegate: Chip { required property var modelData; app: ip.app; label: modelData.l; on: mv.tab === modelData.k; onClicked: { mv.tab = modelData.k; ip.wa.loadMediaList(ip.chat, modelData.k) } }
        }
      }
      GridView {
        id: mgrid
        visible: mv.tab === "media"
        y: mtabs.height + ip.t.sp(12)
        x: ip.t.sp(12)
        width: parent.width - ip.t.sp(24)
        height: parent.height - y
        clip: true
        readonly property real cell: Math.floor(width / 3)
        cellWidth: cell
        cellHeight: cell
        model: mv.tab === "media" ? (mv.items || []) : []
        ScrollBar.vertical: ThinScroll { app: ip.app }
        delegate: Item {
          required property var modelData
          width: mgrid.cell; height: width
          Clip {
            anchors.fill: parent
            anchors.margins: ip.t.sp(2)
            radius: ip.t.sp(4)
            color: ip.t.alpha(ip.t.fg, 0.06)
            Image {
              anchors.fill: parent
              source: modelData.media ? U.fileUrl(modelData.kind === "image" && modelData.media.file ? modelData.media.file : modelData.media.thumb) : ""
              sourceSize.width: mgrid.cell * 2
              fillMode: Image.PreserveAspectCrop
              asynchronous: true
            }
            Icon { visible: modelData.kind !== "image"; anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: ip.t.sp(6); name: modelData.kind === "gif" ? "gif" : "videoFilled"; size: ip.t.sp(18); color: "white" }
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              if (modelData.kind === "image") ip.win.viewMedia(modelData)
              else ip.wa.whenDownloaded(modelData, function(path) { ip.app.playVideo(path, modelData.kind === "gif") })
            }
          }
        }
      }
      ListView {
        visible: mv.tab !== "media"
        y: mtabs.height + ip.t.sp(12)
        width: parent.width
        height: parent.height - y
        clip: true
        spacing: ip.t.sp(8)
        model: mv.tab !== "media" ? (mv.items || []) : []
        ScrollBar.vertical: ThinScroll { app: ip.app }
        delegate: Item {
          required property var modelData
          width: ListView.view.width
          height: mv.tab === "docs" ? doc.height + ip.t.sp(4) : linkCol.implicitHeight + ip.t.sp(16)
          DocumentCard { id: doc; visible: mv.tab === "docs"; x: ip.t.sp(16); app: ip.app; m: modelData; maxWidth: parent.width - ip.t.sp(32); width: parent.width - ip.t.sp(32) }
          Column {
            id: linkCol
            visible: mv.tab === "links"
            x: ip.t.sp(16)
            width: parent.width - ip.t.sp(32)
            spacing: ip.t.sp(4)
            readonly property string url: F.firstLink(modelData.text)
            Text { textFormat: Text.PlainText; width: parent.width; text: parent.url; color: ip.t.link; font.family: ip.t.font; font.pixelSize: ip.t.fsText; elide: Text.ElideRight
              MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: ip.app.openUrl(parent.parent.url) } }
            Text { textFormat: Text.PlainText; width: parent.width; text: F.plain(modelData.text); color: ip.t.dim; font.family: ip.t.font; font.pixelSize: ip.t.fsSmall + 1; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight }
          }
        }
      }
      BusyIndicator { anchors.centerIn: parent; running: mv.items === null; visible: running }
      Text {
        textFormat: Text.PlainText
        anchors.centerIn: parent
        visible: mv.items !== null && mv.items.length === 0
        text: mv.tab === "media" ? ip.app.tr("No media", "Nenhuma mídia") : mv.tab === "docs" ? ip.app.tr("No documents", "Nenhum documento") : ip.app.tr("No links", "Nenhum link")
        color: ip.t.dim
        font.family: ip.t.font
        font.pixelSize: ip.t.fsText
      }
    }
  }
}
