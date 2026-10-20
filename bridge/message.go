package main

// Messages coming in: live ones, the history the phone sends after
// linking (and on demand), receipts and the notices of group changes.

import (
	"encoding/json"
	"os"
	"strings"
	"time"

	"go.mau.fi/whatsmeow/proto/waE2E"
	"go.mau.fi/whatsmeow/proto/waHistorySync"
	"go.mau.fi/whatsmeow/proto/waWeb"
	"go.mau.fi/whatsmeow/types"
	"go.mau.fi/whatsmeow/types/events"
	"google.golang.org/protobuf/reflect/protoreflect"
)

// contextOf is a message's context (the reply it is, its @s, whether it
// was forwarded), whatever kind it is.
func contextOf(m *waE2E.Message) *waE2E.ContextInfo {
	if m == nil {
		return nil
	}
	var ci *waE2E.ContextInfo
	m.ProtoReflect().Range(func(fd protoreflect.FieldDescriptor, v protoreflect.Value) bool {
		if fd.Kind() != protoreflect.MessageKind {
			return true
		}
		if x, ok := v.Message().Interface().(interface{ GetContextInfo() *waE2E.ContextInfo }); ok && x.GetContextInfo() != nil {
			ci = x.GetContextInfo()
			return false
		}
		return true
	})
	return ci
}

// xJSON is a content's x object as stored, its picture written to disk
// next to the message's media.
func xJSON(chat, id string, c Content) string {
	if c.X == nil {
		return ""
	}
	if len(c.Thumb) > 0 {
		path := thumbFile(chat, id, "x")
		if _, err := os.Stat(path); err == nil || writeFile(path, c.Thumb) == nil {
			c.X["thumb"] = path
		}
	}
	js, _ := json.Marshal(c.X)
	return string(js)
}

// quoteOf reads what a reply quotes: its id, who wrote it, what it is, and
// its picture's thumbnail on disk when it has one.
func (b *Bridge) quoteOf(chat string, ci *waE2E.ContextInfo) (id, from, kind, text, thumb string) {
	if ci.GetQuotedMessage() == nil || ci.GetStanzaID() == "" {
		return
	}
	id = ci.GetStanzaID()
	if j, err := types.ParseJID(ci.GetParticipant()); err == nil && !j.IsEmpty() {
		from = b.norm(j).String()
	}
	q := ci.GetQuotedMessage()
	c, ok := contentOf(q)
	if !ok {
		c = Content{Kind: "text"}
	}
	kind, text = c.Kind, c.Text
	if kind == "poll" || kind == "event" || kind == "contact" {
		// Their name is what a quote shows.
		if p := pollOf(q); p != nil {
			text = p.GetName()
		}
		if c.Text == "" {
			if cs, ok := c.X["contacts"].([]any); ok && len(cs) > 0 {
				text, _ = cs[0].(map[string]any)["name"].(string)
			}
		}
	}
	if md, part := mediaOf(q); md != nil {
		var jpg []byte
		switch {
		case part.GetImageMessage() != nil:
			jpg = part.GetImageMessage().GetJPEGThumbnail()
		case part.GetVideoMessage() != nil:
			jpg = part.GetVideoMessage().GetJPEGThumbnail()
		case part.GetPtvMessage() != nil:
			jpg = part.GetPtvMessage().GetJPEGThumbnail()
		case part.GetDocumentMessage() != nil:
			jpg = part.GetDocumentMessage().GetJPEGThumbnail()
		}
		path := thumbFile(chat, id, "thumb")
		if _, err := os.Stat(path); err == nil || (len(jpg) > 0 && writeFile(path, jpg) == nil) {
			thumb = path
		}
	} else if len(c.Thumb) > 0 {
		path := thumbFile(chat, id, "x")
		if _, err := os.Stat(path); err == nil || writeFile(path, c.Thumb) == nil {
			thumb = path
		}
	}
	return
}

