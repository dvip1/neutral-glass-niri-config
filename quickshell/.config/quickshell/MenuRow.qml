// One row in a quick-settings list (networks, devices, outputs, power actions):
// icon, label, optional detail on the right, a check when it is the current one.
import QtQuick

Rectangle {
    id: r
    property string icon: ""
    property string label: ""
    property string detail: ""
    property bool current: false
    property bool dim: false
    signal clicked()

    width: parent ? parent.width : 300
    height: 38
    radius: Theme.radiusSmall
    color: mouse.pressed ? Theme.pillPress : mouse.containsMouse ? Theme.pillHover : Theme.clear(Theme.pillHover)
    Behavior on color { ColorAnimation { duration: mouse.containsMouse ? Theme.hoverIn : Theme.hoverOut } }

    Text {
        id: ic
        x: 10
        anchors.verticalCenter: parent.verticalCenter
        text: r.icon
        color: r.dim ? Theme.fgMuted : Theme.fgTitle
        font { family: Theme.iconFont; pixelSize: 16 }
    }
    Text {
        x: r.icon ? 38 : 10
        width: parent.width - x - tail.width - 16
        anchors.verticalCenter: parent.verticalCenter
        elide: Text.ElideRight
        text: r.label
        color: r.dim ? Theme.fgMuted : Theme.fg
        font { family: Theme.font; pointSize: 13 * 0.75; weight: r.current ? Font.DemiBold : Font.Normal }
    }
    Row {
        id: tail
        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8
        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: text !== ""
            text: r.detail
            color: Theme.fgMuted
            font { family: Theme.font; pointSize: 11.5 * 0.75 }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: r.current
            text: "󰄬"
            color: Theme.fg
            font { family: Theme.iconFont; pixelSize: 16 }
        }
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        onClicked: r.clicked()
    }
}
