// A glass sheet under the bar that opens when its pill is clicked (NowPlaying, PowerPanel).
// The surface is created at its final size and never resized while animating (a layer surface
// resize costs a compositor round trip per frame: it stutters and runs late). Instead the glass
// tint comes up quickly over niri's blur and the contents fade in with a small drop.
// It is a popover: `want` is driven by the bar (click the pill to open, again to close; a
// click anywhere else closes it via the bar's catcher). dismiss() asks the bar to close it.
import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: sheet
    property bool want: false
    property real open: 0             // 0 = hidden, 1 = fully shown
    property int full: 360            // width
    property bool right: false        // hang from the right screen edge instead of the left
    property bool center: false       // or centred under the bar (edge is ignored)
    property bool keyboard: false     // take the keyboard (only while a text field is shown)
    property real edge: 0             // distance from that edge
    property int pad: 6
    property string namespace: "sheet"
    signal dismiss()
    default property alias content: col.data
    readonly property real inner: full - 2 * pad

    anchors { top: true; left: !center && !right; right: !center && right }
    margins { top: 6; left: center || right ? 0 : edge; right: !center && right ? edge : 0 }
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 0
    implicitWidth: full
    implicitHeight: col.implicitHeight + 2 * pad
    color: "transparent"
    visible: want || shut.running
    WlrLayershell.namespace: namespace
    WlrLayershell.layer: WlrLayer.Overlay   // above the bar's click catcher (Top)
    // no keyboard focus: while a sheet held it, the first click on the bar was eaten handing
    // focus back, so clicking the pill again did not close it
    WlrLayershell.keyboardFocus: keyboard ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    onWantChanged: {
        if (want) { shut.stop(); open = 0; grow.restart() }
        else { grow.stop(); shut.restart() }
    }
    NumberAnimation { id: grow; target: sheet; property: "open"; to: 1; duration: 150; easing.type: Easing.OutCubic }
    NumberAnimation { id: shut; target: sheet; property: "open"; to: 0; duration: 100; easing.type: Easing.InCubic }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusLarge
        color: Theme.barBg
        border.color: Theme.barBorder
        border.width: 1
        // the blur behind is there from the first frame, so the tint starts part-way up
        opacity: 0.4 + 0.6 * sheet.open
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
