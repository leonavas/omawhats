package main

// Media kept to be downloaded later: what each message carries is stored
// with it, and `download` fetches it into the cache on demand.

import (
	"context"
	"database/sql"
	"errors"
	"io"
	"mime"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"go.mau.fi/whatsmeow"
	"go.mau.fi/whatsmeow/proto/waE2E"
	"go.mau.fi/whatsmeow/proto/waMmsRetry"
	"go.mau.fi/whatsmeow/types"
	"go.mau.fi/whatsmeow/types/events"
	"google.golang.org/protobuf/proto"
)

// Media is what the app shows of a file before (and after) it's downloaded.
type Media struct {
	// audio, image, video, ptv, document, sticker.
	Kind    string `json:"kind"`
	Mime    string `json:"mime,omitempty"`
	Seconds uint32 `json:"secs,omitempty"`
	// A voice note, recorded in the app, rather than an audio file.
	PTT bool `json:"ptt,omitempty"`
	// A photo's or video's size, and a JPEG of it on disk to show until
	// (for a video, in place of) the file: the one its message carries, or
	// a frame of the video once that's here.
	Width  uint32 `json:"w,omitempty"`
	Height uint32 `json:"h,omitempty"`
	Thumb  string `json:"thumb,omitempty"`
	// A GIF: a video that loops, without sound.
	GIF bool `json:"gif,omitempty"`
	// The file, once it's in the cache.
	File string `json:"file,omitempty"`
	// A document's name, size and pages.
	Size  uint64 `json:"size,omitempty"`
	Name  string `json:"name,omitempty"`
	Pages uint32 `json:"pages,omitempty"`
	// A voice note's waveform: 64 levels, 0 to 100.
	Wave []int `json:"wave,omitempty"`
	// A sticker that moves.
	Animated bool `json:"animated,omitempty"`
}

const unavailable = "unavailable"

// mediaOf finds the downloadable part of a message: what it is, and a
// message with only that part, to keep for downloading it later.
func mediaOf(m *waE2E.Message) (*Media, *waE2E.Message) {
	// A business's card: the photo or video at its top.
	if c := cardOf(m); c != nil && c.header != nil {
		m = c.header
	}
	switch {
	case m.GetAudioMessage() != nil:
		x := m.GetAudioMessage()
		return &Media{Kind: "audio", Mime: x.GetMimetype(), Seconds: x.GetSeconds(), PTT: x.GetPTT()}, &waE2E.Message{AudioMessage: x}
	case m.GetImageMessage() != nil:
		x := m.GetImageMessage()
		return &Media{Kind: "image", Mime: x.GetMimetype()}, &waE2E.Message{ImageMessage: x}
	case m.GetVideoMessage() != nil:
		x := m.GetVideoMessage()
		return &Media{Kind: "video", Mime: x.GetMimetype(), Seconds: x.GetSeconds()}, &waE2E.Message{VideoMessage: x}
	case m.GetPtvMessage() != nil:
		x := m.GetPtvMessage()
		return &Media{Kind: "ptv", Mime: x.GetMimetype(), Seconds: x.GetSeconds()}, &waE2E.Message{PtvMessage: x}
	case m.GetDocumentMessage() != nil:
		x := m.GetDocumentMessage()
		return &Media{Kind: "document", Mime: x.GetMimetype()}, &waE2E.Message{DocumentMessage: x}
	case m.GetStickerMessage() != nil:
		x := m.GetStickerMessage()
		return &Media{Kind: "sticker", Mime: x.GetMimetype()}, &waE2E.Message{StickerMessage: x}
	}
	return nil, nil
}

func partOf(blob []byte) *waE2E.Message {
	part := &waE2E.Message{}
	if blob == nil || proto.Unmarshal(blob, part) != nil {
		return nil
	}
	return part
}

// thumbFile is where a message's small picture goes: its thumbnail
// ("thumb"), a video's frame ("frame") or its x object's ("x").
func thumbFile(chat, id, what string) string {
	name := strings.NewReplacer("@", "_", ".", "_", ":", "_", "/", "_").Replace(chat + "_" + id)
	return filepath.Join(mediaDir(), name+"."+what+".jpg")
}

