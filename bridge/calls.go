package main

// Calls, as WhatsApp Web shows them in their chat: a bubble each, voice or
// video, with how it went ("Answered on another device", missed, the
// length). This device never answers one; it hears of them live, as the
// <call> stanzas every device of the account gets (offer, accept, reject,
// terminate), and from the phone's call log: its app state ("call_log"),
// the history sync's records, and the notices and call log messages in a
// chat's history. What the phone says of a call is final; what was heard
// live stands until then.

import (
	"encoding/json"
	"sync"

	"go.mau.fi/whatsmeow/proto/waE2E"
	"go.mau.fi/whatsmeow/proto/waSyncAction"
	"go.mau.fi/whatsmeow/types"
	"go.mau.fi/whatsmeow/types/events"
)

// Call is a call message's x.call. Outcome is answered, elsewhere (on
// another of your devices), missed, rejected, unanswered (yours, nobody
// took it) or ongoing.
type Call struct {
	Video   bool   `json:"video"`
	Group   bool   `json:"group,omitempty"`
	Outcome string `json:"outcome"`
	Secs    int64  `json:"secs,omitempty"`
	// WhatsApp's call id, when the source had it.
	ID string `json:"id,omitempty"`
	// From the phone's call log, not only heard here.
	Phone bool `json:"phone,omitempty"`
}

// How far apart (seconds) a call without an id and one with it can be and
// still be the same call.
const callWindow = 90

// liveCall is a call while it rings or lasts: what its offer said, and
// when it was accepted.
type liveCall struct {
	chat, sender types.JID
	fromMe       bool
	video, group bool
	start        int64
	accepted     int64
	rejected     bool
}

var calls = struct {
	sync.Mutex
	m map[string]*liveCall
}{m: map[string]*liveCall{}}

// callChat is the chat a live call goes in: its group, else the other
// person (the caller, or whoever a call of yours went to).
func (b *Bridge) callChat(m types.BasicCallMeta) (chat, sender types.JID, fromMe, ok bool) {
	creator := b.norm(m.CallCreator)
	if creator.Server == types.HiddenUserServer && m.CallCreatorAlt.Server == types.DefaultUserServer {
		creator = m.CallCreatorAlt.ToNonAD()
	}
	fromMe = b.mine(creator)
	if fromMe {
		creator = b.me()
	}
	if !m.GroupJID.IsEmpty() {
		return m.GroupJID.ToNonAD(), creator, fromMe, true
	}
	if !fromMe {
		return creator, creator, false, !creator.IsEmpty()
	}
	if to := b.norm(m.From); !to.IsEmpty() && !b.mine(to) {
		return to, creator, true, true
	}
	return types.EmptyJID, creator, true, false
}

// callEvent follows a call live. Nothing shows while it rings: an accept
// of someone's call (by another of your devices) shows it answered there,
// a reject declined, and its end the rest.
func (b *Bridge) callEvent(raw any) {
	switch e := raw.(type) {
	case *events.CallOffer:
		_, video := e.Data.GetOptionalChildByTag("video")
		b.callOffer(e.BasicCallMeta, video, false)
	case *events.CallOfferNotice:
		b.callOffer(e.BasicCallMeta, e.Media == "video", e.Type == "group")
	case *events.CallAccept:
		logf("call %s: accept", e.CallID)
		lc := b.liveCall(e.BasicCallMeta)
		if lc == nil {
			return
		}
		calls.Lock()
		if lc.accepted == 0 {
			lc.accepted = e.Timestamp.Unix()
		}
		calls.Unlock()
		if !lc.fromMe {
			b.liveCallDone(e.CallID, lc, "elsewhere", 0, false)
		}
	case *events.CallReject:
		logf("call %s: reject", e.CallID)
		lc := b.liveCall(e.BasicCallMeta)
		if lc == nil {
			return
		}
		calls.Lock()
		lc.rejected = true
		calls.Unlock()
		b.liveCallDone(e.CallID, lc, "rejected", 0, false)
	case *events.CallTerminate:
		logf("call %s: terminate %q", e.CallID, e.Reason)
		lc := b.liveCall(e.BasicCallMeta)
		calls.Lock()
		delete(calls.m, e.CallID)
		calls.Unlock()
		if lc == nil || lc.rejected {
			return
		}
		switch {
		case lc.accepted > 0 && lc.fromMe:
			b.liveCallDone(e.CallID, lc, "answered", max(e.Timestamp.Unix()-lc.accepted, 0), false)
		case lc.accepted > 0:
			// Shown when it was accepted.
		case lc.fromMe:
			b.liveCallDone(e.CallID, lc, "unanswered", 0, false)
		default:
			// Nobody took it. Only a ring that timed out is surely missed
			// (the caller may have hung up, or the phone answered without
			// this device hearing of it): only that one is news.
			b.liveCallDone(e.CallID, lc, "missed", 0, e.Reason == "timeout")
		}
	}
}

