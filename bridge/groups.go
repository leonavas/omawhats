package main

// People and groups: profile pictures, the info panel, your contacts for
// "New chat", the search, and who may write in each group.

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"go.mau.fi/whatsmeow"
	"go.mau.fi/whatsmeow/types"
)

// syncGroups takes the names of the groups we're in, and who may send in
// each: groups set to admins only, and the ones we left, are read-only.
func (b *Bridge) syncGroups() {
	groups, err := b.cli.GetJoinedGroups(b.ctx)
	if err != nil {
		return
	}
	me, myLID := b.me(), b.cli.Store.GetLID().ToNonAD()
	joined := map[string]bool{}
	for _, g := range groups {
		readOnly := ""
		if g.IsAnnounce {
			readOnly = adminsOnly
			for _, p := range g.Participants {
				mine := p.JID.User == me.User || p.PhoneNumber.User == me.User || (!myLID.IsEmpty() && p.LID.User == myLID.User)
				if mine && (p.IsAdmin || p.IsSuperAdmin) {
					readOnly = ""
				}
			}
		}
		joined[g.JID.String()] = true
		b.db.Exec(`INSERT INTO chats (jid, name, read_only) VALUES (?, ?, ?)
			ON CONFLICT (jid) DO UPDATE SET name = excluded.name, read_only = excluded.read_only`, g.JID.String(), g.Name, readOnly)
	}
	rows, err := b.db.Query(`SELECT jid FROM chats WHERE jid LIKE '%@g.us'`)
	if err == nil {
		var left []string
		for rows.Next() {
			var j string
			if rows.Scan(&j) == nil && !joined[j] {
				left = append(left, j)
			}
		}
		rows.Close()
		for _, j := range left {
			b.db.Exec(`UPDATE chats SET read_only = ? WHERE jid = ?`, notMember, j)
		}
	}
	b.dirty.Store(true)
}

// fetchAvatars downloads profile pictures (the small preview) one at a time
// into <data>/avatars, at most once a day each, and tells the app where they
// are; an empty path means there's no picture to show.
func (b *Bridge) fetchAvatars() {
	dir := filepath.Join(b.dir, "avatars")
	for req := range b.avatars {
		name := strings.NewReplacer("@", "_", ".", "_", ":", "_").Replace(req.jid)
		pic, none := filepath.Join(dir, name+".jpg"), filepath.Join(dir, name+".none")
		fresh := func(p string) bool {
			st, err := os.Stat(p)
			return err == nil && time.Since(st.ModTime()) < 24*time.Hour
		}
		if !req.force {
			if fresh(pic) {
				emit(map[string]any{"t": "avatar", "jid": req.jid, "path": pic})
				continue
			}
			if fresh(none) {
				emit(map[string]any{"t": "avatar", "jid": req.jid, "path": ""})
				continue
			}
		}
		for !b.cli.IsConnected() {
			time.Sleep(time.Second)
		}
		jid, err := types.ParseJID(req.jid)
		// The official account never answers: it gets its mark in the app.
		if err != nil || jid == types.PSAJID {
			emit(map[string]any{"t": "avatar", "jid": req.jid, "path": ""})
			continue
		}
		ctx, cancel := context.WithTimeout(b.ctx, 15*time.Second)
		info, err := b.cli.GetProfilePictureInfo(ctx, jid, &whatsmeow.GetProfilePictureParams{Preview: true})
		cancel()
		hidden := errors.Is(err, whatsmeow.ErrProfilePictureNotSet) || errors.Is(err, whatsmeow.ErrProfilePictureUnauthorized)
		if err != nil && !hidden {
			logf("avatar %s: %v", req.jid, err)
		}
		if err != nil || info == nil {
			if err == nil || hidden {
				os.Remove(pic)
				os.WriteFile(none, nil, 0o600)
				emit(map[string]any{"t": "avatar", "jid": req.jid, "path": ""})
			}
			continue
		}
		if err := download(info.URL, pic); err != nil {
			logf("avatar %s: %v", req.jid, err)
			continue
		}
		os.Remove(none)
		emit(map[string]any{"t": "avatar", "jid": req.jid, "path": pic, "changed": req.force})
		time.Sleep(120 * time.Millisecond)
	}
}