// message stores a received (or history) message and returns it, or nil
// when there's nothing to show. Edits and deletions update the stored one.
func (b *Bridge) message(e *events.Message, status int) *Msg {
	chat := b.norm(e.Info.Chat)
	if skip(chat) || e.Message == nil {
		return nil
	}
	// A reaction changes the message it's on.
	if rm := e.Message.GetReactionMessage(); rm != nil {
		id := rm.GetKey().GetID()
		sender := b.norm(e.Info.Sender).String()
		if e.Info.IsFromMe {
			sender = b.me().String()
		}
		ts := rm.GetSenderTimestampMS() / 1000
		if ts == 0 {
			ts = e.Info.Timestamp.Unix()
		}
		b.react(chat.String(), id, sender, rm.GetText(), ts)
		if m := b.load(chat.String(), id); m != nil {
			// Someone reacting to yours is news the app may tell.
			if !e.Info.IsFromMe && m.FromMe && rm.GetText() != "" {
				emit(map[string]any{"t": "reaction", "chat": chat.String(), "id": id, "emoji": rm.GetText(),
					"who": b.senderName(b.norm(e.Info.Sender), e.Info.PushName), "ts": ts})
			}
			return m
		}
		return nil
	}
	pm := e.Message.GetProtocolMessage()
	if sm := e.Message.GetSecretEncryptedMessage(); sm != nil {
		if pm = b.sealedEdit(e, sm); pm == nil {
			return nil
		}
	}
	if pm != nil {
		id := pm.GetKey().GetID()
		switch pm.GetType() {
		case waE2E.ProtocolMessage_REVOKE:
			b.db.Exec(`UPDATE messages SET kind = 'revoked', text = '', x = '', edited = 0, card = '' WHERE chat = ? AND id = ?`, chat.String(), id)
			b.db.Exec(`DELETE FROM media WHERE chat = ? AND id = ?`, chat.String(), id)
			b.db.Exec(`DELETE FROM reactions WHERE chat = ? AND id = ?`, chat.String(), id)
			b.db.Exec(`DELETE FROM receipts WHERE chat = ? AND id = ?`, chat.String(), id)
		case waE2E.ProtocolMessage_MESSAGE_EDIT:
			c, ok := contentOf(pm.GetEditedMessage())
			if !ok {
				return nil
			}
			b.db.Exec(`UPDATE messages SET text = ?, edited = 1 WHERE chat = ? AND id = ?`, c.Text, chat.String(), id)
		default:
			return nil
		}
		b.dirty.Store(true)
		return b.load(chat.String(), id)
	}
	c, ok := contentOf(e.Message)
	if !ok {
		return nil
	}
	if c.Kind == "call" {
		return b.callMessage(e, c)
	}
	// A view-once photo, video or voice can't be opened here, as on WhatsApp Web.
	viewOnce := e.IsViewOnce
	if viewOnce {
		c = Content{Kind: "view_once", X: map[string]any{"of": c.Kind}}
	}
	sender := b.norm(e.Info.Sender)
	if e.Info.IsFromMe {
		sender = b.me()
	}
	ci := contextOf(e.Message)
	qID, qFrom, qKind, qText, qThumb := b.quoteOf(chat.String(), ci)
	m := &Msg{
		Chat: chat.String(), ID: e.Info.ID, Sender: sender.String(), FromMe: e.Info.IsFromMe,
		TS: e.Info.Timestamp.Unix(), Kind: c.Kind, Text: c.Text, Status: status,
	}
	var card string
	if lo := cardOf(e.Message); lo != nil {
		card = cardJSON(lo)
		if card != "" {
			m.Card = &lo.card
		}
	}
	if ci.GetIsForwarded() {
		m.Forwarded = max(int(ci.GetForwardingScore()), 1)
	}
	x := xJSON(m.Chat, m.ID, c)
	// New here, or decrypted at last in place of its "Waiting for this
	// message" (which counted for nothing): news either way.
	var had string
	m.fresh = b.db.QueryRow(`SELECT kind FROM messages WHERE chat = ? AND id = ?`, m.Chat, m.ID).Scan(&had) != nil || had == "placeholder"
	// A message the phone resends after a placeholder takes its place; an
	// older copy (a history sync's) never undoes what came live.
	_, err := b.db.Exec(`INSERT INTO messages (chat, id, sender, push_name, from_me, ts, kind, text, x, quote_id, quote_from, quote_kind, quote_text, quote_thumb, status, wa_sender, card, forwarded)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
		ON CONFLICT (chat, id) DO UPDATE SET
			kind = CASE WHEN kind IN ('revoked') THEN kind ELSE excluded.kind END,
			text = CASE WHEN kind = 'revoked' OR edited = 1 THEN text ELSE excluded.text END,
			x = CASE WHEN kind = 'revoked' THEN x ELSE excluded.x END,
			status = max(status, excluded.status), card = excluded.card,
			push_name = CASE WHEN excluded.push_name != '' THEN excluded.push_name ELSE push_name END,
			quote_id = CASE WHEN quote_id = '' THEN excluded.quote_id ELSE quote_id END,
			quote_from = CASE WHEN quote_from = '' THEN excluded.quote_from ELSE quote_from END,
			quote_kind = CASE WHEN quote_kind = '' THEN excluded.quote_kind ELSE quote_kind END,
			quote_text = CASE WHEN quote_text = '' THEN excluded.quote_text ELSE quote_text END,
			quote_thumb = CASE WHEN quote_thumb = '' THEN excluded.quote_thumb ELSE quote_thumb END,
			forwarded = max(forwarded, excluded.forwarded)`,
		m.Chat, m.ID, m.Sender, e.Info.PushName, m.FromMe, m.TS, m.Kind, m.Text, x, qID, qFrom, qKind, qText, qThumb, m.Status,
		e.Info.Sender.ToNonAD().String(), card, m.Forwarded)
	if err != nil {
		logf("store message %s: %v", m.ID, err)
		return nil
	}
	// What WhatsApp calls the chat, unless its app state already said.
	b.db.Exec(`INSERT INTO chats (jid, last_ts, wa_jid) VALUES (?, ?, ?)
		ON CONFLICT (jid) DO UPDATE SET last_ts = max(last_ts, excluded.last_ts),
			wa_jid = CASE WHEN wa_jid = '' THEN excluded.wa_jid ELSE wa_jid END, cleared = 0`, m.Chat, m.TS, e.Info.Chat.ToNonAD().String())
	// A business's level and name come with each of its messages: "high"
	// gets the check, the name stands in for the number.
	if vn := e.Info.VerifiedName; vn != nil && !e.Info.IsGroup && !e.Info.IsFromMe {
		if vn.VerifiedLevel != "" {
			b.db.Exec(`UPDATE chats SET verified = ? WHERE jid = ?`, vn.VerifiedLevel, m.Chat)
		}
		b.setBizName(m.Chat, vn.Details.GetVerifiedName())
	}
	// Someone with no name here, never asked: maybe a business (bizNames).
	if chat.Server == types.DefaultUserServer && !e.Info.IsGroup {
		var level string
		if b.db.QueryRow(`SELECT verified FROM chats WHERE jid = ?`, m.Chat).Scan(&level) == nil && level == "" && b.contactName(chat) == "" {
			b.wantBizNames()
		}
	}
	if !viewOnce {
		if md, part := mediaOf(e.Message); md != nil {
			b.storeMedia(m.Chat, m.ID, md, part, e.Info.Chat.String(), e.Info.Sender.String())
		}
	}
	b.dirty.Store(true)
	// As stored, with its media and names; `fresh` is this call's to say
	// (the row read back can't know it), and makes it news (handle).
	out := b.load(m.Chat, m.ID)
	if out != nil {
		out.fresh = m.fresh
	}
	return out
}

