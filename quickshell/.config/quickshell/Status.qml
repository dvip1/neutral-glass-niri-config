// Right: notifications, volume, bluetooth, network, battery and the tray share ONE pill,
// with one highlight gliding between whatever is hovered. Clicks open the same scripts the
// waybar modules did.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Networking
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import Quickshell.Services.SystemTray
import Quickshell.Widgets

Rectangle {
    id: root
    property var window
    readonly property string bin: Quickshell.env("HOME") + "/.local/bin/"

    implicitWidth: row.implicitWidth + 8
    implicitHeight: 26
    radius: Theme.radiusPill
    color: Theme.pillBg

    function sh(cmd) { Quickshell.execDetached(["sh", "-c", cmd]) }
    // icon colour: dim at rest, bright on hover; state colours (muted, warning) win
    function tone(btn, state) { return state !== undefined ? state : btn.hovered ? Theme.fgStrong : Theme.fgTitle }

    Glide { id: hoverGlide }

    Row {
        id: row
        x: 4
        anchors.verticalCenter: parent.verticalCenter

        // ---- notifications (swaync) ----
        Btn {
            id: notif
            window: root.window
            glide: hoverGlide
            property string alt: "none"
            onClicked: m => root.sh(m.button === Qt.RightButton ? "swaync-client -d -sw" : "swaync-client -t -sw")
            Icon {
                text: notif.alt.startsWith("dnd") ? "󰂛" : "󰂚"
                color: root.tone(notif)
                Rectangle {   // the unread dot pops in (waybar drew it as a superscript)
                    width: 5; height: 5; radius: 2.5
                    x: parent.width - 2; y: 2
                    color: parent.color
                    scale: notif.alt.endsWith("notification") ? 1 : 0
                    Behavior on scale { NumberAnimation { duration: Theme.pillMs; easing.type: Easing.OutBack; easing.overshoot: 3 } }
                }
            }
            Process {
                running: true
                command: ["swaync-client", "-swb"]
                stdout: SplitParser {
                    onRead: line => { try { notif.alt = JSON.parse(line).alt } catch (e) {} }
                }
            }
        }

        // ---- volume (PipeWire); up to 150 % like the volume keys ----
        Btn {
            id: vol
            window: root.window
            glide: hoverGlide
            readonly property var sink: Pipewire.defaultAudioSink
            readonly property real level: sink && sink.audio ? sink.audio.volume : 0
            readonly property bool muted: sink && sink.audio ? sink.audio.muted : false
            PwObjectTracker { objects: [vol.sink] }
            tip: sink ? "Volume " + Math.round(level * 100) + "%  ·  " + (sink.description || sink.name) : ""
            onClicked: root.sh("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle")
            onWheel: w => root.sh("wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ " + (w.angleDelta.y > 0 ? "1%+" : "1%-"))
            Icon {
                text: vol.muted ? "󰝟" : vol.level > 1.005 ? "󰝝" : vol.level < 0.34 ? "󰕿" : vol.level < 0.67 ? "󰖀" : "󰕾"
                color: root.tone(vol, vol.muted ? Theme.fgMuted : undefined)
            }
        }

        // ---- bluetooth ----
        Btn {
            id: bt
            window: root.window
            glide: hoverGlide
            readonly property var adapter: Bluetooth.defaultAdapter
            readonly property bool on: adapter !== null && adapter.enabled
            readonly property var connected: adapter ? adapter.devices.values.filter(d => d.connected) : []
            tip: !adapter ? "" : !on ? adapter.name + "  (off)"
                : connected.length === 0 ? adapter.name + "  (on)"
                : adapter.name + "\n" + connected.map(d => d.name + (d.batteryAvailable ? "  " + Math.round(d.battery * 100) + "%" : "")).join("\n")
            onClicked: Quickshell.execDetached([root.bin + "bt-menu"])
            Icon {
                text: !bt.on ? "󰂲" : bt.connected.length > 0 ? "󰂱" : "󰂯"
                color: root.tone(bt, bt.on ? undefined : Theme.fgMuted)
            }
        }

        // ---- network ----
        Btn {
            id: net
            window: root.window
            glide: hoverGlide
            readonly property var dev: {
                const all = Networking.devices.values.filter(d => d.connected)
                return all.find(d => d.type === DeviceType.Wifi) || all[0] || null
            }
            readonly property bool wifi: dev !== null && dev.type === DeviceType.Wifi
            readonly property var network: wifi ? dev.networks.values.find(n => n.connected) || null : null
            readonly property real strength: network ? network.signalStrength : 0
            property string ip: ""
            tip: !dev ? "Disconnected"
                : dev.name + (ip ? "  " + ip : "") + (network ? "\n" + network.name + "  " + Math.round(strength * 100) + "%" : "")
            onHoveredChanged: if (hovered && dev) { ipProc.command = ["nmcli", "-g", "IP4.ADDRESS", "device", "show", dev.name]; ipProc.running = true }
            onClicked: Quickshell.execDetached([root.bin + "wifi-menu"])
            Icon {
                text: !net.dev ? "󰤮" : !net.wifi ? "󰈀"
                    : ["󰤟", "󰤢", "󰤥", "󰤨"][Math.min(3, Math.floor(net.strength * 4))]
                color: root.tone(net, net.dev ? undefined : Theme.crit)
            }
            Process {
                id: ipProc
                stdout: StdioCollector { onStreamFinished: net.ip = text.split("\n")[0].trim() }
            }
        }

        // ---- battery (click: powerpanel); the percentage rolls when it changes ----
        Btn {
            id: bat
            window: root.window
            glide: hoverGlide
            readonly property var dev: UPower.displayDevice
            readonly property real pct: dev ? Math.round(dev.percentage > 1 ? dev.percentage : dev.percentage * 100) : 0
            readonly property bool charging: dev !== null && (dev.state === UPowerDeviceState.Charging
                || dev.state === UPowerDeviceState.FullyCharged || dev.state === UPowerDeviceState.PendingCharge)
            readonly property var state: pct <= 10 ? Theme.crit : pct <= 25 ? Theme.warn : undefined
            visible: dev !== null && dev.isPresent
            padding: 9
            onClicked: Quickshell.execDetached([root.bin + "powerpanel"])
            Icon {
                text: (bat.charging ? ["󰢜", "󰂇", "󰢝", "󰢞", "󰂅"] : ["󰁺", "󰁼", "󰁾", "󰂀", "󰁹"])[Math.min(4, Math.floor(bat.pct / 20))]
                color: root.tone(bat, bat.state)
            }
            Swap {
                text: bat.pct + "%"
                tnum: true
                slide: 7
                color: root.tone(bat, bat.state)
            }
        }

        // ---- tray (passive items hidden, like waybar) ----
        Row {
            anchors.verticalCenter: parent.verticalCenter
            leftPadding: 2
            rightPadding: 4
            Repeater {
                model: SystemTray.items
                Btn {
                    id: trayBtn
                    required property var modelData
                    visible: modelData.status !== Status.Passive
                    window: root.window
                    glide: hoverGlide
                    padding: 4
                    onClicked: m => {
                        const item = modelData
                        if (m.button === Qt.MiddleButton) item.secondaryActivate()
                        else if (m.button === Qt.RightButton || item.onlyMenu) {
                            if (item.hasMenu) {
                                const p = trayBtn.mapToItem(null, 0, trayBtn.height + 10)
                                item.display(root.window, p.x, p.y)
                            }
                        } else item.activate()
                    }
                    onWheel: w => modelData.scroll(w.angleDelta.y / 120, false)
                    IconImage {
                        implicitSize: 16
                        anchors.verticalCenter: parent.verticalCenter
                        source: trayBtn.modelData.icon
                    }
                }
            }
        }
    }
}
