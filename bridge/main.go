// omawhats-bridge: the WhatsApp side of the Omarchy WhatsApp app
// (leonavas.omawhats). It speaks WhatsApp's multi-device protocol
// through whatsmeow, as one more linked device, and talks to the app over
// JSON lines: events on stdout, commands on stdin. Logs go to stderr.
//
// Usage: omawhats-bridge <data dir> <cache dir>
package main

import (
	"bufio"
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"sync/atomic"
	"time"

	"github.com/rs/zerolog"
	"go.mau.fi/whatsmeow"
	"go.mau.fi/whatsmeow/proto/waCompanionReg"
	"go.mau.fi/whatsmeow/proto/waE2E"
	"go.mau.fi/whatsmeow/store"
	"go.mau.fi/whatsmeow/store/sqlstore"
	"go.mau.fi/whatsmeow/types"
	"go.mau.fi/whatsmeow/types/events"
	waLog "go.mau.fi/whatsmeow/util/log"
	_ "modernc.org/sqlite"
)

// Msg is one message as the app draws it.
type Msg struct {
	Chat   string `json:"chat"`
	ID     string `json:"id"`
	Sender string `json:"sender"`
	// Who wrote it, as the chat shows them: "" for you, the contact's
	// name, "~push name" for people you haven't saved, else the number.
	Name   string `json:"name"`
	FromMe bool   `json:"from_me"`
	TS     int64  `json:"ts"`
	// text, image, video, gif, ptv, audio, ptt, document, sticker,
	// location, live_location, contact, poll, event, invite, call, card,
	// system, revoked, view_once, placeholder, unsupported.
	Kind   string `json:"kind"`
	Text   string `json:"text,omitempty"`
	Edited bool   `json:"edited,omitempty"`
	// 0 pending, 1 sent, 2 delivered, 3 read, 4 played; -1 failed.
	Status int `json:"status"`
	// Forwarded, how many times over (WhatsApp's forwarding score); 0 when not.
	Forwarded int        `json:"fwd,omitempty"`
	Starred   bool       `json:"star,omitempty"`
	Quote     *Quote     `json:"quote,omitempty"`
	Mentions  []Mention  `json:"mentions,omitempty"`
	Reactions []Reaction `json:"reactions,omitempty"`
	Media     *Media     `json:"media,omitempty"`
	// What the kind has besides text: link, loc, contacts, poll, event,
	// invite, call, sys, of (a view-once's kind).
	X    json.RawMessage `json:"x,omitempty"`
	Card *Card           `json:"card,omitempty"`
	// Stored just now, not a new version of one we had.
	fresh bool
	// Its media's part, for the picture once it's shown.
	part *waE2E.Message
}

// Quote is the message a reply answers, as its bubble shows it.
type Quote struct {
	ID    string `json:"id"`
	From  string `json:"from"`
	Name  string `json:"name"`
	Kind  string `json:"kind"`
	Text  string `json:"text,omitempty"`
	Thumb string `json:"thumb,omitempty"`
}

// Chat is one row of the chat list.
type Chat struct {
	JID  string `json:"jid"`
	Name string `json:"name"`
	// user, group, self (your own number), official (WhatsApp's).
	Kind   string `json:"kind"`
	Phone  string `json:"phone,omitempty"`
	TS     int64  `json:"ts"`
	Unread int    `json:"unread"`
	// Marked as unread by hand: its one unread may be no message at all.
	Marked bool `json:"marked,omitempty"`
	// When it was pinned: the newest pin comes first; 0 when it isn't.
	Pin      int64 `json:"pin,omitempty"`
	Archived bool  `json:"archived,omitempty"`
	// Muted until (unix seconds); -1 forever; 0 when it isn't.
	Mute     int64 `json:"mute,omitempty"`
	Favorite int64 `json:"fav,omitempty"`
	// Why nothing can be sent here: official, admins, left, cant; empty when it can.
	ReadOnly string `json:"ro,omitempty"`
	// WhatsApp itself, or a business with WhatsApp's check by its name.
	Verified bool  `json:"verified,omitempty"`
	Last     *Last `json:"last,omitempty"`
}

// Last is a chat's newest message, for its row.
type Last struct {
	ID     string `json:"id"`
	FromMe bool   `json:"from_me"`
	Status int    `json:"status"`
	Kind   string `json:"kind"`
	Text   string `json:"text,omitempty"`
	// Who wrote it, in a group: the name its messages show.
	Who     string          `json:"who,omitempty"`
	Seconds uint32          `json:"secs,omitempty"`
	Name    string          `json:"file,omitempty"`
	X       json.RawMessage `json:"x,omitempty"`
}

