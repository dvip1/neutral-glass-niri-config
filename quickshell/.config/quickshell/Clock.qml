// Centre clock: the quiet anchor. Date dimmed, time carries the weight. A dot shows unread
// notifications; clicking opens the date menu (notifications + calendar).
import QtQuick
import Quickshell

Btn {
    id: root
    signal open()
    padding: 12
    implicitHeight: 26
    onClicked: open()

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: Qt.formatDateTime(clock.date, "ddd dd MMM")
        color: Theme.fgStrong
        opacity: 0.55
        font { family: Theme.font; pointSize: Theme.fontPx * 0.75; weight: Font.DemiBold; features: { "tnum": 1 } }
    }
    Item { width: 2; height: 1 }   // + the row's spacing = 12 px between date and time
    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: Qt.formatDateTime(clock.date, "HH:mm")
        color: Theme.fgStrong
        font { family: Theme.font; pointSize: Theme.fontPx * 0.75; weight: Font.DemiBold; features: { "tnum": 1 } }
    }
    // unread notifications
    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        visible: Notifs.unread > 0
        width: 6
        height: 6
        radius: 3
        color: Theme.fgStrong
        opacity: 0.8
    }
}
