import QtQuick
import QtQuick.Controls
import "../lib/Util.js" as U
import "../lib/Registry.js" as Reg

// Linking the phone, as WhatsApp Web's sign-in page: the steps on the left,
// the QR code on the right (or the 8-letter code for "Log in with phone
// number"), and while the app gets ready the first time, what it's doing.
Rectangle {
  id: lv
  property var app: Reg.service
  readonly property var t: app.theme
  readonly property var wa: app.wa
  color: t.panel

  property bool phoneMode: false
  readonly property string build: wa.build
  readonly property bool waiting: build === "building" || (!wa.qr && !phoneMode)

  // ------------------------------------------------------------ brand
  Row {
    x: lv.t.sp(40)
    y: lv.t.sp(30)
    spacing: lv.t.sp(10)
    Image {
      source: Qt.resolvedUrl("../assets/whatsapp.svg")
      width: lv.t.sp(34); height: width
      sourceSize.width: 68; sourceSize.height: 68
      anchors.verticalCenter: parent.verticalCenter
    }
    Text {
      textFormat: Text.PlainText
      text: "WhatsApp"
      color: lv.t.accent
      font.family: lv.t.font
      font.pixelSize: lv.t.px(22)
      font.weight: Font.Bold
      anchors.verticalCenter: parent.verticalCenter
    }
  }

  // ------------------------------------------------------------ the card
  Rectangle {
    id: card
    anchors.centerIn: parent
    width: Math.min(parent.width - lv.t.sp(60), lv.t.sp(900))
    height: Math.max(lv.t.sp(440), content.implicitHeight + lv.t.sp(100))
    radius: lv.t.sp(24)
    color: lv.t.dark ? lv.t.mix(lv.t.bg, lv.t.fg, 0.04) : Qt.lighter(lv.t.bg, 1.03)
    border.width: 1
    border.color: lv.t.line

    Item {
      id: content
      anchors.fill: parent
      anchors.margins: lv.t.sp(50)
      implicitHeight: Math.max(steps.implicitHeight, qrSide.implicitHeight)

      // ---------------------------------------------------------- left
      Column {
        id: steps
        width: parent.width - qrSide.width - lv.t.sp(50)
        spacing: lv.t.sp(18)
        Text {
          textFormat: Text.PlainText
          width: parent.width
          text: lv.build === "building" ? lv.app.tr("Getting WhatsApp ready", "Preparando o WhatsApp")
              : lv.build === "failed" ? lv.app.tr("WhatsApp couldn't start", "Não foi possível iniciar o WhatsApp")
              : lv.phoneMode ? (lv.wa.pairCode ? lv.app.tr("Enter code on phone", "Digite o código no celular") : lv.app.tr("Enter phone number", "Insira o número de telefone"))
              : lv.app.tr("Steps to log in", "Etapas para entrar")
          color: lv.t.textBright
          font.family: lv.t.font
          font.pixelSize: lv.t.px(30)
          font.weight: Font.Light
          wrapMode: Text.Wrap
        }

        // Building, the first run.
        Column {
          visible: lv.build !== ""
          width: parent.width
          spacing: lv.t.sp(14)
          Text {
            textFormat: Text.PlainText
            width: parent.width
            wrapMode: Text.Wrap
            lineHeight: 1.3
            text: lv.build === "building"
              ? lv.app.tr("The first time, the WhatsApp bridge is compiled on this computer (Go comes through mise, already part of Omarchy). It takes a minute or two, and only happens again after an update.",
                          "Na primeira vez, o bridge do WhatsApp é compilado neste computador (o Go vem pelo mise, que já faz parte do Omarchy). Leva um ou dois minutos e só acontece de novo depois de uma atualização.")
              : lv.wa.bridge.buildError === "no_go"
                ? lv.app.tr("Neither mise nor Go were found. Install one of them and try again.", "Não encontrei o mise nem o Go. Instale um deles e tente de novo.")
                : lv.app.tr("The build failed. The log is in ", "A compilação falhou. O log está em ") + "~/.local/share/omawhats/bridge.log"
            color: lv.t.dim
            font.family: lv.t.font
            font.pixelSize: lv.t.fsName - 1
          }
          Rectangle {
            visible: lv.build === "failed"
            width: retryText.implicitWidth + lv.t.sp(40); height: lv.t.sp(40); radius: height / 2
            color: lv.t.accent
            Text { id: retryText; textFormat: Text.PlainText; anchors.centerIn: parent; text: lv.app.tr("Try again", "Tentar de novo"); color: lv.t.onBrand; font.family: lv.t.font; font.pixelSize: lv.t.fsText; font.weight: Font.Medium }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: lv.wa.bridge.retry() }
          }
        }

        // The steps, as WhatsApp words them.
        Column {
          visible: lv.build === ""
          width: parent.width
          spacing: lv.t.sp(16)
          Repeater {
            model: lv.phoneMode && lv.wa.pairCode
              ? [lv.app.tr("Open WhatsApp on your phone", "Abra o WhatsApp no seu celular"),
                 lv.app.tr("On Android tap Menu ⋮, on iPhone tap Settings ⚙", "No Android, toque em Mais opções ⋮. No iPhone, toque em Configurações ⚙"),
                 lv.app.tr("Tap Linked devices, then Link device", "Toque em Dispositivos conectados e, depois, em Conectar dispositivo"),
                 lv.app.tr("Tap Link with phone number instead and enter this code on your phone", "Toque em Conectar com número de telefone e insira este código no celular")]
              : lv.phoneMode
              ? [lv.app.tr("Select a country and enter your phone number, with the country code (55 for Brazil).", "Insira o número de telefone com o código do país (55 para o Brasil).")]
              : [lv.app.tr("Open WhatsApp on your phone", "Abra o WhatsApp no seu celular"),
                 lv.app.tr("On Android tap Menu ⋮, on iPhone tap Settings ⚙", "No Android, toque em Mais opções ⋮. No iPhone, toque em Configurações ⚙"),
                 lv.app.tr("Tap Linked devices, then Link device", "Toque em Dispositivos conectados e, depois, em Conectar dispositivo"),
                 lv.app.tr("Scan the QR code to confirm", "Escaneie o QR code para confirmar")]
            delegate: Row {
              required property var modelData
              required property int index
              width: steps.width
              spacing: lv.t.sp(14)
              Rectangle {
                visible: !lv.phoneMode || lv.wa.pairCode !== ""
                width: lv.t.sp(28); height: width; radius: width / 2
                color: "transparent"
                border.width: 1.5
                border.color: lv.t.dim
                Text { textFormat: Text.PlainText; anchors.centerIn: parent; text: index + 1; color: lv.t.text; font.family: lv.t.font; font.pixelSize: lv.t.fsText }
              }
              Text {
                textFormat: Text.PlainText
                width: parent.width - lv.t.sp(42)
                anchors.verticalCenter: parent.verticalCenter
                text: modelData
                color: lv.t.text
                font.family: lv.t.font
                font.pixelSize: lv.t.fsName
                wrapMode: Text.Wrap
              }
            }
          }
          Text {
            textFormat: Text.PlainText
            visible: lv.build === ""
            topPadding: lv.t.sp(10)
            text: (lv.phoneMode ? lv.app.tr("Log in with QR code", "Entrar com QR code") : lv.app.tr("Log in with phone number", "Entrar com número de telefone")) + "  ›"
            color: lv.t.accent
            font.family: lv.t.font
            font.pixelSize: lv.t.fsName
            font.underline: lma.containsMouse
            MouseArea {
              id: lma
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: { lv.phoneMode = !lv.phoneMode; lv.wa.pairCode = ""; lv.wa.pairError = "" }
            }
          }
        }
      }

      // ---------------------------------------------------------- right
      Item {
        id: qrSide
        anchors.right: parent.right
        width: lv.t.sp(280)
        implicitHeight: lv.t.sp(300)
        height: parent.height

        // Waiting (building, or the first code on its way).
        Column {
          anchors.centerIn: parent
          visible: lv.waiting && lv.build !== "failed"
          spacing: lv.t.sp(14)
          BusyIndicator { anchors.horizontalCenter: parent.horizontalCenter; running: parent.visible; width: lv.t.sp(48); height: width }
          Text {
            textFormat: Text.PlainText
            anchors.horizontalCenter: parent.horizontalCenter
            text: lv.build === "building" ? lv.app.tr("Compiling…", "Compilando…") : lv.app.tr("Loading…", "Carregando…")
            color: lv.t.dim
            font.family: lv.t.font
            font.pixelSize: lv.t.fsText
          }
        }

        // The QR code.
        Item {
          id: qrBox
          visible: !lv.phoneMode && !!lv.wa.qr && lv.build === ""
          anchors.centerIn: parent
          width: lv.t.sp(264); height: width
          Rectangle { anchors.fill: parent; anchors.margins: -lv.t.sp(12); radius: lv.t.sp(10); color: "white" }
          Canvas {
            id: qr
            anchors.fill: parent
            readonly property var rows: lv.wa.qr ? lv.wa.qr.rows : []
            onRowsChanged: requestPaint()
            onPaint: {
              var ctx = getContext("2d")
              ctx.reset()
              ctx.fillStyle = "white"
              ctx.fillRect(0, 0, width, height)
              var n = rows.length
              if (!n) return
              var cell = width / n
              ctx.fillStyle = "#122e31"
              for (var y = 0; y < n; y++) {
                var r = rows[y]
                for (var x = 0; x < r.length; x++) if (r.charCodeAt(x) === 49) ctx.fillRect(Math.floor(x * cell), Math.floor(y * cell), Math.ceil(cell), Math.ceil(cell))
              }
            }
          }
          Rectangle {
            anchors.centerIn: parent
            width: lv.t.sp(58); height: width; radius: width / 2
            color: "white"
            Image {
              anchors.centerIn: parent
              source: Qt.resolvedUrl("../assets/whatsapp.svg")
              width: lv.t.sp(46); height: width
              sourceSize.width: 92; sourceSize.height: 92
            }
          }
        }

        // The phone number, then the code.
        Column {
          visible: lv.phoneMode && lv.build === ""
          anchors.centerIn: parent
          width: parent.width
          spacing: lv.t.sp(16)
          Rectangle {
            visible: !lv.wa.pairCode
            width: parent.width
            height: lv.t.sp(48)
            radius: lv.t.sp(10)
            color: "transparent"
            border.width: 1.5
            border.color: phone.activeFocus ? lv.t.accent : lv.t.lineStrong
            TextInput {
              id: phone
              anchors.fill: parent
              anchors.leftMargin: lv.t.sp(14)
              anchors.rightMargin: lv.t.sp(14)
              verticalAlignment: TextInput.AlignVCenter
              color: lv.t.text
              font.family: lv.t.font
              font.pixelSize: lv.t.fsName
              inputMethodHints: Qt.ImhDialableCharactersOnly
              text: "+55 "
              Keys.onReturnPressed: lv.wa.pairPhone(phone.text)
            }
          }
          Rectangle {
            visible: !lv.wa.pairCode
            width: parent.width; height: lv.t.sp(44); radius: height / 2
            color: lv.t.accent
            Text { textFormat: Text.PlainText; anchors.centerIn: parent; text: lv.app.tr("Next", "Avançar"); color: lv.t.onBrand; font.family: lv.t.font; font.pixelSize: lv.t.fsText; font.weight: Font.Medium }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: lv.wa.pairPhone(phone.text) }
          }
          Text {
            textFormat: Text.PlainText
            visible: lv.wa.pairError !== ""
            width: parent.width
            wrapMode: Text.Wrap
            text: lv.wa.pairError
            color: lv.t.danger
            font.family: lv.t.font
            font.pixelSize: lv.t.fsSmall + 1
          }
          // The code, in WhatsApp's boxes.
          Row {
            visible: lv.wa.pairCode !== ""
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: lv.t.sp(5)
            Repeater {
              model: lv.wa.pairCode.split("")
              delegate: Item {
                required property var modelData
                width: modelData === "-" ? lv.t.sp(14) : lv.t.sp(30)
                height: lv.t.sp(44)
                Rectangle { visible: modelData !== "-"; anchors.fill: parent; radius: lv.t.sp(6); color: "transparent"; border.width: 1.5; border.color: lv.t.lineStrong }
                Text { textFormat: Text.PlainText; anchors.centerIn: parent; text: modelData; color: lv.t.textBright; font.family: lv.t.font; font.pixelSize: lv.t.px(22) }
              }
            }
          }
        }
      }
    }
  }

  Row {
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: lv.t.sp(30)
    spacing: lv.t.sp(6)
    Icon { name: "lock"; size: lv.t.sp(13); color: lv.t.faint; anchors.verticalCenter: parent.verticalCenter }
    Text {
      textFormat: Text.PlainText
      text: lv.app.tr("Your personal messages are end-to-end encrypted", "Suas mensagens pessoais são protegidas com a criptografia de ponta a ponta")
      color: lv.t.faint
      font.family: lv.t.font
      font.pixelSize: lv.t.fsSmall
    }
  }
}
