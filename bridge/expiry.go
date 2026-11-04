package main

import (
	"encoding/json"
	"os"
	"time"

	"go.mau.fi/whatsmeow/proto/waE2E"
	"go.mau.fi/whatsmeow/proto/waWeb"
	"google.golang.org/protobuf/proto"
)

// Apply this at reads as well as cleanup: a stopped bridge must never expose
// expired rows on restart, even before its cleanup worker has caught up.
const liveMessage = `messages.kind != 'expired' AND (messages.expires_at = 0 OR messages.expires_at > unixepoch())`

func (b *Bridge) messageLive(chat, id string) bool {
	var exists bool
	return b.db.QueryRow(`SELECT EXISTS(SELECT 1 FROM messages WHERE chat = ? AND id = ? AND `+liveMessage+`)`, chat, id).Scan(&exists) == nil && exists
}

func (b *Bridge) messageExpired(chat, id string) bool {
	var expired bool
	return b.db.QueryRow(`SELECT kind='expired' OR (expires_at > 0 AND expires_at <= unixepoch()) FROM messages WHERE chat=? AND id=?`, chat, id).Scan(&expired) == nil && expired
}

func (b *Bridge) stripExpiredQuote(chat string, ci *waE2E.ContextInfo) {
	if ci != nil && ci.GetStanzaID() != "" && b.messageExpired(chat, ci.GetStanzaID()) {
		ci.QuotedMessage = nil
		ci.Participant = nil
		ci.StanzaID = nil
	}
}

// Older versions retained context on media but not on plain text. Recover
// timers where the original metadata still exists; never invent a text timer.
func (b *Bridge) recoverExpiry() {
	if b.meta("expiry_migration") != "" {
		return
	}
	rows, err := b.db.Query(`SELECT chat,id,ts,proto FROM messages JOIN media USING(chat,id) WHERE expires_at=0`)
	if err != nil {
		return
	}
	type item struct {
		chat, id string
		expires  int64
	}
	var items []item
	for rows.Next() {
		var chat, id string
		var ts int64
		var blob []byte
		if rows.Scan(&chat, &id, &ts, &blob) != nil {
			continue
		}
		if deadline := messageDeadline(ts, contextOf(partOf(blob)).GetExpiration()); deadline > 0 {
			items = append(items, item{chat, id, deadline})
		}
	}
	if rows.Err() != nil {
		rows.Close()
		return
	}
	rows.Close()
	for _, i := range items {
		if _, err := b.db.Exec(`UPDATE messages SET expires_at=? WHERE chat=? AND id=? AND expires_at=0`, i.expires, i.chat, i.id); err != nil {
			return
		}
	}
	b.setMeta("expiry_migration", "1")
}

func earlierDeadline(a, b int64) int64 {
	if a <= 0 {
		return b
	}
	if b <= 0 {
		return a
	}
	return min(a, b)
}

func messageDeadline(ts int64, seconds uint32) int64 {
	if seconds == 0 {
		return 0
	}
	// Bad timestamps cannot produce an unlimited lifetime or overflow.
	if ts <= 0 || ts > time.Now().Unix() {
		ts = time.Now().Unix()
	}
	return ts + int64(seconds)
}

func historyDeadline(m *waWeb.WebMessageInfo, ts int64) int64 {
	deadline := int64(m.GetEphemeralExpirationTimestamp())
	if m.GetEphemeralExpirationTimestamp() > uint64(time.Now().Unix())+uint64(^uint32(0)) {
		deadline = time.Now().Unix()
	}
	if start := m.GetEphemeralStartTimestamp(); start > 0 && start <= uint64(time.Now().Unix()) {
		ts = int64(start)
	}
	return earlierDeadline(deadline, messageDeadline(ts, m.GetEphemeralDuration()))
}

type disappearingSetting struct {
	Seconds uint32 `json:"seconds"`
	TS      int64  `json:"ts"`
}

func (b *Bridge) disappearing(chat string) disappearingSetting {
	var s disappearingSetting
	_ = json.Unmarshal([]byte(b.meta("disappearing:"+chat)), &s)
	return s
}

func (b *Bridge) setDisappearing(chat string, seconds uint32, ts int64) {
	// History pages without a setting must not undo a live update.
	if ts <= 0 || ts > time.Now().Unix()+300 {
		return
	}
	old := b.disappearing(chat)
	if old.TS > ts {
		return
	}
	data, _ := json.Marshal(disappearingSetting{seconds, ts})
	b.setMeta("disappearing:"+chat, string(data))
}

// Attach the known chat timer to every outgoing content type too.
func (b *Bridge) outgoingDeadline(chat string, m *waE2E.Message, ts int64) int64 {
	s := b.disappearing(chat)
	if s.Seconds == 0 {
		return 0
	}
	ci := contextOf(m)
	if ci == nil {
		ci = &waE2E.ContextInfo{}
	}
	ci.Expiration = proto.Uint32(s.Seconds)
	ci.EphemeralSettingTimestamp = proto.Int64(s.TS)
	if m.Conversation != nil {
		m.ExtendedTextMessage = &waE2E.ExtendedTextMessage{Text: m.Conversation}
		m.Conversation = nil
	}
	setContext(m, ci)
	return messageDeadline(ts, s.Seconds)
}