// fill completes what a media's bubble shows from the part its message
// carries: sizes, a document's name and pages, a voice note's waveform,
// and the thumbnail, written to disk once.
func (md *Media) fill(chat, id string, part *waE2E.Message) {
	path := mediaFile(chat, id, md.Mime)
	thumbPath, framePath := thumbFile(chat, id, "thumb"), thumbFile(chat, id, "frame")
	touch(path, thumbPath, framePath)
	if st, err := os.Stat(path); err == nil && st.Size() > 0 {
		md.File = path
	}
	var thumb []byte
	switch {
	case part.GetImageMessage() != nil:
		x := part.GetImageMessage()
		md.Width, md.Height, thumb, md.Size = x.GetWidth(), x.GetHeight(), x.GetJPEGThumbnail(), x.GetFileLength()
	case part.GetVideoMessage() != nil || part.GetPtvMessage() != nil:
		x := part.GetVideoMessage()
		if x == nil {
			x = part.GetPtvMessage()
		}
		md.Width, md.Height, thumb, md.GIF, md.Size = x.GetWidth(), x.GetHeight(), x.GetJPEGThumbnail(), x.GetGifPlayback(), x.GetFileLength()
		if _, err := os.Stat(framePath); err == nil {
			md.Thumb = framePath
			return
		}
	case part.GetAudioMessage() != nil:
		x := part.GetAudioMessage()
		md.Size = x.GetFileLength()
		if w := x.GetWaveform(); len(w) > 0 {
			md.Wave = make([]int, len(w))
			for i, v := range w {
				md.Wave[i] = int(v)
			}
		}
		return
	case part.GetDocumentMessage() != nil:
		x := part.GetDocumentMessage()
		md.Name, md.Size, md.Pages, thumb = x.GetFileName(), x.GetFileLength(), x.GetPageCount(), x.GetJPEGThumbnail()
		md.Width, md.Height = x.GetThumbnailWidth(), x.GetThumbnailHeight()
		if md.Name == "" {
			md.Name = x.GetTitle()
		}
	case part.GetStickerMessage() != nil:
		// Its file is small: fetched as it shows, no thumbnail needed.
		x := part.GetStickerMessage()
		md.Width, md.Height, md.Animated, md.Size = x.GetWidth(), x.GetHeight(), x.GetIsAnimated(), x.GetFileLength()
		return
	default:
		return
	}
	if _, err := os.Stat(thumbPath); err == nil || (len(thumb) > 0 && writeFile(thumbPath, thumb) == nil) {
		md.Thumb = thumbPath
	}
}

// poster puts a sharper picture of a downloaded video in its bubble than
// the small one its message carries: a frame, through ffmpeg when it's there.
func poster(chat, id, path string) {
	out := thumbFile(chat, id, "frame")
	if _, err := os.Stat(out); err == nil {
		return
	}
	tmp := out + ".tmp"
	err := exec.Command("ffmpeg", "-v", "error", "-y", "-i", path, "-vf", "thumbnail=30,scale='min(720,iw)':-2",
		"-frames:v", "1", "-f", "mjpeg", tmp).Run()
	if err != nil || os.Rename(tmp, out) != nil {
		os.Remove(tmp)
		return
	}
	emit(map[string]any{"t": "thumb", "chat": chat, "id": id, "path": out})
}

func downloadable(m *waE2E.Message) whatsmeow.DownloadableMessage {
	switch {
	case m.GetAudioMessage() != nil:
		return m.GetAudioMessage()
	case m.GetImageMessage() != nil:
		return m.GetImageMessage()
	case m.GetVideoMessage() != nil:
		return m.GetVideoMessage()
	case m.GetPtvMessage() != nil:
		return m.GetPtvMessage()
	case m.GetDocumentMessage() != nil:
		return m.GetDocumentMessage()
	case m.GetStickerMessage() != nil:
		return m.GetStickerMessage()
	}
	return nil
}

func setDirectPath(m *waE2E.Message, p string) {
	switch {
	case m.GetAudioMessage() != nil:
		m.AudioMessage.DirectPath = &p
	case m.GetImageMessage() != nil:
		m.ImageMessage.DirectPath = &p
	case m.GetVideoMessage() != nil:
		m.VideoMessage.DirectPath = &p
	case m.GetPtvMessage() != nil:
		m.PtvMessage.DirectPath = &p
	case m.GetDocumentMessage() != nil:
		m.DocumentMessage.DirectPath = &p
	case m.GetStickerMessage() != nil:
		m.StickerMessage.DirectPath = &p
	}
}