// sealedEdit opens an edit the phones now send sealed with the edited
// message's own secret, into the edit as it used to come; nil for the
// other sealed kinds (a poll's or an event's changes) and what won't open.
func (b *Bridge) sealedEdit(e *events.Message, sm *waE2E.SecretEncryptedMessage) *waE2E.ProtocolMessage {
	if sm.GetSecretEncType() != waE2E.SecretEncryptedMessage_MESSAGE_EDIT {
		return nil
	}
	m, err := b.cli.DecryptSecretEncryptedMessage(b.ctx, e)
	if err != nil {
		logf("edit %s: %v", e.Info.ID, err)
		return nil
	}
	if fp := m.GetEditedMessage().GetMessage(); fp != nil {
		m = fp
	}
	pm := m.GetProtocolMessage()
	if pm == nil {
		pm = &waE2E.ProtocolMessage{Type: waE2E.ProtocolMessage_MESSAGE_EDIT.Enum(), EditedMessage: m}
	}
	if pm.GetKey() == nil {
		pm.Key = sm.GetTargetMessageKey()
	}
	return pm
}

// placeholder stands in for a message this device couldn't decrypt, as
// WhatsApp Web's "Waiting for this message": the phone is asked for it,
// and when it comes it takes the placeholder's place.
func (b *Bridge) placeholder(e *events.UndecryptableMessage) *Msg {
	chat := b.norm(e.Info.Chat)
	if skip(chat) || e.Info.ID == "" {
		return nil
	}
	// Some kinds are left out on purpose (a view-once sent to the phone only).
	if e.UnavailableType != "" {
		return nil
	}
	sender := b.norm(e.Info.Sender)
	if e.Info.IsFromMe {
		sender = b.me()
	}
	_, err := b.db.Exec(`INSERT INTO messages (chat, id, sender, push_name, from_me, ts, kind, status, wa_sender) VALUES (?, ?, ?, ?, ?, ?, 'placeholder', 1, ?)
		ON CONFLICT (chat, id) DO NOTHING`, chat.String(), e.Info.ID, sender.String(), e.Info.PushName, e.Info.IsFromMe, e.Info.Timestamp.Unix(), e.Info.Sender.ToNonAD().String())
	if err != nil {
		return nil
	}
	b.db.Exec(`INSERT INTO chats (jid, last_ts, wa_jid) VALUES (?, ?, ?)
		ON CONFLICT (jid) DO UPDATE SET last_ts = max(last_ts, excluded.last_ts)`, chat.String(), e.Info.Timestamp.Unix(), e.Info.Chat.ToNonAD().String())
	b.dirty.Store(true)
	return b.load(chat.String(), e.Info.ID)
}

