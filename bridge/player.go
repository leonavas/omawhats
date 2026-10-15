package main

// Voice notes and audio play through mpv (Omarchy has it), one at a time,
// driven over its JSON IPC socket: the app asks to play, pause, seek or
// change the speed, and hears back where it is, a few times a second.

import (
	"bufio"
	"encoding/json"
	"fmt"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"sync"
	"time"

	"go.mau.fi/whatsmeow/types"
)

type Player struct {
	mu   sync.Mutex
	cmd  *exec.Cmd
	conn net.Conn
	// What's loaded: the message, and where to go once it's open.
	chat, id string
	seekTo   float64
	pos, dur float64
	paused   bool
	lastEmit time.Time
}

var player = &Player{}

func (p *Player) command(c Cmd) {
	p.mu.Lock()
	defer p.mu.Unlock()
	switch c.C {
	case "play":
		if err := p.start(); err != nil {
			logf("player: %v", err)
			emit(map[string]any{"t": "player", "chat": c.Chat, "id": c.ID, "playing": false, "error": err.Error()})
			return
		}
		p.chat, p.id, p.seekTo, p.pos, p.dur = c.Chat, c.ID, c.Pos, c.Pos, 0
		p.send("loadfile", c.Path, "replace")
		speed := c.Speed
		if speed <= 0 {
			speed = 1
		}
		p.send("set_property", "speed", speed)
		p.send("set_property", "pause", false)
	case "pause":
		p.send("set_property", "pause", true)
	case "resume":
		p.send("set_property", "pause", false)
	case "seek":
		p.send("seek", c.Pos, "absolute")
		p.pos = c.Pos
		p.emit(true)
	case "speed":
		p.send("set_property", "speed", c.Speed)
	case "stop":
		p.send("stop")
	}
}

// start runs mpv, idle and without video, once.
func (p *Player) start() error {
	if p.conn != nil {
		return nil
	}
	sock := filepath.Join(os.TempDir(), fmt.Sprintf("whatsapp-claude-mpv-%d.sock", os.Getpid()))
	os.Remove(sock)
	cmd := exec.Command("mpv", "--idle=yes", "--no-video", "--no-config", "--no-terminal", "--really-quiet",
		"--audio-display=no", "--input-ipc-server="+sock)
	if err := cmd.Start(); err != nil {
		return err
	}
	var conn net.Conn
	var err error
	for range 50 {
		if conn, err = net.Dial("unix", sock); err == nil {
			break
		}
		time.Sleep(40 * time.Millisecond)
	}
	if err != nil {
		cmd.Process.Kill()
		return err
	}
	p.cmd, p.conn = cmd, conn
	for i, prop := range []string{"time-pos", "duration", "pause"} {
		p.send("observe_property", i+1, prop)
	}
	go p.read(conn)
	go func() {
		cmd.Wait()
		p.mu.Lock()
		if p.cmd == cmd {
			p.cmd, p.conn = nil, nil
		}
		p.mu.Unlock()
		os.Remove(sock)
	}()
	return nil
}

func (p *Player) send(args ...any) {
	if p.conn == nil {
		return
	}
	js, _ := json.Marshal(map[string]any{"command": args})
	p.conn.Write(append(js, '\n'))
}

// read follows mpv's events: where it is, how long the file is, paused or
// not, and its end.
func (p *Player) read(conn net.Conn) {
	in := bufio.NewScanner(conn)
	in.Buffer(make([]byte, 64<<10), 1<<20)
	for in.Scan() {
		var ev struct {
			Event  string          `json:"event"`
			Name   string          `json:"name"`
			Data   json.RawMessage `json:"data"`
			Reason string          `json:"reason"`
		}
		if json.Unmarshal(in.Bytes(), &ev) != nil || ev.Event == "" {
			continue
		}
		p.mu.Lock()
		switch ev.Event {
		case "file-loaded":
			if p.seekTo > 0 {
				p.send("seek", p.seekTo, "absolute")
				p.seekTo = 0
			}
		case "property-change":
			var f float64
			var b bool
			switch ev.Name {
			case "time-pos":
				if json.Unmarshal(ev.Data, &f) == nil {
					p.pos = f
					p.emit(false)
				}
			case "duration":
				if json.Unmarshal(ev.Data, &f) == nil {
					p.dur = f
				}
			case "pause":
				if json.Unmarshal(ev.Data, &b) == nil {
					p.paused = b
					p.emit(true)
				}
			}
		case "end-file":
			if p.id != "" {
				emit(map[string]any{"t": "player", "chat": p.chat, "id": p.id, "pos": 0, "dur": p.dur, "playing": false, "ended": ev.Reason == "eof"})
				if ev.Reason == "eof" || ev.Reason == "stop" {
					p.id = ""
				}
			}
		}
		p.mu.Unlock()
	}
}

// emit tells the app where the playing one is: on every change of state,
// and four times a second while it plays.
func (p *Player) emit(now bool) {
	if p.id == "" || (!now && time.Since(p.lastEmit) < 250*time.Millisecond) {
		return
	}
	p.lastEmit = time.Now()
	emit(map[string]any{"t": "player", "chat": p.chat, "id": p.id, "pos": p.pos, "dur": p.dur, "playing": !p.paused})
}

func (p *Player) quit() {
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.cmd != nil && p.cmd.Process != nil {
		p.cmd.Process.Kill()
	}
}

// markPlayed tells whoever sent a voice note that you heard it: their
// ticks turn blue on the microphone, as the phone does it.
func (b *Bridge) markPlayed(chat, id string) {
	var fromMe bool
	var kind, sender, waSender string
	if b.db.QueryRow(`SELECT from_me, kind, sender, wa_sender FROM messages WHERE chat = ? AND id = ?`, chat, id).Scan(&fromMe, &kind, &sender, &waSender) != nil || fromMe || kind != "ptt" {
		return
	}
	wa := b.waJID(chat)
	s := types.EmptyJID
	if wa.Server == types.GroupServer {
		for _, cand := range []string{waSender, sender} {
			if j, err := types.ParseJID(cand); err == nil && cand != "" {
				s = j
				break
			}
		}
	}
	if err := b.cli.MarkRead(b.ctx, []types.MessageID{id}, time.Now(), wa, s, types.ReceiptTypePlayed); err != nil {
		logf("played %s: %v", id, err)
	}
}
