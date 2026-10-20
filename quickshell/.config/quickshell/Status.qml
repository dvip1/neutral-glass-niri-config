// Right: GNOME-style status button. A few icons in ONE pill that highlights as a whole; a click
// anywhere on it opens quick settings, scrolling changes the volume. Shown: microphone (only
// while an app records), do not disturb (when on), Bluetooth (when a device is connected),
// network, volume, battery. Tray apps live in quick settings ("Background apps").
import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Networking
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower

Rectangle {
    id: root
    property var window
    signal opened()               // clicked: open / close quick settings

    implicitWidth: row.implicitWidth + 24
    implicitHeight: 26
    radius: Theme.radiusPill
    color: mouse.pressed ? Theme.pillPress : mouse.containsMouse ? Theme.pillHover : Theme.pillBg
    Behavior on color { ColorAnimation { duration: mouse.containsMouse ? Theme.hoverIn : Theme.hoverOut; easing.type: Easing.OutCubic } }
    scale: mouse.pressed ? 0.96 : 1
    Behavior on scale { NumberAnimation { duration: Theme.pillMs; easing.type: Easing.OutCubic } }
    Behavior on implicitWidth { NumberAnimation { duration: Theme.pillMs; easing.type: Easing.OutCubic } }

    readonly property color ink: mouse.containsMouse ? Theme.fgStrong : Theme.fgTitle

    // ---- state ----
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property real level: sink && sink.audio ? sink.audio.volume : 0
    readonly property bool muted: sink && sink.audio ? sink.audio.muted : false
    // apps recording from a microphone (not cava & co., which capture a speaker's monitor)
    readonly property var streams: Pipewire.nodes.values.filter(n => n.isStream)
    PwObjectTracker { objects: [root.sink].concat(root.streams) }
    readonly property bool recording: streams.some(n => n.properties["media.class"] === "Stream/Input/Audio"
        && n.properties["stream.capture.sink"] !== "true")

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool btConnected: adapter !== null && adapter.enabled && adapter.devices.values.some(d => d.connected)

    readonly property var dev: {
        const all = Networking.devices.values.filter(d => d.connected)
        return all.find(d => d.type === DeviceType.Wifi) || all[0] || null
    }
    readonly property bool wifi: dev !== null && dev.type === DeviceType.Wifi
    readonly property var network: wifi ? dev.networks.values.find(n => n.connected) || null : null
    readonly property real strength: network ? network.signalStrength : 0

    readonly property var bat: UPower.displayDevice
    readonly property real pct: bat ? Math.round(bat.percentage > 1 ? bat.percentage : bat.percentage * 100) : 0
    readonly property bool charging: bat !== null && (bat.state === UPowerDeviceState.Charging
        || bat.state === UPowerDeviceState.FullyCharged || bat.state === UPowerDeviceState.PendingCharge)
    readonly property var batState: pct <= 10 ? Theme.crit : pct <= 25 ? Theme.warn : undefined

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 14

        Icon {
            visible: root.recording
            text: "󰍬"
            color: Theme.warn
        }
        Icon {
            visible: Notifs.dnd
            text: "󰂛"
            color: root.ink
        }
        Icon {
            visible: root.btConnected
            text: "󰂱"
            color: root.ink
        }
        Icon {
            text: !root.dev ? "󰤮" : !root.wifi ? "󰈀" : ["󰤟", "󰤢", "󰤥", "󰤨"][Math.min(3, Math.floor(root.strength * 4))]
            color: root.dev ? root.ink : Theme.crit
        }
        Icon {
            text: root.muted ? "󰝟" : root.level > 1.005 ? "󰝝" : root.level < 0.34 ? "󰕿" : root.level < 0.67 ? "󰖀" : "󰕾"
            color: root.muted ? Theme.fgMuted : root.ink
        }
        Row {
            visible: root.bat !== null && root.bat.isPresent
            anchors.verticalCenter: parent.verticalCenter
            spacing: 5
            Icon {
                text: (root.charging ? ["󰢜", "󰂇", "󰢝", "󰢞", "󰂅"] : ["󰁺", "󰁼", "󰁾", "󰂀", "󰁹"])[Math.min(4, Math.floor(root.pct / 20))]
                color: root.batState !== undefined ? root.batState : root.ink
            }
            Swap {
                text: root.pct + "%"
                tnum: true
                slide: 7
                color: root.batState !== undefined ? root.batState : root.ink
            }
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.opened()
        onDoubleClicked: root.opened()
        onWheel: w => Quickshell.execDetached(["wpctl", "set-volume", "-l", "1.5", "@DEFAULT_AUDIO_SINK@", w.angleDelta.y > 0 ? "2%+" : "2%-"])
    }
}