// system stores a notice (who joined, a new group name): its people named
// by their JIDs, which the app shows by the names here.
func (b *Bridge) system(chat types.JID, id string, ts int64, actor types.JID, c Content, people []string) {
	sys, _ := c.X["sys"].(map[string]any)
	if sys != nil {
		names := []map[string]string{}
		for _, p := range people {
			j, err := types.ParseJID(p)
			if err != nil {
				continue
			}
			j = b.norm(j)
			names = append(names, map[string]string{"jid": j.String(), "name": b.quoteName(j.String())})
		}
		if len(names) > 0 {
			sys["people"] = names
		}
	}
	sender := b.me()
	if !actor.IsEmpty() {
		sender = b.norm(actor)
	}
	x := xJSON(chat.String(), id, c)
	b.db.Exec(`INSERT INTO messages (chat, id, sender, from_me, ts, kind, text, x, status) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 3)
		ON CONFLICT (chat, id) DO NOTHING`, chat.String(), id, sender.String(), sender.User == b.me().User, ts, c.Kind, c.Text, x)
}

// groupInfo turns a live group change into the notice its chat shows, and
// refreshes the group's name and who may write.
func (b *Bridge) groupInfo(e *events.GroupInfo) {
	chat := e.JID.ToNonAD()
	actor := types.EmptyJID
	if e.Sender != nil {
		actor = *e.Sender
	}
	ts := e.Timestamp.Unix()
	id := "sys-" + strings.ReplaceAll(chat.User, "-", "") + "-" + time.Now().Format("150405.000000")
	n := 0
	add := func(kind string, value any, people []types.JID) {
		sys := map[string]any{"type": kind}
		if value != nil {
			sys["value"] = value
		}
		ps := []string{}
		for _, p := range people {
			ps = append(ps, p.String())
		}
		n++
		b.system(chat, id+"-"+string(rune('a'+n)), ts, actor, Content{Kind: "system", X: map[string]any{"sys": sys}}, ps)
	}
	if e.Name != nil {
		add("group_subject", e.Name.Name, nil)
	}
	if e.Topic != nil {
		add("group_description", nil, nil)
	}
	if e.Announce != nil {
		add("group_announce", e.Announce.IsAnnounce, nil)
	}
	if e.Locked != nil {
		add("group_restrict", e.Locked.IsLocked, nil)
	}
	if e.Ephemeral != nil {
		add("ephemeral", e.Ephemeral.DisappearingTimer, nil)
	}
	if len(e.Join) > 0 {
		if !actor.IsEmpty() && !(len(e.Join) == 1 && e.Join[0].User == actor.User) {
			add("group_add", nil, e.Join)
		} else {
			add("group_join", nil, e.Join)
		}
	}
	if len(e.Leave) > 0 {
		if !actor.IsEmpty() && !(len(e.Leave) == 1 && e.Leave[0].User == actor.User) {
			add("group_remove", nil, e.Leave)
		} else {
			add("group_leave", nil, e.Leave)
		}
	}
	if len(e.Promote) > 0 {
		add("group_promote", nil, e.Promote)
	}
	if len(e.Demote) > 0 {
		add("group_demote", nil, e.Demote)
	}
	if n > 0 {
		b.db.Exec(`INSERT INTO chats (jid, last_ts) VALUES (?, ?) ON CONFLICT (jid) DO UPDATE SET last_ts = max(last_ts, excluded.last_ts)`, chat.String(), ts)
		emit(map[string]any{"t": "refresh", "chat": chat.String()})
	}
	b.syncGroups()
}

