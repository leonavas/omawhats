import QtQuick
import "../lib/Registry.js" as Reg

// The side panel: the chat list, or one of the views that slide over it
// (archived, new chat, settings, your profile, starred messages), each
// with WhatsApp Web's back arrow.
Rectangle {
  id: side
  property var app: Reg.service
  property var win
  readonly property var t: app.theme
  color: t.panel
  clip: true

  function focusSearch() { if (chats.item && chats.item.focusSearch) chats.item.focusSearch() }

  Loader {
    id: chats
    anchors.fill: parent
    sourceComponent: ChatsView { app: side.app; win: side.win; archived: false }
  }

  // The views over the list slide in from the left, as WhatsApp Web's drawers.
  // Opaque, so the list under it doesn't show through.
  Rectangle {
    id: drawer
    width: parent.width
    height: parent.height
    color: side.t.panel
    readonly property string view: side.win.sideView
    readonly property bool open: view !== "chats"
    visible: open || x > -width
    x: open ? 0 : -width
    Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    Loader {
      id: over
      anchors.fill: parent
      active: drawer.open
      sourceComponent: drawer.view === "archived" ? archivedC
                     : drawer.view === "newchat" ? newChatC
                     : drawer.view === "settings" ? settingsC
                     : drawer.view === "profile" ? profileC
                     : drawer.view === "starred" ? starredC : null
    }
  }
  Component { id: archivedC; ChatsView { app: side.app; win: side.win; archived: true } }
  Component { id: newChatC; NewChatView { app: side.app; win: side.win } }
  Component { id: settingsC; SettingsView { app: side.app; win: side.win } }
  Component { id: profileC; ProfileView { app: side.app; win: side.win } }
  Component { id: starredC; StarredView { app: side.app; win: side.win } }
}
