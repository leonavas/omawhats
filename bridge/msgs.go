package main

// A message's own menu: edit yours, delete for you or for everyone. As with
// the chats, the change is made here first and sent to the app at once,
// then to WhatsApp; if WhatsApp refuses it, it goes back.

import (
	"strings"

	"go.mau.fi/whatsmeow/appstate"
	"go.mau.fi/whatsmeow/proto/waE2E"
	"go.mau.fi/whatsmeow/proto/waSyncAction"
	"go.mau.fi/whatsmeow/types"
	"google.golang.org/protobuf/proto"
)

// removeMsgs drops messages from here and tells the app.
func (b *Bridge) removeMsgs(chat string, ids []string) {
	if len(ids) == 0 {
		return
	}
	args := []any{chat}
	for _, id := range ids {
		args = append(args, id)
	}
	in := `chat = ? AND id IN (?` + strings.Repeat(", ?", len(ids)-1) + `)`
	for _, t := range []string{"messages", "media", "reactions"} {
		b.db.Exec(`DELETE FROM `+t+` WHERE `+in, args...)
	}
	b.dirty.Store(true)
	emit(map[string]any{"t": "removed", "chat": chat, "ids": ids})
}

// deleteForMe drops the messages here and tells your other devices, through
// the app state, as the phone's "Delete for me" does.
func (b *Bridge) deleteForMe(chat string, ids []string) {
	wa := b.waJID(chat)
	if wa.IsEmpty() {
		return
	}
	var muts []appstate.MutationInfo
	for _, id := range ids {
		var fromMe bool
		var ts int64
		var sender, waSender string
		if b.db.QueryRow(`SELECT from_me, ts, sender, wa_sender FROM messages WHERE chat = ? AND id = ?`, chat, id).
			Scan(&fromMe, &ts, &sender, &waSender) != nil {
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
		muts = append(muts, appstate.MutationInfo{
			Index:   []string{appstate.IndexDeleteMessageForMe, wa.String(), id, mine, participant},
			Version: 3,
			Value: &waSyncAction.SyncActionValue{DeleteMessageForMeAction: &waSyncAction.DeleteMessageForMeAction{
				DeleteMedia:      proto.Bool(false),
				MessageTimestamp: proto.Int64(ts),
			}},
		})
	}
	b.removeMsgs(chat, ids)
	b.flush()
	if len(muts) == 0 {
		return
	}
	if err := b.cli.SendAppState(b.ctx, appstate.PatchInfo{Type: appstate.WAPatchRegularHigh, Mutations: muts}); err != nil {
		logf("delete for me %s: %v", chat, err)
		fail("delete_for_me", err)
	}
}

// revoke deletes your messages for everyone.
func (b *Bridge) revoke(chat string, ids []string) {
	jid, err := types.ParseJID(chat)
	if err != nil {
		return
	}
	for _, id := range ids {
		var fromMe bool
		if b.db.QueryRow(`SELECT from_me FROM messages WHERE chat = ? AND id = ?`, chat, id).Scan(&fromMe) != nil || !fromMe {
			continue
		}
		if _, err := b.cli.SendMessage(b.ctx, jid, b.cli.BuildRevoke(jid, types.EmptyJID, id)); err != nil {
			// The app already shows it gone: it comes back as it was.
			b.emitMsg(chat, id)
			fail("revoke", err)
			continue
		}
		b.db.Exec(`UPDATE messages SET kind = 'revoked', text = '', x = '', edited = 0, card = '' WHERE chat = ? AND id = ?`, chat, id)
		b.db.Exec(`DELETE FROM media WHERE chat = ? AND id = ?`, chat, id)
		b.db.Exec(`DELETE FROM reactions WHERE chat = ? AND id = ?`, chat, id)
		b.emitMsg(chat, id)
	}
	b.dirty.Store(true)
}

// edit changes the text of one of your messages (a photo's or video's
// caption too).
func (b *Bridge) edit(chat, id, text string) {
	text = strings.TrimSpace(text)
	jid, err := types.ParseJID(chat)
	if err != nil || text == "" {
		return
	}
	var old, kind string
	var fromMe, edited bool
	var blob []byte
	if b.db.QueryRow(`SELECT text, messages.kind, from_me, edited, proto FROM messages LEFT JOIN media USING (chat, id) WHERE chat = ? AND id = ?`, chat, id).
		Scan(&old, &kind, &fromMe, &edited, &blob) != nil || !fromMe {
		return
	}
	content := &waE2E.Message{Conversation: proto.String(text)}
	if kind != "text" {
		part := partOf(blob)
		switch {
		case part.GetImageMessage() != nil:
			part.ImageMessage.Caption = proto.String(text)
		case part.GetVideoMessage() != nil:
			part.VideoMessage.Caption = proto.String(text)
		case part.GetDocumentMessage() != nil:
			part.DocumentMessage.Caption = proto.String(text)
		default:
			return
		}
		content = part
	}
	b.db.Exec(`UPDATE messages SET text = ?, edited = 1 WHERE chat = ? AND id = ?`, text, chat, id)
	b.emitMsg(chat, id)
	b.dirty.Store(true)
	if _, err := b.cli.SendMessage(b.ctx, jid, b.cli.BuildEdit(jid, id, content)); err != nil {
		b.db.Exec(`UPDATE messages SET text = ?, edited = ? WHERE chat = ? AND id = ?`, old, edited, chat, id)
		b.emitMsg(chat, id)
		fail("edit", err)
	}
}

// deleteMsgs is the app's "Delete": for everyone, or for you only.
func (b *Bridge) deleteMsgs(chat string, ids []string, everyone bool) {
	if everyone {
		b.revoke(chat, ids)
	} else {
		b.deleteForMe(chat, ids)
	}
}
