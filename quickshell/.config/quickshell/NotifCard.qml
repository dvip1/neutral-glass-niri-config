// One notification (a popup, or a row in the centre): picture, app + time, summary, body,
// action buttons, and a close button on hover. Clicking it runs its default action.
import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Notifications

Rectangle {
    id: card
    required property var entry
    property bool popup: false
    readonly property var n: entry.n
    readonly property string summary: n ? n.summary : entry.summary || ""
    readonly property string body: n ? n.body : entry.body || ""
    readonly property bool critical: entry.urgency === NotificationUrgency.Critical
    readonly property var actions: n ? n.actions.filter(a => a.identifier !== "default" && a.text) : []
    readonly property bool hot: hover.hovered

    implicitHeight: content.implicitHeight + 24
    radius: Theme.radiusSmall
    color: popup ? Theme.clear(Theme.wsHover) : hot ? Theme.wsHover : Theme.pillBg
    Behavior on color { ColorAnimation { duration: card.hot ? Theme.hoverIn : Theme.hoverOut } }
    border.width: critical ? 1 : 0
    border.color: Theme.fgMuted

    HoverHandler { id: hover }
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onClicked: m => m.button === Qt.MiddleButton ? Notifs.dismiss(card.entry) : Notifs.invoke(card.entry)
    }

    function ago(t) {
        const m = Math.floor((Notifs.now - t) / 60000)
        if (m < 1) return "now"
        if (m < 60) return m + " min"
        const d = new Date(t)
        return new Date(Notifs.now).toDateString() === d.toDateString() ? Qt.formatTime(d, "HH:mm") : Qt.formatDate(d, "d MMM")
    }

    Row {
        id: content
        x: 12; y: 12
        width: parent.width - 24
        spacing: 12

        ClippingRectangle {
            visible: pic.status === Image.Ready
            width: 36; height: 36
            radius: 8
            color: "transparent"
            Image {
                id: pic
                anchors.fill: parent
                source: card.entry.icon || ""
                sourceSize: Qt.size(72, 72)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }
        }

        Column {
            width: parent.width - (pic.status === Image.Ready ? 36 + 12 : 0)
            spacing: 2

            Item {
                width: parent.width
                height: appLine.implicitHeight
                Text {
                    id: appLine
                    width: parent.width - 30
                    elide: Text.ElideRight
                    text: (card.entry.app || "Notification") + "  ·  " + card.ago(card.entry.time)
                    color: Theme.fgMuted
                    font { family: Theme.font; pointSize: 11.5 * 0.75 }
                }
            }
            Text {
                width: parent.width
                elide: Text.ElideRight
                text: card.summary
                color: Theme.fgStrong
                font { family: Theme.font; pointSize: Theme.fontPx * 0.75; weight: Font.DemiBold }
            }
            Text {
                width: parent.width
                visible: text !== ""
                text: card.body
                textFormat: Text.StyledText
                wrapMode: Text.Wrap
                maximumLineCount: card.popup ? 3 : 4
                elide: Text.ElideRight
                color: Theme.fgTitle
                linkColor: Theme.fg
                font { family: Theme.font; pointSize: 13 * 0.75 }
                onLinkActivated: link => Qt.openUrlExternally(link)
            }
            Row {
                visible: card.actions.length > 0
                topPadding: 6
                spacing: 6
                Repeater {
                    model: card.actions
                    Btn {
                        required property var modelData
                        implicitHeight: 26
                        padding: 10
                        color: hovered ? Theme.pillPress : Theme.pillHover
                        onClicked: Notifs.invoke(card.entry, modelData)
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.text
                            color: Theme.fg
                            font { family: Theme.font; pointSize: 12.5 * 0.75 }
                        }
                    }
                }
            }
        }
    }

    // close, top right, on hover
    Btn {
        anchors { top: parent.top; right: parent.right; topMargin: 6; rightMargin: 6 }
        implicitHeight: 22
        padding: 4
        opacity: card.hot ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.hoverIn } }
        onClicked: Notifs.dismiss(card.entry)
        Icon { text: "󰅖"; color: Theme.fgTitle; pointSize: 14 * 0.75 }
    }
}