type Cmd struct {
	C     string `json:"c"`
	Chat  string `json:"chat"`
	Text  string `json:"text"`
	Limit int    `json:"limit"`
	// download: the message whose media to fetch; Auto when nobody
	// clicked (a photo shown), so the phone isn't asked for it.
	ID   string `json:"id"`
	Auto bool   `json:"auto"`
	// send_file: a file on disk, its name as sent, and what it goes as
	// (image, video, audio, ptt, document, sticker); Temp ones are removed
	// once sent.
	Path    string `json:"path"`
	Name    string `json:"name"`
	Caption string `json:"caption"`
	Kind    string `json:"kind"`
	Temp    bool   `json:"temp"`
	// read: without read receipts, only your other devices hear of it.
	Quiet bool `json:"quiet"`
	// chat_action: archive, unarchive, pin, unpin, read, unread, mute
	// (for Secs, 0 is forever), unmute, favorite, unfavorite, clear, delete.
	// sticker_fav: favorite or unfavorite; neither only asks.
	Action string `json:"action"`
	Secs   int64  `json:"secs"`
	// delete_msgs, star: the messages; delete for everyone or for you only.
	IDs      []string `json:"ids"`
	Everyone bool     `json:"everyone"`
	// forward: the chats the messages (IDs, of Chat) go to.
	To []string `json:"to"`
	// send, send_file: the message it replies to, if any.
	Reply string `json:"reply"`
	// history: the page before this message (its time and id); none for the newest.
	Before   int64  `json:"before"`
	BeforeID string `json:"before_id"`
	// play: where to start, in seconds, and how fast.
	Pos   float64 `json:"pos"`
	Speed float64 `json:"speed"`
	// typing: composing, recording or paused; presence: available or unavailable.
	State string `json:"state"`
	// pair_phone: the number to link with a code instead of the QR.
	Phone string `json:"phone"`
	// send_sticker: the chat a recent sticker came in (with ID), or Name,
	// a favorite's hash.
	From string `json:"from"`
	// notify: a desktop notification (its body is Text).
	Title string `json:"title"`
	App   string `json:"app"`
	Icon  string `json:"icon"`
	Exec  string `json:"exec"`
}

var (
	outMu sync.Mutex
	enc   = json.NewEncoder(os.Stdout)
)

func emit(v map[string]any) {
	outMu.Lock()
	defer outMu.Unlock()
	_ = enc.Encode(v)
}

// fail is an error the app shows: a code it words, and the detail.
func fail(code string, err error) {
	detail := ""
	if err != nil {
		detail = err.Error()
	}
	emit(map[string]any{"t": "error", "code": code, "text": detail})
}

// stderrLog is whatsmeow's logger, on stderr: stdout belongs to the protocol.
type stderrLog struct {
	mod string
	min int
}

var levels = map[string]int{"DEBUG": 0, "INFO": 1, "WARN": 2, "ERROR": 3}

func (l stderrLog) log(lvl, msg string, args ...any) {
	if levels[lvl] < l.min {
		return
	}
	fmt.Fprintf(os.Stderr, "%s [%s %s] %s\n", time.Now().Format("15:04:05.000"), l.mod, lvl, fmt.Sprintf(msg, args...))
}
func (l stderrLog) Debugf(m string, a ...any)   { l.log("DEBUG", m, a...) }
func (l stderrLog) Infof(m string, a ...any)    { l.log("INFO", m, a...) }
func (l stderrLog) Warnf(m string, a ...any)    { l.log("WARN", m, a...) }
func (l stderrLog) Errorf(m string, a ...any)   { l.log("ERROR", m, a...) }
func (l stderrLog) Sub(mod string) waLog.Logger { return stderrLog{l.mod + "/" + mod, l.min} }
func newLog(mod string, min string) stderrLog   { return stderrLog{mod, levels[min]} }

type Bridge struct {
	cli     *whatsmeow.Client
	db      *sql.DB
	ctx     context.Context
	dir     string
	dirty   atomic.Bool
	avatars chan avatarReq
	// Chat actions, one at a time and in order: a pin and its undo can't swap.
	actions chan Cmd
	// The chats as last sent, by JID: only the ones that change go again.
	sentMu sync.Mutex
	sent   map[string]string
	full   atomic.Bool
	// Whether the app's window is in front: WhatsApp then counts you as
	// online, as it does WhatsApp Web's tab.
	online atomic.Bool
}

