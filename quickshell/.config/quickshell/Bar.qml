// One glass bar per screen: workspaces + media | clock | status pill. Like GNOME's top bar it
// spans the whole top edge (no gap, no rounded corners) with a hairline along its bottom.
// niri blurs it via the "bar" layer-rule.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: bar
    required property var modelData
    screen: modelData

    // Mod+W: the whole surface slides up out of view (moving the surface, not just its content,
    // so niri's blur goes with it), then unmaps; showing reverses it with a soft spring.
    property bool shown: true
    property real slide: 0          // 0 = in place, 1 = fully above the screen edge
    visible: shown || slide < 1
    onShownChanged: shown ? slideIn.restart() : slideOut.restart()
    NumberAnimation { id: slideOut; target: bar; property: "slide"; to: 1; duration: 170; easing.type: Easing.InCubic }
    NumberAnimation { id: slideIn; target: bar; property: "slide"; to: 0; duration: Theme.pillMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring }

    anchors { top: true; left: true; right: true }
    margins { top: -slide * implicitHeight }
    implicitHeight: 34
    exclusiveZone: implicitHeight
    color: "transparent"

    WlrLayershell.namespace: "bar"

    // ---- popovers: at most one of the media sheet, quick settings and the date menu
    // (notifications + calendar) is open. Click its pill to open, again to close; a click anywhere else closes it. ----
    property string popover: ""       // "media" | "quick" | "notif" | ""
    function toggle(name) {
        if (name === "media" && nowPlaying.players.length === 0) name = ""
        popover = popover === name ? "" : name
    }
    IpcHandler {
        target: "nowplaying"
        function toggle(): void { bar.toggle("media") }
    }
    IpcHandler {
        target: "quicksettings"
        function toggle(): void { bar.toggle("quick") }
    }
    IpcHandler {
        target: "notifications"
        function toggle(): void { bar.toggle("notif") }
        function clear(): void { Notifs.clear() }
        function clearApp(app: string): void { Notifs.clearApp(app) }
        function dnd(): void { Notifs.dnd = !Notifs.dnd }
    }

    // The catcher: an invisible layer over everything below the bar (it keeps out of the bar's
    // exclusive zone, so the pills stay clickable). The sheets sit above it on the overlay layer. The click that closes a popover is not passed on.
    PanelWindow {
        screen: bar.screen
        visible: bar.popover !== ""
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Normal
        exclusiveZone: 0
        color: "transparent"
        WlrLayershell.namespace: "popover-catcher"
        WlrLayershell.layer: WlrLayer.Top
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onPressed: bar.popover = ""
        }
    }
    WlrLayershell.layer: WlrLayer.Top

    Rectangle {
        anchors.fill: parent
        color: Theme.barBg
        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 1
            color: Theme.barBorder
        }
    }

    Row {
        id: left
        x: 10
        height: parent.height
        spacing: 16

        Workspaces {
            height: parent.height
            output: bar.screen ? bar.screen.name : ""
        }
        Media {
            id: media
            anchors.verticalCenter: parent.verticalCenter
            window: bar
            onPanel: bar.toggle("media")
        }
    }

    NowPlaying {
        id: nowPlaying
        screen: bar.screen
        want: bar.popover === "media"
        onDismiss: bar.popover = ""
        edge: bar.margins.left + left.x + media.x
    }

    Clock {
        anchors.centerIn: parent
        window: bar
        onOpen: bar.toggle("notif")
    }

    DateMenu {
        screen: bar.screen
        want: bar.popover === "notif"
        onDismiss: bar.popover = ""
    }

    Status {
        id: status
        onOpened: bar.toggle("quick")
        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        window: bar
    }

    QuickSettings {
        screen: bar.screen
        want: bar.popover === "quick"
        onDismiss: bar.popover = ""
    }
}
