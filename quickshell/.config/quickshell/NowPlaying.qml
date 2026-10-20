// Now playing: a glass sheet under the bar's media pill, one card per player, built from the
// same pieces as quick settings and the date menu (round buttons, the shared Slider for
// seeking). Clicking a card hands the bar to that player (it becomes playerctld's active
// player; that card is lifted). Open/close behaviour comes from Sheet.qml.
// (Replaces ~/.local/bin/nowplaying, the GTK4 version.)
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Widgets

Sheet {
    id: np
    property var order: []            // playerctld's order (instance names); first = the bar's player

    namespace: "nowplaying"
    full: 380
    pad: 12

    readonly property string ctld: "org.mpris.MediaPlayer2.playerctld"
    readonly property var players: Mpris.players.values
        .filter(p => p.dbusName !== ctld)
        .sort((a, b) => rank(a) - rank(b))
    function inst(p) { return p.dbusName.replace("org.mpris.MediaPlayer2.", "") }
    function rank(p) { const i = order.indexOf(inst(p)); return i < 0 ? order.length : i }

    onWantChanged: if (want) orderProc.running = true
    onPlayersChanged: if (want && players.length === 0) dismiss()

    // playerctld's order, and making a player the active one (rotate the list the shorter way)
    Process {
        id: orderProc
        command: ["busctl", "--user", "--json=short", "get-property", np.ctld, "/org/mpris/MediaPlayer2",
                  "com.github.altdesktop.playerctld", "PlayerNames"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const o = JSON.parse(text).data.map(n => n.replace("org.mpris.MediaPlayer2.", ""))
                    // only on a real change: a new array rebuilds every card (and eats clicks)
                    if (JSON.stringify(o) !== JSON.stringify(np.order)) np.order = o
                } catch (e) {}
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

    Text {
        x: 4
        topPadding: 2
        bottomPadding: 4
        text: "Now playing"
        color: Theme.fg
        font { family: Theme.font; pointSize: Theme.fontPx * 0.75; weight: Font.DemiBold }
    }

    Repeater {
        model: np.players
        delegate: Card {}
    }

    component Card: Rectangle {
        id: c
        required property var modelData
        readonly property var p: modelData
        readonly property bool active: np.rank(p) === 0
        readonly property real len: p.lengthSupported ? p.length : 0
        readonly property color ink: Qt.rgba(Theme.barBg.r, Theme.barBg.g, Theme.barBg.b, 1)

        width: np.inner
        implicitHeight: body.implicitHeight + 28
        radius: Theme.radiusLarge
        color: active || hover.hovered ? Theme.pillHover : Theme.pillBg
        Behavior on color { ColorAnimation { duration: hover.hovered ? Theme.hoverIn : Theme.hoverOut } }

        HoverHandler { id: hover }
        MouseArea {
            anchors.fill: parent
            onClicked: np.pick(c.p)
        }

        Column {
            id: body
            x: 14; y: 14
            width: parent.width - 28
            spacing: 12

            Row {
                width: parent.width
                spacing: 14

                // cover, or the player's icon on a tile
                ClippingRectangle {
                    width: 64; height: 64
                    radius: Theme.radiusSmall + 3
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
                    width: parent.width - 64 - 14
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: c.p.trackTitle || c.p.identity
                        color: Theme.fgStrong
                        font { family: Theme.font; pointSize: Theme.fontPx * 0.75; weight: Font.DemiBold }
                    }
                    Text {
                        width: parent.width
                        visible: text !== ""
                        elide: Text.ElideRight
                        text: c.p.trackArtist || ""
                        color: Theme.fgTitle
                        font { family: Theme.font; pointSize: 13 * 0.75 }
                    }
                    Row {
                        topPadding: 4
                        spacing: 6
                        Rectangle {   // the player the bar follows
                            visible: c.active
                            width: 6; height: 6; radius: 3
                            anchors.verticalCenter: parent.verticalCenter
                            color: Theme.fgTitle
                        }
                        Text {
                            text: (np.icons[np.appName(c.p)] || "󰝚") + "  " + c.p.identity
                            color: Theme.fgMuted
                            font { family: Theme.font; pointSize: 11.5 * 0.75 }
                        }
                    }
                }
            }

            // seek bar (the shared slider) with the times under it
            Column {
                visible: c.len > 0
                width: parent.width
                Slider {
                    id: seek
                    width: parent.width
                    implicitHeight: 22
                    enabled: c.p.canSeek
                    value: c.len > 0 ? c.p.position / c.len : 0
                    onReleased: v => c.p.position = v * c.len
                }
                Item {
                    width: parent.width
                    height: 14
                    Text {
                        x: 9
                        text: np.fmt(seek.dragging ? seek.dragValue * c.len : c.p.position)
                        color: Theme.fgMuted
                        font { family: Theme.font; pointSize: 11 * 0.75; features: { "tnum": 1 } }
                    }
                    Text {
                        anchors.right: parent.right
                        anchors.rightMargin: 9
                        text: np.fmt(c.len)
                        color: Theme.fgMuted
                        font { family: Theme.font; pointSize: 11 * 0.75; features: { "tnum": 1 } }
                    }
                }
            }

            // controls: round buttons, play / pause filled like an "on" tile
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 18
                RoundBtn {
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "󰒮"
                    enabled: c.p.canGoPrevious
                    opacity: enabled ? 1 : 0.4
                    onClicked: c.p.previous()
                }
                Rectangle {
                    id: play
                    width: 46; height: 46; radius: 23
                    color: Theme.wsPill
                    opacity: playMouse.containsMouse ? 0.88 : 1
                    scale: playMouse.pressed ? 0.92 : 1
                    Behavior on scale { NumberAnimation { duration: Theme.pillMs; easing.type: Easing.OutCubic } }
                    Text {
                        anchors.centerIn: parent
                        text: c.p.isPlaying ? "󰏤" : "󰐊"
                        color: c.ink
                        font { family: Theme.iconFont; pixelSize: 22 }
                    }
                    MouseArea {
                        id: playMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: c.p.canTogglePlaying
                        onClicked: c.p.togglePlaying()
                        onDoubleClicked: c.p.togglePlaying()
                    }
                }
                RoundBtn {
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "󰒭"
                    enabled: c.p.canGoNext
                    opacity: enabled ? 1 : 0.4
                    onClicked: c.p.next()
                }
            }
        }
    }
}
