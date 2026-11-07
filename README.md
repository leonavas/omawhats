<p align="center">
  <img src="preview.webp" alt="Omawhats: WhatsApp inside the Omarchy shell">
</p>

# Omawhats

WhatsApp inside the [Omarchy](https://omarchy.org) shell. A native QML window
laid out like WhatsApp Web and drawn in your current theme's colors, plus a
bar icon with unread badges, a hover preview and desktop notifications. It
links to your phone as one more device through a small Go bridge on
[whatsmeow](https://github.com/tulir/whatsmeow). No browser, no Electron.

> **This is the app I use everyday for both my personal and professional use,
> so every little detail I see out of tune, expect a fix.**

## Install

```sh
omarchy plugin add https://github.com/leonavas/omawhats --enable
```

Click the bar icon, then on your phone go to **WhatsApp → Linked devices →
Link a device** and scan the QR code (or pick **Log in with phone number**).
Your phone doesn't need to stay online afterwards.

There's nothing else to set up. The first start builds the bridge from the
source in this repo, with Go fetched through `mise`, which ships with
Omarchy: about a minute and some 700 MB of downloads the first time (Go
itself and the bridge's modules, pinned by `go.sum`), and only a quick
rebuild after an update. Everything else it uses (`mpv`, `ffmpeg`,
`wl-clipboard`, `xdg-open`, `omarchy-file-select`) comes with Omarchy too.

Installed before 0.2.0, as `leonavas.whatsapp-claude`? Reinstall once instead
of updating; your settings and the session move over on their own:

```sh
omarchy plugin remove leonavas.whatsapp-claude && omarchy plugin add https://github.com/leonavas/omawhats --enable
```

## Screenshots

| | |
|---|---|
| ![Conversation](docs/screenshots/conversation.webp) **Chats**: media, replies, voice notes, link previews, documents, reactions | ![Group](docs/screenshots/group.webp) **Groups**: mentions, polls, the unread band |
| ![Contact info](docs/screenshots/info.webp) **Contact info**: about, groups in common, mute | ![Media](docs/screenshots/media.webp) **Shared media**, docs and links |
| ![Emoji](docs/screenshots/emoji.webp) **Emoji and stickers** panel | ![Message menu](docs/screenshots/menu.webp) **Message actions** and quick reactions |
| ![Settings](docs/screenshots/settings.webp) **Settings** | ![Account menu](docs/screenshots/account.webp) **Your menu** (Alt+S): profile, pause notifications, updates |
| ![Bar preview](docs/screenshots/bar-preview.webp) **The bar**: badges and a preview of what's unread | ![Shortcuts](docs/screenshots/shortcuts.webp) **Keyboard-first** (Ctrl+/) |

## Features

- Chats with WhatsApp Web's filters (All, Unread, Favorites, Groups),
  archived chats, pins, mutes, and search across chats and messages.
- History synced from the phone; older messages load as you scroll.
- Images, videos, GIFs, stickers, documents, voice notes (waveform, 1.5×/2×),
  locations, contacts, polls and events.
- Replies, reactions, edits, delete for everyone, forward, star; read
  receipts, typing and online status.
- A composer with formatting, emoji and stickers, attachments, pasted
  images, voice recording, mentions (@everyone too) and drafts.
- Contact and group info, business profiles with opening hours, and your own
  profile (name, about, photo).
- English and Portuguese; zoom with Ctrl+= / Ctrl+-.

## The bar

- **Badges**: red for unread direct chats, blue for groups. Muted and
  archived chats count in neither. "Group notifications" folds them into one.
- **Hover** shows the unread chats with their newest messages; a click opens
  the chat, a middle click marks it read.
- **Notifications** for new messages, except in muted chats, while paused, or
  for the chat on screen. Pause them for 30 minutes up to a chosen date.
- **Scratchpad parking**: the window lives in a special workspace (Omarchy's
  scratchpad by default). A click shows it, another puts it away, and
  WhatsApp keeps running.

Left click shows or hides the window, middle click quits WhatsApp, right
click opens the menu. Every option is in the widget's settings.

## Updates

Every six hours the app reads `manifest.json` on this repo's `main` branch
(a plain `curl`, nothing of yours is sent). When there's a new version, a
notice offers a one-click update (`omarchy plugin update`). Turn the check
off in Settings.

## Files

All of them only yours (folders `0700`, files `0600`):

- `~/.config/omawhats/settings.json`: settings and drafts, separated by linked account.
- `~/.local/share/omawhats/`: the session, the message store, avatars,
  the built bridge and its log.
- `~/.cache/omawhats/`: downloaded media, and Go's module and build caches
  for the bridge (`go/`). Media not seen in 7 days goes; over 900 MB, the
  Go build cache goes, then the media seen longest ago.
- Go itself, which `mise` keeps in `~/.local/share/mise/installs/go/`.

Log out from Settings (or unlink the device on your phone) to end the
session. Your messages only travel between your machine and WhatsApp.
Location previews use the thumbnail included in the message, without requesting
map tiles from a third party. Clicking a location opens its link in your browser.

Messages with an expiration deadline are hidden when it passes; the bridge
removes their local content, media keys and cached files while running and on
startup. Older media timers are recovered where the original metadata remains.
Older text messages whose timer was never stored cannot be expired retroactively
without a fresh history sync containing that metadata. Copies you explicitly
save, forward or favorite are separate from this cleanup; it is not a guarantee
of forensic erasure or removal from backups.

Logging out clears that account's drafts. On upgrade, legacy drafts without an
account identifier are discarded because their owner cannot be established.

## Remove

Log out first (Settings → Log out), so your phone drops the linked device;
otherwise remove it on the phone under **Linked devices**. Then:

```sh
omarchy plugin remove leonavas.omawhats
```

That removes the plugin and leaves your data. To remove the session,
messages, media and settings too:

```sh
rm -rf ~/.config/omawhats ~/.local/share/omawhats ~/.cache/omawhats
```

And the Go that `mise` fetched for the build, if nothing else of yours uses
it: `mise uninstall go@1.27.2`.

## Development

Link a clone of this repo into Omarchy's plugin folder, from the folder
that holds it:

```sh
ln -s "$PWD/omawhats" ~/.config/omarchy/plugins/leonavas.omawhats
omarchy-shell shell rescanPlugins
omarchy plugin enable leonavas.omawhats --section right
```

The shell caches plugin QML, so reload edits with `omarchy-restart-shell`.
IPC: `omarchy-shell omawhats toggle` (also `show`, `hide`,
`open <jid>`, `pause <minutes>`, `resume`, `status`).

### While the marketplace review is open

Omawhats is under review at
[omacom/omarchy-plugin-marketplace#11728](https://github.com/omacom/omarchy-plugin-marketplace/issues/11728).
Each push to `main` moves the HEAD the reviewer looks at, so until the
plugin is listed:

- New features and improvements go to a branch, not `main`.
- `main` gets only fixes for the reviewer's findings, each answered in the
  issue with its commit.
- Once it's listed, merge the branch and release as usual.

## Disclaimer

Unofficial client, not affiliated with WhatsApp LLC or Meta Platforms, Inc.
WhatsApp's terms don't allow third-party clients: use it at your own risk.

Screenshots show made-up people and chats. Avatars are
[DiceBear Notionists](https://www.dicebear.com/styles/notionists/) (CC0);
photos are from [Unsplash](https://unsplash.com) via
[Lorem Picsum](https://picsum.photos).