func (b *Bridge) historySync(e *events.HistorySync) {
	// An answer to `older` or to recoverMedia: only its messages count,
	// not the chat's state in it (unread, archived, names).
	onDemand := e.Data.GetSyncType() == waHistorySync.HistorySync_ON_DEMAND
	logf("history sync %s: %d chats, %d%%", e.Data.GetSyncType(), len(e.Data.GetConversations()), e.Data.GetProgress())
	for _, conv := range e.Data.GetConversations() {
		jid, err := types.ParseJID(conv.GetID())
		if err != nil {
			continue
		}
		chat := b.norm(jid)
		if skip(chat) {
			continue
		}
		if !onDemand {
			// Forever comes as -1 (all bits set); milliseconds at times.
			mute := int64(conv.GetMuteEndTime())
			if mute > 1e12 {
				mute /= 1000
			}
			if mute < 0 {
				mute = muteForever
			}
			unread, marked := conv.GetUnreadCount(), conv.GetMarkedAsUnread()
			if marked {
				unread = max(unread, 1)
			}
			readOnly := ""
			switch {
			case chat == types.PSAJID:
				readOnly = officialOnly
			case conv.GetReadOnly() && chat.Server == types.GroupServer:
				readOnly = notMember
			case conv.GetReadOnly():
				readOnly = cantSend
			}
			// pinned is when it was pinned. Only the first sync carries pins (the
			// later ones say 0 for every chat): those keep what the app state set.
			b.db.Exec(`INSERT INTO chats (jid, name, last_ts, unread, pinned, archived, mute_until, read_only, wa_jid, marked) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
				ON CONFLICT (jid) DO UPDATE SET
					name = CASE WHEN excluded.name != '' THEN excluded.name ELSE name END,
					last_ts = max(last_ts, excluded.last_ts), unread = excluded.unread,
					pinned = CASE WHEN excluded.pinned > 0 THEN excluded.pinned ELSE pinned END, archived = excluded.archived, mute_until = excluded.mute_until,
					read_only = excluded.read_only, wa_jid = excluded.wa_jid, marked = excluded.marked`,
				chat.String(), conv.GetName(), int64(conv.GetConversationTimestamp()), unread,
				int64(conv.GetPinned()), conv.GetArchived(), mute, readOnly, jid.ToNonAD().String(), marked)
		}
		for _, hm := range conv.GetMessages() {
			b.historyMessage(jid, chat, hm.GetMessage())
		}
		if onDemand {
			emit(map[string]any{"t": "refresh", "chat": chat.String(), "older": true})
		}
	}
	// The phone's call log: each call in its chat.
	for _, r := range e.Data.GetCallLogRecords() {
		b.callRecord(r)
	}
	if !onDemand {
		emit(map[string]any{"t": "sync", "progress": e.Data.GetProgress(), "type": strings.ToLower(e.Data.GetSyncType().String())})
	}
	b.dirty.Store(true)
}

