package main

// The app's own database (app.db): chats, messages, their media's keys,
// reactions and a few flags. whatsmeow keeps the session, contacts and
// keys in session.db.

import (
	"database/sql"
	"encoding/json"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"go.mau.fi/whatsmeow/types"
)

const schema = `
CREATE TABLE IF NOT EXISTS chats (
	jid TEXT PRIMARY KEY,
	name TEXT NOT NULL DEFAULT '',
	last_ts INTEGER NOT NULL DEFAULT 0,
	unread INTEGER NOT NULL DEFAULT 0,
	pinned INTEGER NOT NULL DEFAULT 0,
	archived INTEGER NOT NULL DEFAULT 0,
	mute_until INTEGER NOT NULL DEFAULT 0,
	read_only TEXT NOT NULL DEFAULT '',
	-- The JID WhatsApp knows the chat by (maybe a LID), for app state patches.
	wa_jid TEXT NOT NULL DEFAULT '',
	-- Its place among the favorites, from 1; 0 when it isn't one. fav_id is
	-- how WhatsApp's list names it.
	favorite INTEGER NOT NULL DEFAULT 0,
	fav_id TEXT NOT NULL DEFAULT '',
	-- Marked as unread by hand.
	marked INTEGER NOT NULL DEFAULT 0,
	-- Cleared: listed without messages until one comes.
	cleared INTEGER NOT NULL DEFAULT 0,
	-- A business's verified_level ("high" gets the check), "none" when it
	-- has none; empty until asked.
	verified TEXT NOT NULL DEFAULT '',
	-- A business's verified name, which WhatsApp Web shows in place of the
	-- number; empty for people, and until it's known.
	biz_name TEXT NOT NULL DEFAULT ''
);
CREATE TABLE IF NOT EXISTS messages (
	chat TEXT NOT NULL,
	id TEXT NOT NULL,
	sender TEXT NOT NULL,
	push_name TEXT NOT NULL DEFAULT '',
	from_me INTEGER NOT NULL,
	ts INTEGER NOT NULL,
	kind TEXT NOT NULL DEFAULT 'text',
	text TEXT NOT NULL DEFAULT '',
	-- What the kind has besides text, as JSON (Msg.X).
	x TEXT NOT NULL DEFAULT '',
	edited INTEGER NOT NULL DEFAULT 0,
	-- The message it replies to: its id, who wrote it, what it is.
	quote_id TEXT NOT NULL DEFAULT '',
	quote_from TEXT NOT NULL DEFAULT '',
	quote_kind TEXT NOT NULL DEFAULT '',
	quote_text TEXT NOT NULL DEFAULT '',
	quote_thumb TEXT NOT NULL DEFAULT '',
	status INTEGER NOT NULL DEFAULT 0,
	-- The sender as WhatsApp has it (maybe a LID), for message keys.
	wa_sender TEXT NOT NULL DEFAULT '',
	-- A business's Card, as JSON; empty for the rest.
	card TEXT NOT NULL DEFAULT '',
	-- Forwarded: its forwarding score, at least 1; 0 when it wasn't.
	forwarded INTEGER NOT NULL DEFAULT 0,
	starred INTEGER NOT NULL DEFAULT 0,
	PRIMARY KEY (chat, id)
);
CREATE INDEX IF NOT EXISTS messages_chat_ts ON messages (chat, ts);
CREATE TABLE IF NOT EXISTS media (
	chat TEXT NOT NULL,
	id TEXT NOT NULL,
	kind TEXT NOT NULL,
	mime TEXT NOT NULL DEFAULT '',
	seconds INTEGER NOT NULL DEFAULT 0,
	ptt INTEGER NOT NULL DEFAULT 0,
	-- A waE2E.Message with only the media part, keys and path: enough to download it.
	proto BLOB,
	-- The chat and sender as WhatsApp has them (maybe LIDs), to ask the phone for a new upload.
	wa_chat TEXT NOT NULL DEFAULT '',
	wa_sender TEXT NOT NULL DEFAULT '',
	PRIMARY KEY (chat, id)
);
-- One reaction per message and sender, as WhatsApp allows.
CREATE TABLE IF NOT EXISTS reactions (
	chat TEXT NOT NULL,
	id TEXT NOT NULL,
	sender TEXT NOT NULL,
	emoji TEXT NOT NULL,
	ts INTEGER NOT NULL,
	PRIMARY KEY (chat, id, sender)
);
-- Favorite stickers, as the app state has them: hash is the mutation's
-- index (the file's SHA-256, base64), enc_hash the encrypted file's, action
-- the StickerAction.
CREATE TABLE IF NOT EXISTS fav_stickers (
	hash TEXT PRIMARY KEY,
	enc_hash TEXT NOT NULL DEFAULT '',
	action BLOB
);
CREATE TABLE IF NOT EXISTS meta (
	k TEXT PRIMARY KEY,
	v TEXT NOT NULL
);
`

