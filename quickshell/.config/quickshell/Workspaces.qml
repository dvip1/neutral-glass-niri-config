// GNOME-style workspaces: a round dot per workspace, the active one stretched into a pill.
// Inside the active pill a solid "thumb" shows where you are in niri's scrolling strip: the
// pill is split into one segment per column and the thumb sits on the focused window's column.
// The thumb moves like a worm: its leading edge springs ahead, the trailing edge follows.
// Live from `niri msg --json event-stream` (no polling). Click a dot to go there.
// nowplaying's bar_x() follows these sizes (dot 8 + 2*3 padding, pill 32): keep in sync.
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root
    property string output: ""
    property var all: []          // niri workspaces
    property var wins: ({})       // window id -> { ws, col }; col 0 = floating
    property int rev: 0           // bumped when `wins` changes (it is mutated in place)

    readonly property var spaces: all.filter(w => w.output === output).sort((a, b) => a.idx - b.idx)
    readonly property int activeIdx: spaces.findIndex(w => w.is_active)
    readonly property var activeWs: activeIdx >= 0 ? spaces[activeIdx] : null

    // columns of the active workspace and the focused window's column (0 = none / floating)
    readonly property int cols: {
        rev
        if (!activeWs) return 0
        let n = 0
        for (const id in wins) if (wins[id].ws === activeWs.id) n = Math.max(n, wins[id].col)
        return n
    }
    readonly property int col: {
        rev
        const w = activeWs && activeWs.active_window_id !== null ? wins[activeWs.active_window_id] : null
        return w ? w.col : 0
    }

    readonly property int dot: 8
    readonly property int pill: 32
    readonly property int pad: 3

    implicitWidth: dots.implicitWidth

    // ---- where the thumb should end up (in the final layout, before cells finish resizing) ----
    readonly property real trackX: pad + Math.max(0, activeIdx) * (dot + 2 * pad)
    readonly property real thumbW: cols > 1 && col > 0 ? Math.max(6, pill / cols) : pill
    readonly property real thumbX: trackX + (cols > 1 && col > 0 ? (col - 1) * (pill - thumbW) / (cols - 1) : 0)
    onThumbXChanged: worm.go()
    onThumbWChanged: worm.go()

    function setWin(w) {
        const pos = w.layout ? w.layout.pos_in_scrolling_layout : null
        wins[w.id] = { ws: w.workspace_id, col: !w.is_floating && pos ? pos[0] : 0 }
    }

    Process {
        running: true
        command: ["niri", "msg", "--json", "event-stream"]
        stdout: SplitParser {
            onRead: line => {
                if (!line.startsWith('{"Workspace') && !line.startsWith('{"Window')) return
                const ev = JSON.parse(line)
                if (ev.WorkspacesChanged) {
                    root.all = ev.WorkspacesChanged.workspaces
                } else if (ev.WorkspaceActivated) {
                    const id = ev.WorkspaceActivated.id
                    const focused = ev.WorkspaceActivated.focused
                    const target = root.all.find(w => w.id === id)
                    if (!target) return
                    root.all = root.all.map(w => Object.assign({}, w, {
                        is_active: w.output === target.output ? w.id === id : w.is_active,
                        is_focused: focused ? w.id === id : w.is_focused
                    }))
                } else if (ev.WorkspaceActiveWindowChanged) {
                    const e = ev.WorkspaceActiveWindowChanged
                    root.all = root.all.map(w => w.id === e.workspace_id ? Object.assign({}, w, { active_window_id: e.active_window_id }) : w)
                } else if (ev.WorkspaceUrgencyChanged) {
                    const u = ev.WorkspaceUrgencyChanged
                    root.all = root.all.map(w => w.id === u.id ? Object.assign({}, w, { is_urgent: u.urgent }) : w)
                } else if (ev.WindowsChanged) {
                    root.wins = {}
                    ev.WindowsChanged.windows.forEach(root.setWin)
                    root.rev++
                } else if (ev.WindowOpenedOrChanged) {
                    root.setWin(ev.WindowOpenedOrChanged.window)
                    root.rev++
                } else if (ev.WindowClosed) {
                    delete root.wins[ev.WindowClosed.id]
                    root.rev++
                } else if (ev.WindowLayoutsChanged) {
                    for (const [id, layout] of ev.WindowLayoutsChanged.changes) {
                        const w = root.wins[id]
                        if (!w) continue
                        w.col = layout.pos_in_scrolling_layout ? layout.pos_in_scrolling_layout[0] : 0
                    }
                    root.rev++
                }
            }
        }
    }

    // ---- the dots (the active one is the pill's track) ----
    Row {
        id: dots
        height: root.height

        // a count model keeps the delegates alive across updates, so width/colour animate
        Repeater {
            model: root.spaces.length

            Item {
                id: cell
                required property int index
                readonly property var ws: root.spaces[index]
                readonly property bool active: index === root.activeIdx

                width: track.width + 2 * root.pad
                height: root.height

                Rectangle {
                    id: track
                    anchors.centerIn: parent
                    height: root.dot
                    width: cell.active ? root.pill : root.dot
                    radius: root.dot / 2
                    color: cell.ws && cell.ws.is_urgent ? Theme.crit
                         : mouse.containsMouse && !cell.active ? Theme.wsDotHover : Theme.wsDot
                    scale: mouse.pressed ? 0.85 : 1

                    Behavior on width { NumberAnimation { duration: Theme.pillMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring } }
                    Behavior on scale { NumberAnimation { duration: Theme.pillMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring } }
                    Behavior on color { ColorAnimation { duration: mouse.containsMouse ? Theme.hoverIn : Theme.hoverOut; easing.type: Easing.OutCubic } }
                }

                MouseArea {
                    id: mouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: if (cell.ws) Quickshell.execDetached(["niri", "msg", "action", "focus-workspace", String(cell.ws.idx)])
                }
            }
        }
    }

    // ---- the worm / thumb ----
    Rectangle {
        id: worm
        property real l: root.thumbX
        property real r: root.thumbX + root.thumbW
        property bool started: false

        x: Math.min(l, r - root.dot / 2)
        width: Math.max(root.dot / 2, r - l)
        height: root.dot
        anchors.verticalCenter: parent.verticalCenter
        radius: root.dot / 2
        color: Theme.wsPill
        visible: root.activeIdx >= 0

        // leading edge springs ahead, trailing edge catches up a little later
        function go() {
            const tl = root.thumbX, tr = root.thumbX + root.thumbW
            if (!started) { l = tl; r = tr; return }
            const right = tr > r || (tr === r && tl > l)
            lead.stop(); trail.stop()
            lead.target = worm; trail.target = worm
            lead.property = right ? "r" : "l"; lead.to = right ? tr : tl
            trail.property = right ? "l" : "r"; trail.to = right ? tl : tr
            lead.start(); trail.start()
        }
        Component.onCompleted: started = true

        NumberAnimation { id: lead; duration: Theme.pillMs * 0.6; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring }
        NumberAnimation { id: trail; duration: Theme.pillMs; easing.type: Easing.InOutCubic }
    }
}
