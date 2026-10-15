package main

// Replies: a message sent as an answer to another carries the quoted one
// in its context, as WhatsApp sends it, and shows it quoted here at once.

import (
	"os"

	"go.mau.fi/whatsmeow/proto/waE2E"
	"go.mau.fi/whatsmeow/types"
	"google.golang.org/protobuf/proto"
)

// quoting is a reply's quoted message: the context it's sent with, and
// what's stored to show the quote.
type quoting struct {
	ctx                         *waE2E.ContextInfo
	id, from, kind, text, thumb string
}

// quoting finds the message a reply quotes; nil when it's not here.
func (b *Bridge) quoting(chat, id string) *quoting {
	if id == "" {
		return nil
	}
	var kind, text, sender, waSender string
	var blob []byte
	err := b.db.QueryRow(`SELECT messages.kind, text, sender, messages.wa_sender, proto FROM messages LEFT JOIN media USING (chat, id)
		WHERE chat = ? AND id = ?`, chat, id).Scan(&kind, &text, &sender, &waSender, &blob)
	if err != nil {
		return nil
	}
	// The participant names who wrote it as WhatsApp has them.
	by := b.me().String()
	for _, s := range []string{waSender, sender} {
		if j, err := types.ParseJID(s); err == nil && s != "" {
			by = j.String()
			break
		}
	}
	// A photo, video or file goes as stored; anything else as its text.
	quoted := partOf(blob)
	if quoted != nil {
		// Only the message, not what it replied to.
		setContext(quoted, nil)
	} else {
		quoted = &waE2E.Message{Conversation: proto.String(text)}
	}
	q := &quoting{
		ctx:  &waE2E.ContextInfo{StanzaID: proto.String(id), Participant: proto.String(by), QuotedMessage: quoted},
		id:   id,
		from: sender,
		kind: kind,
		text: text,
	}
	if t := thumbFile(chat, id, "thumb"); fileExists(t) {
		q.thumb = t
	} else if t := thumbFile(chat, id, "x"); fileExists(t) {
		q.thumb = t
	}
	return q
}

func fileExists(path string) bool {
	st, err := os.Stat(path)
	return err == nil && st.Size() > 0
}

// cols is what the messages table keeps of it: quote_id, quote_from,
// quote_kind, quote_text, quote_thumb.
func (q *quoting) cols() (string, string, string, string, string) {
	if q == nil {
		return "", "", "", "", ""
	}
	return q.id, q.from, q.kind, q.text, q.thumb
}

// setContext puts the context on a media message's part.
func setContext(m *waE2E.Message, ci *waE2E.ContextInfo) {
	switch {
	case m.ImageMessage != nil:
		m.ImageMessage.ContextInfo = ci
	case m.VideoMessage != nil:
		m.VideoMessage.ContextInfo = ci
	case m.PtvMessage != nil:
		m.PtvMessage.ContextInfo = ci
	case m.AudioMessage != nil:
		m.AudioMessage.ContextInfo = ci
	case m.DocumentMessage != nil:
		m.DocumentMessage.ContextInfo = ci
	case m.StickerMessage != nil:
		m.StickerMessage.ContextInfo = ci
	}
}