// storeMedia keeps what a message's media is; a nil part keeps the keys
// stored before (a pending message rewritten).
func (b *Bridge) storeMedia(chat, id string, md *Media, part *waE2E.Message, waChat, waSender string) {
	if md == nil {
		return
	}
	var blob []byte
	if part != nil {
		blob, _ = proto.Marshal(part)
	}
	defer func() {
		if part != nil && takeRecovery(chat, id) {
			logf("recover %s %s: media arrived", chat, id)
			go func() {
				// Its bubble learns what it is, then it shows.
				b.emitMsg(chat, id)
				b.download(chat, id, false)
			}()
		}
	}()
	_, err := b.db.Exec(`INSERT INTO media (chat, id, kind, mime, seconds, ptt, proto, wa_chat, wa_sender) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
		ON CONFLICT (chat, id) DO UPDATE SET kind = excluded.kind, mime = excluded.mime,
			seconds = max(seconds, excluded.seconds), ptt = excluded.ptt, proto = COALESCE(excluded.proto, proto),
			wa_chat = excluded.wa_chat, wa_sender = excluded.wa_sender`,
		chat, id, md.Kind, md.Mime, md.Seconds, md.PTT, blob, waChat, waSender)
	if err != nil {
		logf("store media %s: %v", id, err)
	}
}

var exts = map[string]string{
	"audio/ogg": "ogg", "audio/mpeg": "mp3", "audio/mp4": "m4a", "audio/x-m4a": "m4a", "audio/aac": "aac", "audio/amr": "amr",
	"image/jpeg": "jpg", "image/png": "png", "image/webp": "webp", "video/mp4": "mp4", "video/3gpp": "3gp", "application/pdf": "pdf",
}

func extOf(mimeType string) string {
	t, _, _ := mime.ParseMediaType(mimeType)
	if e, ok := exts[t]; ok {
		return e
	}
	if es, _ := mime.ExtensionsByType(t); len(es) > 0 {
		return strings.TrimPrefix(es[0], ".")
	}
	return "bin"
}

// mediaDir is where the media goes: <cache>/media.
func mediaDir() string { return filepath.Join(cacheRoot, "media") }

// mediaFile is where a message's media goes: <mediaDir>/<chat>_<id>.<ext>.
func mediaFile(chat, id, mimeType string) string {
	name := strings.NewReplacer("@", "_", ".", "_", ":", "_", "/", "_").Replace(chat + "_" + id)
	return filepath.Join(mediaDir(), name+"."+extOf(mimeType))
}

// Media and profile pictures not seen in this long leave the disk: the keys
// stay in the database, so they're fetched again when they're wanted.
const keepUnseen = 7 * 24 * time.Hour

// touch marks files as just seen: their mtime is when they last showed.
// Missing ones are left alone.
func touch(paths ...string) {
	now := time.Now()
	for _, p := range paths {
		os.Chtimes(p, now, now)
	}
}

// sweep removes, at start and once a day, the media not seen and the
// profile pictures not asked for (fetched at most daily) in keepUnseen.
func (b *Bridge) sweep() {
	for {
		for _, dir := range []string{mediaDir(), filepath.Join(b.dir, "avatars")} {
			entries, _ := os.ReadDir(dir)
			for _, e := range entries {
				if info, err := e.Info(); err == nil && !e.IsDir() && time.Since(info.ModTime()) > keepUnseen {
					os.Remove(filepath.Join(dir, e.Name()))
				}
			}
		}
		time.Sleep(24 * time.Hour)
	}
}

func writeFile(path string, data []byte) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return err
	}
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, data, 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}

// linkOrCopy: a hard link when it's the same disk, a copy when not.
func linkOrCopy(from, to string) error {
	if err := os.MkdirAll(filepath.Dir(to), 0o700); err != nil {
		return err
	}
	os.Remove(to)
	if os.Link(from, to) == nil {
		return nil
	}
	in, err := os.Open(from)
	if err != nil {
		return err
	}
	defer in.Close()
	tmp := to + ".tmp"
	out, err := os.Create(tmp)
	if err != nil {
		return err
	}
	if _, err := io.Copy(out, in); err != nil {
		out.Close()
		return err
	}
	out.Close()
	return os.Rename(tmp, to)
}

// A media the phone was asked to upload again, waiting for its answer.
type reupload struct {
	chat, id, path string
	part           *waE2E.Message
}

var (
	inFlight  sync.Map
	reMu      sync.Mutex
	reuploads = map[types.MessageID]reupload{}
	// Messages whose media's keys were asked of the phone, by chat and id.
	recovering = map[string]bool{}
)

func mediaDone(chat, id, path string) {
	emit(map[string]any{"t": "media", "chat": chat, "id": id, "path": path})
}

func mediaFailed(chat, id, why string) {
	emit(map[string]any{"t": "media", "chat": chat, "id": id, "error": why})
}

// mediaSkipped is an `auto` download given up: the app shows the picture's
// download button again, whose click may ask the phone.
func mediaSkipped(chat, id string) {
	emit(map[string]any{"t": "media", "chat": chat, "id": id, "skipped": true})
}

