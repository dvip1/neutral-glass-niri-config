// A clickable item on the bar: soft background that lights up quickly on hover and settles
// slowly, a small press-in, and an optional tooltip. Put the content (Icon / Text) inside.
// With `glide` set, the pill's shared Glide highlight is used instead of its own background.
import QtQuick

Rectangle {
    id: root
    property int padding: 8
    property string tip: ""
    property bool tipMono: false
    property var window
    property Glide glide: null
    readonly property alias hovered: mouse.containsMouse
    readonly property alias pressed: mouse.pressed
    default property alias content: row.data
    signal clicked(var mouse)
    signal wheel(var wheel)

    implicitWidth: row.implicitWidth + 2 * padding
    implicitHeight: 20
    radius: Theme.radiusSmall

    color: glide ? "transparent" : pressed ? Theme.pillPress : hovered ? Theme.pillHover : Theme.clear(Theme.pillHover)
    Behavior on color { ColorAnimation { duration: root.hovered ? Theme.hoverIn : Theme.hoverOut; easing.type: Easing.OutCubic } }

    scale: pressed ? 0.92 : 1
    Behavior on scale { NumberAnimation { duration: Theme.pillMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring } }

    onHoveredChanged: {
        if (!glide) return
        if (hovered) glide.target = root
        else if (glide.target === root) glide.target = null
    }
    onPressedChanged: if (glide && glide.target === root) glide.pressed = pressed

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 5
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: m => root.clicked(m)
        onDoubleClicked: m => root.clicked(m)   // a quick second click (e.g. open, then close) counts too
        onWheel: w => root.wheel(w)
    }

    Tip {
        target: root
        window: root.window
        text: root.tip
        mono: root.tipMono
        show: root.hovered && !root.pressed
    }
}
