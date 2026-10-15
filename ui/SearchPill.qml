import QtQuick
import "../lib/Registry.js" as Reg

// WhatsApp Web's search pill: the magnifier (an arrow back while there's
// a query or focus), the placeholder, an ✕ to clear.
Rectangle {
  id: f
  property var app: Reg.service
  readonly property var t: app.theme
  property alias text: input.text
  property string placeholder: ""
  readonly property bool active: input.activeFocus || input.text.length > 0
  signal accepted()
  signal escaped()
  signal downPressed()
  function focusInput() { input.forceActiveFocus() }
  function clearText() { input.text = "" }

  height: t.sp(40)
  radius: height / 2
  color: t.field
  border.width: input.activeFocus ? 2 : 0
  border.color: t.accent

  IconButton {
    id: lead
    x: f.t.sp(6)
    anchors.verticalCenter: parent.verticalCenter
    implicitWidth: f.t.sp(30)
    implicitHeight: f.t.sp(30)
    icon: f.active ? "back" : "search"
    iconSize: f.t.sp(20)
    color: f.active ? f.t.accent : f.t.dim
    hoverColor: "transparent"
    onClicked: { if (f.active) { input.text = ""; input.focus = false; f.escaped() } else input.forceActiveFocus() }
  }
  TextInput {
    id: input
    anchors.left: lead.right
    anchors.leftMargin: f.t.sp(8)
    anchors.right: clearBtn.visible ? clearBtn.left : parent.right
    anchors.rightMargin: f.t.sp(10)
    anchors.verticalCenter: parent.verticalCenter
    color: f.t.text
    font.family: f.t.font
    font.pixelSize: f.t.fsText
    selectionColor: f.t.alpha(f.t.accent, 0.4)
    selectedTextColor: f.t.textBright
    clip: true
    Keys.onEscapePressed: { input.text = ""; input.focus = false; f.escaped() }
    Keys.onReturnPressed: f.accepted()
    Keys.onDownPressed: f.downPressed()
    Text {
      anchors.fill: parent
      verticalAlignment: Text.AlignVCenter
      visible: input.text.length === 0
      text: f.placeholder
      color: f.t.faint
      font: input.font
      elide: Text.ElideRight
    }
  }
  IconButton {
    id: clearBtn
    visible: input.text.length > 0
    anchors.right: parent.right
    anchors.rightMargin: f.t.sp(6)
    anchors.verticalCenter: parent.verticalCenter
    implicitWidth: f.t.sp(30)
    implicitHeight: f.t.sp(30)
    icon: "close"
    iconSize: f.t.sp(18)
    color: f.t.dim
    onClicked: { input.text = ""; input.forceActiveFocus() }
  }
}