// download fetches a message's media into the cache, once; the answer is a
// `media` event with the file, or with why not. An `auto` one (a photo
// on screen) gives up where the phone would have to be asked, and says so
// with mediaSkipped.
func (b *Bridge) download(chat, id string, auto bool) {
	key := chat + "\x00" + id
	if _, busy := inFlight.LoadOrStore(key, true); busy {
		return
	}
	defer inFlight.Delete(key)
	var mimeType, kind, waChat, waSender, sender string
	var blob []byte
	var fromMe bool
	var ts int64
	err := b.db.QueryRow(`SELECT COALESCE(mime, ''), COALESCE(media.kind, ''), proto, COALESCE(media.wa_chat, ''), COALESCE(media.wa_sender, ''), sender, from_me, ts
		FROM messages LEFT JOIN media USING (chat, id) WHERE chat = ? AND id = ?`, chat, id).
		Scan(&mimeType, &kind, &blob, &waChat, &waSender, &sender, &fromMe, &ts)
	if err != nil {
		if !auto {
			logf("download %s %s: not stored: %v", chat, id, err)
			mediaFailed(chat, id, unavailable)
			return
		}
		if !errors.Is(err, sql.ErrNoRows) {
			logf("download %s %s (auto): %v", chat, id, err)
		}
		mediaSkipped(chat, id)
		return
	}
	path := mediaFile(chat, id, mimeType)
	done := func() {
		mediaDone(chat, id, path)
		if kind == "video" || kind == "ptv" {
			poster(chat, id, path)
		}
	}
	if st, err := os.Stat(path); mimeType != "" && err == nil && st.Size() > 0 {
		touch(path, thumbFile(chat, id, "frame"))
		done()
		return
	}
	part := &waE2E.Message{}
	if blob == nil || proto.Unmarshal(blob, part) != nil || downloadable(part) == nil {
		// Stored before the keys were kept: the phone has them.
		if !auto {
			b.recoverMedia(chat, id, sender, ts)
		} else {
			mediaSkipped(chat, id)
		}
		return
	}
	err = b.fetch(part, path)
	switch {
	case err == nil:
		done()
	case auto:
		logf("download %s (auto): %v", id, err)
		mediaSkipped(chat, id)
	case errors.Is(err, whatsmeow.ErrMediaDownloadFailedWith404) || errors.Is(err, whatsmeow.ErrMediaDownloadFailedWith410):
		// Expired on the server: the phone, if it still has it, uploads it again.
		logf("download %s %s: expired (%v), asking the phone", chat, id, err)
		if b.askReupload(chat, id, path, part, waChat, waSender, fromMe) != nil {
			mediaFailed(chat, id, unavailable)
		}
	default:
		logf("download %s: %v", id, err)
		mediaFailed(chat, id, unavailable)
	}
}

func (b *Bridge) fetch(part *waE2E.Message, path string) error {
	ctx, cancel := context.WithTimeout(b.ctx, 2*time.Minute)
	defer cancel()
	dl := downloadable(part)
	var data []byte
	var err error
	// WhatsApp's own announcements (the official account) carry no path,
	// only a public static URL, still encrypted with the message's key.
	if st, ok := dl.(interface{ GetStaticURL() string }); ok && dl.GetDirectPath() == "" && st.GetStaticURL() != "" {
		data, err = b.cli.DangerousInternals().DownloadAndDecrypt(ctx, st.GetStaticURL(), dl.GetMediaKey(), whatsmeow.GetMediaType(dl), dl.GetFileEncSHA256(), dl.GetFileSHA256())
	} else {
		data, err = b.cli.Download(ctx, dl)
	}
	if err != nil {
		return err
	}
	return writeFile(path, data)
}

func (b *Bridge) askReupload(chat, id, path string, part *waE2E.Message, waChat, waSender string, fromMe bool) error {
	c, err := types.ParseJID(waChat)
	if err != nil {
		return err
	}
	s, _ := types.ParseJID(waSender)
	info := &types.MessageInfo{
		MessageSource: types.MessageSource{Chat: c, Sender: s, IsFromMe: fromMe, IsGroup: c.Server == types.GroupServer},
		ID:            id,
	}
	if err := b.cli.SendMediaRetryReceipt(b.ctx, info, downloadable(part).GetMediaKey()); err != nil {
		logf("media retry %s: %v", id, err)
		return err
	}
	reMu.Lock()
	reuploads[id] = reupload{chat, id, path, part}
	reMu.Unlock()
	// The phone may be off, or no longer have it.
	time.AfterFunc(30*time.Second, func() {
		if _, ok := takeReupload(id); ok {
			logf("media retry %s: no answer from the phone", id)
			mediaFailed(chat, id, unavailable)
		}
	})
	return nil
}