func download(url, path string) error {
	resp, err := http.Get(url)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("HTTP %d", resp.StatusCode)
	}
	tmp := path + ".tmp"
	f, err := os.Create(tmp)
	if err != nil {
		return err
	}
	if _, err := io.Copy(f, resp.Body); err != nil {
		f.Close()
		return err
	}
	f.Close()
	return os.Rename(tmp, path)
}

// profile is what WhatsApp's contact (or group) info panel shows, with the
// picture at full size after it.
func (b *Bridge) profile(chat string) {
	jid, err := types.ParseJID(chat)
	if err != nil {
		return
	}
	p := map[string]any{"t": "profile", "chat": chat}
	// The full-size picture comes after the rest, not to hold it up.
	defer b.photo(chat, jid)
	var media, docs, links int
	b.db.QueryRow(`SELECT count(*) FROM media WHERE chat = ? AND kind IN ('image', 'video')`, chat).Scan(&media)
	b.db.QueryRow(`SELECT count(*) FROM media WHERE chat = ? AND kind = 'document'`, chat).Scan(&docs)
	b.db.QueryRow(`SELECT count(*) FROM messages WHERE chat = ? AND (text LIKE '%http://%' OR text LIKE '%https://%')`, chat).Scan(&links)
	p["counts"] = map[string]int{"media": media, "docs": docs, "links": links}
	var starred int
	b.db.QueryRow(`SELECT count(*) FROM messages WHERE chat = ? AND starred = 1`, chat).Scan(&starred)
	p["starred"] = starred
	if jid == types.PSAJID {
		p["name"] = "WhatsApp"
		p["official"] = true
		emit(p)
		return
	}
	ctx, cancel := context.WithTimeout(b.ctx, 20*time.Second)
	defer cancel()
	if jid.Server == types.GroupServer {
		g, err := b.cli.GetGroupInfo(ctx, jid)
		if err != nil {
			p["error"] = err.Error()
			emit(p)
			return
		}
		p["group"] = true
		p["name"] = g.Name
		p["about"] = g.Topic
		p["created"] = g.GroupCreated.Unix()
		p["announce"] = g.IsAnnounce
		p["locked"] = g.IsLocked
		if g.OwnerJID.User != "" {
			p["owner"] = b.quoteName(b.norm(g.OwnerJID).String())
		}
		me := b.me()
		type member struct {
			JID   string `json:"jid"`
			Name  string `json:"name"`
			Phone string `json:"phone"`
			Admin bool   `json:"admin"`
			Me    bool   `json:"me"`
			Push  string `json:"push,omitempty"`
		}
		members := []member{}
		amAdmin := false
		for _, m := range g.Participants {
			pj := m.PhoneNumber
			if pj.IsEmpty() {
				pj = b.norm(m.JID)
			}
			phone := ""
			if pj.Server == types.DefaultUserServer {
				phone = pj.User
			}
			mine := pj.User == me.User
			if mine && (m.IsAdmin || m.IsSuperAdmin) {
				amAdmin = true
			}
			push := m.DisplayName
			if push == "" {
				push = b.contact(pj).PushName
			}
			members = append(members, member{pj.String(), b.contactName(pj), phone, m.IsAdmin || m.IsSuperAdmin, mine, push})
		}
		// You first, then admins, then by name (named before numbers).
		sort.SliceStable(members, func(i, j int) bool {
			a, c := members[i], members[j]
			if a.Me != c.Me {
				return a.Me
			}
			if a.Admin != c.Admin {
				return a.Admin
			}
			if (a.Name == "") != (c.Name == "") {
				return a.Name != ""
			}
			return fold(a.Name+a.Push) < fold(c.Name+c.Push)
		})
		p["members"] = members
		p["admin"] = amAdmin
	} else {
		// A hidden number (@lid) is its number when we know it, for the
		// saved name and to show; the about is asked as the chat is.
		pn := b.norm(jid)
		c := b.contact(jid)
		p["push"] = c.PushName
		p["saved"] = savedName(types.ContactInfo{FullName: c.FullName, FirstName: c.FirstName})
		verified := ""
		if info, err := b.cli.GetUserInfo(ctx, []types.JID{jid}); err != nil {
			logf("user info %s: %v", jid, err)
		} else {
			for _, u := range info {
				p["about"] = b.aboutOf(ctx, jid, u.Status)
				if u.VerifiedName != nil {
					verified = u.VerifiedName.Details.GetVerifiedName()
				}
				b.setVerified(chat, u.VerifiedName)
			}
		}
		if verified == "" {
			verified = c.BusinessName
		}
		if verified == "" && jid.Server == types.DefaultUserServer {
			if r, err := b.cli.IsOnWhatsApp(ctx, []string{"+" + jid.User}); err == nil && len(r) > 0 && r[0].VerifiedName != nil {
				verified = r[0].VerifiedName.Details.GetVerifiedName()
			}
		}
		// The verified name, then what you saved, then what they set.
		for _, n := range []string{verified, c.FullName, c.FirstName} {
			if n != "" {
				p["name"] = n
				break
			}
		}
		if pn.Server == types.DefaultUserServer {
			p["phone"] = pn.User
		}
		p["self"] = pn.User == b.me().User
		p["business"] = verified
		lat, lon, biz := b.bizProfile(ctx, jid, p)
		p["biz"] = biz || verified != ""
		if addr, _ := p["address"].(string); biz && (addr != "" || lat != 0 || lon != 0) {
			p["maps"] = mapsLink(addr, lat, lon)
		}
		// Groups in common, as the panel lists them.
		var common []map[string]string
		if rows, err := b.db.Query(`SELECT jid, name FROM chats WHERE jid LIKE '%@g.us' AND read_only != ? ORDER BY name`, notMember); err == nil {
			var gs [][2]string
			for rows.Next() {
				var j, n string
				if rows.Scan(&j, &n) == nil {
					gs = append(gs, [2]string{j, n})
				}
			}
			rows.Close()
			// Only what whatsmeow already knows, to stay quick: groups whose
			// messages came from them.
			for _, g := range gs {
				var one int
				if b.db.QueryRow(`SELECT 1 FROM messages WHERE chat = ? AND sender = ? LIMIT 1`, g[0], pn.String()).Scan(&one) == nil {
					common = append(common, map[string]string{"jid": g[0], "name": g[1]})
				}
			}
		}
		p["common"] = common
	}
	emit(p)
}

