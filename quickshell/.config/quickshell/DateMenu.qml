// The clock's menu, like GNOME's: notifications on the left (newest first, Clear), today's
// date, a month calendar and the do-not-disturb switch on the right. Opened by clicking the
// clock (a popover, see Bar.qml / Sheet.qml).
import QtQuick
import Quickshell

Sheet {
    id: dm
    namespace: "datemenu"
    center: true
    full: 740
    pad: 12

    property date today: new Date()
    property int monthOffset: 0           // months away from today's month in the calendar
    readonly property date month: new Date(today.getFullYear(), today.getMonth() + monthOffset, 1)

    onWantChanged: {
        Notifs.centreOpen = want
        if (want) { today = new Date(); monthOffset = 0; Notifs.seen() }
    }

    Row {
        spacing: 0

        // ---- notifications ----
        Column {
            id: left
            width: 420
            spacing: 8

            Item {
                width: parent.width
                height: 30
                Text {
                    x: 4
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Notifications"
                    color: Theme.fg
                    font { family: Theme.font; pointSize: Theme.fontPx * 0.75; weight: Font.DemiBold }
                }
                Btn {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Notifs.items.length > 0
                    implicitHeight: 26
                    padding: 12
                    color: hovered ? Theme.pillPress : Theme.pillHover
                    onClicked: Notifs.clear()
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Clear"
                        color: Theme.fg
                        font { family: Theme.font; pointSize: 12.5 * 0.75 }
                    }
                }
            }

            ListView {
                id: list
                width: parent.width
                height: Notifs.items.length ? Math.min(contentHeight, 470) : 0
                clip: true
                spacing: 6
                model: Notifs.items
                boundsBehavior: Flickable.StopAtBounds
                delegate: NotifCard {
                    required property var modelData
                    entry: modelData
                    width: list.width
                }
            }

            // nothing to show
            Column {
                visible: Notifs.items.length === 0
                width: parent.width
                topPadding: 60
                bottomPadding: 60
                spacing: 8
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "󰂚"
                    color: Theme.fgMuted
                    font { family: Theme.iconFont; pixelSize: 40 }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "No notifications"
                    color: Theme.fgMuted
                    font { family: Theme.font; pointSize: Theme.fontPx * 0.75 }
                }
            }
        }

        // divider
        Item {
            width: 25
            height: Math.max(left.height, right.height)
            Rectangle {
                anchors.centerIn: parent
                width: 1
                height: parent.height - 8
                color: Theme.barBorder
            }
        }

        // ---- date, calendar, do not disturb ----
        Column {
            id: right
            width: dm.inner - left.width - 25
            spacing: 10

            Column {
                x: 4
                Text {
                    text: Qt.formatDate(dm.today, "dddd")
                    color: Theme.fgTitle
                    font { family: Theme.font; pointSize: 12.5 * 0.75; weight: Font.DemiBold }
                }
                Text {
                    text: Qt.formatDate(dm.today, "d MMMM yyyy")
                    color: Theme.fgStrong
                    font { family: Theme.font; pointSize: 18 * 0.75; weight: Font.Medium }
                }
            }

            // month header
            Item {
                width: parent.width
                height: 28
                Btn {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    implicitHeight: 26; padding: 6
                    onClicked: dm.monthOffset--
                    Icon { text: "󰅁"; color: Theme.fgTitle }
                }
                Btn {
                    anchors.centerIn: parent
                    implicitHeight: 26; padding: 10
                    onClicked: dm.monthOffset = 0
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Qt.formatDate(dm.month, dm.month.getFullYear() === dm.today.getFullYear() ? "MMMM" : "MMMM yyyy")
                        color: Theme.fg
                        font { family: Theme.font; pointSize: Theme.fontPx * 0.75; weight: Font.DemiBold }
                    }
                }
                Btn {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    implicitHeight: 26; padding: 6
                    onClicked: dm.monthOffset++
                    Icon { text: "󰅂"; color: Theme.fgTitle }
                }
            }

            // month grid, Monday first; today is a filled circle
            Grid {
                id: grid
                columns: 7
                readonly property real cell: Math.floor(parent.width / 7)
                readonly property int lead: (dm.month.getDay() + 6) % 7
                readonly property int days: new Date(dm.month.getFullYear(), dm.month.getMonth() + 1, 0).getDate()

                Repeater {
                    model: ["M", "T", "W", "T", "F", "S", "S"]
                    Text {
                        required property string modelData
                        width: grid.cell; height: 24
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: modelData
                        color: Theme.fgMuted
                        font { family: Theme.font; pointSize: 11.5 * 0.75; weight: Font.DemiBold }
                    }
                }
                Repeater {
                    model: 42
                    Item {
                        required property int index
                        readonly property int day: index - grid.lead + 1
                        readonly property bool inMonth: day >= 1 && day <= grid.days
                        readonly property bool isToday: inMonth && dm.monthOffset === 0 && day === dm.today.getDate()
                        width: grid.cell
                        height: 32
                        visible: index < Math.ceil((grid.lead + grid.days) / 7) * 7
                        Rectangle {
                            anchors.centerIn: parent
                            width: 30; height: 30; radius: 15
                            visible: parent.isToday
                            color: Theme.wsPill
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: parent.inMonth
                            text: parent.day
                            color: parent.isToday ? Qt.rgba(Theme.barBg.r, Theme.barBg.g, Theme.barBg.b, 1) : Theme.fg
                            font { family: Theme.font; pointSize: 12.5 * 0.75; weight: parent.isToday ? Font.Bold : Font.Normal; features: { "tnum": 1 } }
                        }
                    }
                }
            }

            // do not disturb
            Rectangle {
                width: parent.width
                height: 44
                radius: Theme.radiusSmall
                color: dndMouse.containsMouse ? Theme.pillHover : Theme.pillBg
                Behavior on color { ColorAnimation { duration: dndMouse.containsMouse ? Theme.hoverIn : Theme.hoverOut } }
                Text {
                    x: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Do not disturb"
                    color: Theme.fg
                    font { family: Theme.font; pointSize: Theme.fontPx * 0.75 }
                }
                Switch {
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    on: Notifs.dnd
                }
                MouseArea {
                    id: dndMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: Notifs.dnd = !Notifs.dnd
                }
            }
        }
    }
}
