package main

// Messages going out, and what WhatsApp Web tells the others while you're
// there: read receipts, "typing…", online.

import (
	"strings"
	"time"

	"go.mau.fi/whatsmeow"
	"go.mau.fi/whatsmeow/appstate"
	"go.mau.fi/whatsmeow/proto/waE2E"
	"go.mau.fi/whatsmeow/proto/waSyncAction"
	"go.mau.fi/whatsmeow/types"
	"google.golang.org/protobuf/proto"
)

// readOnly says why nothing can be sent to the chat, "" when it can.
func (b *Bridge) readOnly(chat string) string {
	var ro string
	b.db.QueryRow(`SELECT read_only FROM chats WHERE jid = ?`, chat).Scan(&ro)
	return ro
}

// mentionedJIDs are the people the text's @s name: the ones the app picked,
// and any @number in it. An "@all" in a group names everyone (all), as
// WhatsApp's "@everyone": every member goes along too, for the apps that
// only know mentions by number.
func (b *Bridge) mentionedJIDs(chat types.JID, text string) (out []string, all bool) {
	got := map[string]bool{}
	for i := 0; i < len(text); i++ {
		if chat.Server == types.GroupServer && allAt(text, i) {
			all = true
			continue
		}
		user, end := mentionAt(text, i)
		if user == "" || got[user] {
			continue
		}
		got[user] = true
		i = end - 1
		server := types.DefaultUserServer
		if len(user) > 13 {
			server = types.HiddenUserServer
		}
		out = append(out, types.NewJID(user, server).String())
	}
	if all {
		if g, err := b.cli.GetGroupInfo(b.ctx, chat); err == nil {
			me := b.me()
			for _, p := range g.Participants {
				j := p.JID
				if j.User == me.User || p.PhoneNumber.User == me.User || got[j.User] || got[p.PhoneNumber.User] {
					continue
				}
				got[j.User] = true
				out = append(out, j.String())
			}
		}
	}
	return out, all
}

// send shows the message right away (pending) and again once the server took it.
func (b *Bridge) send(c Cmd) {
	text := strings.TrimSpace(c.Text)
	jid, err := types.ParseJID(c.Chat)
	if err != nil || text == "" {
		return
	}
	if ro := b.readOnly(c.Chat); ro != "" {
		fail("read_only_"+ro, nil)
		return
	}
	id := b.cli.GenerateMessageID()
	me := b.me()
	now := time.Now().Unix()
	out := &waE2E.Message{Conversation: proto.String(text)}
	q := b.quoting(c.Chat, c.Reply)
	mentioned, all := b.mentionedJIDs(jid, text)
	link := firstURL(text)
	if q != nil || len(mentioned) > 0 || all || link != "" {
		ci := &waE2E.ContextInfo{}
		if q != nil {
			ci = q.ctx
		}
		ci.MentionedJID = mentioned
		if all {
			ci.NonJIDMentions = proto.Uint32(1)
		}
		ext := &waE2E.ExtendedTextMessage{Text: proto.String(text), ContextInfo: ci}
		if link != "" {
			ext.MatchedText = proto.String(link)
		}
		out = &waE2E.Message{ExtendedTextMessage: ext}
	}
	qID, qFrom, qKind, qText, qThumb := q.cols()
	b.db.Exec(`INSERT INTO messages (chat, id, sender, from_me, ts, kind, text, quote_id, quote_from, quote_kind, quote_text, quote_thumb, status)
		VALUES (?, ?, ?, 1, ?, 'text', ?, ?, ?, ?, ?, ?, 0)`, c.Chat, id, me.String(), now, text, qID, qFrom, qKind, qText, qThumb)
	b.db.Exec(`INSERT INTO chats (jid, last_ts) VALUES (?, ?) ON CONFLICT (jid) DO UPDATE SET last_ts = excluded.last_ts, cleared = 0, archived = 0`, c.Chat, now)
	b.emitMsg(c.Chat, id)
	b.flush()

	_, err = b.cli.SendMessage(b.ctx, jid, out, whatsmeow.SendRequestExtra{ID: id})
	if err != nil {
		logf("send %s: %v", c.Chat, err)
		b.setStatus(jid, []types.MessageID{id}, -1)
		fail("send", err)
		return
	}
	b.setStatus(jid, []types.MessageID{id}, 1)
}