func takeReupload(id types.MessageID) (reupload, bool) {
	reMu.Lock()
	defer reMu.Unlock()
	r, ok := reuploads[id]
	delete(reuploads, id)
	return r, ok
}

// mediaRetry is the phone's answer: the media's new path, or that it's gone.
func (b *Bridge) mediaRetry(e *events.MediaRetry) {
	r, ok := takeReupload(e.MessageID)
	if !ok {
		return
	}
	n, err := whatsmeow.DecryptMediaRetryNotification(e, downloadable(r.part).GetMediaKey())
	if err != nil || n.GetResult() != waMmsRetry.MediaRetryNotification_SUCCESS || n.GetDirectPath() == "" {
		logf("media retry %s: %v, result %v", r.id, err, n.GetResult())
		mediaFailed(r.chat, r.id, unavailable)
		return
	}
	setDirectPath(r.part, n.GetDirectPath())
	if blob, err := proto.Marshal(r.part); err == nil {
		b.db.Exec(`UPDATE media SET proto = ? WHERE chat = ? AND id = ?`, blob, r.chat, r.id)
	}
	if err := b.fetch(r.part, r.path); err != nil {
		logf("download %s after retry: %v", r.id, err)
		mediaFailed(r.chat, r.id, unavailable)
		return
	}
	mediaDone(r.chat, r.id, r.path)
	if r.part.GetVideoMessage() != nil || r.part.GetPtvMessage() != nil {
		poster(r.chat, r.id, r.path)
	}
}

func takeRecovery(chat, id string) bool {
	reMu.Lock()
	defer reMu.Unlock()
	ok := recovering[chat+"\x00"+id]
	delete(recovering, chat+"\x00"+id)
	return ok
}

// recoverMedia asks the phone again for a message stored without its
// media's keys, two ways: the message itself by its key (the request
// WhatsApp uses for messages a device couldn't decrypt), and an on-demand
// history sync around it. Whichever answers first stores the keys, and
// storeMedia carries on into the download.
func (b *Bridge) recoverMedia(chat, id, sender string, ts int64) {
	key := chat + "\x00" + id
	reMu.Lock()
	busy := recovering[key]
	recovering[key] = true
	reMu.Unlock()
	if busy {
		return
	}
	time.AfterFunc(20*time.Second, func() {
		if takeRecovery(chat, id) {
			logf("recover %s %s: no answer from the phone", chat, id)
			mediaFailed(chat, id, unavailable)
		}
	})
	jid, err := types.ParseJID(chat)
	if err != nil {
		return
	}
	// The phone may know a 1:1 chat by its LID: ask under both.
	chats := []types.JID{jid}
	if jid.Server == types.DefaultUserServer && b.stored() {
		if lid, err := b.cli.Store.LIDs.GetLIDForPN(b.ctx, jid); err == nil && !lid.IsEmpty() {
			chats = append(chats, lid)
		}
	}
	from, _ := types.ParseJID(sender)

	// A history request returns the messages before its anchor: the next
	// one we have, or, for the newest, one that doesn't exist, from now.
	anchor := types.MessageInfo{ID: b.cli.GenerateMessageID(), Timestamp: time.Now()}
	anchor.IsFromMe = true
	var aID string
	var aFromMe bool
	var aTS int64
	if b.db.QueryRow(`SELECT id, from_me, ts FROM messages WHERE chat = ? AND (ts > ? OR (ts = ? AND id > ?)) ORDER BY ts, id LIMIT 1`,
		chat, ts, ts, id).Scan(&aID, &aFromMe, &aTS) == nil {
		anchor = types.MessageInfo{ID: aID, Timestamp: time.Unix(aTS, 0)}
		anchor.IsFromMe = aFromMe
	}
	for _, c := range chats {
		_, err := b.cli.SendPeerMessage(b.ctx, b.cli.BuildUnavailableMessageRequest(c, from, id))
		logf("recover %s: asked the phone for message %s (sender %s): err=%v", c, id, from, err)
		a := anchor
		a.Chat = c
		_, err = b.cli.SendPeerMessage(b.ctx, b.cli.BuildHistorySyncRequest(&a, 10))
		logf("recover %s: asked for 10 messages before %s (ts %d, from me %v, real %v): err=%v", c, a.ID, a.Timestamp.Unix(), a.IsFromMe, aID != "", err)
	}
}
