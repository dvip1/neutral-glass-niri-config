// GNOME-style workspaces: a round dot per workspace, the active one stretched into a pill.
// Live from `niri msg --json event-stream` (no polling). Click a dot to go there.
// nowplaying's bar_x() follows these sizes (dot 8 + 2*3 padding, pill 32): keep in sync.
import QtQuick
import Quickshell
import Quickshell.Io

Row {
    id: root
    property string output: ""
    property var all: []
    readonly property var spaces: all.filter(w => w.output === output).sort((a, b) => a.idx - b.idx)

    Process {
        running: true
        command: ["niri", "msg", "--json", "event-stream"]
        stdout: SplitParser {
            onRead: line => {
                if (!line.startsWith('{"Workspace')) return
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
                } else if (ev.WorkspaceUrgencyChanged) {
                    const u = ev.WorkspaceUrgencyChanged
                    root.all = root.all.map(w => w.id === u.id ? Object.assign({}, w, { is_urgent: u.urgent }) : w)
                }
            }
        }
    }

    // A count model keeps the delegates alive across updates, so width/colour animate.
    Repeater {
        model: root.spaces.length

        Item {
            id: cell
            required property int index
            readonly property var ws: root.spaces[index]
            readonly property bool active: ws ? ws.is_active : false

            width: dot.width + 6
            height: root.height

            Rectangle {
                id: dot
                anchors.centerIn: parent
                height: 8
                width: cell.active ? 32 : 8
                radius: 4
                color: cell.ws && cell.ws.is_urgent ? Theme.crit
                     : cell.active ? Theme.wsPill
                     : mouse.containsMouse ? Theme.wsDotHover : Theme.wsDot
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
