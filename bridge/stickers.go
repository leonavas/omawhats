package main

// Favorite stickers, as WhatsApp keeps them in its app state: one
// "favoriteSticker" mutation each, indexed by the file's SHA-256 and with
// what's needed to download it. The viewer adds or removes the one it shows;
// the phone's changes come as app state events (removals only in the log).

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"go.mau.fi/whatsmeow"
	"go.mau.fi/whatsmeow/types"

	"go.mau.fi/whatsmeow/appstate"
	"go.mau.fi/whatsmeow/proto/waE2E"
	"go.mau.fi/whatsmeow/proto/waSyncAction"
	"google.golang.org/protobuf/proto"
)

// stickerVersion is the mutation's version until one comes from the phone
// (see stickerLog): whatsmeow has no builder, so no number, for it.
const stickerVersion = 7

func b64(b []byte) string {
	if len(b) == 0 {
		return ""
	}
	return base64.StdEncoding.EncodeToString(b)
}

// favSticker keeps one from the phone; a false isFavorite takes it out.
func (b *Bridge) favSticker(hash string, a *waSyncAction.StickerAction) {
	if a == nil || hash == "" {
		return
	}
	if a.IsFavorite != nil && !a.GetIsFavorite() {
		b.db.Exec(`DELETE FROM fav_stickers WHERE hash = ?`, hash)
		return
	}
	blob, _ := proto.Marshal(a)
	b.db.Exec(`INSERT INTO fav_stickers (hash, enc_hash, action) VALUES (?, ?, ?)
		ON CONFLICT (hash) DO UPDATE SET enc_hash = excluded.enc_hash, action = excluded.action`, hash, b64(a.GetFileEncSHA256()), blob)
}

// stickerLog reads a favoriteSticker line of whatsmeow's log (favLog): the
// version and collection the phone writes them with, and the removals,
// which whatsmeow sends no event for.
func (b *Bridge) stickerLog(p []byte) {
	var r struct {
		Message   string   `json:"message"`
		Patch     string   `json:"patch_name"`
		Version   int32    `json:"version"`
		Operation string   `json:"operation"`
		Index     []string `json:"index"`
	}
	if json.Unmarshal(p, &r) != nil || r.Message != "Received app state mutation" {
		return
	}
	if r.Version > 0 && r.Patch != "" {
		b.setMeta("sticker_version", strconv.Itoa(int(r.Version)))
		b.setMeta("sticker_patch", r.Patch)
	}
	if r.Operation == "REMOVE" && len(r.Index) > 1 {
		b.db.Exec(`DELETE FROM fav_stickers WHERE hash = ?`, r.Index[1])
	}
}

// stickersOnce reads regular_low in full, once per account: the syncs
// from before favorite stickers were kept left them out.
func (b *Bridge) stickersOnce() {
	if b.meta("stickers") != "" {
		return
	}
	if err := b.cli.FetchAppState(b.ctx, appstate.WAPatchRegularLow, true, false); err != nil {
		logf("app state resync for stickers: %v", err)
		return
	}
	b.setMeta("stickers", "1")
}

// stickerOf is the message's sticker as stored, keys and all; nil when it
// isn't one or its keys weren't kept.
func (b *Bridge) stickerOf(chat, id string) *waE2E.StickerMessage {
	var blob []byte
	b.db.QueryRow(`SELECT proto FROM media WHERE chat = ? AND id = ? AND kind = 'sticker'`, chat, id).Scan(&blob)
	x := partOf(blob).GetStickerMessage()
	if len(x.GetFileSHA256()) == 0 || len(x.GetMediaKey()) == 0 {
		return nil
	}
	return x
}

