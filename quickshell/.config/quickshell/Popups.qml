// Notification popups, top centre under the bar, newest on top. Each is its own blurred glass
// window (niri layer-rule "notification"): it fades in, waits (paused while hovered), fades
// out. When one goes, the ones below jump up: moving a layer surface can't be animated smoothly
// (see Sheet.qml). Critical ones stay until clicked or closed.
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications

Scope {
    id: root
    property var screen
    readonly property int gap: 8

    Variants {
        id: wins
        model: Notifs.popups.map(e => e.key)    // plain keys: windows stay put when the list changes

        PanelWindow {
            id: w
            required property int modelData
            readonly property int index: Notifs.popups.findIndex(x => x.key === modelData)
            readonly property var entry: index >= 0 ? Notifs.popups[index] : ({ key: modelData })
            readonly property bool critical: entry.urgency === NotificationUrgency.Critical
            // stack under the newer ones
            readonly property real offset: {
                let y = 0
                for (const o of wins.instances) if (o && o.index >= 0 && o.index < index) y += o.implicitHeight + root.gap
                return y
            }
            property real shown: 0

            screen: root.screen
            anchors.top: true
            margins.top: 6 + offset
            exclusionMode: ExclusionMode.Normal
            exclusiveZone: 0
            implicitWidth: 400
            implicitHeight: card.implicitHeight
            color: "transparent"
            WlrLayershell.namespace: "notification"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            NumberAnimation on shown { from: 0; to: 1; duration: 160; easing.type: Easing.OutCubic }
            NumberAnimation { id: fade; target: w; property: "shown"; to: 0; duration: 140; easing.type: Easing.InCubic; onFinished: Notifs.unpop(w.entry) }
            Timer {
                interval: w.entry.urgency === NotificationUrgency.Low ? 4000 : 6500
                running: !w.critical && !card.hot && !fade.running
                onTriggered: fade.start()
            }

            Rectangle {
                anchors.fill: parent
                radius: Theme.radiusLarge
                color: Theme.barBg
                border.color: Theme.barBorder
                border.width: 1
                opacity: 0.4 + 0.6 * w.shown
            }
            NotifCard {
                id: card
                entry: w.entry
                popup: true
                width: parent.width
                opacity: w.shown
                transform: Translate { y: (1 - w.shown) * -4 }
            }
        }
    }
}
