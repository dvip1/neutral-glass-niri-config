// A glass sheet under the bar that opens when its pill is clicked (NowPlaying, PowerPanel).
// The surface is created at its final size and never resized while animating (a layer surface
// resize costs a compositor round trip per frame: it stutters and runs late). Instead the glass
// tint comes up quickly over niri's blur and the contents fade in with a small drop.
// Closes on Esc, when the pointer leaves it, if the pointer never comes in, or when `want`
// is toggled off (the pill clicked again).
import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: sheet
    property bool want: false
    property real open: 0             // 0 = hidden, 1 = fully shown
    property int full: 360            // width
    property bool right: false        // hang from the right screen edge instead of the left
    property real edge: 0             // distance from that edge
    property int pad: 6
    property string namespace: "sheet"
    property bool entered: false
    default property alias content: col.data
    readonly property real inner: full - 2 * pad

    anchors { top: true; left: !right; right: right }
    margins { top: 6; left: right ? 0 : edge; right: right ? edge : 0 }
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 0
    implicitWidth: full
    implicitHeight: col.implicitHeight + 2 * pad
    color: "transparent"
    visible: want || shut.running
    WlrLayershell.namespace: namespace
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: want ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    onWantChanged: {
        if (want) { entered = false; shut.stop(); open = 0; grow.restart(); idle.restart() }
        else { grow.stop(); leave.stop(); shut.restart() }
    }
    NumberAnimation { id: grow; target: sheet; property: "open"; to: 1; duration: 150; easing.type: Easing.OutCubic }
    NumberAnimation { id: shut; target: sheet; property: "open"; to: 0; duration: 100; easing.type: Easing.InCubic }

    Timer { id: leave; interval: 300; onTriggered: sheet.want = false }
    Timer { id: idle; interval: 4000; onTriggered: if (!sheet.entered) sheet.want = false }
    HoverHandler {
        onHoveredChanged: {
            if (hovered) { sheet.entered = true; leave.stop() }
            else if (sheet.entered && sheet.want) leave.restart()
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusLarge
        color: Theme.barBg
        border.color: Theme.barBorder
        border.width: 1
        // the blur behind is there from the first frame, so the tint starts part-way up
        opacity: 0.4 + 0.6 * sheet.open
        focus: true
        Keys.onEscapePressed: sheet.want = false
    }

    Column {
        id: col
        x: sheet.pad
        y: sheet.pad
        width: sheet.inner
        spacing: 4
        opacity: sheet.open
        transform: Translate { y: (1 - sheet.open) * -4 }
    }
}
