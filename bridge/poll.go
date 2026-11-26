package main

// Poll votes: kept per poll and voter (the newest vote replaces the one
// before, an empty one takes it back), tallied under each option as
// WhatsApp Web shows them. A vote names its options by their SHA-256, so
// the tally reads the poll's options to match them.

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"strings"
	"time"

	"go.mau.fi/whatsmeow"
	"go.mau.fi/whatsmeow/proto/waE2E"
	"go.mau.fi/whatsmeow/types"
	"go.mau.fi/whatsmeow/types/events"
)

// PollVote is one option's votes: how many, whether yours is one, and who,
// the first to vote first. Msg.Votes has one per option, in their order.
type PollVote struct {
	Count int       `json:"count"`
	Mine  bool      `json:"mine,omitempty"`
	By    []Reactor `json:"by,omitempty"`
}

func optionHash(name string) string {
	h := sha256.Sum256([]byte(name))
	return hex.EncodeToString(h[:])
}

// vote keeps voter's choice on a poll; an older one (a history sync's)
// doesn't undo a newer.
func (b *Bridge) vote(chat, id, voter string, hashes [][]byte, ts int64) {
	hs := make([]string, len(hashes))
	for i, h := range hashes {
		hs[i] = hex.EncodeToString(h)
	}
	b.db.Exec(`INSERT INTO votes (chat, id, voter, options, ts) SELECT ?, ?, ?, ?, ? WHERE NOT EXISTS(SELECT 1 FROM messages WHERE chat=? AND id=? AND NOT (`+liveMessage+`))
		ON CONFLICT (chat, id, voter) DO UPDATE SET options = excluded.options, ts = excluded.ts WHERE excluded.ts >= ts`,
		chat, id, voter, strings.Join(hs, ","), ts, chat, id)
}

// pollUpdate keeps a vote that came as a message and returns the poll it
// changes, when it's here.
func (b *Bridge) pollUpdate(e *events.Message, chat types.JID, pu *waE2E.PollUpdateMessage) *Msg {
	v, err := b.cli.DecryptPollVote(b.ctx, e)
	if err != nil {
		logf("poll vote %s: %v", e.Info.ID, err)
		return nil
	}
	voter := b.norm(e.Info.Sender).String()
	if e.Info.IsFromMe {
		voter = b.me().String()
	}
	ts := pu.GetSenderTimestampMS() / 1000
	if ts == 0 {
		ts = e.Info.Timestamp.Unix()
	}
	id := pu.GetPollCreationMessageKey().GetID()
	b.vote(chat.String(), id, voter, v.GetSelectedOptions(), ts)
	return b.load(chat.String(), id)
}

// pollOptions is a stored poll's options and whether it takes more than one.
func pollOptions(x []byte) (opts []string, multi bool) {
	var p struct {
		Poll struct {
			Options []string `json:"options"`
			Multi   bool     `json:"multi"`
		} `json:"poll"`
	}
	if json.Unmarshal(x, &p) != nil {
		return nil, false
	}
	return p.Poll.Options, p.Poll.Multi
}

// withVotes fills in the polls' tallies.
func (b *Bridge) withVotes(ms []Msg) {
	me := b.me().String()
	names := map[string]string{}
	for i := range ms {
		if ms[i].Kind != "poll" {
			continue
		}
		opts, _ := pollOptions(ms[i].X)
		at := map[string]int{}
		for k := len(opts) - 1; k >= 0; k-- {
			at[optionHash(opts[k])] = k
		}
		rows, err := b.db.Query(`SELECT voter, options FROM votes WHERE chat = ? AND id = ? AND options != '' ORDER BY ts`, ms[i].Chat, ms[i].ID)
		if err != nil {
			continue
		}
		votes := make([]PollVote, len(opts))
		any := false
		for rows.Next() {
			var voter, hs string
			if rows.Scan(&voter, &hs) != nil {
				continue
			}
			name, ok := names[voter]
			if !ok {
				name = b.quoteName(voter)
				names[voter] = name
			}
			seen := map[int]bool{}
			for _, h := range strings.Split(hs, ",") {
				k, ok := at[h]
				if !ok || seen[k] {
					continue
				}
				seen[k] = true
				any = true
				votes[k].Count++
				votes[k].Mine = votes[k].Mine || voter == me
				votes[k].By = append(votes[k].By, Reactor{JID: voter, Name: name})
			}
		}
		rows.Close()
		if any {
			ms[i].Votes = votes
		}
	}
}

// sendVote votes on a poll with the options named (none takes your vote
// back): here at once, then to WhatsApp.
func (b *Bridge) sendVote(chat, id string, picked []string) {
	jid, err := types.ParseJID(chat)
	if err != nil || id == "" {
		return
	}
	var fromMe bool
	var sender, waSender, kind string
	var x []byte
	if b.db.QueryRow(`SELECT from_me, sender, wa_sender, kind, x FROM messages WHERE chat = ? AND id = ? AND `+liveMessage, chat, id).Scan(&fromMe, &sender, &waSender, &kind, &x) != nil || kind != "poll" {
		return
	}
	// Only the poll's own options, in its order; one when it takes one.
	opts, multi := pollOptions(x)
	want := map[string]bool{}
	for _, p := range picked {
		want[p] = true
	}
	names := []string{}
	for _, o := range opts {
		if want[o] && (multi || len(names) == 0) {
			names = append(names, o)
			delete(want, o)
		}
	}
	// The key names who wrote it as WhatsApp has them: the vote's secret
	// is derived from it.
	by := b.me()
	for _, s := range []string{waSender, sender} {
		if j, err := types.ParseJID(s); err == nil && s != "" {
			by = j
			break
		}
	}
	me := b.me().String()
	var old string
	var oldTS int64
	had := b.db.QueryRow(`SELECT options, ts FROM votes WHERE chat = ? AND id = ? AND voter = ?`, chat, id, me).Scan(&old, &oldTS) == nil
	b.vote(chat, id, me, whatsmeow.HashPollOptions(names), time.Now().Unix())
	b.emitMsg(chat, id)

	info := &types.MessageInfo{ID: id, MessageSource: types.MessageSource{Chat: jid, Sender: by, IsFromMe: fromMe, IsGroup: jid.Server == types.GroupServer}}
	msg, err := b.cli.BuildPollVote(b.ctx, info, names)
	if err == nil {
		_, err = b.cli.SendMessage(b.ctx, jid, msg)
	}
	if err != nil {
		if had {
			b.db.Exec(`UPDATE votes SET options = ?, ts = ? WHERE chat = ? AND id = ? AND voter = ?`, old, oldTS, chat, id, me)
		} else {
			b.db.Exec(`DELETE FROM votes WHERE chat = ? AND id = ? AND voter = ?`, chat, id, me)
		}
		b.emitMsg(chat, id)
		fail("vote", err)
	}
}