// migrate adds what later versions need to an older database.
func migrate(db *sql.DB) {
	for _, col := range []string{
		`messages ADD COLUMN starred INTEGER NOT NULL DEFAULT 0`,
		`chats ADD COLUMN biz_name TEXT NOT NULL DEFAULT ''`,
	} {
		db.Exec(`ALTER TABLE ` + col)
	}
	// Omawhats was whatsapp-claude, and its cache folder moved with the
	// name: the pictures of link previews and quotes stored before point
	// into the old one. Once per database.
	var renamed string
	db.QueryRow(`SELECT v FROM meta WHERE k = 'renamed'`).Scan(&renamed)
	if renamed == "" {
		old := filepath.Join(filepath.Dir(cacheRoot), "whatsapp-claude", "media") + "/"
		if _, err := db.Exec(`UPDATE messages SET x = replace(x, ?1, ?2), quote_thumb = replace(quote_thumb, ?1, ?2)
			WHERE instr(x, ?1) > 0 OR instr(quote_thumb, ?1) > 0`, old, mediaDir()+"/"); err == nil {
			db.Exec(`INSERT INTO meta (k, v) VALUES ('renamed', '1') ON CONFLICT (k) DO NOTHING`)
		}
	}
}

// ---------------------------------------------------------------- names

// savedName is the name you gave someone (or their business's), "" when none.
func savedName(c types.ContactInfo) string { return personName(c, "") }

// personName is what WhatsApp Web calls someone, in its order: the name you
// saved, the business's verified name (biz, as its chat keeps it), the
// business name whatsmeow has; "" when none, for the push name (where a
// group shows it) or the number to stand in.
func personName(c types.ContactInfo, biz string) string {
	for _, n := range []string{c.FullName, c.FirstName, biz, c.BusinessName} {
		if n != "" {
			return n
		}
	}
	return ""
}

// bizName is the verified name a chat keeps for its business, "" when none.
func (b *Bridge) bizName(j types.JID) string {
	var n string
	b.db.QueryRow(`SELECT biz_name FROM chats WHERE jid = ?`, j.String()).Scan(&n)
	return n
}

func (b *Bridge) contact(j types.JID) types.ContactInfo {
	if !b.stored() {
		return types.ContactInfo{}
	}
	c, err := b.cli.Store.Contacts.GetContact(b.ctx, j)
	if err == nil && c.Found && savedName(c) != "" {
		return c
	}
	// A number WhatsApp also knows by a hidden id: the contact may be under
	// it, or its names only (a business's comes with the id it writes from).
	if j.Server == types.DefaultUserServer {
		if lid, err := b.cli.Store.LIDs.GetLIDForPN(b.ctx, j); err == nil && !lid.IsEmpty() {
			if lc, err := b.cli.Store.Contacts.GetContact(b.ctx, lid); err == nil && lc.Found && (savedName(lc) != "" || !c.Found) {
				if lc.PushName == "" {
					lc.PushName = c.PushName
				}
				return lc
			}
		}
	}
	if err == nil && c.Found {
		return c
	}
	return types.ContactInfo{}
}

func (b *Bridge) contactName(j types.JID) string { return savedName(b.contact(j)) }

// senderName is who wrote a message, as a group shows them: "" for you,
// the saved name or the business's, "~push name" for people you haven't
// saved, else the number (with its +).
func (b *Bridge) senderName(j types.JID, push string) string {
	if j.User == b.me().User || (b.stored() && j.User == b.cli.Store.GetLID().User) {
		return ""
	}
	c := b.contact(j)
	if n := personName(c, b.bizName(j)); n != "" {
		return n
	}
	if push == "" {
		push = c.PushName
	}
	if push != "" {
		return "~" + push
	}
	if j.Server == types.DefaultUserServer {
		return "+" + j.User
	}
	return ""
}

// pushOf is the push name someone's messages here came with, "" when none.
func (b *Bridge) pushOf(sender string) string {
	var push string
	b.db.QueryRow(`SELECT push_name FROM messages WHERE (sender = ? OR wa_sender = ?) AND push_name != '' ORDER BY ts DESC LIMIT 1`, sender, sender).Scan(&push)
	return push
}