type avatarReq struct {
	jid   string
	force bool
}

// Where nothing can be sent, and why: the app words it.
const (
	officialOnly = "official"
	adminsOnly   = "admins"
	notMember    = "left"
	cantSend     = "cant"
)

// cacheRoot is where media and pictures go (the second argument).
var cacheRoot string

func main() {
	if len(os.Args) < 3 {
		fmt.Fprintln(os.Stderr, "usage: omawhats-bridge <data dir> <cache dir>")
		os.Exit(2)
	}
	dir := os.Args[1]
	cacheRoot = os.Args[2]
	for _, d := range []string{dir, cacheRoot, mediaDir(), filepath.Join(dir, "avatars")} {
		if err := os.MkdirAll(d, 0o700); err != nil {
			fatal(err)
		}
	}
	ctx := context.Background()
	emit(map[string]any{"t": "state", "state": "starting"})

	// How the phone lists it under Linked devices: the name, and a computer
	// icon. Read only when pairing.
	store.SetOSInfo("Omarchy", [3]uint32{0, 1, 0})
	store.DeviceProps.PlatformType = waCompanionReg.DeviceProps_DESKTOP.Enum()
	container, err := sqlstore.New(ctx, "sqlite", "file:"+filepath.Join(dir, "session.db")+"?_pragma=foreign_keys(1)&_pragma=busy_timeout(5000)&_pragma=journal_mode(WAL)", newLog("db", "WARN"))
	if err != nil {
		fatal(err)
	}
	device, err := container.GetFirstDevice(ctx)
	if err != nil {
		fatal(err)
	}
	db, err := sql.Open("sqlite", "file:"+filepath.Join(dir, "app.db")+"?_pragma=busy_timeout(5000)&_pragma=journal_mode(WAL)&_pragma=synchronous(NORMAL)")
	if err != nil {
		fatal(err)
	}
	if _, err := db.Exec(schema); err != nil {
		fatal(err)
	}
	migrate(db)

	b := &Bridge{cli: whatsmeow.NewClient(device, newLog("wa", "INFO")), db: db, dir: dir,
		avatars: make(chan avatarReq, 4096), actions: make(chan Cmd, 64), sent: map[string]string{}}
	// whatsmeow's context logger, for the favorites' version (see favLog).
	b.ctx = zerolog.New(favLog{b}).Level(zerolog.DebugLevel).WithContext(ctx)
	b.cli.BackgroundEventCtx = b.ctx
	b.cli.AppStateDebugLogs = true
	// Pins, archives, mutes and favorites also from the first full sync, not
	// only from the changes after it.
	b.cli.EmitAppStateEventsOnFullSync = true
	// What a device couldn't decrypt, asked of the phone, as WhatsApp Web does.
	b.cli.AutomaticMessageRerequestFromPhone = true
	b.cli.AddEventHandler(b.handle)
	if b.cli.Store.ID == nil {
		b.wipe()
	}
	go b.flushChats()
	go b.sweep()
	go b.chatActions()
	for range 3 {
		go b.fetchAvatars()
	}
	b.full.Store(true)
	b.dirty.Store(true)

	if b.cli.Store.ID == nil {
		go b.pair()
	} else {
		emit(map[string]any{"t": "state", "state": "connecting", "me": b.meInfo()})
		if err := b.cli.Connect(); err != nil {
			fail("connect", err)
		}
	}
	b.commands()
}

func fatal(err error) {
	emit(map[string]any{"t": "error", "code": "fatal", "text": err.Error(), "fatal": true})
	os.Exit(1)
}

// meInfo is who's linked: the number, the name and the hidden id.
func (b *Bridge) meInfo() map[string]any {
	if b.cli.Store.ID == nil {
		return nil
	}
	// A business account's name is its business name, which only the phone
	// changes (WhatsApp Web Business shows it read-only).
	return map[string]any{"jid": b.me().String(), "phone": b.me().User, "name": b.cli.Store.PushName, "lid": b.cli.Store.GetLID().ToNonAD().String(),
		"business": b.cli.Store.BusinessName != "", "businessName": b.cli.Store.BusinessName}
}

