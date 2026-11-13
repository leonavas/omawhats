package main

// Link previews, as WhatsApp Web's: the large picture a link's message
// carries (fetched once, next to its small one), and the preview of a
// link being typed (the page's title, description and picture), which
// goes along with the message when it's sent.

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"html"
	"image"
	_ "image/gif"
	"image/jpeg"
	_ "image/png"
	"io"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"sync"
	"time"

	"go.mau.fi/whatsmeow"
	"go.mau.fi/whatsmeow/proto/waE2E"
	"google.golang.org/protobuf/proto"
)

// LinkPreview is a page's preview: its title, description and picture
// (a JPEG on disk, with its size).
type LinkPreview struct {
	URL   string `json:"url"`
	Title string `json:"title"`
	Desc  string `json:"desc"`
	Image string `json:"image,omitempty"`
	W     int    `json:"w,omitempty"`
	H     int    `json:"h,omitempty"`
}

// Big pictures come down two at a time; older than this, WhatsApp no longer has them.
var (
	linkThumbSem = make(chan struct{}, 2)
	linkThumbAge = int64(30 * 24 * 3600)
)

// linkThumb fetches the large picture of a message's link preview, when
// it has one, and shows the message again with it.
func (b *Bridge) linkThumb(chat, id string, ts int64, x *waE2E.ExtendedTextMessage) {
	if x == nil || x.GetThumbnailDirectPath() == "" || len(x.GetMediaKey()) == 0 || time.Now().Unix()-ts > linkThumbAge {
		return
	}
	path := thumbFile(chat, id, "link")
	// Here already: back in the link object, which a new copy of the
	// message (a history sync's) wrote over.
	if f, err := os.Open(path); err == nil {
		cfg, _, err := image.DecodeConfig(f)
		f.Close()
		if err == nil {
			b.setLinkImage(chat, id, path, cfg.Width, cfg.Height)
		}
		return
	}
	go func() {
		linkThumbSem <- struct{}{}
		defer func() { <-linkThumbSem }()
		ctx, cancel := context.WithTimeout(b.ctx, 45*time.Second)
		defer cancel()
		data, err := b.cli.DownloadThumbnail(ctx, x)
		if err != nil {
			logf("link thumb %s: %v", id, err)
			return
		}
		cfg, _, err := image.DecodeConfig(bytes.NewReader(data))
		if err != nil || !b.messageLive(chat, id) || writeFile(path, data) != nil {
			return
		}
		b.setLinkImage(chat, id, path, cfg.Width, cfg.Height)
		b.emitMsg(chat, id)
	}()
}

// setLinkImage puts the large picture in the message's link object.
func (b *Bridge) setLinkImage(chat, id, path string, w, h int) {
	var raw string
	if b.db.QueryRow(`SELECT x FROM messages WHERE chat = ? AND id = ?`, chat, id).Scan(&raw) != nil || raw == "" {
		return
	}
	var x map[string]any
	if json.Unmarshal([]byte(raw), &x) != nil {
		return
	}
	link, ok := x["link"].(map[string]any)
	if !ok {
		return
	}
	link["image"], link["w"], link["h"] = path, w, h
	js, _ := json.Marshal(x)
	b.db.Exec(`UPDATE messages SET x = ? WHERE chat = ? AND id = ?`, string(js), chat, id)
}

// ------------------------------------------------------------ typed links

var (
	previewMu    sync.Mutex
	previewCache = map[string]*LinkPreview{}
	metaTagRE    = regexp.MustCompile(`(?is)<meta\s[^>]*>`)
	attrRE       = regexp.MustCompile(`(?is)([a-z:_-]+)\s*=\s*("([^"]*)"|'([^']*)')`)
	titleRE      = regexp.MustCompile(`(?is)<title[^>]*>(.*?)</title>`)
)

const previewUA = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36 WhatsApp/2"

// linkPreview answers the app with a link's preview (empty when the page
// has none): a link in the box being typed.
func (b *Bridge) linkPreview(raw string) {
	p := fetchPreview(b.ctx, raw)
	if p == nil {
		emit(map[string]any{"t": "link_preview", "url": raw})
		return
	}
	emit(map[string]any{"t": "link_preview", "url": raw, "preview": p})
}

func fetchPreview(ctx context.Context, raw string) *LinkPreview {
	if webURL(raw) == "" {
		return nil
	}
	previewMu.Lock()
	if p, ok := previewCache[raw]; ok {
		previewMu.Unlock()
		return p
	}
	previewMu.Unlock()
	p := readPreview(ctx, raw)
	previewMu.Lock()
	previewCache[raw] = p
	previewMu.Unlock()
	return p
}

func previewGet(ctx context.Context, u string, limit int64) ([]byte, string, *url.URL, error) {
	ctx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, "GET", u, nil)
	if err != nil {
		return nil, "", nil, err
	}
	req.Header.Set("User-Agent", previewUA)
	req.Header.Set("Accept-Language", "pt-BR,pt;q=0.9,en;q=0.8")
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, "", nil, err
	}
	defer res.Body.Close()
	if res.StatusCode >= 400 {
		return nil, "", nil, io.ErrUnexpectedEOF
	}
	data, err := io.ReadAll(io.LimitReader(res.Body, limit))
	return data, res.Header.Get("Content-Type"), res.Request.URL, err
}

