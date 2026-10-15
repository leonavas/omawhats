package main

// What a message is, for the app to draw: its kind, its text (the body, or
// a photo's caption) and, for the kinds that have more, an "x" object with
// it (a link's preview, a place, a contact card, a poll's options, what a
// system notice says). The app writes its own labels ("Foto", "Áudio")
// from the kind; nothing here is worded for a language.

import (
	"strings"

	"go.mau.fi/whatsmeow/proto/waE2E"
	"go.mau.fi/whatsmeow/proto/waWeb"
	"google.golang.org/protobuf/reflect/protoreflect"
)

// Content is a message's part the app draws, besides its media.
type Content struct {
	Kind string
	Text string
	X    map[string]any
	// A JPEG the x object points at once it's on disk (a link's or a
	// place's picture): the caller writes it and sets X["thumb"].
	Thumb []byte
}

// contentOf reads a message; false for what isn't shown as one (reactions,
// key exchanges, protocol messages, poll votes).
func contentOf(m *waE2E.Message) (Content, bool) {
	if m == nil {
		return Content{}, false
	}
	if c := cardOf(m); c != nil {
		return Content{Kind: "card", Text: c.body}, true
	}
	switch {
	case m.GetConversation() != "":
		return Content{Kind: "text", Text: m.GetConversation()}, true
	case m.GetExtendedTextMessage() != nil:
		x := m.GetExtendedTextMessage()
		c := Content{Kind: "text", Text: x.GetText()}
		if x.GetTitle() != "" || x.GetDescription() != "" {
			url := webURL(x.GetMatchedText())
			if url == "" {
				url = firstURL(x.GetText())
			}
			c.X = map[string]any{"link": map[string]any{"url": url, "title": x.GetTitle(), "desc": x.GetDescription()}}
			c.Thumb = x.GetJPEGThumbnail()
		}
		return c, true
	case m.GetImageMessage() != nil:
		return Content{Kind: "image", Text: m.GetImageMessage().GetCaption()}, true
	case m.GetVideoMessage() != nil:
		x := m.GetVideoMessage()
		if x.GetGifPlayback() {
			return Content{Kind: "gif", Text: x.GetCaption()}, true
		}
		return Content{Kind: "video", Text: x.GetCaption()}, true
	case m.GetPtvMessage() != nil:
		return Content{Kind: "ptv"}, true
	case m.GetAudioMessage() != nil:
		if m.GetAudioMessage().GetPTT() {
			return Content{Kind: "ptt"}, true
		}
		return Content{Kind: "audio"}, true
	case m.GetDocumentMessage() != nil:
		return Content{Kind: "document", Text: m.GetDocumentMessage().GetCaption()}, true
	case m.GetStickerMessage() != nil:
		return Content{Kind: "sticker"}, true
	case m.GetLocationMessage() != nil:
		x := m.GetLocationMessage()
		kind := "location"
		if x.GetIsLive() {
			kind = "live_location"
		}
		return Content{Kind: kind, Text: x.GetComment(), Thumb: x.GetJPEGThumbnail(), X: map[string]any{"loc": map[string]any{
			"lat": x.GetDegreesLatitude(), "lon": x.GetDegreesLongitude(), "name": x.GetName(), "addr": x.GetAddress(), "url": webURL(x.GetURL()),
		}}}, true
	case m.GetLiveLocationMessage() != nil:
		x := m.GetLiveLocationMessage()
		return Content{Kind: "live_location", Text: x.GetCaption(), Thumb: x.GetJPEGThumbnail(), X: map[string]any{"loc": map[string]any{
			"lat": x.GetDegreesLatitude(), "lon": x.GetDegreesLongitude(),
		}}}, true
	case m.GetContactMessage() != nil:
		x := m.GetContactMessage()
		return Content{Kind: "contact", X: map[string]any{"contacts": []any{vcardOf(x.GetDisplayName(), x.GetVcard())}}}, true
	case m.GetContactsArrayMessage() != nil:
		x := m.GetContactsArrayMessage()
		list := []any{}
		for _, c := range x.GetContacts() {
			list = append(list, vcardOf(c.GetDisplayName(), c.GetVcard()))
		}
		return Content{Kind: "contact", Text: x.GetDisplayName(), X: map[string]any{"contacts": list}}, true
	case pollOf(m) != nil:
		p := pollOf(m)
		opts := []string{}
		for _, o := range p.GetOptions() {
			opts = append(opts, o.GetOptionName())
		}
		return Content{Kind: "poll", Text: p.GetName(), X: map[string]any{"poll": map[string]any{
			"options": opts, "multi": p.GetSelectableOptionsCount() != 1,
		}}}, true
	case m.GetEventMessage() != nil:
		x := m.GetEventMessage()
		ev := map[string]any{"name": x.GetName(), "desc": x.GetDescription(), "start": x.GetStartTime(), "end": x.GetEndTime(), "canceled": x.GetIsCanceled()}
		if l := x.GetLocation(); l != nil {
			ev["place"] = l.GetName()
		}
		return Content{Kind: "event", Text: x.GetName(), X: map[string]any{"event": ev}}, true
	case m.GetGroupInviteMessage() != nil:
		x := m.GetGroupInviteMessage()
		return Content{Kind: "invite", Text: x.GetCaption(), Thumb: x.GetJPEGThumbnail(), X: map[string]any{"invite": map[string]any{
			"group": x.GetGroupName(), "jid": x.GetGroupJID(), "code": x.GetInviteCode(),
		}}}, true
	case m.GetCallLogMesssage() != nil:
		return Content{Kind: "call", X: map[string]any{"call": callContent(m.GetCallLogMesssage())}}, true
	case m.GetPinInChatMessage() != nil:
		pin := m.GetPinInChatMessage().GetType() == waE2E.PinInChatMessage_PIN_FOR_ALL
		return Content{Kind: "system", X: map[string]any{"sys": map[string]any{"type": map[bool]string{true: "pin", false: "unpin"}[pin]}}}, true
	// Answers to a business's buttons and lists: what was picked.
	case m.GetTemplateButtonReplyMessage().GetSelectedDisplayText() != "":
		return Content{Kind: "text", Text: m.GetTemplateButtonReplyMessage().GetSelectedDisplayText()}, true
	case m.GetButtonsResponseMessage().GetSelectedDisplayText() != "":
		return Content{Kind: "text", Text: m.GetButtonsResponseMessage().GetSelectedDisplayText()}, true
	case m.GetListResponseMessage().GetTitle() != "":
		return Content{Kind: "text", Text: m.GetListResponseMessage().GetTitle()}, true
	case m.GetInteractiveResponseMessage().GetBody().GetText() != "":
		return Content{Kind: "text", Text: m.GetInteractiveResponseMessage().GetBody().GetText()}, true
	case m.GetPlaceholderMessage() != nil:
		return Content{Kind: "placeholder"}, true
	}
	// Signals, not messages: nothing to show.
	if m.GetReactionMessage() != nil || m.GetEncReactionMessage() != nil || m.GetProtocolMessage() != nil ||
		m.GetPollUpdateMessage() != nil || m.GetSenderKeyDistributionMessage() != nil || m.GetKeepInChatMessage() != nil ||
		m.GetAlbumMessage() != nil || m.GetEncEventResponseMessage() != nil || m.GetStickerSyncRmrMessage() != nil {
		return Content{}, false
	}
	// Nothing but its context (what a key exchange leaves): nothing either.
	n := 0
	m.ProtoReflect().Range(func(fd protoreflect.FieldDescriptor, _ protoreflect.Value) bool {
		if fd.Name() != "messageContextInfo" {
			n++
		}
		return true
	})
	if n == 0 {
		return Content{}, false
	}
	// Something this app doesn't know yet: WhatsApp Web says it can't show it.
	return Content{Kind: "unsupported"}, true
}

