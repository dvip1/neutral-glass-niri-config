// A level slider (quick settings, media seek bar): soft track, filled part, round knob. Drag,
// click or scroll; `moved(v)` reports 0..1 live, `released(v)` once when you let go (or per
// scroll step). While dragging it shows the drag, not `value`. `mark` draws a tick (e.g. the
// 100 % point of an over-amplified volume) and values near it snap to it.
import QtQuick

Item {
    id: s
    property real value: 0        // 0..1
    property bool dim: false      // e.g. muted
    property real mark: -1        // 0..1, or -1 for none
    signal moved(real v)
    signal released(real v)

    implicitHeight: 32
    readonly property bool hot: mouse.containsMouse || mouse.pressed
    property bool dragging: false
    property real dragValue: 0
    readonly property real v: dragging ? dragValue : Math.max(0, Math.min(1, value))
    function clamp(x) { return Math.max(0, Math.min(1, x)) }
    function snap(x) { return mark >= 0 && Math.abs(x - mark) < 0.025 ? mark : x }

    Rectangle {
        id: track
        x: 9
        width: parent.width - 18
        height: 6
        radius: 3
        anchors.verticalCenter: parent.verticalCenter
        color: Theme.pillHover
        Rectangle {
            visible: s.mark >= 0
            x: parent.width * s.mark - 1
            width: 2
            height: parent.height + 8
            anchors.verticalCenter: parent.verticalCenter
            radius: 1
            color: Theme.fgMuted
            opacity: 0.6
        }
        Rectangle {
            width: Math.max(parent.height, parent.width * s.v)
            height: parent.height
            radius: parent.radius
            color: s.dim ? Theme.fgMuted : Theme.fgTitle
            Behavior on width { enabled: !s.dragging; NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
        }
    }
    Rectangle {
        property real size: s.hot ? 18 : 16
        width: size; height: size; radius: size / 2
        anchors.verticalCenter: parent.verticalCenter
        x: track.x + track.width * s.v - size / 2
        color: Theme.fgStrong
        Behavior on size { NumberAnimation { duration: Theme.hoverIn } }
        Behavior on x { enabled: !s.dragging; NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        preventStealing: true
        function at(x) { return s.snap(s.clamp((x - track.x) / track.width)) }
        onPressed: m => { s.dragging = true; s.dragValue = at(m.x); s.moved(s.dragValue) }
        onPositionChanged: m => { if (pressed) { s.dragValue = at(m.x); s.moved(s.dragValue) } }
        onReleased: { s.released(s.dragValue); s.dragging = false }
        onWheel: w => { const v = s.clamp(s.value + (w.angleDelta.y > 0 ? 0.05 : -0.05)); s.moved(v); s.released(v) }
    }
}