func (b *Bridge) commands() {
	in := bufio.NewScanner(os.Stdin)
	in.Buffer(make([]byte, 1<<20), 16<<20)
	for in.Scan() {
		var c Cmd
		if err := json.Unmarshal(in.Bytes(), &c); err != nil {
			continue
		}
		switch c.C {
		case "chats":
			// Everything again: the app (re)started.
			b.full.Store(true)
			b.dirty.Store(true)
		case "history":
			go b.history(c)
		case "older":
			go b.older(c.Chat)
		case "unread":
			go b.unread(c.Chat, c.Limit)
		case "send":
			go b.send(c)
		case "react":
			go b.sendReaction(c.Chat, c.ID, c.Text)
		case "edit":
			go b.edit(c.Chat, c.ID, c.Text)
		case "delete_msgs":
			go b.deleteMsgs(c.Chat, c.IDs, c.Everyone)
		case "star":
			go b.star(c.Chat, c.IDs, c.Action != "unstar")
		case "send_file":
			b.sendFile(c)
		case "read":
			go b.markRead(c.Chat, c.Quiet, false)
		case "chat_action":
			b.actions <- c
		case "search":
			go b.search(c.Text, c.Chat)
		case "media_list":
			go b.mediaList(c.Chat, c.Kind)
		case "contacts":
			go b.contactList()
		case "starred":
			go func() {
				ms := b.query(`WHERE starred = 1 ORDER BY ts DESC LIMIT 300`)
				if ms == nil {
					ms = []Msg{}
				}
				emit(map[string]any{"t": "starred", "msgs": ms})
			}()
		case "profile":
			go b.profile(c.Chat)
		case "set_name":
			go b.setName(c.Text)
		case "set_about":
			go b.setAbout(c.Text)
		case "set_photo":
			go b.setPhoto(c.Text)
		case "avatar":
			select {
			case b.avatars <- avatarReq{jid: c.Chat}:
			default:
			}
		case "subscribe":
			go b.subscribe(c.Chat)
		case "typing":
			go b.typing(c.Chat, c.State)
		case "presence":
			go b.setPresence(c.State == "available")
		case "sticker_fav":
			b.actions <- c
		case "stickers":
			go b.stickerList()
		case "send_sticker":
			go b.sendSticker(c)
		case "forward":
			go b.forward(c.Chat, c.IDs, c.To)
		case "chat_subs":
			go b.chatSubs()
		case "download":
			go b.download(c.Chat, c.ID, c.Auto)
		case "play", "pause", "resume", "seek", "speed", "stop":
			player.command(c)
			if c.C == "play" {
				go b.markPlayed(c.Chat, c.ID)
			}
		case "pair_phone":
			go b.pairPhone(c.Phone)
		case "notify":
			go notify(c)
		case "logout":
			// Unlinks this device on the phone too; offline, nothing changes.
			if err := b.cli.Logout(b.ctx); err != nil {
				fail("logout", err)
				continue
			}
			b.wipe()
			emit(map[string]any{"t": "state", "state": "logged_out"})
			player.quit()
			os.Exit(0)
		}
	}
	// The app went away.
	player.quit()
	b.cli.Disconnect()
}