// quoteName is how a quote names its author: as their messages do, with
// the push name one of them came with when they're no contact.
func (b *Bridge) quoteName(from string) string {
	j, err := types.ParseJID(from)
	if err != nil || j.IsEmpty() {
		return ""
	}
	var push string
	if j.User != b.me().User && b.contactName(j) == "" {
		push = b.pushOf(from)
	}
	return b.senderName(j, push)
}

// ---------------------------------------------------------------- meta

func (b *Bridge) meta(k string) string {
	var v string
	b.db.QueryRow(`SELECT v FROM meta WHERE k = ?`, k).Scan(&v)
	return v
}

func (b *Bridge) setMeta(k, v string) {
	b.db.Exec(`INSERT INTO meta (k, v) VALUES (?, ?) ON CONFLICT (k) DO UPDATE SET v = excluded.v`, k, v)
}

// ---------------------------------------------------------------- chats

// flushChats sends what changed in the chat list, at most a few times a
// second (a history sync changes it hundreds of times): the chats whose
// row differs from the last sent, and the ones gone.
func (b *Bridge) flushChats() {
	for range time.Tick(300 * time.Millisecond) {
		if b.dirty.Swap(false) {
			b.sendChats()
		}
	}
}

// flush sends the chat list now, not on the next tick: what a menu did shows at once.
func (b *Bridge) flush() {
	b.dirty.Store(false)
	b.sendChats()
}

func (b *Bridge) sendChats() {
	list := b.chats()
	full := b.full.Swap(false)
	b.sentMu.Lock()
	defer b.sentMu.Unlock()
	if full {
		b.sent = map[string]string{}
	}
	changed := []Chat{}
	seen := map[string]bool{}
	for _, c := range list {
		seen[c.JID] = true
		js, _ := json.Marshal(c)
		if b.sent[c.JID] != string(js) {
			b.sent[c.JID] = string(js)
			changed = append(changed, c)
		}
	}
	gone := []string{}
	for jid := range b.sent {
		if !seen[jid] {
			delete(b.sent, jid)
			gone = append(gone, jid)
		}
	}
	if full || len(changed) > 0 || len(gone) > 0 {
		emit(map[string]any{"t": "chats", "full": full, "chats": changed, "gone": gone})
	}
}

// chats lists the conversations that have messages, as WhatsApp does: the
// groups we're in and the contacts we know stay out until someone writes.
func (b *Bridge) chats() []Chat {
	// Cleared ones stay, empty, as on the phone.
	rows, err := b.db.Query(`SELECT c.jid, c.name, c.last_ts, c.unread, c.marked, c.pinned, c.archived, c.mute_until, c.read_only, c.favorite, c.verified, c.biz_name,
		COALESCE(m.id, ''), COALESCE(m.kind, ''), COALESCE(m.text, ''), COALESCE(m.x, ''), COALESCE(m.from_me, 0), COALESCE(m.status, 0),
		COALESCE(m.sender, ''), COALESCE(m.push_name, ''), COALESCE(md.seconds, 0), COALESCE(md.proto, X'')
		FROM chats c
		LEFT JOIN messages m ON m.rowid = (SELECT rowid FROM messages WHERE chat = c.jid ORDER BY ts DESC LIMIT 1)
		LEFT JOIN media md ON md.chat = m.chat AND md.id = m.id
		WHERE m.rowid IS NOT NULL OR c.cleared > 0`)
	if err != nil {
		logf("chats: %v", err)
		return nil
	}
	defer rows.Close()
	contacts := map[types.JID]types.ContactInfo{}
	if b.stored() {
		if all, err := b.cli.Store.Contacts.GetAllContacts(b.ctx); err == nil {
			contacts = all
		}
	}
	me := b.me()
	out := []Chat{}
	seen := map[string]*Mention{}
	names := map[string]string{}
	for rows.Next() {
		var c Chat
		var level, groupName, bizName, id, kind, text, x, sender, push string
		var fromMe bool
		var status int
		var secs uint32
		var blob []byte
		if rows.Scan(&c.JID, &groupName, &c.TS, &c.Unread, &c.Marked, &c.Pin, &c.Archived, &c.Mute, &c.ReadOnly, &c.Favorite, &level, &bizName,
			&id, &kind, &text, &x, &fromMe, &status, &sender, &push, &secs, &blob) != nil {
			continue
		}
		jid, _ := types.ParseJID(c.JID)
		c.Verified = jid == types.PSAJID || level == "high"
		switch {
		case jid.Server == types.GroupServer:
			c.Kind, c.Name = "group", groupName
		case jid == types.PSAJID:
			c.Kind, c.Name = "official", "WhatsApp"
		case jid.User == me.User:
			c.Kind = "self"
		default:
			c.Kind = "user"
			info, ok := contacts[jid]
			if !ok || savedName(info) == "" {
				info = b.contact(jid)
			}
			// The saved name, the business's; else what the phone's history
			// called the chat, else the number (the app's to write).
			c.Name = personName(info, bizName)
			if c.Name == "" {
				c.Name = groupName
			}
		}
		if jid.Server == types.DefaultUserServer {
			c.Phone = jid.User
		}
		if c.Mute > 0 && c.Mute < time.Now().Unix() {
			c.Mute = 0
		}
		if id != "" {
			l := &Last{ID: id, FromMe: fromMe, Status: status, Kind: kind, Seconds: secs}
			l.Text = withMentions(text, b.mentions(text, seen))
			if len(l.Text) > 300 {
				l.Text = cut(l.Text, 300)
			}
			if kind == "system" || kind == "call" || kind == "poll" || kind == "view_once" || kind == "contact" || kind == "event" {
				l.X = json.RawMessage(x)
			}
			if kind == "document" {
				if md := partOf(blob).GetDocumentMessage(); md != nil {
					l.Name = md.GetFileName()
				}
			}
			// In a group, who wrote it, as WhatsApp Web shows it before the text.
			if c.Kind == "group" && !fromMe && sender != "" {
				key := sender + "\x00" + push
				n, ok := names[key]
				if !ok {
					if j, err := types.ParseJID(sender); err == nil {
						n = b.senderName(j, push)
					}
					names[key] = n
				}
				l.Who = n
			}
			if len(x) == 0 || !json.Valid([]byte(x)) {
				l.X = nil
			}
			c.Last = l
		}
		out = append(out, c)
	}
	// Pinned first, the last pinned on top, then by the newest message.
	sort.SliceStable(out, func(i, j int) bool {
		if out[i].Pin != out[j].Pin {
			return out[i].Pin > out[j].Pin
		}
		return out[i].TS > out[j].TS
	})
	return out
}

