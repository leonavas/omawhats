package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"go.mau.fi/whatsmeow"
	"go.mau.fi/whatsmeow/appstate"
	waBinary "go.mau.fi/whatsmeow/binary"
	"go.mau.fi/whatsmeow/types"
)

// WhatsApp's limits for your name and your about.
const (
	maxNameLen  = 25
	maxAboutLen = 139
)

// setName changes your name, the one others see: an app state setting, as
// WhatsApp Web's profile does, which the phone and your other devices follow.
func (b *Bridge) setName(text string) {
	name := strings.TrimSpace(text)
	if name == "" || utf8.RuneCountInString(name) > maxNameLen {
		fail("set_name", errors.New("invalid name"))
		return
	}
	ctx, cancel := context.WithTimeout(b.ctx, 20*time.Second)
	defer cancel()
	if err := b.cli.SendAppState(ctx, appstate.BuildSettingPushName(name)); err != nil {
		logf("set_name: %v", err)
		fail("set_name", err)
		return
	}
	// Fetching the patch back already sets it; when that didn't happen, the
	// presence still goes out with the new name.
	if b.cli.Store.PushName != name {
		logf("set_name: sent, but the patch didn't come back; keeping it locally")
		b.cli.Store.PushName = name
		_ = b.cli.Store.Save(ctx)
	}
	logf("set_name: ok")
	emit(map[string]any{"t": "me", "me": b.meInfo(), "name": name})
}

// setAbout changes your about, the text under your name. Two places keep
// it: the text status, which the phones show and edit now (and so what
// everyone sees), and the older "status" WhatsApp Web's profile still sends,
// for the clients that read that one. Both go, as the phone does; the text
// status is the one that counts, and it's read back to tell it took.
func (b *Bridge) setAbout(text string) {
	about := strings.TrimSpace(text)
	if about == "" || utf8.RuneCountInString(about) > maxAboutLen {
		fail("set_about", errors.New("invalid about"))
		return
	}
	ctx, cancel := context.WithTimeout(b.ctx, 20*time.Second)
	defer cancel()
	// No emoji, and -1 for one that doesn't expire (the server refuses 0,
	// what whatsmeow's SetStatusMessage sends, and a missing duration).
	res, err := b.cli.DangerousInternals().SendMexIQ(ctx, mutationUpdateTextStatus, map[string]any{
		"input": map[string]any{"text": about, "ephemeral_duration_sec": -1},
	})
	if err != nil {
		logf("set_about: text status: %v", err)
		fail("set_about", err)
		return
	}
	if _, err := b.cli.DangerousInternals().SendIQ(ctx, whatsmeow.DangerousInfoQuery{
		Namespace: "status",
		Type:      "set",
		To:        types.ServerJID,
		Content:   []waBinary.Node{{Tag: "status", Content: []byte(about)}},
	}); err != nil {
		logf("set_about: status IQ: %v", err)
	}
	if ts, ok := b.textStatus(ctx, b.me()); ok && ts.Text != about {
		logf("set_about: the server kept %q (%s)", ts.Text, cut(string(res), 200))
		fail("set_about", errors.New("not saved"))
		return
	}
	logf("set_about: ok")
	emit(map[string]any{"t": "about", "about": about})
}

// setPhoto changes your profile picture to the image at path, cropped
// square from the middle and made a 640px JPEG (what WhatsApp keeps); an
// empty path removes it.
func (b *Bridge) setPhoto(path string) {
	var jpeg []byte
	if path != "" {
		if _, err := os.Stat(path); err != nil {
			fail("set_photo", err)
			return
		}
		out, err := exec.Command("magick", path+"[0]", "-auto-orient", "-resize", "640x640^",
			"-gravity", "center", "-extent", "640x640", "-strip", "-quality", "90", "jpg:-").Output()
		if err != nil || len(out) == 0 {
			logf("set_photo: convert: %v", err)
			fail("set_photo", fmt.Errorf("couldn't read the image"))
			return
		}
		jpeg = out
	}
	ctx, cancel := context.WithTimeout(b.ctx, 60*time.Second)
	defer cancel()
	// No target: your own picture.
	if _, err := b.cli.SetGroupPhoto(ctx, types.EmptyJID, jpeg); err != nil {
		logf("set_photo: %v", err)
		fail("set_photo", err)
		return
	}
	logf("set_photo: ok (removed: %v)", jpeg == nil)
	me := b.me().String()
	select {
	case b.avatars <- avatarReq{jid: me, force: true}:
	default:
	}
	b.photo(me, b.me())
	emit(map[string]any{"t": "photo_set", "removed": jpeg == nil})
}

// The query WhatsApp Web's contacts ask the newer about with (the "text
// status": text, emoji and how long it lasts), which the phones show and edit.
const (
	queryTextStatusList      = "24072923595647473"
	mutationUpdateTextStatus = "9152604461510864"
)

type textStatusInfo struct {
	JID      string `json:"jid"`
	Text     string `json:"text"`
	Duration *int64 `json:"ephemeral_duration_sec"`
	Updated  any    `json:"last_update_time"`
	Emoji    *struct {
		Content string `json:"content"`
	} `json:"emoji"`
}

// textStatus asks the text status of jid; ok is false when it couldn't.
func (b *Bridge) textStatus(ctx context.Context, jid types.JID) (textStatusInfo, bool) {
	data, err := b.cli.DangerousInternals().SendMexIQ(ctx, queryTextStatusList, map[string]any{
		"input": []map[string]any{{"jid": jid.ToNonAD().String()}},
	})
	if err != nil {
		logf("text status %s: %v", jid, err)
		return textStatusInfo{}, false
	}
	var resp struct {
		List []textStatusInfo `json:"xwa2_text_status_list"`
	}
	if err := json.Unmarshal(data, &resp); err != nil || len(resp.List) == 0 {
		logf("text status %s: %v (%s)", jid, err, cut(string(data), 300))
		return textStatusInfo{}, false
	}
	return resp.List[0], true
}

// aboutOf is the about the others see for jid: the text status when it has
// one that hasn't expired, else the older status (legacy, from usync).
func (b *Bridge) aboutOf(ctx context.Context, jid types.JID, legacy string) string {
	ts, ok := b.textStatus(ctx, jid)
	if !ok || ts.Text == "" {
		return legacy
	}
	if ts.Duration != nil && *ts.Duration > 0 {
		var at int64
		switch v := ts.Updated.(type) {
		case float64:
			at = int64(v)
		case string:
			at, _ = strconv.ParseInt(v, 10, 64)
		}
		if at > 0 && time.Now().Unix() > at+*ts.Duration {
			return legacy
		}
	}
	return ts.Text
}
