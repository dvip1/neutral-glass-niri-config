// The notification daemon (replaces swaync): owns org.freedesktop.Notifications.
// `items` is the centre's list, newest first; live entries carry their Notification `n`
// (actions work), entries restored from the history file have n = null. `popups` are the
// entries currently shown as popups. Delegates get copies of entries, so everything that
// comes back from the UI is looked up again by its `key`. The last 50 are saved to
// ~/.local/state/quickshell/notifications.json so they survive logouts.
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

Singleton {
    id: root
    property bool dnd: false
    property var items: []
    property var popups: []
    property int unread: 0                // since the centre was last opened
    property bool centreOpen: false       // the date menu is showing the list: no popups, no unread
    property int nextKey: 1
    readonly property int keep: 50
    property double now: Date.now()       // for "5 min ago" labels
    Timer { interval: 30000; running: true; repeat: true; onTriggered: root.now = Date.now() }
    readonly property string file: Quickshell.env("HOME") + "/.local/state/quickshell/notifications.json"

    NotificationServer {
        keepOnReload: true
        persistenceSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: true
        actionsSupported: true
        imageSupported: true
        onNotification: n => root.add(n)
    }

    // the picture for a notification: its image, else its app icon (a path or an icon name)
    function iconFor(n, appIcon, desktopEntry) {
        if (n && n.image) return n.image
        const name = appIcon || desktopEntry || ""
        if (name.startsWith("/") || name.startsWith("file://")) return name
        return name ? Quickshell.iconPath(name, true) : ""
    }

    function add(n) {
        n.tracked = true
        // a replacement of a live one, or (after a reload) the saved copy of one still alive
        const old = items.find(e => e.n ? e.n.id === n.id : e.nid === n.id && e.summary === n.summary)
        // re-announced after a Quickshell reload (e.g. a theme switch): already seen, don't pop it again
        const reannounced = old !== undefined && !old.n
        const e = old || { key: nextKey++ }
        if (!old || old.n !== n) n.closed.connect(reason => root.closed(e, reason))   // a new live object
        Object.assign(e, {
            n: n, nid: n.id, app: n.appName || "", summary: n.summary, body: n.body, urgency: n.urgency,
            icon: iconFor(n, n.appIcon, n.desktopEntry), time: reannounced ? old.time : Date.now()
        })
        items = [e].concat(items.filter(x => x.key !== e.key)).slice(0, keep)
        if (!old && !centreOpen) unread++
        if (centreOpen || reannounced) {}
        else if (!dnd || n.urgency === NotificationUrgency.Critical)
            popups = [e].concat(popups.filter(x => x.key !== e.key))
        else if (old) popups = popups.slice()     // refresh a shown one in place
        save.restart()
    }

    // the app (or we) closed it: it leaves the centre too, unless it only expired
    function closed(e, reason) {
        if (reason === NotificationCloseReason.Expired) { e.n = null; items = items.slice(); return }
        e.n = null
        drop(e)
    }

    function find(e) { return items.find(x => x.key === e.key) || popups.find(x => x.key === e.key) }
    function drop(e) {
        items = items.filter(x => x.key !== e.key)
        popups = popups.filter(x => x.key !== e.key)
        save.restart()
    }
    function dismiss(e) {
        const o = find(e)
        if (o && o.n) o.n.dismiss()          // -> closed() -> drop()
        else drop(e)
    }
    function clearApp(app) { items.filter(x => x.app === app).forEach(dismiss) }
    function clear() { items.slice().forEach(dismiss); items = []; popups = []; save.restart() }
    function unpop(e) { popups = popups.filter(x => x.key !== e.key) }
    // run an action (or the default one); the notification goes away unless it is resident
    function invoke(e, action) {
        const o = find(e)
        if (!o || !o.n) return
        const a = action || o.n.actions.find(x => x.identifier === "default")
        if (a) a.invoke()
        if (o.n && !o.n.resident) dismiss(o)
    }
    function seen() { unread = 0; popups = [] }

    // ---- history file ----
    // written at once, blocking: a reload (theme switch) right after a change must not lose it
    QtObject {
        id: save
        function restart() { root.write() }
    }
    function write() {
        const plain = root.items.map(e => ({
            nid: e.nid, app: e.app, summary: e.n ? e.n.summary : e.summary, body: e.n ? e.n.body : e.body,
            urgency: e.urgency, time: e.time,
            icon: (e.icon || "").startsWith("image:") ? "" : e.icon
        }))
        history.setText(JSON.stringify({ dnd: root.dnd, items: plain }))
    }
    onDndChanged: save.restart()

    Process {
        running: true
        command: ["mkdir", "-p", Quickshell.env("HOME") + "/.local/state/quickshell"]
    }
    FileView {
        id: history
        path: root.file
        atomicWrites: true
        blockWrites: true
        printErrors: false
        onLoaded: {
            try {
                const d = JSON.parse(text())
                root.dnd = !!d.dnd
                const restored = (d.items || []).map(x => Object.assign({ key: root.nextKey++, n: null }, x))
                root.items = root.items.concat(restored).slice(0, root.keep)
            } catch (e) {}
        }
    }
}