// historyMessage stores one message of a history sync.
func (b *Bridge) historyMessage(jid, chat types.JID, web *waWeb.WebMessageInfo) {
	if web == nil {
		return
	}
	// A notice: no content, a stub type and its parameters.
	if web.GetMessage() == nil && web.GetMessageStubType() != 0 {
		c, people, ok := stubOf(web)
		if !ok {
			return
		}
		var actor types.JID
		if p := web.GetParticipant(); p != "" {
			actor, _ = types.ParseJID(p)
		} else if p := web.GetKey().GetParticipant(); p != "" {
			actor, _ = types.ParseJID(p)
		}
		if web.GetKey().GetFromMe() {
			actor = b.me()
		}
		if c.Kind == "system" {
			b.system(chat, web.GetKey().GetID(), int64(web.GetMessageTimestamp()), actor, c, people)
			return
		}
		// A missed call or a deleted message: a message of its own kind.
		sender := chat
		if !actor.IsEmpty() {
			sender = b.norm(actor)
		}
		if call, ok := c.X["call"].(Call); ok {
			b.putCall(chat, "", web.GetKey().GetID(), int64(web.GetMessageTimestamp()), web.GetKey().GetFromMe(), sender, call)
			return
		}
		x := xJSON(chat.String(), web.GetKey().GetID(), c)
		b.db.Exec(`INSERT INTO messages (chat, id, sender, push_name, from_me, ts, kind, x, status) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 3)
			ON CONFLICT (chat, id) DO NOTHING`, chat.String(), web.GetKey().GetID(), sender.String(), web.GetPushName(), web.GetKey().GetFromMe(),
			int64(web.GetMessageTimestamp()), c.Kind, x)
		return
	}
	evt, err := b.cli.ParseWebMessage(jid, web)
	if err != nil {
		return
	}
	// A business's verified name, as WhatsApp Web shows it in place of
	// the number; live messages get it from whatsmeow itself.
	biz := web.GetVerifiedBizName()
	if evt.Info.IsFromMe || evt.Info.IsGroup {
		biz = ""
	}
	if biz != "" && b.stored() {
		b.cli.Store.Contacts.PutBusinessName(b.ctx, b.norm(evt.Info.Sender), biz)
	}
	// WebMessageInfo: 2 server ack, 3 delivered, 4 read, 5 played.
	status := 1
	switch s := int(web.GetStatus()); {
	case s >= 5:
		status = 4
	case s == 4:
		status = 3
	case s == 3:
		status = 2
	}
	b.message(evt, status)
	// Who got and read it, for its info.
	if web.GetKey().GetFromMe() {
		for _, r := range web.GetUserReceipt() {
			if j, err := types.ParseJID(r.GetUserJID()); err == nil && !b.mine(j) {
				b.receipted(chat.String(), web.GetKey().GetID(), b.norm(j).String(), r.GetReceiptTimestamp(), r.GetReadTimestamp(), r.GetPlayedTimestamp())
			}
		}
	}
	// On its chat too, now that the row is there.
	b.setBizName(chat.String(), biz)
	for _, r := range web.GetReactions() {
		b.react(chat.String(), web.GetKey().GetID(), b.reactionSender(chat, r.GetKey()), r.GetText(), r.GetSenderTimestampMS()/1000)
	}
	if web.GetStarred() {
		b.db.Exec(`UPDATE messages SET starred = 1 WHERE chat = ? AND id = ?`, chat.String(), web.GetKey().GetID())
	}
}