// stickerFav says whether the viewer's sticker is a favorite, or with
// favorite/unfavorite makes it one or not: here first, then the patch,
// undone if WhatsApp refuses it. The answer is a `sticker_fav` event.
func (b *Bridge) stickerFav(c Cmd) {
	x := b.stickerOf(c.Chat, c.ID)
	if x == nil {
		return
	}
	hash, enc := b64(x.GetFileSHA256()), b64(x.GetFileEncSHA256())
	// The phone's by its index or, should it index them otherwise, by the encrypted file's hash.
	var key string
	var stored []byte
	b.db.QueryRow(`SELECT hash, action FROM fav_stickers WHERE hash = ? OR (enc_hash != '' AND enc_hash = ?)`, hash, enc).Scan(&key, &stored)
	if key != "" && key != hash {
		logf("favorite sticker indexed as %s, not by its file hash %s", key, hash)
	}
	state := func(on bool) {
		emit(map[string]any{"t": "sticker_fav", "chat": c.Chat, "id": c.ID, "fav": on})
	}
	on := c.Action == "favorite"
	if (c.Action != "favorite" && c.Action != "unfavorite") || on == (key != "") {
		state(key != "")
		return
	}
	a := &waSyncAction.StickerAction{
		URL:             proto.String(x.GetURL()),
		FileEncSHA256:   x.GetFileEncSHA256(),
		MediaKey:        x.GetMediaKey(),
		Mimetype:        proto.String(x.GetMimetype()),
		Height:          proto.Uint32(x.GetHeight()),
		Width:           proto.Uint32(x.GetWidth()),
		DirectPath:      proto.String(x.GetDirectPath()),
		FileLength:      proto.Uint64(x.GetFileLength()),
		IsLottie:        proto.Bool(x.GetIsLottie()),
		IsAvatarSticker: proto.Bool(x.GetIsAvatar()),
	}
	if on {
		key = hash
		blob, _ := proto.Marshal(a)
		b.db.Exec(`INSERT OR REPLACE INTO fav_stickers (hash, enc_hash, action) VALUES (?, ?, ?)`, key, enc, blob)
	} else {
		// Taken out as the phone put it in.
		if old := (&waSyncAction.StickerAction{}); stored != nil && proto.Unmarshal(stored, old) == nil {
			a = old
		}
		b.db.Exec(`DELETE FROM fav_stickers WHERE hash = ?`, key)
	}
	a.IsFavorite = proto.Bool(on)
	state(on)
	version, _ := strconv.Atoi(b.meta("sticker_version"))
	if version <= 0 {
		version = stickerVersion
	}
	collection := b.meta("sticker_patch")
	if collection == "" {
		collection = string(appstate.WAPatchRegularLow)
	}
	patch := appstate.PatchInfo{
		Type: appstate.WAPatchName(collection),
		Mutations: []appstate.MutationInfo{{
			Index:   []string{appstate.IndexFavoriteSticker, key},
			Version: int32(version),
			Value:   &waSyncAction.SyncActionValue{StickerAction: a},
		}},
	}
	if err := b.cli.SendAppState(b.ctx, patch); err != nil {
		logf("sticker %s %s %s: %v", c.Action, c.Chat, c.ID, err)
		fail("sticker_fav", err)
		if on {
			b.db.Exec(`DELETE FROM fav_stickers WHERE hash = ?`, key)
		} else {
			a.IsFavorite = proto.Bool(true)
			blob, _ := proto.Marshal(a)
			b.db.Exec(`INSERT OR REPLACE INTO fav_stickers (hash, enc_hash, action) VALUES (?, ?, ?)`, key, b64(a.GetFileEncSHA256()), blob)
		}
		state(!on)
	}
}

// stickerItem is one sticker of the panel: a favorite (by its hash) or a
// recent one (by the message it came in), and its file once downloaded.
type stickerItem struct {
	Hash string `json:"hash,omitempty"`
	Chat string `json:"chat,omitempty"`
	ID   string `json:"id,omitempty"`
	Path string `json:"path"`
	Fav  bool   `json:"fav,omitempty"`
}

// stickerFile is where a sticker's file goes, by its file hash.
func stickerFile(sha []byte) string {
	name := strings.NewReplacer("/", "_", "+", "-", "=", "").Replace(b64(sha))
	return filepath.Join(cacheRoot, "stickers", name+".webp")
}

