import QtQuick
import "../lib/Icons.js" as Icons

// One of WhatsApp's icons, drawn in `color` at `size` px.
Image {
  id: ic
  property string name: ""
  property color color: "white"
  property real size: 24
  width: size
  height: size
  sourceSize.width: Math.ceil(size * 2)
  sourceSize.height: Math.ceil(size * 2)
  fillMode: Image.PreserveAspectFit
  smooth: true
  mipmap: true
  asynchronous: false
  source: name ? Icons.url(name, String(color)) : ""
}
