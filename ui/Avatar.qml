import QtQuick
import "../lib/Util.js" as U
import "../lib/Registry.js" as Reg

// A round profile picture: the photo once it's here, else the initials in
// a color of the palette (as WhatsApp now draws them), a group's or a
// person's silhouette when there's no name to take them from.
Item {
  id: av
  property var app: Reg.service
  readonly property var t: app.theme
  property string jid: ""
  property string name: ""
  property bool group: false
  property real size: t.avatar
  // A photo given directly (the info panel's full-size one).
  property string source: ""
  readonly property string photo: av.source !== "" ? av.source : (av.jid ? av.app.wa.avatar(av.jid) : "")
  readonly property string letters: av.group ? "" : U.initials(av.name)
  readonly property var colors: av.t.avatarColors(av.jid || av.name)

  width: size
  height: size

  Rectangle {
    anchors.fill: parent
    radius: width / 2
    color: av.colors.bg
    visible: img.status !== Image.Ready
    Text {
      anchors.centerIn: parent
      visible: av.letters !== ""
      text: av.letters
      color: av.colors.fg
      font.family: av.t.font
      font.pixelSize: Math.round(av.size * (av.letters.length > 1 ? 0.36 : 0.42))
      font.weight: Font.Medium
    }
    Icon {
      anchors.centerIn: parent
      visible: av.letters === ""
      name: av.group ? "groupFilled" : "personFilled"
      size: av.size * 0.58
      color: av.colors.fg
    }
  }
  Clip {
    anchors.fill: parent
    radius: width / 2
    visible: img.status === Image.Ready
    Image {
      id: img
      anchors.fill: parent
      source: av.photo
      sourceSize.width: Math.ceil(av.size * 2)
      sourceSize.height: Math.ceil(av.size * 2)
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      cache: true
      smooth: true
      mipmap: true
    }
  }
}
