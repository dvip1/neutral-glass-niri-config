// Power: a glass sheet under the status pill, opened by clicking the battery. Charge and
// time left (UPower), IdeaPad charge-limit state (read-only), the power profile (tuned-ppd via
// power-profiles, no root) and a "Power settings" row (~/.local/bin/power-settings).
// Open/close behaviour comes from Sheet.qml. (Replaces ~/.local/bin/powerpanel, the GTK4 version.)
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

Sheet {
    id: pp

    namespace: "powerpanel"
    full: 320
    pad: 12
    right: true
    edge: 10                          // the bar's right margin

    readonly property var dev: UPower.displayDevice
    readonly property real pct: dev ? Math.round(dev.percentage > 1 ? dev.percentage : dev.percentage * 100) : 0
    readonly property int state: dev ? dev.state : 0
    readonly property bool charging: state === UPowerDeviceState.Charging || state === UPowerDeviceState.PendingCharge
        || state === UPowerDeviceState.FullyCharged
    property string limit: ""         // "1" / "0" / "" (no IdeaPad charge limit here)
    property string summary: ""

    onWantChanged: if (want) { limitProc.running = true; idleProc.running = true }

    function duration(secs) {
        const m = Math.round(secs / 60), h = Math.floor(m / 60)
        return h ? h + " h " + String(m % 60).padStart(2, "0") + " min" : m + " min"
    }
    readonly property string status: {
        if (state === UPowerDeviceState.Charging) return dev.timeToFull > 0 ? "Charging · full in " + duration(dev.timeToFull) : "Charging"
        if (state === UPowerDeviceState.Discharging) return dev.timeToEmpty > 0 ? duration(dev.timeToEmpty) + " left" : "On battery"
        if (state === UPowerDeviceState.FullyCharged) return "Fully charged"
        if (state === UPowerDeviceState.PendingCharge) return "Plugged in · not charging"
        return "On battery"
    }
    readonly property string detail: {
        const d = []
        if (dev && Math.abs(dev.changeRate) > 0.05) d.push(Math.abs(dev.changeRate).toFixed(1) + " W")
        if (limit !== "") d.push(limit === "1" ? "charge limit on (~80 %)" : "charge limit off")
        return d.join("  ·  ")
    }

    Process {
        id: limitProc
        command: ["sh", "-c", "cat /sys/bus/platform/drivers/ideapad_acpi/*/conservation_mode 2>/dev/null | head -1"]
        stdout: StdioCollector { onStreamFinished: pp.limit = text.trim() }
    }
    // one line from power.conf (via `idle --print`) for the current power source
    Process {
        id: idleProc
        command: [Quickshell.env("HOME") + "/.local/bin/idle", "--print"]
        stdout: StdioCollector {
            onStreamFinished: {
                const cfg = {}
                let src = "battery"
                for (const line of text.split("\n")) {
                    if (line.startsWith("power source:")) src = line.split(":")[1].trim()
                    else if (line.includes(" = ")) { const [k, v] = line.split(" = "); cfg[k.trim()] = v.trim() }
                }
                const mins = key => { const v = parseFloat(cfg[src + "_" + key] || 0); return v ? v + "m" : "never" }
                pp.summary = (src === "battery" ? "On battery" : "Plugged in") + ": lock " + mins("lock")
                    + " · off " + mins("screen_off") + " · sleep " + mins("suspend")
            }
        }
    }

    // ---- battery ----
    Row {
        x: 4
        spacing: 12
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: (pp.charging ? ["󰢜", "󰂇", "󰢝", "󰢞", "󰂅"] : ["󰁺", "󰁼", "󰁾", "󰂀", "󰁹"])[Math.min(4, Math.floor(pp.pct / 20))]
            color: Theme.fgTitle
            font { family: Theme.iconFont; pixelSize: 26 }
        }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            Row {
                spacing: 8
                Text {
                    text: pp.pct + "%"
                    color: Theme.fg
                    font { family: Theme.font; pointSize: 18 * 0.75; weight: Font.Medium; features: { "tnum": 1 } }
                }
                Text {
                    anchors.baseline: parent.children[0].baseline
                    text: pp.status
                    color: Theme.fgTitle
                    font { family: Theme.font; pointSize: Theme.fontPx * 0.75 }
                }
            }
            Text {
                visible: text !== ""
                topPadding: 1
                text: pp.detail
                color: Theme.fgMuted
                font { family: Theme.font; pointSize: 12 * 0.75 }
            }
        }
    }

    Item { width: 1; height: 6 }

    // ---- power profile: one pill, the active segment's background slides between them ----
    Rectangle {
        id: seg
        readonly property var profiles: [
            { key: PowerProfile.PowerSaver, icon: "󰾆", name: "Saver" },
            { key: PowerProfile.Balanced, icon: "󰾅", name: "Balanced" },
            { key: PowerProfile.Performance, icon: "󰓅", name: "Performance" }
        ]
        readonly property int current: profiles.findIndex(p => p.key === PowerProfiles.profile)
        readonly property real cell: (width - 6) / 3

        width: pp.inner
        height: 56
        radius: Theme.radiusPill
        color: Theme.pillBg

        Rectangle {
            visible: seg.current >= 0
            x: 3 + seg.cell * Math.max(0, seg.current)
            y: 3
            width: seg.cell
            height: parent.height - 6
            radius: Theme.radiusSmall
            color: Theme.wsActiveBg
            Behavior on x { NumberAnimation { duration: Theme.pillMs; easing.type: Easing.OutCubic } }
        }

        Row {
            x: 3; y: 3
            Repeater {
                model: seg.profiles
                Rectangle {
                    id: prof
                    required property var modelData
                    required property int index
                    readonly property bool on: index === seg.current
                    readonly property bool usable: modelData.key !== PowerProfile.Performance || PowerProfiles.hasPerformanceProfile
                    width: seg.cell
                    height: seg.height - 6
                    radius: Theme.radiusSmall
                    opacity: usable ? 1 : 0.4
                    color: profMouse.containsMouse && !on ? Theme.pillHover : Theme.clear(Theme.pillHover)
                    Behavior on color { ColorAnimation { duration: profMouse.containsMouse ? Theme.hoverIn : Theme.hoverOut } }
                    scale: profMouse.pressed ? 0.95 : 1
                    Behavior on scale { NumberAnimation { duration: Theme.pillMs; easing.type: Easing.OutCubic } }

                    Column {
                        anchors.centerIn: parent
                        spacing: 2
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: prof.modelData.icon
                            color: prof.on ? Theme.fgStrong : profMouse.containsMouse ? Theme.fg : Theme.fgMuted
                            font { family: Theme.iconFont; pixelSize: 24 }
                            Behavior on color { ColorAnimation { duration: Theme.hoverOut } }
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: prof.modelData.name
                            color: prof.on ? Theme.fgStrong : profMouse.containsMouse ? Theme.fg : Theme.fgMuted
                            font { family: Theme.font; pointSize: 12 * 0.75 }
                            Behavior on color { ColorAnimation { duration: Theme.hoverOut } }
                        }
                    }
                    MouseArea {
                        id: profMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: prof.usable
                        onClicked: PowerProfiles.profile = prof.modelData.key
                    }
                }
            }
        }
    }

    Item { width: 1; height: 4 }

    // ---- settings row ----
    Rectangle {
        width: pp.inner
        height: 46
        radius: Theme.radiusSmall
        color: setMouse.containsMouse ? Theme.pillHover : Theme.clear(Theme.pillHover)
        Behavior on color { ColorAnimation { duration: setMouse.containsMouse ? Theme.hoverIn : Theme.hoverOut } }

        Text {
            id: gear
            x: 8
            anchors.verticalCenter: parent.verticalCenter
            text: "󰒓"
            color: Theme.fgTitle
            font { family: Theme.iconFont; pixelSize: 16 }
        }
        Column {
            x: gear.x + gear.width + 10
            width: parent.width - x - 30
            anchors.verticalCenter: parent.verticalCenter
            Text {
                text: "Power settings"
                color: Theme.fg
                font { family: Theme.font; pointSize: Theme.fontPx * 0.75 }
            }
            Text {
                width: parent.width
                elide: Text.ElideRight
                visible: text !== ""
                text: pp.summary
                color: Theme.fgMuted
                font { family: Theme.font; pointSize: 12 * 0.75 }
            }
        }
        Text {
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: "󰅂"
            color: Theme.fgTitle
            font { family: Theme.iconFont; pixelSize: 16 }
        }
        MouseArea {
            id: setMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: {
                Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/power-settings"])
                pp.dismiss()
            }
        }
    }
}
