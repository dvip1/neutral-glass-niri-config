// A quick-settings tile, like GNOME's: icon, title and subtitle in a rounded pill, filled when
// on. With `menu`, the right end is its own button (arrow) that opens the tile's list.
import QtQuick

Rectangle {
    id: t
    property string icon: ""
    property string title: ""
    property string subtitle: ""
    property bool on: false
    property bool menu: false
    property bool open: false         // its list is showing
    signal toggled()
    signal more()

    readonly property color ink: on ? Qt.rgba(Theme.barBg.r, Theme.barBg.g, Theme.barBg.b, 1) : Theme.fg
    readonly property bool hot: main.containsMouse
    height: 56
    radius: Theme.radiusLarge
    color: on ? Theme.wsPill : hot || arrow.containsMouse ? Theme.pillHover : Theme.pillBg
    Behavior on color { ColorAnimation { duration: Theme.hoverOut } }
    scale: main.pressed || arrow.pressed ? 0.97 : 1
    Behavior on scale { NumberAnimation { duration: Theme.pillMs; easing.type: Easing.OutCubic } }

    Row {
        x: 14
        anchors.verticalCenter: parent.verticalCenter
        spacing: 12
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: t.icon
            color: t.ink
            font { family: Theme.iconFont; pixelSize: 19 }
        }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: t.width - 14 - 19 - 12 - (t.menu ? 44 : 14)
            Text {
                width: parent.width
                elide: Text.ElideRight
                text: t.title
                color: t.ink
                font { family: Theme.font; pointSize: 13 * 0.75; weight: Font.DemiBold }
            }
            Text {
                width: parent.width
                visible: text !== ""
                elide: Text.ElideRight
                text: t.subtitle
                color: t.ink
                opacity: 0.75
                font { family: Theme.font; pointSize: 11.5 * 0.75 }
            }
        }
    }

    MouseArea {
        id: main
        width: parent.width - (t.menu ? 40 : 0)
        height: parent.height
        hoverEnabled: true
        onClicked: t.toggled()
        onDoubleClicked: t.toggled()
    }

    // the menu part: a hairline, then an arrow that turns down when the list is open
    Item {
        visible: t.menu
        anchors.right: parent.right
        width: 40
        height: parent.height
        Rectangle {
            width: 1
            height: parent.height - 24
            anchors.verticalCenter: parent.verticalCenter
            color: t.ink
            opacity: 0.18
        }
        Text {
            anchors.centerIn: parent
            text: "󰅂"
            color: t.ink
            rotation: t.open ? 90 : 0
            Behavior on rotation { NumberAnimation { duration: Theme.pillMs; easing.type: Easing.OutCubic } }
            font { family: Theme.iconFont; pixelSize: 16 }
        }
        MouseArea {
            id: arrow
            anchors.fill: parent
            hoverEnabled: true
            onClicked: t.more()
        }
    }
}