// cut shortens s to about n bytes, on a rune boundary.
func cut(s string, n int) string {
	if len(s) <= n {
		return s
	}
	for n > 0 && (s[n]&0xC0) == 0x80 {
		n--
	}
	return s[:n]
}

// ---------------------------------------------------------------- messages

const msgCols = `chat, id, sender, push_name, from_me, ts, messages.kind, text, x, edited, quote_id, quote_from, quote_kind, quote_text, quote_thumb,
	status, card, forwarded, starred, COALESCE(media.kind, ''), COALESCE(mime, ''), COALESCE(seconds, 0), COALESCE(ptt, 0), proto`

func (b *Bridge) load(chat, id string) *Msg {
	ms := b.query(`WHERE chat = ? AND id = ?`, chat, id)
	if len(ms) == 0 {
		return nil
	}
	return &ms[0]
}

func (b *Bridge) query(where string, args ...any) []Msg {
	rows, err := b.db.Query(`SELECT `+msgCols+` FROM messages LEFT JOIN media USING (chat, id) `+where, args...)
	if err != nil {
		logf("query: %v", err)
		return nil
	}
	defer rows.Close()
	names := map[string]string{}
	seen := map[string]*Mention{}
	var out []Msg
	for rows.Next() {
		var m Msg
		var push, x, qID, qFrom, qKind, qText, qThumb, card string
		var md Media
		var blob []byte
		if err := rows.Scan(&m.Chat, &m.ID, &m.Sender, &push, &m.FromMe, &m.TS, &m.Kind, &m.Text, &x, &m.Edited,
			&qID, &qFrom, &qKind, &qText, &qThumb, &m.Status, &card, &m.Forwarded, &m.Starred,
			&md.Kind, &md.Mime, &md.Seconds, &md.PTT, &blob); err != nil {
			logf("scan: %v", err)
			continue
		}
		if x != "" && json.Valid([]byte(x)) {
			m.X = json.RawMessage(x)
		}
		if md.Kind != "" {
			md.fill(m.Chat, m.ID, partOf(blob))
			m.Media = &md
		}
		if card != "" {
			m.Card = &Card{}
			json.Unmarshal([]byte(card), m.Card)
		}
		key := m.Sender + "\x00" + push
		if n, ok := names[key]; ok {
			m.Name = n
		} else {
			j, _ := types.ParseJID(m.Sender)
			m.Name = b.senderName(j, push)
			names[key] = m.Name
		}
		if qID != "" {
			q := &Quote{ID: qID, From: qFrom, Kind: qKind}
			if n, ok := names[qFrom]; ok {
				q.Name = n
			} else {
				q.Name = b.quoteName(qFrom)
				names[qFrom] = q.Name
			}
			q.Text = withMentions(qText, b.mentions(qText, seen))
			if qThumb != "" {
				if _, err := os.Stat(qThumb); err == nil {
					q.Thumb = qThumb
				}
			}
			m.Quote = q
		}
		m.Mentions = b.mentions(m.Text, seen)
		out = append(out, m)
	}
	rows.Close()
	b.withReactions(out)
	return out
}