// stickerList answers the sticker panel: the favorites, then the recent
// ones (sent or received), each downloaded once into the cache.
func (b *Bridge) stickerList() {
	out := []stickerItem{}
	seen := map[string]bool{}
	get := func(x *waE2E.StickerMessage) string {
		path := stickerFile(x.GetFileSHA256())
		if fileExists(path) {
			touch(path)
			return path
		}
		ctx, cancel := context.WithTimeout(b.ctx, 30*time.Second)
		defer cancel()
		data, err := b.cli.Download(ctx, x)
		if err != nil || writeFile(path, data) != nil {
			return ""
		}
		return path
	}
	if rows, err := b.db.Query(`SELECT hash, action FROM fav_stickers`); err == nil {
		type fav struct {
			hash string
			a    *waSyncAction.StickerAction
		}
		var favs []fav
		for rows.Next() {
			var hash string
			var blob []byte
			a := &waSyncAction.StickerAction{}
			if rows.Scan(&hash, &blob) == nil && proto.Unmarshal(blob, a) == nil {
				favs = append(favs, fav{hash, a})
			}
		}
		rows.Close()
		for _, f := range favs {
			sha, _ := base64.StdEncoding.DecodeString(f.hash)
			x := &waE2E.StickerMessage{URL: f.a.URL, FileSHA256: sha, FileEncSHA256: f.a.FileEncSHA256, MediaKey: f.a.MediaKey,
				Mimetype: f.a.Mimetype, DirectPath: f.a.DirectPath, FileLength: f.a.FileLength}
			if p := get(x); p != "" {
				seen[f.hash] = true
				out = append(out, stickerItem{Hash: f.hash, Path: p, Fav: true})
			}
		}
	}
	if rows, err := b.db.Query(`SELECT m.chat, m.id, md.proto FROM messages m JOIN media md USING (chat, id)
		WHERE md.kind = 'sticker' ORDER BY m.ts DESC LIMIT 120`); err == nil {
		type recent struct {
			chat, id string
			x        *waE2E.StickerMessage
		}
		var rs []recent
		for rows.Next() {
			var chat, id string
			var blob []byte
			if rows.Scan(&chat, &id, &blob) != nil {
				continue
			}
			x := partOf(blob).GetStickerMessage()
			h := b64(x.GetFileSHA256())
			if x == nil || h == "" || seen[h] || len(x.GetMediaKey()) == 0 {
				continue
			}
			seen[h] = true
			rs = append(rs, recent{chat, id, x})
			if len(rs) >= 40 {
				break
			}
		}
		rows.Close()
		for _, r := range rs {
			if p := get(r.x); p != "" {
				out = append(out, stickerItem{Chat: r.chat, ID: r.id, Path: p})
			}
		}
	}
	emit(map[string]any{"t": "stickers", "stickers": out})
}

// sendSticker sends a sticker of the panel again, with the keys it came
// with: nothing is uploaded.
func (b *Bridge) sendSticker(c Cmd) {
	jid, err := types.ParseJID(c.Chat)
	if err != nil {
		return
	}
	if ro := b.readOnly(c.Chat); ro != "" {
		fail("read_only_"+ro, nil)
		return
	}
	var x *waE2E.StickerMessage
	if c.ID != "" {
		x = b.stickerOf(c.From, c.ID)
	} else if c.Name != "" {
		var blob []byte
		a := &waSyncAction.StickerAction{}
		if b.db.QueryRow(`SELECT action FROM fav_stickers WHERE hash = ?`, c.Name).Scan(&blob) == nil && proto.Unmarshal(blob, a) == nil {
			sha, _ := base64.StdEncoding.DecodeString(c.Name)
			x = &waE2E.StickerMessage{URL: a.URL, FileSHA256: sha, FileEncSHA256: a.FileEncSHA256, MediaKey: a.MediaKey,
				Mimetype: a.Mimetype, DirectPath: a.DirectPath, FileLength: a.FileLength, Height: a.Height, Width: a.Width,
				IsAnimated: proto.Bool(false), MediaKeyTimestamp: proto.Int64(time.Now().Unix())}
		}
	}
	if x == nil {
		fail("sticker", nil)
		return
	}
	x = proto.Clone(x).(*waE2E.StickerMessage)
	x.ContextInfo = nil
	msg := &waE2E.Message{StickerMessage: x}
	q := b.quoting(c.Chat, c.Reply)
	if q != nil {
		x.ContextInfo = q.ctx
	}
	id := b.cli.GenerateMessageID()
	me := b.me().String()
	now := time.Now().Unix()
	qID, qFrom, qKind, qText, qThumb := q.cols()
	b.db.Exec(`INSERT INTO messages (chat, id, sender, from_me, ts, kind, quote_id, quote_from, quote_kind, quote_text, quote_thumb, status)
		VALUES (?, ?, ?, 1, ?, 'sticker', ?, ?, ?, ?, ?, 0)`, c.Chat, id, me, now, qID, qFrom, qKind, qText, qThumb)
	md, part := mediaOf(msg)
	b.storeMedia(c.Chat, id, md, part, jid.String(), me)
	if p := stickerFile(x.GetFileSHA256()); fileExists(p) {
		linkOrCopy(p, mediaFile(c.Chat, id, "image/webp"))
	}
	b.db.Exec(`INSERT INTO chats (jid, last_ts) VALUES (?, ?) ON CONFLICT (jid) DO UPDATE SET last_ts = excluded.last_ts, cleared = 0, archived = 0`, c.Chat, now)
	b.emitMsg(c.Chat, id)
	b.flush()
	if _, err := b.cli.SendMessage(b.ctx, jid, msg, whatsmeow.SendRequestExtra{ID: id}); err != nil {
		b.setStatus(jid, []types.MessageID{id}, -1)
		fail("send", err)
		return
	}
	b.setStatus(jid, []types.MessageID{id}, 1)
}