func pollOf(m *waE2E.Message) *waE2E.PollCreationMessage {
	for _, p := range []*waE2E.PollCreationMessage{m.GetPollCreationMessage(), m.GetPollCreationMessageV2(), m.GetPollCreationMessageV3(), m.GetPollCreationMessageV5(), m.GetPollCreationMessageV6()} {
		if p != nil {
			return p
		}
	}
	return nil
}

// firstURL is the first http(s) link in text.
// webURL is a link its sender attached, kept only when a browser opens it
// (http or https): any other scheme could hand a file or a command to
// whatever handles it.
func webURL(s string) string {
	s = strings.TrimSpace(s)
	if l := strings.ToLower(s); strings.HasPrefix(l, "https://") || strings.HasPrefix(l, "http://") {
		return s
	}
	return ""
}

func firstURL(text string) string {
	for _, w := range strings.Fields(text) {
		if strings.HasPrefix(w, "http://") || strings.HasPrefix(w, "https://") {
			return strings.TrimRight(w, ".,;:!?)")
		}
	}
	return ""
}

// vcardOf is a contact card's name and phone numbers (with the WhatsApp
// id the vCard gives them, when it does).
func vcardOf(name, vcard string) map[string]any {
	phones := []map[string]string{}
	for _, line := range strings.Split(strings.ReplaceAll(vcard, "\r\n", "\n"), "\n") {
		up := strings.ToUpper(line)
		if !strings.HasPrefix(up, "TEL") && !strings.Contains(up, ".TEL") {
			continue
		}
		i := strings.LastIndex(line, ":")
		if i < 0 {
			continue
		}
		p := map[string]string{"number": strings.TrimSpace(line[i+1:])}
		if j := strings.Index(up, "WAID="); j >= 0 {
			wa := line[j+5:]
			if k := strings.IndexAny(wa, ";:"); k >= 0 {
				wa = wa[:k]
			}
			p["wa"] = wa
		}
		phones = append(phones, p)
	}
	return map[string]any{"name": name, "phones": phones}
}

