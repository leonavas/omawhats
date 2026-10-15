import QtQuick
import "../lib/Registry.js" as Reg

// The ticks of a message you sent: a clock while it goes, one tick sent,
// two delivered, two in the read color once read (or played); a red mark
// when it failed.
Icon {
  id: tk
  property var app: Reg.service
  readonly property var t: app.theme
  property int status: 0
  property color base: t.dim
  property bool overMedia: false
  name: status < 0 ? "error" : status === 0 ? "pending" : status === 1 ? "sent" : "ticks"
  color: status < 0 ? t.danger : (status >= 3 ? t.read : (overMedia ? "white" : base))
  size: status === 0 ? t.sp(15) : t.sp(18)
}
