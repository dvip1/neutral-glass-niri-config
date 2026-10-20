// One glass bar per screen: workspaces + media | clock | status pill.
// Geometry follows the old waybar (36 px tall, 8 px from the top, 10 px from the sides) so
// nowplaying / powerpanel popups still line up. niri blurs it via the "bar" layer-rule.
import QtQuick
import Quickshell
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
            onPanel: nowPlaying.want = !nowPlaying.want
        }
    }

    NowPlaying {
        id: nowPlaying
        screen: bar.screen
        edge: bar.margins.left + left.x + media.x
    }

    Clock {
        anchors.centerIn: parent
        window: bar
    }

    Status {
        id: status
        onBatteryClicked: power.want = !power.want
        anchors.right: parent.right
        anchors.rightMargin: 5
        anchors.verticalCenter: parent.verticalCenter
        window: bar
    }

    PowerPanel {
        id: power
        screen: bar.screen
    }
}