func (b *Bridge) handle(raw any) {
	switch e := raw.(type) {
	case *events.Connected:
		emit(map[string]any{"t": "state", "state": "ready", "me": b.meInfo()})
		// Online only while the window is in front, as WhatsApp Web's tab:
		// the phone keeps notifying while you're elsewhere. Either way the
		// server learns your name from it.
		go b.setPresence(b.online.Load())
		go b.syncGroups()
		go b.resyncOnce()
		go b.stickersOnce()
		go b.bizNamesOnce()
		select {
		case b.avatars <- avatarReq{jid: b.me().String()}:
		default:
		}
	case *events.Disconnected:
		emit(map[string]any{"t": "state", "state": "offline"})
	case *events.KeepAliveTimeout:
		emit(map[string]any{"t": "state", "state": "offline"})
	case *events.KeepAliveRestored:
		emit(map[string]any{"t": "state", "state": "ready", "me": b.meInfo()})
	case *events.StreamReplaced:
		emit(map[string]any{"t": "state", "state": "replaced"})
	case *events.LoggedOut:
		_ = b.cli.Store.Delete(b.ctx)
		b.wipe()
		emit(map[string]any{"t": "state", "state": "logged_out"})
		player.quit()
		os.Exit(0)
	case *events.OfflineSyncPreview:
		emit(map[string]any{"t": "offline_sync", "total": e.Total, "done": false})
	case *events.OfflineSyncCompleted:
		emit(map[string]any{"t": "offline_sync", "total": e.Count, "done": true})
	case *events.HistorySync:
		b.historySync(e)
	case *events.Message:
		if m := b.message(e, 1); m != nil {
			// Someone else's message we didn't have: edits, deletions and
			// what the phone resends are not news.
			news := m.fresh && !m.FromMe && e.UnavailableRequestID == "" && m.Kind != "system"
			if e.UnavailableRequestID != "" {
				logf("recover: phone resent %s %s (request %s, media %v)", m.Chat, m.ID, e.UnavailableRequestID, m.Media != nil)
			} else if news {
				b.db.Exec(`UPDATE chats SET unread = unread + 1 WHERE jid = ?`, m.Chat)
				b.unarchiveOnNews(m.Chat)
				// message() marked the list dirty before this count: a flush in
				// between would leave it unsent.
				b.dirty.Store(true)
			}
			emit(map[string]any{"t": "message", "msg": m, "new": news})
		}
	case *events.UndecryptableMessage:
		// WhatsApp Web's "Waiting for this message": the real one takes its
		// place once the phone resends it.
		if m := b.placeholder(e); m != nil {
			emit(map[string]any{"t": "message", "msg": m})
		}
	case *events.Receipt:
		b.receipt(e)
	case *events.MediaRetry:
		go b.mediaRetry(e)
	case *events.ChatPresence:
		chat := b.norm(e.Chat).String()
		state := string(e.State)
		if e.State == types.ChatPresenceComposing && e.Media == types.ChatPresenceMediaAudio {
			state = "recording"
		}
		sender := b.norm(e.Sender)
		emit(map[string]any{"t": "typing", "chat": chat, "jid": sender.String(), "who": b.senderName(sender, ""), "state": state})
	case *events.Presence:
		jid := b.norm(e.From)
		p := map[string]any{"t": "presence", "jid": jid.String(), "online": !e.Unavailable}
		if !e.LastSeen.IsZero() {
			p["last_seen"] = e.LastSeen.Unix()
		}
		emit(p)
	case *events.GroupInfo:
		go b.groupInfo(e)
	case *events.JoinedGroup:
		go b.syncGroups()
	case *events.Picture:
		select {
		case b.avatars <- avatarReq{jid: b.norm(e.JID).String(), force: true}:
		default:
		}
	case *events.PushNameSetting:
		// Your name, changed on the phone (or first had from it).
		if n := e.Action.GetName(); n != "" {
			emit(map[string]any{"t": "me", "me": b.meInfo(), "name": n})
		}
	case *events.PushName, *events.Contact, *events.BusinessName:
		b.dirty.Store(true)
	default:
		b.appStateEvent(raw)
	}
}

// norm turns a LID (WhatsApp's hidden user ids) into the phone number JID
// when the mapping is known, so one person is one chat.
func (b *Bridge) norm(j types.JID) types.JID {
	j = j.ToNonAD()
	if j.Server == types.HiddenUserServer && b.stored() {
		if pn, err := b.cli.Store.LIDs.GetPNForLID(b.ctx, j); err == nil && !pn.IsEmpty() {
			return pn.ToNonAD()
		}
	}
	return j
}

func (b *Bridge) me() types.JID {
	if b.cli.Store.ID == nil {
		return types.EmptyJID
	}
	return b.cli.Store.ID.ToNonAD()
}

// stored says the device has its stores: a fresh one (never paired, or just
// logged out) has none until pairing saves it, and chats left in the database
// from before must not reach them.
func (b *Bridge) stored() bool {
	return b.cli.Store.Contacts != nil && b.cli.Store.LIDs != nil
}

func skip(chat types.JID) bool {
	return chat.Server == types.BroadcastServer || chat.Server == types.NewsletterServer || chat.IsEmpty()
}

// wipe forgets the account: its chats, messages, media keys, pictures and
// downloads. For a logout, from here or from the phone, and for a start
// without a session, so a new one never shows the last one's chats.
func (b *Bridge) wipe() {
	for _, t := range []string{"chats", "messages", "media", "reactions", "fav_stickers", "meta"} {
		b.db.Exec("DELETE FROM " + t)
	}
	b.db.Exec("PRAGMA wal_checkpoint(TRUNCATE)")
	b.db.Exec("VACUUM")
	// The folders stay: the avatar workers write into theirs.
	for _, dir := range []string{filepath.Join(b.dir, "avatars"), mediaDir()} {
		entries, _ := os.ReadDir(dir)
		for _, e := range entries {
			os.RemoveAll(filepath.Join(dir, e.Name()))
		}
	}
}