// stubOf reads what a history message without content says: the notices
// WhatsApp draws in the middle of a chat (who joined a group, who changed
// its name, a missed call). The people are JIDs here; the caller names
// them. False for the ones the app doesn't show.
func stubOf(web *waWeb.WebMessageInfo) (Content, []string, bool) {
	params := web.GetMessageStubParameters()
	var kind string
	switch web.GetMessageStubType() {
	case waWeb.WebMessageInfo_GROUP_CREATE:
		kind = "group_create"
	case waWeb.WebMessageInfo_GROUP_CHANGE_SUBJECT:
		kind = "group_subject"
	case waWeb.WebMessageInfo_GROUP_CHANGE_ICON:
		kind = "group_icon"
	case waWeb.WebMessageInfo_GROUP_CHANGE_DESCRIPTION:
		kind = "group_description"
	case waWeb.WebMessageInfo_GROUP_CHANGE_RESTRICT:
		kind = "group_restrict"
	case waWeb.WebMessageInfo_GROUP_CHANGE_ANNOUNCE:
		kind = "group_announce"
	case waWeb.WebMessageInfo_GROUP_PARTICIPANT_ADD:
		kind = "group_add"
	case waWeb.WebMessageInfo_GROUP_PARTICIPANT_REMOVE:
		kind = "group_remove"
	case waWeb.WebMessageInfo_GROUP_PARTICIPANT_LEAVE:
		kind = "group_leave"
	case waWeb.WebMessageInfo_GROUP_PARTICIPANT_INVITE, waWeb.WebMessageInfo_GROUP_PARTICIPANT_ACCEPT, waWeb.WebMessageInfo_GROUP_PARTICIPANT_LINKED_GROUP_JOIN:
		kind = "group_join"
	case waWeb.WebMessageInfo_GROUP_PARTICIPANT_PROMOTE:
		kind = "group_promote"
	case waWeb.WebMessageInfo_GROUP_PARTICIPANT_DEMOTE:
		kind = "group_demote"
	case waWeb.WebMessageInfo_GROUP_PARTICIPANT_CHANGE_NUMBER, waWeb.WebMessageInfo_INDIVIDUAL_CHANGE_NUMBER:
		kind = "change_number"
	case waWeb.WebMessageInfo_CHANGE_EPHEMERAL_SETTING:
		kind = "ephemeral"
	case waWeb.WebMessageInfo_E2E_IDENTITY_CHANGED:
		kind = "security_code"
	case waWeb.WebMessageInfo_CALL_MISSED_VOICE, waWeb.WebMessageInfo_CALL_MISSED_VIDEO, waWeb.WebMessageInfo_CALL_MISSED_GROUP_VOICE, waWeb.WebMessageInfo_CALL_MISSED_GROUP_VIDEO:
		t := web.GetMessageStubType()
		return Content{Kind: "call", X: map[string]any{"call": Call{Outcome: "missed", Phone: true,
			Video: t == waWeb.WebMessageInfo_CALL_MISSED_VIDEO || t == waWeb.WebMessageInfo_CALL_MISSED_GROUP_VIDEO,
			Group: t == waWeb.WebMessageInfo_CALL_MISSED_GROUP_VOICE || t == waWeb.WebMessageInfo_CALL_MISSED_GROUP_VIDEO}}}, nil, true
	case waWeb.WebMessageInfo_REVOKE:
		return Content{Kind: "revoked"}, nil, true
	case waWeb.WebMessageInfo_CIPHERTEXT:
		return Content{Kind: "placeholder"}, nil, true
	default:
		return Content{}, nil, false
	}
	sys := map[string]any{"type": kind}
	var people []string
	switch kind {
	case "group_subject", "group_description", "ephemeral":
		if len(params) > 0 {
			sys["value"] = params[0]
		}
	case "group_restrict", "group_announce":
		if len(params) > 0 {
			sys["value"] = params[0] == "on"
		}
	case "group_create":
		if len(params) > 0 {
			sys["value"] = params[0]
		}
	default:
		people = params
	}
	return Content{Kind: "system", X: map[string]any{"sys": sys}}, people, true
}