// contactList is "New chat": your contacts on WhatsApp, by name.
func (b *Bridge) contactList() {
	out := []map[string]string{}
	if b.stored() {
		all, err := b.cli.Store.Contacts.GetAllContacts(b.ctx)
		if err == nil {
			seen := map[string]bool{}
			me := b.me()
			for jid, c := range all {
				j := b.norm(jid)
				name := savedName(c)
				if j.Server != types.DefaultUserServer || name == "" || seen[j.User] || j.User == me.User {
					continue
				}
				seen[j.User] = true
				out = append(out, map[string]string{"jid": j.String(), "name": name, "phone": j.User, "push": c.PushName})
			}
		}
	}
	sort.Slice(out, func(i, j int) bool { return fold(out[i]["name"]) < fold(out[j]["name"]) })
	emit(map[string]any{"t": "contacts", "contacts": out})
}

// looksLikePhone: only what people type in a number (digits, +, spaces, dashes, parentheses).
func looksLikePhone(s string) bool {
	return strings.Trim(s, "0123456789+-() ") == ""
}

// search answers the side panel's field: contacts we have no chat with yet,
// messages with the text, and, for a phone number, whether it's on WhatsApp.
// With a chat, only that chat's messages (the search in a chat's panel).
func (b *Bridge) search(q, chat string) {
	q = strings.TrimSpace(q)
	out := map[string]any{"t": "search", "query": q, "chat": chat, "contacts": []any{}, "messages": []Msg{}}
	if q == "" {
		emit(out)
		return
	}
	if chat != "" {
		if ms := b.query(`WHERE chat = ? AND text LIKE ? AND messages.kind NOT IN ('revoked', 'system') ORDER BY ts DESC LIMIT 200`, chat, "%"+q+"%"); ms != nil {
			out["messages"] = ms
		}
		emit(out)
		return
	}
	lq, digits := fold(q), digitsOf(q)

	chats := map[string]bool{}
	if rows, err := b.db.Query(`SELECT jid FROM chats`); err == nil {
		for rows.Next() {
			var j string
			if rows.Scan(&j) == nil {
				chats[j] = true
			}
		}
		rows.Close()
	}
	type contact struct {
		JID   string `json:"jid"`
		Name  string `json:"name"`
		Phone string `json:"phone"`
	}
	var contacts []contact
	seen := map[string]bool{}
	if b.stored() {
		if all, err := b.cli.Store.Contacts.GetAllContacts(b.ctx); err == nil {
			for jid, c := range all {
				j := b.norm(jid)
				name := savedName(c)
				if j.Server != types.DefaultUserServer || name == "" || seen[j.User] || chats[j.String()] || j.User == b.me().User {
					continue
				}
				if strings.Contains(fold(name), lq) || (len(digits) >= 3 && strings.Contains(j.User, digits)) {
					seen[j.User] = true
					contacts = append(contacts, contact{j.String(), name, j.User})
				}
			}
		}
	}
	sort.Slice(contacts, func(i, j int) bool { return fold(contacts[i].Name) < fold(contacts[j].Name) })
	if len(contacts) > 30 {
		contacts = contacts[:30]
	}
	if contacts != nil {
		out["contacts"] = contacts
	}
	if ms := b.query(`WHERE text LIKE ? AND messages.kind NOT IN ('revoked', 'system') ORDER BY ts DESC LIMIT 60`, "%"+q+"%"); ms != nil {
		out["messages"] = ms
	}

	// A number: Brazilian ones may come without the country code.
	if looksLikePhone(q) && len(digits) >= 10 && len(digits) <= 15 {
		if len(digits) <= 11 {
			digits = "55" + digits
		}
		ctx, cancel := context.WithTimeout(b.ctx, 10*time.Second)
		res, err := b.cli.IsOnWhatsApp(ctx, []string{"+" + digits})
		cancel()
		if err == nil && len(res) > 0 {
			jid := res[0].JID
			if jid.IsEmpty() {
				jid = types.NewJID(digits, types.DefaultUserServer)
			}
			out["number"] = map[string]any{"jid": jid.String(), "phone": digits, "exists": res[0].IsIn}
		}
	}
	emit(out)
}

// mediaList answers the info panel's "Media, links and docs": a chat's
// photos and videos, its documents, or its messages with links, newest first.
func (b *Bridge) mediaList(chat, kind string) {
	var ms []Msg
	switch kind {
	case "docs":
		ms = b.query(`WHERE chat = ? AND messages.kind = 'document' ORDER BY ts DESC LIMIT 300`, chat)
	case "links":
		ms = b.query(`WHERE chat = ? AND messages.kind = 'text' AND (text LIKE '%http://%' OR text LIKE '%https://%' OR text LIKE '%www.%') ORDER BY ts DESC LIMIT 300`, chat)
	default:
		ms = b.query(`WHERE chat = ? AND messages.kind IN ('image', 'video', 'gif') ORDER BY ts DESC LIMIT 400`, chat)
	}
	if ms == nil {
		ms = []Msg{}
	}
	emit(map[string]any{"t": "media_list", "chat": chat, "kind": kind, "msgs": ms})
}
