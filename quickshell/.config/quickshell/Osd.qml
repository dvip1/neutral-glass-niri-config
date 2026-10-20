// Volume / microphone / brightness OSD (replaces swayosd): a glass pill with icon, level bar and percentage
// that fades in quickly and fades away. Its surface keeps one size (resizing a layer surface per
// frame stutters), niri blurs it via the "osd" layer-rule. Volume pops up on its own whenever the default
// output's volume or mute changes (keys, bar scroll, apps); brightness via
//   qs ipc call osd brightness <percent>     (~/.local/bin/brightness does this)
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Wayland

PanelWindow {
    id: osd

    // what is shown
    property string icon: ""
    property real level: 0        // 0..max
    property real max: 1          // volume goes to 1.5 (150 %), brightness to 1
    property bool dim: false      // muted

    property real open: 0         // 0 = hidden, 1 = fully shown
    readonly property int full: 280
    readonly property int tall: 46

    anchors.bottom: true
    margins.bottom: 110
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: full
    implicitHeight: tall
    color: "transparent"
    // own flag: tying this to the timers unmapped the window on every key press (restart() stops first)
    property bool shown: false
    visible: shown
    WlrLayershell.namespace: "osd"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region {}   // never takes the pointer

    function pop(icon, level, max, dim) {
        osd.icon = icon; osd.level = level; osd.max = max; osd.dim = dim
        shrink.stop()
        if (!shown) { open = 0; shown = true }
        if (open < 1 && !grow.running) grow.restart()
        hold.restart()
    }

    NumberAnimation { id: grow; target: osd; property: "open"; to: 1; duration: 120; easing.type: Easing.OutCubic }
    NumberAnimation { id: shrink; target: osd; property: "open"; to: 0; duration: 110; easing.type: Easing.InCubic; onFinished: osd.shown = false }
    Timer { id: hold; interval: 1100; onTriggered: shrink.restart() }

    // ---- volume: follow the default output ----
    readonly property var sink: Pipewire.defaultAudioSink
    PwObjectTracker { objects: [osd.sink] }
    property bool armed: false    // ignore the values PipeWire reports at startup
    Timer { running: true; interval: 1500; onTriggered: osd.armed = true }
    function volumeChanged() {
        if (!armed || !sink || !sink.audio) return
        const v = sink.audio.volume, m = sink.audio.muted
        pop(m ? "󰝟" : v > 1.005 ? "󰝝" : v < 0.34 ? "󰕿" : v < 0.67 ? "󰖀" : "󰕾", v, 1.5, m)
    }
    Connections {
        target: osd.sink ? osd.sink.audio : null
        function onVolumesChanged() { osd.volumeChanged() }
        function onMutedChanged() { osd.volumeChanged() }
    }

    // ---- microphone: the default input (Fn mic key, bar click / scroll) ----
    readonly property var source: Pipewire.defaultAudioSource
    PwObjectTracker { objects: [osd.source] }
    function micChanged() {
        if (!armed || !source || !source.audio) return
        pop(source.audio.muted ? "󰍭" : "󰍬", source.audio.volume, 1, source.audio.muted)
    }
    Connections {
        target: osd.source ? osd.source.audio : null
        function onVolumesChanged() { osd.micChanged() }
        function onMutedChanged() { osd.micChanged() }
    }

    IpcHandler {
        target: "osd"
        function brightness(percent: int): void {
            osd.pop(percent < 34 ? "󰃞" : percent < 67 ? "󰃟" : "󰃠", percent / 100, 1, false)
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusLarge
        color: Theme.osdBg
        border.color: Theme.osdBorder
        border.width: 1
        opacity: 0.4 + 0.6 * osd.open   // the blur is there from the first frame

        Row {
            anchors.verticalCenter: parent.verticalCenter
            x: 18
            spacing: 14
            opacity: osd.open
            transform: Translate { y: (1 - osd.open) * 3 }

            Icon {
                text: osd.icon
                pointSize: Theme.iconPx * 0.75 * 1.25
                color: Theme.osdFg
                opacity: osd.dim ? 0.5 : 1
            }

            // level bar; the 100 % point is marked when the scale goes past it
            Item {
                anchors.verticalCenter: parent.verticalCenter
                width: osd.full - 18 * 2 - 14 * 2 - 22 - 40
                height: 6
                Rectangle {
                    anchors.fill: parent
                    radius: 3
                    color: Theme.osdTrough
                }
                Rectangle {
                    height: parent.height
                    radius: 3
                    width: Math.max(height, parent.width * Math.min(1, osd.level / osd.max))
                    color: Theme.osdBar
                    opacity: osd.dim ? 0.4 : 1
                    Behavior on width { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                }
                Rectangle {
                    visible: osd.max > 1
                    x: parent.width / osd.max - 1
                    width: 2; height: parent.height + 6
                    anchors.verticalCenter: parent.verticalCenter
                    radius: 1
                    color: Theme.osdFg
                    opacity: 0.35
                }
            }

            Swap {
                width: 40
                text: Math.round(osd.level * 100) + "%"
                color: Theme.osdFg
                tnum: true
                slide: 6
                duration: 120
                opacity: osd.dim ? 0.5 : 1
            }
        }
    }
}
