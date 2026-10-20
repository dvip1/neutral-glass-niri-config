// One glass bar per screen: workspaces + media | clock | status pill.
// Geometry follows the old waybar (36 px tall, 8 px from the top, 10 px from the sides) so
// nowplaying / powerpanel popups still line up. niri blurs it via the "bar" layer-rule.
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
    margins { top: 8 - slide * 48; left: 10; right: 10 }
    implicitHeight: 36
    exclusiveZone: 36 + 4
    color: "transparent"

    WlrLayershell.namespace: "bar"

    // ---- popovers: at most one of the media sheet, the power sheet and swaync's notification
    // centre is open. Click its pill to open, again to close; a click anywhere else closes it. ----
    property string popover: ""       // "media" | "power" | "notif" | ""
    function toggle(name) {
        if (name === "media" && nowPlaying.players.length === 0) name = ""
        popover = popover === name ? "" : name
    }
    onPopoverChanged: {
        if (popover === "notif") Quickshell.execDetached(["swaync-client", "-op", "-sw"])
        else if (status.ccOpen) Quickshell.execDetached(["swaync-client", "-cp", "-sw"])
    }
    IpcHandler {
        target: "nowplaying"
        function toggle(): void { bar.toggle("media") }
    }
    IpcHandler {
        target: "powerpanel"
        function toggle(): void { bar.toggle("power") }
    }

    // The catcher: an invisible layer over everything below the bar (it keeps out of the bar's
    // exclusive zone, so the pills stay clickable). Sheets and swaync's centre sit above it
    // on the overlay layer. The click that closes a popover is not passed on.
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
        border.color: Theme.barBorder
        border.width: 1
        radius: Theme.radius
    }

    Row {
        id: left
        x: 8
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
    }

    Status {
        id: status
        onBatteryClicked: bar.toggle("power")
        onBellClicked: bar.toggle("notif")
        onCcOpenChanged: {
            if (ccOpen) bar.popover = "notif"
            else if (bar.popover === "notif") bar.popover = ""
        }
        anchors.right: parent.right
        anchors.rightMargin: 5
        anchors.verticalCenter: parent.verticalCenter
        window: bar
    }

    PowerPanel {
        id: power
        screen: bar.screen
        want: bar.popover === "power"
        onDismiss: bar.popover = ""
    }
}
