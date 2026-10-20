// A small on/off switch (display only; the row around it handles the click).
import QtQuick

Rectangle {
    property bool on: false
    width: 38
    height: 22
    radius: 11
    color: on ? Theme.wsPill : Theme.pillHover
    Behavior on color { ColorAnimation { duration: Theme.pillMs } }

    Rectangle {
        width: 16; height: 16; radius: 8
        anchors.verticalCenter: parent.verticalCenter
        x: parent.on ? parent.width - width - 3 : 3
        color: parent.on ? Qt.rgba(Theme.barBg.r, Theme.barBg.g, Theme.barBg.b, 1) : Theme.fgTitle
        Behavior on x { NumberAnimation { duration: Theme.pillMs; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: Theme.pillMs } }
    }
}
