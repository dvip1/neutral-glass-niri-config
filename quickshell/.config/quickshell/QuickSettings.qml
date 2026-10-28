// Quick settings, like GNOME's: opened by clicking the status pill. Battery and session
// buttons on top (power settings, lock, power menu), sliders for output volume (with an output
// picker), microphone and brightness, then tiles for Wi-Fi, Bluetooth, power mode, dark style
// and do not disturb; "Background apps" at the bottom (tray apps + Flatpaks without a window,
// each can be opened or closed). Tiles with an arrow open their list inside the menu; a list makes the
// glass jump to its new height once (see Sheet.qml) while its rows fade in.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Networking
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import Quickshell.Services.SystemTray
import Quickshell.Widgets

Sheet {
    id: qs
    namespace: "quicksettings"
    right: true
    edge: 10
    full: 380
    pad: 14
    keyboard: askFor !== ""           // only while the Wi-Fi password field is shown

    property string sub: ""           // the open list: wifi | bt | profile | audio | power
    property string confirm: ""       // a power action waiting for its second click
    function toggleSub(name) { sub = sub === name ? "" : name; confirm = ""; askFor = "" }
    onWantChanged: if (want) { sub = ""; confirm = ""; askFor = ""; brightProc.running = true; bgProc.running = true }

    readonly property string bin: Quickshell.env("HOME") + "/.local/bin/"
    function run(cmd) { Quickshell.execDetached(cmd) }

    // ---------------- data ----------------
    // battery
    readonly property var bat: UPower.displayDevice
    readonly property real pct: bat ? Math.round(bat.percentage > 1 ? bat.percentage : bat.percentage * 100) : 0
    readonly property bool charging: bat !== null && (bat.state === UPowerDeviceState.Charging
        || bat.state === UPowerDeviceState.PendingCharge || bat.state === UPowerDeviceState.FullyCharged)
    function duration(secs) {
        const m = Math.round(secs / 60), h = Math.floor(m / 60)
        return h ? h + " h " + String(m % 60).padStart(2, "0") + " min" : m + " min"
    }
    readonly property string batStatus: {
        if (!bat) return ""
        if (bat.state === UPowerDeviceState.Charging) return bat.timeToFull > 0 ? "full in " + duration(bat.timeToFull) : "charging"
        if (bat.state === UPowerDeviceState.Discharging) return bat.timeToEmpty > 0 ? duration(bat.timeToEmpty) + " left" : ""
        if (bat.state === UPowerDeviceState.FullyCharged) return "charged"
        if (bat.state === UPowerDeviceState.PendingCharge) return "not charging"
        return ""
    }

    // audio
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    readonly property var sinks: Pipewire.nodes.values.filter(n => n.isSink && !n.isStream && n.audio)
    PwObjectTracker { objects: [qs.sink, qs.source].concat(qs.sinks) }
    function volIcon(v, muted) { return muted ? "󰝟" : v > 1.005 ? "󰝝" : v < 0.34 ? "󰕿" : v < 0.67 ? "󰖀" : "󰕾" }

    // brightness (brightnessctl; writes are throttled while dragging)
    property real bright: 0
    property real brightWant: -1
    Process {
        id: brightProc
        command: ["brightnessctl", "-m"]
        stdout: StdioCollector { onStreamFinished: qs.bright = (parseInt(text.split(",")[3]) || 0) / 100 }
    }
    Timer {
        id: brightTimer
        interval: 40
        onTriggered: {
            if (qs.brightWant < 0) return
            qs.run(["brightnessctl", "-q", "set", Math.max(1, Math.round(qs.brightWant * 100)) + "%"])
            qs.brightWant = -1
        }
    }
    function setBright(v) { bright = v; brightWant = v; if (!brightTimer.running) brightTimer.start() }

    // Wi-Fi
    readonly property var wdev: Networking.devices.values.find(d => d.type === DeviceType.Wifi) || null
    readonly property bool wifiOn: Networking.wifiEnabled
    readonly property var nets: wdev ? wdev.networks.values.slice().sort((a, b) =>
        (b.connected - a.connected) || (b.known - a.known) || (b.signalStrength - a.signalStrength)) : []
    readonly property var current: nets.find(n => n.connected) || null
    Binding { target: qs.wdev; property: "scannerEnabled"; value: qs.want && qs.sub === "wifi"; when: qs.wdev !== null }
    function sigIcon(s) { return ["󰤟", "󰤢", "󰤥", "󰤨"][Math.min(3, Math.floor(s * 4))] }
    property string askFor: ""        // network that needs a password
    property string wifiError: ""
    function pickNet(n) {
        wifiError = ""
        if (n.connected) return
        if (n.known || n.security === WifiSecurityType.Open || n.security === WifiSecurityType.Owe) { n.connect(); askFor = "" }
        else askFor = n.name
    }
    Process {
        id: nmConnect
        onExited: code => { if (code === 0) { qs.askFor = ""; qs.wifiError = "" } else qs.wifiError = "Could not connect. Wrong password?" }
    }

    // Bluetooth
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool btOn: adapter !== null && adapter.enabled
    readonly property var btDevs: adapter ? adapter.devices.values.filter(d => d.paired || d.connected)
        .sort((a, b) => (b.connected - a.connected) || a.name.localeCompare(b.name)) : []
    readonly property var btConnected: btDevs.filter(d => d.connected)

    // power profile
    readonly property var profiles: [
        { key: PowerProfile.PowerSaver, icon: "󰾆", name: "Power saver" },
        { key: PowerProfile.Balanced, icon: "󰾅", name: "Balanced" },
        { key: PowerProfile.Performance, icon: "󰓅", name: "Performance" }
    ]
    readonly property var profile: profiles.find(p => p.key === PowerProfiles.profile) || profiles[1]

    // background apps: every tray item, plus Flatpaks that run without a window or tray item
    readonly property var trayItems: SystemTray.items.values
    property var bgTray: ({})        // tray id -> its Flatpak app id ("" if not a Flatpak)
    property var bgFlatpaks: []      // [{ app, name, icon }]
    readonly property int bgCount: trayItems.length + bgFlatpaks.length
    Process {
        id: bgProc
        command: [qs.bin + "background-apps"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { const d = JSON.parse(text); qs.bgTray = d.tray; qs.bgFlatpaks = d.flatpak } catch (e) {}
            }
        }
    }
    Timer { interval: 2000; repeat: true; running: qs.want && qs.sub === "apps"; onTriggered: bgProc.running = true }
    // close a tray app: its own Quit/Exit menu entry if it has one, else stop its process
    function quitTray(item, quitEntry) {
        if (quitEntry) quitEntry.triggered()
        else run([bin + "tray-quit", item.id])
        bgRefresh.restart()
    }
    function quitFlatpak(app) { run(["flatpak", "kill", app]); bgRefresh.restart() }
    Timer { id: bgRefresh; interval: 700; onTriggered: bgProc.running = true }

    // ---------------- layout ----------------
    component Panel: Rectangle {
        default property alias rows: list.data
        property string title: ""
        width: qs.inner
        implicitHeight: list.implicitHeight + 12
        radius: Theme.radiusLarge
        color: Theme.pillBg
        Column {
            id: list
            x: 6; y: 6
            width: parent.width - 12
            spacing: 2
            Text {
                visible: parent.parent.title !== ""
                leftPadding: 10
                topPadding: 4
                bottomPadding: 6
                text: parent.parent.title
                color: Theme.fgMuted
                font { family: Theme.font; pointSize: 12 * 0.75; weight: Font.DemiBold }
            }
        }
    }
    component AppRow: Rectangle {
        id: ar
        property string iconSource: ""
        property string label: ""
        property bool hasMenu: false
        property bool menuOpen: false
        signal activated()
        signal menu()
        signal close()
        width: parent ? parent.width : qs.inner
        height: 40
        radius: Theme.radiusSmall
        color: rowMouse.containsMouse ? Theme.pillHover : Theme.clear(Theme.pillHover)
        Behavior on color { ColorAnimation { duration: rowMouse.containsMouse ? Theme.hoverIn : Theme.hoverOut } }
        IconImage {
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            implicitSize: 20
            source: ar.iconSource
        }
        Text {
            x: 40
            width: parent.width - x - (ar.hasMenu ? 84 : 50)
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: ar.label
            color: Theme.fg
            font { family: Theme.font; pointSize: 13 * 0.75 }
        }
        MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: m => {
                if (m.button === Qt.RightButton) { if (ar.hasMenu) ar.menu() }
                else ar.activated()
            }
        }
        Row {
            anchors.right: parent.right
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            RoundBtn {
                visible: ar.hasMenu
                width: 30; height: 30; radius: 15
                icon: "󰇘"
                on: ar.menuOpen
                onClicked: ar.menu()
            }
            RoundBtn {
                width: 30; height: 30; radius: 15
                icon: "󰅖"
                onClicked: ar.close()
            }
        }
    }
    component SliderRow: Row {
        property alias icon: btn.icon
        property alias dim: btn.dim
        property alias value: slider.value
        property alias mark: slider.mark
        property bool menu: false
        property bool menuOpen: false
        signal iconClicked()
        signal moved(real v)
        signal more()
        width: qs.inner
        spacing: 6
        RoundBtn { id: btn; onClicked: parent.iconClicked() }
        Slider {
            id: slider
            width: parent.width - 36 - 6 - (parent.menu ? 36 + 6 : 0)
            anchors.verticalCenter: parent.verticalCenter
            dim: btn.dim
            onMoved: v => parent.moved(v)
        }
        RoundBtn {
            visible: parent.menu
            icon: "󰅂"
            on: parent.menuOpen
            rotation: parent.menuOpen ? 90 : 0
            Behavior on rotation { NumberAnimation { duration: Theme.pillMs; easing.type: Easing.OutCubic } }
            onClicked: parent.more()
        }
    }

    Column {
        width: qs.inner
        spacing: 12

        // ---- battery + session buttons ----
        Item {
            width: parent.width
            height: 36
            Rectangle {
                height: 36
                width: batRow.implicitWidth + 28
                radius: 18
                color: Theme.pillBg
                Row {
                    id: batRow
                    x: 14
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: (qs.charging ? ["󰢜", "󰂇", "󰢝", "󰢞", "󰂅"] : ["󰁺", "󰁼", "󰁾", "󰂀", "󰁹"])[Math.min(4, Math.floor(qs.pct / 20))]
                        color: Theme.fg
                        font { family: Theme.iconFont; pixelSize: 17 }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: qs.pct + "%" + (qs.batStatus ? "  ·  " + qs.batStatus : "")
                        color: Theme.fg
                        font { family: Theme.font; pointSize: 12.5 * 0.75; features: { "tnum": 1 } }
                    }
                }
            }
            Row {
                anchors.right: parent.right
                spacing: 8
                RoundBtn { icon: "󰒓"; onClicked: { qs.run([qs.bin + "niri-settings", "power"]); qs.dismiss() } }
                RoundBtn { icon: "󰌾"; onClicked: { qs.dismiss(); qs.run([qs.bin + "power", "lock"]) } }
                RoundBtn { icon: "󰐥"; on: qs.sub === "power"; onClicked: qs.toggleSub("power") }
            }
        }

        Panel {
            visible: qs.sub === "power"
            title: "Power"
            Repeater {
                model: [
                    { key: "suspend", icon: "󰒲", name: "Suspend", cmd: ["systemctl", "suspend"], ask: false },
                    { key: "logout", icon: "󰍃", name: "Log out", cmd: ["niri", "msg", "action", "quit", "--skip-confirmation"], ask: true },
                    { key: "reboot", icon: "󰜉", name: "Restart", cmd: ["systemctl", "reboot"], ask: true },
                    { key: "shutdown", icon: "󰐥", name: "Shut down", cmd: ["systemctl", "poweroff"], ask: true }
                ]
                MenuRow {
                    required property var modelData
                    icon: modelData.icon
                    label: qs.confirm === modelData.key ? modelData.name + "?  Click again" : modelData.name
                    current: qs.confirm === modelData.key
                    onClicked: {
                        if (modelData.ask && qs.confirm !== modelData.key) { qs.confirm = modelData.key; return }
                        qs.dismiss()
                        qs.run(modelData.cmd)
                    }
                }
            }
        }

        // ---- sliders ----
        Column {
            width: parent.width
            spacing: 6

            SliderRow {
                icon: qs.volIcon(qs.sink && qs.sink.audio ? qs.sink.audio.volume : 0, qs.sink && qs.sink.audio && qs.sink.audio.muted)
                dim: qs.sink && qs.sink.audio ? qs.sink.audio.muted : false
                // 0..150 % like the volume keys; the tick marks 100 %
                value: qs.sink && qs.sink.audio ? qs.sink.audio.volume / 1.5 : 0
                mark: 1 / 1.5
                menu: qs.sinks.length > 1
                menuOpen: qs.sub === "audio"
                onIconClicked: if (qs.sink && qs.sink.audio) qs.sink.audio.muted = !qs.sink.audio.muted
                onMoved: v => { if (qs.sink && qs.sink.audio) { qs.sink.audio.muted = false; qs.sink.audio.volume = v * 1.5 } }
                onMore: qs.toggleSub("audio")
            }
            Panel {
                visible: qs.sub === "audio"
                title: "Sound output"
                Repeater {
                    model: qs.sinks
                    MenuRow {
                        required property var modelData
                        icon: "󰓃"
                        label: modelData.description || modelData.nickname || modelData.name
                        current: qs.sink !== null && modelData.id === qs.sink.id
                        onClicked: Pipewire.preferredDefaultAudioSink = modelData
                    }
                }
            }
            SliderRow {
                visible: qs.source !== null
                icon: qs.source && qs.source.audio && qs.source.audio.muted ? "󰍭" : "󰍬"
                dim: qs.source && qs.source.audio ? qs.source.audio.muted : false
                value: qs.source && qs.source.audio ? qs.source.audio.volume : 0
                onIconClicked: if (qs.source && qs.source.audio) qs.source.audio.muted = !qs.source.audio.muted
                onMoved: v => { if (qs.source && qs.source.audio) { qs.source.audio.muted = false; qs.source.audio.volume = v } }
            }
            SliderRow {
                icon: qs.bright < 0.34 ? "󰃞" : qs.bright < 0.67 ? "󰃟" : "󰃠"
                value: qs.bright
                onIconClicked: {}
                onMoved: v => qs.setBright(v)
            }
        }

        // ---- tiles ----
        Grid {
            id: tiles
            columns: 2
            spacing: 8
            readonly property real tw: (qs.inner - spacing) / 2

            Tile {
                width: tiles.tw
                icon: !qs.wifiOn ? "󰤮" : qs.current ? qs.sigIcon(qs.current.signalStrength) : "󰤯"
                title: "Wi-Fi"
                subtitle: !qs.wifiOn ? "Off" : qs.current ? qs.current.name : "Not connected"
                on: qs.wifiOn
                menu: true
                open: qs.sub === "wifi"
                onToggled: qs.run(["nmcli", "radio", "wifi", qs.wifiOn ? "off" : "on"])
                onMore: qs.toggleSub("wifi")
            }
            Tile {
                width: tiles.tw
                icon: !qs.btOn ? "󰂲" : qs.btConnected.length ? "󰂱" : "󰂯"
                title: "Bluetooth"
                subtitle: !qs.btOn ? "Off" : qs.btConnected.length === 1 ? qs.btConnected[0].name
                    : qs.btConnected.length > 1 ? qs.btConnected.length + " devices" : "On"
                on: qs.btOn
                menu: true
                open: qs.sub === "bt"
                onToggled: if (qs.adapter) qs.adapter.enabled = !qs.adapter.enabled
                onMore: qs.toggleSub("bt")
            }
            Tile {
                width: tiles.tw
                icon: qs.profile.icon
                title: "Power mode"
                subtitle: qs.profile.name
                on: PowerProfiles.profile !== PowerProfile.Balanced
                menu: true
                open: qs.sub === "profile"
                onToggled: PowerProfiles.profile = PowerProfiles.profile === PowerProfile.Balanced ? PowerProfile.PowerSaver : PowerProfile.Balanced
                onMore: qs.toggleSub("profile")
            }
            Tile {
                width: tiles.tw
                icon: "󰔎"
                title: "Dark style"
                subtitle: Theme.mode === "dark" ? "On" : "Off"
                on: Theme.mode === "dark"
                onToggled: qs.run([qs.bin + "theme", "toggle"])
            }
            Tile {
                width: tiles.tw
                icon: Notifs.dnd ? "󰂛" : "󰂚"
                title: "Do not disturb"
                subtitle: Notifs.dnd ? "On" : "Off"
                on: Notifs.dnd
                onToggled: Notifs.dnd = !Notifs.dnd
            }
        }

        // ---- the tiles' lists ----
        Panel {
            visible: qs.sub === "wifi"
            title: qs.wifiOn ? "Wi-Fi networks" : "Wi-Fi is off"
            Repeater {
                model: qs.wifiOn ? qs.nets.slice(0, 8) : []
                MenuRow {
                    required property var modelData
                    icon: qs.sigIcon(modelData.signalStrength)
                    label: modelData.name
                    detail: modelData.security === WifiSecurityType.Open ? "" : "󰌾"
                    current: modelData.connected
                    onClicked: qs.pickNet(modelData)
                }
            }
            // password for a new secured network
            Rectangle {
                visible: qs.askFor !== ""
                width: parent.width
                height: 40
                radius: Theme.radiusSmall
                color: Theme.pillHover
                TextInput {
                    id: pwField
                    x: 12
                    width: parent.width - 24
                    anchors.verticalCenter: parent.verticalCenter
                    echoMode: TextInput.Password
                    color: Theme.fg
                    font { family: Theme.font; pointSize: 13 * 0.75 }
                    focus: visible
                    onVisibleChanged: { text = ""; if (visible) forceActiveFocus() }
                    Keys.onEscapePressed: qs.askFor = ""
                    onAccepted: {
                        qs.wifiError = "Connecting…"
                        nmConnect.command = ["nmcli", "dev", "wifi", "connect", qs.askFor, "password", text]
                        nmConnect.running = true
                    }
                    Text {
                        visible: !parent.text
                        text: "Password for " + qs.askFor + "  (Enter to connect)"
                        color: Theme.fgMuted
                        font: parent.font
                    }
                }
            }
            Text {
                visible: qs.wifiError !== ""
                leftPadding: 10
                text: qs.wifiError
                color: Theme.fgMuted
                font { family: Theme.font; pointSize: 12 * 0.75 }
            }
            MenuRow {
                icon: "󰒓"
                label: "More networks…"
                onClicked: { qs.dismiss(); qs.run([qs.bin + "wifi-menu"]) }
            }
        }
        Panel {
            visible: qs.sub === "bt"
            title: qs.btOn ? "Bluetooth devices" : "Bluetooth is off"
            Repeater {
                model: qs.btOn ? qs.btDevs : []
                MenuRow {
                    required property var modelData
                    icon: modelData.connected ? "󰂱" : "󰂯"
                    label: modelData.name
                    detail: modelData.connected && modelData.batteryAvailable ? Math.round(modelData.battery * 100) + "%" : ""
                    current: modelData.connected
                    onClicked: modelData.connected ? modelData.disconnect() : modelData.connect()
                }
            }
            MenuRow {
                icon: "󰐕"
                label: "Pair a new device…"
                onClicked: { qs.dismiss(); qs.run([qs.bin + "bt-menu"]) }
            }
        }
        Panel {
            visible: qs.sub === "profile"
            title: "Power mode"
            Repeater {
                model: qs.profiles
                MenuRow {
                    required property var modelData
                    icon: modelData.icon
                    label: modelData.name
                    dim: modelData.key === PowerProfile.Performance && !PowerProfiles.hasPerformanceProfile
                    current: modelData.key === PowerProfiles.profile
                    onClicked: if (!dim) PowerProfiles.profile = modelData.key
                }
            }
        }

        // ---- background apps ----
        MenuRow {
            visible: qs.bgCount > 0
            width: qs.inner
            icon: "󰀻"
            label: qs.bgCount === 1 ? "1 background app" : qs.bgCount + " background apps"
            detail: qs.sub === "apps" ? "󰅀" : "󰅂"
            current: false
            onClicked: qs.toggleSub("apps")
        }
        Panel {
            visible: qs.sub === "apps"
            title: "Background apps"
            Repeater {
                model: qs.trayItems
                Column {
                    id: trayRow
                    required property var modelData
                    readonly property var item: modelData
                    property bool expanded: false
                    width: parent.width
                    QsMenuOpener { id: opener; menu: trayRow.item.hasMenu ? trayRow.item.menu : null }
                    readonly property var entries: opener.children ? opener.children.values.filter(e => !e.isSeparator && e.text) : []
                    readonly property var quitEntry: entries.find(e => /^(quit|exit)\b/i.test(e.text.replace(/&/g, ""))) || null

                    AppRow {
                        iconSource: trayRow.item.icon
                        label: trayRow.item.tooltipTitle || trayRow.item.title || trayRow.item.id
                        hasMenu: trayRow.entries.length > 0
                        menuOpen: trayRow.expanded
                        onActivated: { trayRow.item.activate(); qs.dismiss() }
                        onMenu: trayRow.expanded = !trayRow.expanded
                        onClose: qs.quitTray(trayRow.item, trayRow.quitEntry)
                    }
                    // the app's own menu, drawn here (top level only)
                    Column {
                        visible: trayRow.expanded
                        width: parent.width
                        leftPadding: 30
                        Repeater {
                            model: trayRow.expanded ? trayRow.entries : []
                            MenuRow {
                                required property var modelData
                                width: trayRow.width - 30
                                label: modelData.text.replace(/&/g, "")
                                dim: !modelData.enabled
                                current: modelData.checkState === Qt.Checked
                                detail: modelData.hasChildren ? "󰅂" : ""
                                onClicked: if (modelData.enabled && !modelData.hasChildren) { modelData.triggered(); qs.dismiss() }
                            }
                        }
                    }
                }
            }
            Repeater {
                model: qs.bgFlatpaks
                AppRow {
                    required property var modelData
                    iconSource: Quickshell.iconPath(modelData.icon, true)
                    label: modelData.name
                    onActivated: { qs.run(["flatpak", "run", modelData.app]); qs.dismiss() }
                    onClose: qs.quitFlatpak(modelData.app)
                }
            }
        }
    }
}
