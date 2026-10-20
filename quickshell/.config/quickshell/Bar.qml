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

    anchors { top: true; left: true; right: true }
    margins { top: 8; left: 10; right: 10 }
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

    // nowplaying's bar_x() follows these sizes (8 px in, dots, 16 px gap to the media pill): keep in sync
    Row {
        x: 8
        height: parent.height
        spacing: 16

        Workspaces {
            height: parent.height
            output: bar.screen ? bar.screen.name : ""
        }
        Media {
            anchors.verticalCenter: parent.verticalCenter
            window: bar
        }
    }

    Clock {
        anchors.centerIn: parent
        window: bar
    }

    Status {
        anchors.right: parent.right
        anchors.rightMargin: 5
        anchors.verticalCenter: parent.verticalCenter
        window: bar
    }
}
