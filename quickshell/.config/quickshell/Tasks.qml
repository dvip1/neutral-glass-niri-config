// Running background tasks (screen recording, timers) started through ~/.local/bin/task. Each is
// a systemd user unit; `task` keeps ~/.local/state/tasks/active.json up to date, and this watches
// that file (no polling). `now` ticks once a second while anything runs, for elapsed/remaining times.
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property var list: []              // [{ unit, kind, label, started, ends, file }]
    property real now: Date.now()
    readonly property string bin: Quickshell.env("HOME") + "/.local/bin/"

    function stop(unit) { Quickshell.execDetached([bin + "task", "stop", unit]) }
    // "0:42", "1:02:05"
    function clock(ms) {
        const s = Math.max(0, Math.round(ms / 1000)), h = Math.floor(s / 3600), m = Math.floor(s / 60) % 60, x = s % 60
        return (h ? h + ":" + String(m).padStart(2, "0") : m) + ":" + String(x).padStart(2, "0")
    }
    // what the bar and the launcher show for a task: time left if it has an end, else time so far
    function status(t) { return t.ends ? clock(t.ends - now) + " left" : clock(now - t.started) }

    FileView {
        path: Quickshell.env("HOME") + "/.local/state/tasks/active.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { try { root.list = JSON.parse(text()) } catch (e) { root.list = [] } }
        onLoadFailed: root.list = []
    }
    Timer {
        running: root.list.length > 0
        repeat: true
        interval: 1000
        triggeredOnStart: true
        onTriggered: root.now = Date.now()
    }
}
