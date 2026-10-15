import QtQuick
import Quickshell
import Quickshell.Io

// The wire to WhatsApp: bridge/run.sh (the Go bridge, built the first time),
// spoken to in JSON lines. Commands go in on stdin; events come back as
// `event` signals. It restarts itself if it dies, a bit later each time;
// a failed build waits for `retry()`.
Item {
  id: root

  property string dataDir: ""
  property string cacheDir: ""
  property bool enabled: true

  readonly property string script: String(Qt.resolvedUrl("../bridge/run.sh")).replace(/^file:\/\//, "")
  property bool started: false
  // "", "building", "failed": the first run compiles the bridge.
  property string build: ""
  property string buildError: ""
  property int restarts: 0

  signal event(var ev)
  signal exited(int code)

  property var _queue: []

  function send(obj) {
    var line = JSON.stringify(obj) + "\n"
    if (root.started && proc.running) proc.write(line)
    else if (root._queue.length < 500) root._queue.push(line)
  }

  function retry() {
    root.build = ""
    root.buildError = ""
    root.restarts = 0
    if (!proc.running) proc.running = true
  }

  function stop() {
    root.enabled = false
    if (proc.running) proc.signal(15)
  }

  function _line(text) {
    if (!text) return
    var ev
    try { ev = JSON.parse(text) } catch (e) { console.warn("whatsapp-claude: bad bridge line", text.slice(0, 200)); return }
    if (ev.t === "build") {
      if (ev.state === "start") root.build = "building"
      else if (ev.state === "done") root.build = ""
      else if (ev.state === "failed") { root.build = "failed"; root.buildError = ev.error || "" }
      return
    }
    if (ev.t === "state" && ev.state === "ready") root.restarts = 0
    root.event(ev)
  }

  Process {
    id: proc
    command: ["bash", root.script, root.dataDir, root.cacheDir]
    running: root.enabled && root.dataDir !== "" && root.cacheDir !== ""
    stdinEnabled: true
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: data => root._line(data)
    }
    onStarted: {
      root.started = true
      var q = root._queue
      root._queue = []
      for (var i = 0; i < q.length; i++) proc.write(q[i])
    }
    onExited: (code, status) => {
      root.started = false
      root.exited(code)
      if (!root.enabled || root.build === "failed") return
      root.restarts++
      restartTimer.interval = Math.min(30000, 1000 * Math.pow(2, Math.min(root.restarts, 5)))
      restartTimer.restart()
    }
  }

  // The binding on `running` is gone after a restart sets it: follow
  // `enabled` by hand too (WhatsApp quit from the bar, started again).
  onEnabledChanged: {
    if (!root.enabled) { restartTimer.stop(); if (proc.running) proc.running = false }
    else if (!proc.running && root.dataDir !== "" && root.cacheDir !== "") proc.running = true
  }

  Timer {
    id: restartTimer
    onTriggered: if (root.enabled && !proc.running && root.build !== "failed") proc.running = true
  }

  Component.onDestruction: {
    root.enabled = false
    if (proc.running) proc.signal(15)
  }
}
