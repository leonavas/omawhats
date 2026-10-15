package main

// Desktop notifications, sent for the app over the session bus. Not through
// notify-send: a command's arguments can be read by any user of the machine
// (/proc/<pid>/cmdline), and these carry who wrote and what. The app decides
// when to notify and what it says; this only delivers it.

import (
	"sync"

	"github.com/godbus/dbus/v5"
)

var (
	busMu sync.Mutex
	bus   *dbus.Conn
)

// notify shows c.Title and c.Text (the body, as markup) from c.App, with
// c.Icon; c.Exec is the argv Omarchy's notification center runs on a click
// (its omarchy-exec-argv hint, a JSON array).
func notify(c Cmd) {
	busMu.Lock()
	defer busMu.Unlock()
	if bus == nil || !bus.Connected() {
		conn, err := dbus.ConnectSessionBus()
		if err != nil {
			logf("notify: %v", err)
			return
		}
		bus = conn
	}
	hints := map[string]dbus.Variant{}
	if c.Exec != "" {
		hints["omarchy-exec-argv"] = dbus.MakeVariant(c.Exec)
	}
	call := bus.Object("org.freedesktop.Notifications", "/org/freedesktop/Notifications").Call(
		"org.freedesktop.Notifications.Notify", 0,
		c.App, uint32(0), c.Icon, c.Title, c.Text, []string{}, hints, int32(-1))
	if call.Err != nil {
		logf("notify: %v", call.Err)
	}
}