// markRead sends read receipts for the chat's unread messages (the last
// `unread` received ones), grouped by sender as groups require. Quiet ones
// reach only your other devices, so the sender sees no blue ticks. A chat
// marked unread by hand (or `patch`, the menu's "Mark as read") also
// tells the app state, or the phone keeps its mark.
func (b *Bridge) markRead(chat string, quiet, patch bool) {
	var unread int
	var marked bool
	if b.db.QueryRow(`SELECT unread, marked FROM chats WHERE jid = ?`, chat).Scan(&unread, &marked) != nil || unread == 0 && !marked {
		return
	}
	b.db.Exec(`UPDATE chats SET unread = 0, marked = 0 WHERE jid = ?`, chat)
	b.dirty.Store(true)
	jid, err := types.ParseJID(chat)
	if err != nil {
		return
	}
	if marked || patch {
		ts, key := b.lastKey(chat)
		if err := b.cli.SendAppState(b.ctx, appstate.BuildMarkChatAsRead(b.waJID(chat), true, ts, key)); err != nil {
			logf("mark read %s: %v", chat, err)
		}
	}
	ms := b.query(`WHERE chat = ? AND from_me = 0 AND messages.kind NOT IN ('system', 'placeholder', 'call') ORDER BY ts DESC LIMIT ?`, chat, min(max(unread, 1), 50))
	bySender := map[string][]types.MessageID{}
	waSender := map[string]string{}
	for _, m := range ms {
		bySender[m.Sender] = append(bySender[m.Sender], m.ID)
	}
	if jid.Server == types.GroupServer {
		for s := range bySender {
			var wa string
			b.db.QueryRow(`SELECT wa_sender FROM messages WHERE chat = ? AND sender = ? AND wa_sender != '' ORDER BY ts DESC LIMIT 1`, chat, s).Scan(&wa)
			waSender[s] = wa
		}
	}
	for sender, ids := range bySender {
		s := types.EmptyJID
		if jid.Server == types.GroupServer {
			for _, cand := range []string{waSender[sender], sender} {
				if j, err := types.ParseJID(cand); err == nil && cand != "" {
					s = j
					break
				}
			}
		}
		kind := types.ReceiptTypeRead
		if quiet {
			kind = types.ReceiptTypeReadSelf
		}
		if err := b.cli.MarkRead(b.ctx, ids, time.Now(), b.waJID(chat), s, kind); err != nil {
			logf("mark read %s: %v", chat, err)
		}
	}
}

// typing tells the chat you're writing (composing), recording a voice
// note (recording) or stopped (paused).
func (b *Bridge) typing(chat, state string) {
	jid, err := types.ParseJID(chat)
	if err != nil || !b.cli.IsConnected() {
		return
	}
	st, media := types.ChatPresencePaused, types.ChatPresenceMediaText
	switch state {
	case "composing":
		st = types.ChatPresenceComposing
	case "recording":
		st, media = types.ChatPresenceComposing, types.ChatPresenceMediaAudio
	}
	if err := b.cli.SendChatPresence(b.ctx, jid, st, media); err != nil {
		logf("typing %s: %v", chat, err)
	}
}

// setPresence is "online" while the app's window is in front, as WhatsApp
// Web's tab: the phone stops notifying then, and other people's online
// and typing reach this device.
func (b *Bridge) setPresence(available bool) {
	b.online.Store(available)
	if !b.cli.IsConnected() || b.cli.Store.PushName == "" {
		return
	}
	p := types.PresenceUnavailable
	if available {
		p = types.PresenceAvailable
	}
	if err := b.cli.SendPresence(b.ctx, p); err != nil {
		logf("presence: %v", err)
	}
}

// subscribe asks for someone's online and last seen, for the chat's
// header; groups have none.
func (b *Bridge) subscribe(chat string) {
	jid, err := types.ParseJID(chat)
	if err != nil || jid.Server != types.DefaultUserServer || !b.cli.IsConnected() {
		return
	}
	if err := b.cli.SubscribePresence(b.ctx, jid); err != nil {
		logf("subscribe %s: %v", chat, err)
	}
}

// star marks messages starred (or not), here and on your other devices.
func (b *Bridge) star(chat string, ids []string, on bool) {
	wa := b.waJID(chat)
	if wa.IsEmpty() {
		return
	}
	var muts []appstate.MutationInfo
	for _, id := range ids {
		var fromMe bool
		var sender, waSender string
		if b.db.QueryRow(`SELECT from_me, sender, wa_sender FROM messages WHERE chat = ? AND id = ?`, chat, id).Scan(&fromMe, &sender, &waSender) != nil {
			continue
		}
		mine, participant := "0", "0"
		if fromMe {
			mine = "1"
		} else if wa.Server == types.GroupServer {
			participant = waSender
			if participant == "" {
				participant = sender
			}
		}
		b.db.Exec(`UPDATE messages SET starred = ? WHERE chat = ? AND id = ?`, on, chat, id)
		b.emitMsg(chat, id)
		muts = append(muts, appstate.MutationInfo{
			Index:   []string{appstate.IndexStar, wa.String(), id, mine, participant},
			Version: 2,
			Value:   &waSyncAction.SyncActionValue{StarAction: &waSyncAction.StarAction{Starred: proto.Bool(on)}},
		})
	}
	if len(muts) == 0 {
		return
	}
	if err := b.cli.SendAppState(b.ctx, appstate.PatchInfo{Type: appstate.WAPatchRegularHigh, Mutations: muts}); err != nil {
		logf("star %s: %v", chat, err)
		fail("star", err)
	}
}