func (b *Bridge) callOffer(m types.BasicCallMeta, video, group bool) {
	chat, sender, fromMe, ok := b.callChat(m)
	logf("call %s: offer (video %v, group %v)", m.CallID, video, group || !m.GroupJID.IsEmpty())
	if !ok || skip(chat) || m.CallID == "" {
		return
	}
	calls.Lock()
	defer calls.Unlock()
	// One whose end never came here (the bridge went offline) is let go.
	for id, lc := range calls.m {
		if lc.start < m.Timestamp.Unix()-86400 {
			delete(calls.m, id)
		}
	}
	if calls.m[m.CallID] == nil {
		calls.m[m.CallID] = &liveCall{chat: chat, sender: sender, fromMe: fromMe, video: video,
			group: group || !m.GroupJID.IsEmpty(), start: m.Timestamp.Unix()}
	}
}

// liveCall is the call an event is about, nil when its offer never came
// here (the bridge started while it rang): the phone's log tells of it.
func (b *Bridge) liveCall(m types.BasicCallMeta) *liveCall {
	calls.Lock()
	defer calls.Unlock()
	return calls.m[m.CallID]
}

// liveCallDone stores what was heard of a call and tells the app; a missed
// one is news, as a message is.
func (b *Bridge) liveCallDone(id string, lc *liveCall, outcome string, secs int64, news bool) {
	m, fresh := b.putCall(lc.chat, id, "", lc.start, lc.fromMe, lc.sender,
		Call{Video: lc.video, Group: lc.group, Outcome: outcome, Secs: secs, ID: id})
	if m == nil {
		return
	}
	news = news && fresh && !m.FromMe
	if news {
		b.db.Exec(`UPDATE chats SET unread = unread + 1 WHERE jid = ?`, m.Chat)
		b.unarchiveOnNews(m.Chat)
		b.dirty.Store(true)
	}
	emit(map[string]any{"t": "message", "msg": m, "new": news})
}

// callRecord stores a call of the phone's log (its app state, or a history
// sync's): the whole of what WhatsApp knows of it, its length too.
func (b *Bridge) callRecord(r *waSyncAction.CallLogRecord) *Msg {
	if r == nil || r.GetCallID() == "" || r.GetCallResult() == waSyncAction.CallLogRecord_UPCOMING {
		return nil
	}
	// Seconds, or milliseconds at times.
	ts, secs := r.GetStartTime(), r.GetDuration()
	if ts > 1e12 {
		ts, secs = ts/1000, secs/1000
	}
	if ts <= 0 {
		return nil
	}
	var creator types.JID
	if j, err := types.ParseJID(r.GetCallCreatorJID()); err == nil {
		creator = b.norm(j)
	}
	fromMe := !r.GetIsIncoming()
	if !creator.IsEmpty() {
		fromMe = b.mine(creator)
	}
	var others []types.JID
	for _, p := range r.GetParticipants() {
		if j, err := types.ParseJID(p.GetUserJID()); err == nil && !j.IsEmpty() && !b.mine(j) {
			others = append(others, b.norm(j))
		}
	}
	c := Call{Video: r.GetIsVideo(), Secs: secs, ID: r.GetCallID(), Phone: true,
		Group: r.GetGroupJID() != "" || len(others) > 1 || r.GetCallType() == waSyncAction.CallLogRecord_VOICE_CHAT}
	switch r.GetCallResult() {
	case waSyncAction.CallLogRecord_CONNECTED:
		c.Outcome = "answered"
	case waSyncAction.CallLogRecord_ACCEPTEDELSEWHERE:
		c.Outcome = "elsewhere"
	case waSyncAction.CallLogRecord_REJECTED:
		c.Outcome = "rejected"
	case waSyncAction.CallLogRecord_ONGOING:
		c.Outcome = "ongoing"
	default:
		// Missed, cancelled, failed, unavailable: nobody took it.
		c.Outcome = "missed"
	}
	sender := b.me()
	if !fromMe && !creator.IsEmpty() {
		sender = creator
	}
	var chat types.JID
	switch {
	case r.GetGroupJID() != "":
		chat, _ = types.ParseJID(r.GetGroupJID())
		chat = chat.ToNonAD()
	case !fromMe:
		chat = creator
	case len(others) == 1:
		chat = others[0]
	}
	if chat.IsEmpty() || skip(chat) {
		return nil
	}
	m, _ := b.putCall(chat, r.GetCallID(), "", ts, fromMe, sender, c)
	return m
}

