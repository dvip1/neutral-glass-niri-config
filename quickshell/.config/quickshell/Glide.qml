// One soft highlight per pill that glides between the hovered buttons (Btn { glide: ... })
// instead of each button lighting up on its own. Put it first in the pill so it draws behind.
import QtQuick

Rectangle {
    id: g
    property Item target: null    // the hovered Btn, set by the buttons themselves
    property bool pressed: false
    property Item last: null      // stays on the last button while fading out
    property bool jump: false

    // touching last.x / last.width makes this follow the button when the row reflows
    readonly property point pos: last ? (last.x, last.width, last.mapToItem(parent, 0, 0)) : Qt.point(0, 0)

    x: pos.x
    y: pos.y
    width: last ? last.width : 0
    height: last ? last.height : 0
    radius: Theme.radiusSmall
    color: pressed ? Theme.pillPress : Theme.pillHover
    opacity: target ? 1 : 0
    scale: pressed ? 0.92 : 1

    onTargetChanged: {
        if (!target) return
        // coming in from outside the pill: appear on the button, don't slide from the old one
        jump = opacity < 0.05
        last = target
        jump = false
    }

    Behavior on x { enabled: !g.jump; NumberAnimation { duration: Theme.pillMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring } }
    Behavior on width { enabled: !g.jump; NumberAnimation { duration: Theme.pillMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring } }
    Behavior on opacity { NumberAnimation { duration: g.target ? Theme.hoverIn : Theme.hoverOut; easing.type: Easing.OutCubic } }
    Behavior on scale { NumberAnimation { duration: Theme.pillMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring } }
    Behavior on color { ColorAnimation { duration: Theme.hoverIn } }
}
