# omawhats

A whole WhatsApp client living inside the Omarchy shell, written as an Omarchy
plugin (QML, with a small Go bridge on [whatsmeow](https://github.com/tulir/whatsmeow)
for the network). The bar shows WhatsApp's mark with its badges; a click opens
the window: WhatsApp Web's layout (rail, chat list, conversation, contact info)
drawn in the current Omarchy theme's colors.

## Install

```sh
omarchy plugin add https://github.com/leonavas/omawhats --enable
```

Or from a checkout of your own:

```sh
git clone https://github.com/leonavas/omawhats
ln -s "$PWD/omawhats" ~/.config/omarchy/plugins/leonavas.whatsapp-claude
omarchy-shell shell rescanPlugins
omarchy plugin enable leonavas.whatsapp-claude --section right
```

Requirements: nothing beyond what Omarchy ships. The first start builds the
bridge with Go fetched through `mise` (a minute or two, once per version; no
cgo, so no C compiler). Audio plays through `mpv`, voice notes are recorded
with `ffmpeg`, and it uses `notify-send`, `wl-clipboard`, `zenity` (file
picker) and `xdg-open`.

## Link your phone

The window shows a QR code: on the phone, WhatsApp → Linked devices → Link a
device. Or pick **Log in with phone number**, type your number and enter the
code it shows on the phone. It appears there as "Omarchy", one more linked
device next to WhatsApp Web; the phone doesn't need to stay online.

Files:

- `~/.config/whatsapp-claude/settings.json`: settings and drafts.
- `~/.local/share/whatsapp-claude/`: the session (`session.db`), the message
  store (`app.db`), avatars, the built bridge and its log.
- `~/.cache/whatsapp-claude/`: downloaded media, stickers, pasted images,
  recordings.

Log out from Settings (or unlink it on the phone) to end the session.

## What's there

Chats with WhatsApp Web's filters (All, Unread, Favorites, Groups), archived
chats, pins, mutes and search across chats and messages; history synced from
the phone, with older messages fetched as you scroll; bubbles with their
tails, day chips and the unread band; text with WhatsApp's formatting, links
with previews and mentions; images, videos, GIFs, stickers, documents,
voice notes (waveform, 1.5×/2× speed), locations, contacts, polls and events;
replies, reactions, edits, delete for me or for everyone, forward, star; the
composer with emoji and stickers, attachments, pasted images, voice recording,
mentions and drafts; read receipts, typing and online status; contact and
group info with shared media, docs and links; starred messages; new chat by
contact or number; desktop notifications; keyboard shortcuts (Ctrl+/);
English and Portuguese; zoom (Ctrl+= / Ctrl+-).

## The bar

- **Icon.** WhatsApp's mark, Mono by default (Color or a glyph in the
  settings).
- **Badges.** Red at the bottom-right counts unread direct chats, blue at the
  top-right unread groups; muted and archived chats count in neither.
  "Group notifications" folds both into one badge.
- **Hover preview.** The unread chats with their newest messages. A click
  opens the chat.
- **Pause notifications** for 30 minutes, 1 hour, 8 hours or until tomorrow.
- **Scratchpad parking.** The window lives in a special workspace (Omarchy's
  scratchpad by default): a click shows it, another puts it away.

| Mouse | Action |
|---|---|
| Left click | Show the window, or put it away |
| Middle click | Close the window |
| Right click | The menu |
| Hover | Preview of what's unread |

IPC: `quickshell ipc -p $OMARCHY_PATH/shell call whatsapp-claude toggle`
(also `show`, `hide`, `open <jid>`, `pause <minutes>`, `resume`, `status`).

## Keyboard

| Keys | Action |
|---|---|
| Ctrl+K | Search |
| Ctrl+N | New chat |
| Alt+↑ / Alt+↓ | Previous / next chat |
| Ctrl+Alt+E | Archive |
| Ctrl+Alt+Shift+M / U / P | Mute / mark unread / pin |
| Ctrl+Alt+Shift+F | Search in the chat |
| Ctrl+Alt+I | Contact info |
| Ctrl+, | Settings |
| Ctrl+W | Hide the window |
| Ctrl+/ | All shortcuts |

## Notes

The window is Quickshell's (app id `org.quickshell`, shared by every window
of the shell), so docks and taskbars show Quickshell's icon for it.

Unofficial client, not affiliated with WhatsApp LLC or Meta Platforms, Inc.
Use it at your own risk: WhatsApp's terms don't allow third-party clients.