// callMessage stores a call log message as the call it tells of. A missed
// one is news (handle), as a message is; the rest isn't.
func (b *Bridge) callMessage(e *events.Message, c Content) *Msg {
	call, _ := c.X["call"].(Call)
	sender := b.norm(e.Info.Sender)
	if e.Info.IsFromMe {
		sender = b.me()
	}
	m, fresh := b.putCall(b.norm(e.Info.Chat), "", e.Info.ID, e.Info.Timestamp.Unix(), e.Info.IsFromMe, sender, call)
	if m != nil {
		m.fresh = fresh && call.Outcome == "missed"
	}
	return m
}

// callContent is a call log message's x.call: what the phone wrote into a
// chat once a call ended. It has no call id.
func callContent(x *waE2E.CallLogMessage) Call {
	c := Call{Video: x.GetIsVideo(), Secs: x.GetDurationSecs(), Phone: true,
		Group: x.GetCallType() == waE2E.CallLogMessage_VOICE_CHAT || len(x.GetParticipants()) > 1}
	switch x.GetCallOutcome() {
	case waE2E.CallLogMessage_CONNECTED:
		c.Outcome = "answered"
	case waE2E.CallLogMessage_ACCEPTED_ELSEWHERE:
		c.Outcome = "elsewhere"
	case waE2E.CallLogMessage_REJECTED:
		c.Outcome = "rejected"
	case waE2E.CallLogMessage_ONGOING:
		c.Outcome = "ongoing"
	default:
		// Missed, failed, silenced (do not disturb, an unknown caller).
		c.Outcome = "missed"
	}
	return c
}

// storedCall reads a call message's x back.
func storedCall(x string) Call {
	var v struct {
		Call Call `json:"call"`
	}
	json.Unmarshal([]byte(x), &v)
	return v.Call
}

// putCall stores a call as a message of its chat, or updates the one it
// is: by its call id or, for what comes without one (a missed call's
// notice, a call log message, under id), the call next to it in time. The
// phone's word on a call stands over what was heard here. fresh is true
// when the row is new.
func (b *Bridge) putCall(chat types.JID, callID, id string, ts int64, fromMe bool, sender types.JID, c Call) (*Msg, bool) {
	// A call of yours nobody took wasn't missed: it went unanswered.
	if fromMe && c.Outcome == "missed" {
		c.Outcome = "unanswered"
	}
	key := callID
	if key == "" {
		key = id
	}
	jid := chat.String()
	have, x := "", ""
	var old Call
	if b.db.QueryRow(`SELECT id, x FROM messages WHERE chat = ? AND id = ? AND kind = 'call'`, jid, key).Scan(&have, &x) == nil {
		old = storedCall(x)
	} else if rows, err := b.db.Query(`SELECT id, x FROM messages WHERE chat = ? AND kind = 'call' AND abs(ts - ?) <= ? ORDER BY abs(ts - ?)`,
		jid, ts, callWindow, ts); err == nil {
		// Another call nearby is this one when one of the two has no id.
		for rows.Next() {
			var oid string
			if rows.Scan(&oid, &x) != nil {
				continue
			}
			if o := storedCall(x); o.ID == "" || callID == "" {
				have, old = oid, o
				break
			}
		}
		rows.Close()
	}
	if have != "" {
		if old.Phone && !c.Phone {
			return b.load(jid, have), false
		}
		if c.Secs == 0 {
			c.Secs = old.Secs
		}
		if c.ID == "" {
			c.ID = old.ID
		}
		c.Group = c.Group || old.Group
		c.Phone = c.Phone || old.Phone
		js, _ := json.Marshal(map[string]any{"call": c})
		b.db.Exec(`UPDATE messages SET x = ? WHERE chat = ? AND id = ?`, string(js), jid, have)
		b.dirty.Store(true)
		return b.load(jid, have), false
	}
	// A call from before a clear stays cleared.
	var cleared int64
	b.db.QueryRow(`SELECT cleared FROM chats WHERE jid = ?`, jid).Scan(&cleared)
	if cleared > 0 && ts <= cleared {
		return nil, false
	}
	js, _ := json.Marshal(map[string]any{"call": c})
	if _, err := b.db.Exec(`INSERT INTO messages (chat, id, sender, from_me, ts, kind, x, status) VALUES (?, ?, ?, ?, ?, 'call', ?, 3)
		ON CONFLICT (chat, id) DO NOTHING`, jid, key, sender.String(), fromMe, ts, string(js)); err != nil {
		logf("store call %s: %v", key, err)
		return nil, false
	}
	b.db.Exec(`INSERT INTO chats (jid, last_ts) VALUES (?, ?)
		ON CONFLICT (jid) DO UPDATE SET last_ts = max(last_ts, excluded.last_ts), cleared = 0`, jid, ts)
	b.dirty.Store(true)
	logf("call %s: stored, %s", key, c.Outcome)
	return b.load(jid, key), true
}