func (b *Bridge) receipt(e *events.Receipt) {
	chat := b.norm(e.Chat)
	switch e.Type {
	case types.ReceiptTypeReadSelf:
		// Read on another device: no longer unread here either.
		b.db.Exec(`UPDATE chats SET unread = 0, marked = 0 WHERE jid = ?`, chat.String())
		b.dirty.Store(true)
		emit(map[string]any{"t": "read", "chat": chat.String()})
		return
	}
	ts := e.Timestamp.Unix()
	if e.Timestamp.IsZero() {
		ts = time.Now().Unix()
	}
	var status int
	var delivered, read, played int64
	switch e.Type {
	case types.ReceiptTypeDelivered:
		status, delivered = 2, ts
	case types.ReceiptTypeRead:
		status, read = 3, ts
	case types.ReceiptTypePlayed:
		status, played = 4, ts
	default:
		return
	}
	// Who it was, for the message's info (before the app hears of it and
	// asks); your other devices aren't anyone.
	if who := b.norm(e.Sender); !b.mine(who) {
		for _, id := range e.MessageIDs {
			b.receipted(chat.String(), id, who.String(), delivered, read, played)
		}
	}
	if e.IsGroup {
		b.groupTicks(chat, e.MessageIDs, status)
		return
	}
	b.setStatus(chat, e.MessageIDs, status)
}

// groupTicks moves yours in a group on as its members' receipts come, as
// WhatsApp does: delivered at the first, read (or played) once everyone
// in it has.
func (b *Bridge) groupTicks(chat types.JID, ids []types.MessageID, status int) {
	others := 0
	if status > 2 {
		others = b.othersIn(chat)
	}
	by := map[int][]types.MessageID{}
	for _, id := range ids {
		s := 2
		if others > 0 {
			var read, played int
			b.db.QueryRow(`SELECT coalesce(sum(read > 0), 0), coalesce(sum(played > 0), 0) FROM receipts WHERE chat = ? AND id = ?`,
				chat.String(), id).Scan(&read, &played)
			switch {
			case played >= others:
				s = 4
			case read >= others:
				s = 3
			}
		}
		by[s] = append(by[s], id)
	}
	for s, ids := range by {
		b.setStatus(chat, ids, s)
	}
}

// receipted keeps when someone got, read or played one of your messages,
// the first time of each: a play is also a read, a read also a delivery.
func (b *Bridge) receipted(chat, id, user string, delivered, read, played int64) {
	if played > 0 && (read == 0 || played < read) {
		read = played
	}
	if read > 0 && (delivered == 0 || read < delivered) {
		delivered = read
	}
	b.db.Exec(`INSERT INTO receipts (chat, id, user, delivered, read, played) VALUES (?, ?, ?, ?, ?, ?)
		ON CONFLICT (chat, id, user) DO UPDATE SET
			delivered = min(coalesce(nullif(delivered, 0), excluded.delivered), coalesce(nullif(excluded.delivered, 0), delivered)),
			read = min(coalesce(nullif(read, 0), excluded.read), coalesce(nullif(excluded.read, 0), read)),
			played = min(coalesce(nullif(played, 0), excluded.played), coalesce(nullif(excluded.played, 0), played))`,
		chat, id, user, delivered, read, played)
}

func (b *Bridge) setStatus(chat types.JID, ids []types.MessageID, status int) {
	for _, id := range ids {
		if status < 0 {
			b.db.Exec(`UPDATE messages SET status = ? WHERE chat = ? AND id = ? AND from_me = 1`, status, chat.String(), id)
		} else {
			b.db.Exec(`UPDATE messages SET status = max(status, ?) WHERE chat = ? AND id = ? AND from_me = 1`, status, chat.String(), id)
		}
	}
	b.dirty.Store(true)
	emit(map[string]any{"t": "status", "chat": chat.String(), "ids": ids, "status": status})
}