func readPreview(ctx context.Context, raw string) *LinkPreview {
	page, ctype, final, err := previewGet(ctx, raw, 1<<20)
	if err != nil || !strings.Contains(strings.ToLower(ctype), "html") {
		return nil
	}
	meta := map[string]string{}
	for _, tag := range metaTagRE.FindAllString(string(page), -1) {
		attrs := map[string]string{}
		for _, a := range attrRE.FindAllStringSubmatch(tag, -1) {
			attrs[strings.ToLower(a[1])] = a[3] + a[4]
		}
		key := strings.ToLower(attrs["property"])
		if key == "" {
			key = strings.ToLower(attrs["name"])
		}
		if key != "" && meta[key] == "" {
			meta[key] = clean(attrs["content"])
		}
	}
	first := func(keys ...string) string {
		for _, k := range keys {
			if meta[k] != "" {
				return meta[k]
			}
		}
		return ""
	}
	p := &LinkPreview{URL: raw, Title: first("og:title", "twitter:title"), Desc: first("og:description", "twitter:description", "description")}
	if p.Title == "" {
		if m := titleRE.FindSubmatch(page); m != nil {
			p.Title = clean(string(m[1]))
		}
	}
	if p.Title == "" && p.Desc == "" {
		return nil
	}
	if img := first("og:image:secure_url", "og:image", "og:image:url", "twitter:image", "twitter:image:src"); img != "" {
		if u, err := final.Parse(img); err == nil && webURL(u.String()) != "" {
			p.Image, p.W, p.H = previewImage(ctx, u.String())
		}
	}
	return p
}

// previewFile is where a typed link's picture goes: with the media, so it
// ages out (and goes on logout) as they do.
func previewFile(name string) string { return filepath.Join(mediaDir(), "preview_"+name+".jpg") }

// isPreviewFile says the app's path is one of those, not any file.
func isPreviewFile(path string) bool {
	return filepath.Dir(path) == mediaDir() && strings.HasPrefix(filepath.Base(path), "preview_")
}

func clean(s string) string {
	s = strings.Join(strings.Fields(html.UnescapeString(s)), " ")
	if r := []rune(s); len(r) > 300 {
		s = string(r[:300]) + "…"
	}
	return s
}

// previewImage downloads a page's picture as a JPEG (up to 1200 wide),
// in the cache; "" when it won't come or open.
func previewImage(ctx context.Context, u string) (string, int, int) {
	data, _, _, err := previewGet(ctx, u, 8<<20)
	if err != nil || len(data) == 0 {
		return "", 0, 0
	}
	img, _, err := image.Decode(bytes.NewReader(data))
	if err != nil {
		// WebP, AVIF and the like, through ffmpeg when it's there.
		cmd := exec.CommandContext(ctx, "ffmpeg", "-v", "error", "-i", "-", "-frames:v", "1", "-f", "image2pipe", "-vcodec", "mjpeg", "-")
		cmd.Stdin = bytes.NewReader(data)
		out, err := cmd.Output()
		if err != nil {
			return "", 0, 0
		}
		if img, err = jpeg.Decode(bytes.NewReader(out)); err != nil {
			return "", 0, 0
		}
	}
	r := img.Bounds()
	if r.Dx() < 16 || r.Dy() < 16 {
		return "", 0, 0
	}
	side := min(max(r.Dx(), r.Dy()), 1200)
	out := jpegThumb(img, side)
	if out == nil {
		return "", 0, 0
	}
	cfg, _ := jpeg.DecodeConfig(bytes.NewReader(out))
	sum := sha256.Sum256([]byte(u))
	path := previewFile(hex.EncodeToString(sum[:12]))
	if writeFile(path, out) != nil {
		return "", 0, 0
	}
	return path, cfg.Width, cfg.Height
}

// withPreview fills a message being sent with its link's preview: the
// title and description and a small picture inside it, as WhatsApp's apps
// send it. The x object it returns is what this app shows of it; the
// large picture's bytes go up with uploadLinkThumb.
func withPreview(ext *waE2E.ExtendedTextMessage, p *LinkPreview, chat, id string) (map[string]any, []byte) {
	ext.MatchedText = proto.String(p.URL)
	ext.Title = proto.String(p.Title)
	ext.Description = proto.String(p.Desc)
	ext.PreviewType = waE2E.ExtendedTextMessage_NONE.Enum()
	link := map[string]any{"url": p.URL, "title": p.Title, "desc": p.Desc}
	x := map[string]any{"link": link}
	if p.Image == "" {
		return x, nil
	}
	data, err := os.ReadFile(p.Image)
	if err != nil {
		return x, nil
	}
	img, err := jpeg.Decode(bytes.NewReader(data))
	if err != nil {
		return x, nil
	}
	if small := jpegThumb(img, 140); small != nil {
		ext.JPEGThumbnail = small
		if path := thumbFile(chat, id, "x"); writeFile(path, small) == nil {
			x["thumb"] = path
		}
	}
	if path := thumbFile(chat, id, "link"); writeFile(path, data) == nil {
		link["image"], link["w"], link["h"] = path, p.W, p.H
	}
	return x, data
}

// uploadLinkThumb sends the large picture up, for the message to point at.
func (b *Bridge) uploadLinkThumb(ext *waE2E.ExtendedTextMessage, p *LinkPreview, data []byte) {
	if len(data) == 0 {
		return
	}
	ctx, cancel := context.WithTimeout(b.ctx, 30*time.Second)
	defer cancel()
	up, err := b.cli.Upload(ctx, data, whatsmeow.MediaLinkThumbnail)
	if err != nil {
		logf("link thumb upload: %v", err)
		return
	}
	ext.ThumbnailDirectPath = proto.String(up.DirectPath)
	ext.ThumbnailSHA256 = up.FileSHA256
	ext.ThumbnailEncSHA256 = up.FileEncSHA256
	ext.MediaKey = up.MediaKey
	ext.MediaKeyTimestamp = proto.Int64(time.Now().Unix())
	ext.ThumbnailWidth = proto.Uint32(uint32(p.W))
	ext.ThumbnailHeight = proto.Uint32(uint32(p.H))
}