func (b *Bridge) expiryLoop() {
	ticker := time.NewTicker(time.Second)
	defer ticker.Stop()
	for range ticker.C {
		b.expireMessages()
	}
}

func (b *Bridge) expireMessages() {
	b.messageMu.Lock()
	defer b.messageMu.Unlock()
	b.mediaMu.Lock()
	defer b.mediaMu.Unlock()
	rows, err := b.db.Query(`SELECT messages.chat, messages.id, COALESCE(media.mime, ''), media.proto FROM messages LEFT JOIN media USING(chat,id)
		WHERE expires_at > 0 AND expires_at <= unixepoch() AND messages.kind != 'expired' LIMIT 500`)
	if err != nil {
		return
	}
	type expired struct {
		chat, id, mime string
		blob           []byte
	}
	var due []expired
	for rows.Next() {
		var e expired
		if rows.Scan(&e.chat, &e.id, &e.mime, &e.blob) == nil {
			due = append(due, e)
		}
	}
	rows.Close()
	byChat := map[string][]string{}
	for _, e := range due {
		tx, err := b.db.Begin()
		if err != nil {
			return
		}
		// Keep only an ID tombstone, so an old history page cannot restore it.
		_, err = tx.Exec(`UPDATE messages SET kind='expired', text='', x='', card='', push_name='',
			quote_id='', quote_from='', quote_kind='', quote_text='', quote_thumb='', edited=0, starred=0, forwarded=0
			WHERE chat=? AND id=?`, e.chat, e.id)
		if err == nil {
			// A reply's media protobuf can carry a full copy of the quoted
			// content and its keys, independent of the visible quote columns.
			var refs []struct {
				id   string
				blob []byte
			}
			quoted, queryErr := tx.Query(`SELECT media.id,proto FROM media JOIN messages USING(chat,id) WHERE chat=? AND quote_id=?`, e.chat, e.id)
			if queryErr != nil {
				err = queryErr
			} else {
				for quoted.Next() {
					var ref struct {
						id   string
						blob []byte
					}
					if scanErr := quoted.Scan(&ref.id, &ref.blob); scanErr != nil {
						err = scanErr
						break
					}
					refs = append(refs, ref)
				}
				if rowsErr := quoted.Err(); rowsErr != nil {
					err = rowsErr
				}
				quoted.Close()
			}
			for _, ref := range refs {
				if err != nil {
					break
				}
				part := partOf(ref.blob)
				ci := contextOf(part)
				if ci == nil {
					continue
				}
				ci.QuotedMessage, ci.Participant, ci.StanzaID = nil, nil, nil
				var blob []byte
				blob, err = proto.Marshal(part)
				if err == nil {
					_, err = tx.Exec(`UPDATE media SET proto=? WHERE chat=? AND id=?`, blob, e.chat, ref.id)
				}
			}
		}
		if err == nil {
			_, err = tx.Exec(`UPDATE messages SET quote_from='', quote_kind='expired', quote_text='', quote_thumb='' WHERE chat=? AND quote_id=?`, e.chat, e.id)
		}
		for _, table := range []string{"media", "reactions", "receipts"} {
			if err == nil {
				_, err = tx.Exec(`DELETE FROM `+table+` WHERE chat=? AND id=?`, e.chat, e.id)
			}
		}
		if err != nil {
			tx.Rollback()
			continue
		}
		// Remove files before committing the tombstone, so interrupted cleanup
		// is retried next startup. Download completion uses this same lock.
		paths := []string{mediaFile(e.chat, e.id, e.mime)}
		if sticker := partOf(e.blob).GetStickerMessage(); len(sticker.GetFileSHA256()) > 0 {
			var favorite bool
			if tx.QueryRow(`SELECT EXISTS(SELECT 1 FROM fav_stickers WHERE hash=?)`, b64(sticker.GetFileSHA256())).Scan(&favorite) == nil && !favorite {
				paths = append(paths, stickerFile(sticker.GetFileSHA256()))
			}
		}
		for _, kind := range []string{"thumb", "frame", "x"} {
			paths = append(paths, thumbFile(e.chat, e.id, kind))
		}
		removed := true
		for _, p := range paths {
			for _, path := range []string{p, p + ".tmp"} {
				if err := os.Remove(path); err != nil && !os.IsNotExist(err) {
					removed = false
				}
			}
		}
		if !removed {
			tx.Rollback()
			continue
		}
		if tx.Commit() != nil {
			continue
		}
		byChat[e.chat] = append(byChat[e.chat], e.id)
		takeRecovery(e.chat, e.id)
		takeReupload(e.id)
	}
	for chat, ids := range byChat {
		b.db.Exec(`UPDATE chats SET last_ts=COALESCE((SELECT max(ts) FROM messages WHERE chat=? AND `+liveMessage+`),0),
			unread=min(unread,(SELECT count(*) FROM messages WHERE chat=? AND from_me=0 AND `+liveMessage+`)), cleared=1 WHERE jid=?`, chat, chat, chat)
		player.expire(chat, ids)
		emit(map[string]any{"t": "removed", "chat": chat, "ids": ids, "expired": true})
		b.dirty.Store(true)
	}
}
