// Now playing: a glass sheet under the bar's media pill, one card per player with
// prev / play / next and a seek bar. Clicking a card hands the bar to that player (it becomes
// playerctld's active player). Open/close behaviour comes from Sheet.qml.
// (Replaces ~/.local/bin/nowplaying, the GTK4 version.)   qs ipc call nowplaying toggle
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Widgets

Sheet {
    id: np
    property var order: []            // playerctld's order (instance names); first = the bar's player

    namespace: "nowplaying"
    full: 360

    readonly property string ctld: "org.mpris.MediaPlayer2.playerctld"
    readonly property var players: Mpris.players.values
        .filter(p => p.dbusName !== ctld)
        .sort((a, b) => rank(a) - rank(b))
    function inst(p) { return p.dbusName.replace("org.mpris.MediaPlayer2.", "") }
    function rank(p) { const i = order.indexOf(inst(p)); return i < 0 ? order.length : i }

    onWantChanged: if (want) orderProc.running = true
    onPlayersChanged: if (want && players.length === 0) want = false

    IpcHandler {
        target: "nowplaying"
        function toggle(): void { np.want = !np.want && np.players.length > 0 }
    }

    // playerctld's order, and making a player the active one (rotate the list the shorter way)
    Process {
        id: orderProc
        command: ["busctl", "--user", "--json=short", "get-property", np.ctld, "/org/mpris/MediaPlayer2",
                  "com.github.altdesktop.playerctld", "PlayerNames"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { np.order = JSON.parse(text).data.map(n => n.replace("org.mpris.MediaPlayer2.", "")) } catch (e) {}
            }
        }
    }
    Timer { interval: 1000; repeat: true; running: np.visible; onTriggered: orderProc.running = true }
    function pick(p) {
        const i = order.indexOf(inst(p))
        if (i <= 0) return
        const [method, times] = i <= order.length - i ? ["Shift", i] : ["Unshift", order.length - i]
        const call = "busctl --user call " + ctld + " /org/mpris/MediaPlayer2 com.github.altdesktop.playerctld " + method
        Quickshell.execDetached(["sh", "-c", Array(times).fill(call).join("; ")])
        order = order.slice(i).concat(order.slice(0, i))   // show it right away; the timer confirms
    }

    // MPRIS positions are not pushed: poll while open
    Timer {
        interval: 500; repeat: true; running: np.visible
        onTriggered: np.players.forEach(p => p.positionChanged())
    }

    function fmt(sec) {
        const s = Math.max(0, Math.floor(sec)), h = Math.floor(s / 3600), m = Math.floor(s / 60) % 60
        const ss = String(s % 60).padStart(2, "0")
        return h ? h + ":" + String(m).padStart(2, "0") + ":" + ss : m + ":" + ss
    }
    readonly property var icons: ({ spotify: "󰓇", firefox: "󰈹", chromium: "", chrome: "", brave: "", mpv: "", vlc: "󰕼" })
    function appName(p) { return inst(p).split(".")[0] }

    Repeater {
        model: np.players
        delegate: card
    }

    component Card: Rectangle {
        id: c
        required property var modelData
        required property int index
        readonly property var p: modelData
        readonly property bool active: np.rank(p) === 0
        readonly property bool hot: mouse.containsMouse
        readonly property real len: p.lengthSupported ? p.length : 0

        width: np.inner
        implicitHeight: body.implicitHeight + 16
        radius: Theme.radiusSmall
        color: active ? Theme.wsActiveBg : hot ? Theme.wsHover : Theme.clear(Theme.wsHover)
        Behavior on color { ColorAnimation { duration: c.hot ? Theme.hoverIn : Theme.hoverOut } }

        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: np.pick(c.p)
        }

        Column {
            id: body
            x: 8; y: 8
            width: parent.width - 16
            spacing: 6

            Row {
                spacing: 12
                width: parent.width

                // cover, or the player's icon on a tile
                ClippingRectangle {
                    width: 64; height: 64
                    radius: Theme.radiusSmall
                    color: Theme.pillHover
                    Text {
                        anchors.centerIn: parent
                        visible: cover.status !== Image.Ready
                        text: np.icons[np.appName(c.p)] || "󰝚"
                        color: Theme.fgMuted
                        font { family: Theme.iconFont; pixelSize: 26 }
                    }
                    Image {
                        id: cover
                        anchors.fill: parent
                        source: c.p.trackArtUrl || ""
                        sourceSize: Qt.size(128, 128)
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }
                }

                Column {
                    width: parent.width - 64 - 12
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: c.p.trackTitle || c.p.identity
                        color: c.p.isPlaying ? Theme.fgStrong : Theme.fg
                        font { family: Theme.font; pointSize: Theme.fontPx * 0.75; weight: Font.DemiBold }
                    }
                    Text {
                        width: parent.width
                        visible: text !== ""
                        topPadding: 1
                        elide: Text.ElideRight
                        text: c.p.trackArtist || ""
                        color: Theme.fgTitle
                        font { family: Theme.font; pointSize: 13 * 0.75 }
                    }
                    Item {
                        width: parent.width
                        height: 30
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: (np.icons[np.appName(c.p)] || "󰝚") + "  " + c.p.identity
                            color: Theme.fgMuted
                            font { family: Theme.font; pointSize: 12 * 0.75 }
                        }
                        Row {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            Btn {
                                implicitHeight: 26; padding: 8
                                enabled: c.p.canGoPrevious; opacity: enabled ? 1 : 0.4
                                onClicked: c.p.previous()
                                Icon { text: "󰒮"; color: Theme.fg; pointSize: 15 * 0.75 }
                            }
                            Btn {
                                implicitHeight: 26; padding: 8
                                enabled: c.p.canTogglePlaying; opacity: enabled ? 1 : 0.4
                                onClicked: c.p.togglePlaying()
                                Icon { text: c.p.isPlaying ? "󰏤" : "󰐊"; color: Theme.fg; pointSize: 15 * 0.75 }
                            }
                            Btn {
                                implicitHeight: 26; padding: 8
                                enabled: c.p.canGoNext; opacity: enabled ? 1 : 0.4
                                onClicked: c.p.next()
                                Icon { text: "󰒭"; color: Theme.fg; pointSize: 15 * 0.75 }
                            }
                        }
                    }
                }
            }

            // seek bar: a hairline that thickens and shows its knob when you reach for it
            Row {
                visible: c.len > 0
                width: parent.width
                spacing: 8

                Text {
                    width: 34
                    anchors.verticalCenter: parent.verticalCenter
                    text: np.fmt(seek.dragging ? seek.dragFrac * c.len : c.p.position)
                    color: Theme.fgMuted
                    font { family: Theme.font; pointSize: 11 * 0.75; features: { "tnum": 1 } }
                }
                Item {
                    id: seek
                    width: parent.width - 2 * (34 + 8)
                    height: 16
                    anchors.verticalCenter: parent.verticalCenter
                    readonly property bool hot: seekMouse.containsMouse || seekMouse.pressed
                    property bool dragging: false
                    property real dragFrac: 0
                    readonly property real frac: dragging ? dragFrac : c.len > 0 ? Math.min(1, c.p.position / c.len) : 0

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: seek.hot ? 5 : 3
                        radius: height / 2
                        color: Theme.pillHover
                        Behavior on height { NumberAnimation { duration: 150 } }
                        Rectangle {
                            height: parent.height
                            radius: height / 2
                            width: parent.width * seek.frac
                            color: c.p.canSeek ? Theme.fgTitle : Theme.fgMuted
                        }
                    }
                    Rectangle {
                        property real size: seek.hot && c.p.canSeek ? 11 : 0
                        width: size; height: size; radius: size / 2
                        x: parent.width * seek.frac - size / 2
                        anchors.verticalCenter: parent.verticalCenter
                        color: Theme.fgStrong
                        Behavior on size { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
                    }
                    MouseArea {
                        id: seekMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: c.p.canSeek
                        function at(mx) { return Math.max(0, Math.min(1, mx / width)) }
                        onPressed: m => { seek.dragging = true; seek.dragFrac = at(m.x) }
                        onPositionChanged: m => { if (pressed) seek.dragFrac = at(m.x) }
                        onReleased: { c.p.position = seek.dragFrac * c.len; seek.dragging = false }
                    }
                }
                Text {
                    width: 34
                    horizontalAlignment: Text.AlignRight
                    anchors.verticalCenter: parent.verticalCenter
                    text: np.fmt(c.len)
                    color: Theme.fgMuted
                    font { family: Theme.font; pointSize: 11 * 0.75; features: { "tnum": 1 } }
                }
            }
        }
    }
    Component { id: card; Card {} }
}
