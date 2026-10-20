// A round icon button (quick settings: settings, lock, power, mute toggles beside sliders).
import QtQuick

Rectangle {
    id: b
    property string icon: ""
    property bool on: false           // highlighted (e.g. its submenu is open)
    property bool dim: false
    signal clicked()

    width: 36; height: 36; radius: 18
    color: on || mouse.pressed ? Theme.pillPress : mouse.containsMouse ? Theme.pillHover : Theme.pillBg
    Behavior on color { ColorAnimation { duration: mouse.containsMouse ? Theme.hoverIn : Theme.hoverOut } }
    scale: mouse.pressed ? 0.92 : 1
    Behavior on scale { NumberAnimation { duration: Theme.pillMs; easing.type: Easing.OutCubic } }

    Text {
        anchors.centerIn: parent
        text: b.icon
        color: b.dim ? Theme.fgMuted : Theme.fg
        font { family: Theme.iconFont; pixelSize: 17 }
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        onClicked: b.clicked()
        onDoubleClicked: b.clicked()
    }
}
