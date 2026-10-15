package main

// Linking this device to the phone: QR codes until one is scanned, or the
// 8-letter code WhatsApp shows for "Link with phone number instead".

import (
	"strings"
	"sync"

	"github.com/skip2/go-qrcode"
	"go.mau.fi/whatsmeow"
)

var (
	pairMu   sync.Mutex
	lastCode string
)

// qrRows is a QR code as rows of 0s and 1s, for the app to draw.
func qrRows(code string) []string {
	q, err := qrcode.New(code, qrcode.Low)
	if err != nil {
		return nil
	}
	q.DisableBorder = true
	bm := q.Bitmap()
	rows := make([]string, len(bm))
	for y, row := range bm {
		var sb strings.Builder
		for _, on := range row {
			if on {
				sb.WriteByte('1')
			} else {
				sb.WriteByte('0')
			}
		}
		rows[y] = sb.String()
	}
	return rows
}

// pair shows QR codes until the phone scans one, starting over when a round
// of codes runs out.
func (b *Bridge) pair() {
	for {
		qr, err := b.cli.GetQRChannel(b.ctx)
		if err != nil {
			fatal(err)
		}
		if err := b.cli.Connect(); err != nil {
			fail("connect", err)
			return
		}
		emit(map[string]any{"t": "state", "state": "pairing"})
		for item := range qr {
			switch item.Event {
			case "code":
				pairMu.Lock()
				lastCode = item.Code
				pairMu.Unlock()
				emit(map[string]any{"t": "qr", "code": item.Code, "rows": qrRows(item.Code), "timeout": item.Timeout.Seconds()})
			case "success":
				// A new link syncs the app state in full, events and all.
				b.setMeta("resynced", "1")
				b.setMeta("stickers", "1")
				emit(map[string]any{"t": "state", "state": "paired", "me": b.meInfo()})
				return
			case "timeout":
				emit(map[string]any{"t": "state", "state": "qr_timeout"})
			default:
				if item.Error != nil {
					fail("pair", item.Error)
				}
			}
		}
		b.cli.Disconnect()
	}
}

// pairPhone asks for the code to type on the phone, for the number given.
func (b *Bridge) pairPhone(phone string) {
	digits := digitsOf(phone)
	if len(digits) < 8 {
		fail("pair_phone_number", nil)
		return
	}
	code, err := b.cli.PairPhone(b.ctx, digits, true, whatsmeow.PairClientChrome, "Chrome (Linux)")
	if err != nil {
		fail("pair_phone", err)
		return
	}
	emit(map[string]any{"t": "pair_code", "code": code, "phone": digits})
}

func digitsOf(s string) string {
	var d strings.Builder
	for _, r := range s {
		if r >= '0' && r <= '9' {
			d.WriteRune(r)
		}
	}
	return d.String()
}
