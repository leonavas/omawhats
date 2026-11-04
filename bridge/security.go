package main

import (
	"context"
	"database/sql"
	"errors"
	"net"
	"net/http"
	"net/netip"
	"net/url"
	"strings"
	"time"

	"go.mau.fi/whatsmeow/proto/waE2E"
	"go.mau.fi/whatsmeow/types"
	"go.mau.fi/whatsmeow/types/events"
)

type officialMediaRequest struct{}

func officialMediaURL(u *url.URL) bool {
	return u != nil && u.Scheme == "https" && u.User == nil && u.Opaque == "" &&
		strings.EqualFold(u.Hostname(), "static.whatsapp.net") && (u.Port() == "" || u.Port() == "443")
}

// Keep the exceptional static-media path separate from ordinary CDN downloads.
// Every redirect is checked too; DNS results are pinned to a public IP before
// dialing, while net/http still verifies TLS for the original hostname.
type mediaTransport struct {
	normal, official *http.Transport
}

func (t mediaTransport) RoundTrip(r *http.Request) (*http.Response, error) {
	if r.Context().Value(officialMediaRequest{}) != nil {
		if !officialMediaURL(r.URL) {
			return nil, errors.New("untrusted static media destination")
		}
		return t.official.RoundTrip(r)
	}
	return t.normal.RoundTrip(r)
}

func mediaHTTPClient() *http.Client {
	normal := http.DefaultTransport.(*http.Transport).Clone()
	official := normal.Clone()
	official.Proxy = nil
	official.DialContext = func(ctx context.Context, network, address string) (net.Conn, error) {
		host, port, err := net.SplitHostPort(address)
		if err != nil || !strings.EqualFold(host, "static.whatsapp.net") || port != "443" {
			return nil, errors.New("untrusted static media address")
		}
		ips, err := net.DefaultResolver.LookupNetIP(ctx, "ip", host)
		if err != nil {
			return nil, err
		}
		dialer := net.Dialer{Timeout: 10 * time.Second}
		for _, ip := range ips {
			ip = ip.Unmap()
			if !ip.IsGlobalUnicast() || ip.IsPrivate() || ip.IsLoopback() ||
				netip.MustParsePrefix("100.64.0.0/10").Contains(ip) || netip.MustParsePrefix("198.18.0.0/15").Contains(ip) {
				continue
			}
			if conn, err := dialer.DialContext(ctx, network, net.JoinHostPort(ip.String(), port)); err == nil {
				return conn, nil
			}
		}
		return nil, errors.New("no reachable public static media address")
	}
	return &http.Client{
		Transport: mediaTransport{normal: normal, official: official},
		CheckRedirect: func(r *http.Request, via []*http.Request) error {
			if len(via) >= 10 || (r.Context().Value(officialMediaRequest{}) != nil && !officialMediaURL(r.URL)) {
				return errors.New("media redirect refused")
			}
			return nil
		},
	}
}

func (b *Bridge) sameSender(stored string, sender types.JID) bool {
	j, err := types.ParseJID(stored)
	return err == nil && !j.IsEmpty() && !sender.IsEmpty() && b.norm(j) == b.norm(sender)
}

// A message ID is not an authorization token. In particular, group peers know
// each other's IDs. Only a verified current admin may revoke another author.
func (b *Bridge) mayMutate(e *events.Message, pm *waE2E.ProtocolMessage) bool {
	chat := b.norm(e.Info.Chat)
	key := pm.GetKey()
	if key.GetID() == "" {
		return false
	}
	if key.GetRemoteJID() != "" {
		j, err := types.ParseJID(key.GetRemoteJID())
		if err != nil || b.norm(j) != chat {
			return false
		}
	}
	var sender string
	var fromMe bool
	if b.db.QueryRow(`SELECT sender, from_me FROM messages WHERE chat = ? AND id = ? AND kind != 'revoked' AND `+liveMessage,
		chat.String(), key.GetID()).Scan(&sender, &fromMe) != nil {
		return false
	}
	if (e.Info.IsFromMe && fromMe) || (!e.Info.IsFromMe && !fromMe && b.sameSender(sender, e.Info.Sender)) {
		return true
	}
	if pm.GetType() != waE2E.ProtocolMessage_REVOKE || chat.Server != types.GroupServer {
		return false
	}
	// For an admin revoke, the participant must identify the target author.
	participant, err := types.ParseJID(key.GetParticipant())
	if err != nil || !b.sameSender(sender, participant) {
		return false
	}
	actor := e.Info.Sender
	if e.Info.IsFromMe {
		actor = b.me()
	}
	ctx, cancel := context.WithTimeout(b.ctx, 5*time.Second)
	defer cancel()
	g, err := b.cli.GetGroupInfo(ctx, e.Info.Chat)
	if err != nil || g == nil {
		return false
	}
	for _, p := range g.Participants {
		if (p.IsAdmin || p.IsSuperAdmin) && (b.sameSender(p.JID.String(), actor) ||
			b.sameSender(p.PhoneNumber.String(), actor) || b.sameSender(p.LID.String(), actor)) {
			return true
		}
	}
	return false
}

func (b *Bridge) mayReplace(chat, id string, sender types.JID, fromMe bool) bool {
	var owner, kind string
	var mine bool
	var expires int64
	err := b.db.QueryRow(`SELECT sender, from_me, kind, expires_at FROM messages WHERE chat = ? AND id = ?`, chat, id).
		Scan(&owner, &mine, &kind, &expires)
	if errors.Is(err, sql.ErrNoRows) {
		return true
	}
	return err == nil && kind != "expired" && kind != "revoked" && (expires == 0 || expires > time.Now().Unix()) &&
		mine == fromMe && (fromMe || b.sameSender(owner, sender))
}
