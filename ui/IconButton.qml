import QtQuick
import "../lib/Registry.js" as Reg

// A round button with an icon, as WhatsApp Web's headers have them; the
// tooltip shows on hover.
Item {
  id: b
  property var app: Reg.service
  readonly property var t: app.theme
  property string icon: ""
  property real iconSize: t.sp(24)
  property color color: t.icon
  property color hoverColor: t.hoverStrong
  property bool active: false
  property bool enabledState: true
  property string tip: ""
  property real rotationAngle: 0
  signal clicked(var mouse)
  signal pressed()

  implicitWidth: t.sp(40)
  implicitHeight: t.sp(40)
  opacity: enabledState ? 1 : 0.4

  Rectangle {
    anchors.fill: parent
    radius: width / 2
    color: b.active ? b.t.selected : (ma.pressed ? b.t.press : (ma.containsMouse ? b.hoverColor : "transparent"))
    Behavior on color { ColorAnimation { duration: 90 } }
  }
  Icon {
    anchors.centerIn: parent
    name: b.icon
    size: b.iconSize
    color: b.color
    rotation: b.rotationAngle
  }
  MouseArea {
    id: ma
    anchors.fill: parent
    hoverEnabled: true
    enabled: b.enabledState
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: Qt.PointingHandCursor
    onPressed: b.pressed()
    onClicked: mouse => b.clicked(mouse)
  }
  Tip { text: b.tip; shown: ma.containsMouse && b.tip !== "" }
}