// history answers with a page of a chat's messages, oldest first: the
// newest ones, or the ones before Before/BeforeID. "more" says whether
// older ones are here; when not, the app may ask the phone (older).
func (b *Bridge) history(c Cmd) {
	limit := c.Limit
	if limit <= 0 {
		limit = 60
	}
	go b.verifiedOnce(c.Chat)
	var ms []Msg
	if c.Before > 0 {
		ms = b.query(`WHERE chat = ? AND (ts < ? OR (ts = ? AND id < ?)) ORDER BY ts DESC, id DESC LIMIT ?`, c.Chat, c.Before, c.Before, c.BeforeID, limit+1)
	} else {
		ms = b.query(`WHERE chat = ? ORDER BY ts DESC, id DESC LIMIT ?`, c.Chat, limit+1)
	}
	more := len(ms) > limit
	if more {
		ms = ms[:limit]
	}
	for i, j := 0, len(ms)-1; i < j; i, j = i+1, j-1 {
		ms[i], ms[j] = ms[j], ms[i]
	}
	if ms == nil {
		ms = []Msg{}
	}
	emit(map[string]any{"t": "history", "chat": c.Chat, "msgs": ms, "more": more, "page": c.Before > 0})
}

// unread answers with a chat's newest messages from other people, up to
// `limit` and no more than it has unread, oldest first: the preview the bar
// shows.
func (b *Bridge) unread(chat string, limit int) {
	var n int
	b.db.QueryRow(`SELECT unread FROM chats WHERE jid = ?`, chat).Scan(&n)
	ms := []Msg{}
	if n = min(n, limit); n > 0 {
		ms = b.query(`WHERE chat = ? AND from_me = 0 ORDER BY ts DESC LIMIT ?`, chat, n)
		for i, j := 0, len(ms)-1; i < j; i, j = i+1, j-1 {
			ms[i], ms[j] = ms[j], ms[i]
		}
	}
	emit(map[string]any{"t": "unread", "chat": chat, "msgs": ms})
}

// older asks the phone for messages before the oldest one here, as
// WhatsApp Web does when you scroll past what it has. They come as an
// on-demand history sync (historySync), and the app is told then.
func (b *Bridge) older(chat string) {
	var id string
	var fromMe bool
	var ts int64
	if b.db.QueryRow(`SELECT id, from_me, ts FROM messages WHERE chat = ? ORDER BY ts, id LIMIT 1`, chat).Scan(&id, &fromMe, &ts) != nil {
		emit(map[string]any{"t": "older", "chat": chat, "asked": false})
		return
	}
	wa := b.waJID(chat)
	info := &types.MessageInfo{ID: id, Timestamp: time.Unix(ts, 0)}
	info.Chat = wa
	info.IsFromMe = fromMe
	info.IsGroup = wa.Server == types.GroupServer
	_, err := b.cli.SendPeerMessage(b.ctx, b.cli.BuildHistorySyncRequest(info, 50))
	if err != nil {
		logf("older %s: %v", chat, err)
	}
	emit(map[string]any{"t": "older", "chat": chat, "asked": err == nil})
}

// waJID is the chat as WhatsApp's app state names it: a patch under another
// JID (the number where the phone has the LID) would be another chat to it.
func (b *Bridge) waJID(chat string) types.JID {
	var wa string
	b.db.QueryRow(`SELECT wa_jid FROM chats WHERE jid = ?`, chat).Scan(&wa)
	for _, s := range []string{wa, chat} {
		if j, err := types.ParseJID(s); err == nil && s != "" {
			return j
		}
	}
	return types.EmptyJID
}

// fold lowercases and drops accents, for searching.
var unaccent = strings.NewReplacer("á", "a", "à", "a", "â", "a", "ã", "a", "ä", "a", "é", "e", "ê", "e", "è", "e", "ë", "e",
	"í", "i", "ì", "i", "î", "i", "ï", "i", "ó", "o", "ò", "o", "ô", "o", "õ", "o", "ö", "o", "ú", "u", "ù", "u", "û", "u", "ü", "u", "ç", "c", "ñ", "n")

func fold(s string) string { return unaccent.Replace(strings.ToLower(s)) }
