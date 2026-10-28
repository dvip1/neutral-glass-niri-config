// Bar: one small pill per running task (Tasks.qml), left of the status pill. A recording shows a
// pulsing red dot and the time so far; a timer the time left. Hover shows a stop square; click stops it.
import QtQuick

Row {
    id: root
    spacing: 6
    visible: Tasks.list.length > 0

    Repeater {
        model: Tasks.list
        Rectangle {
            id: pill
            required property var modelData
            readonly property bool rec: modelData.kind === "rec"
            implicitWidth: line.implicitWidth + 20
            implicitHeight: 26
            anchors.verticalCenter: parent ? parent.verticalCenter : undefined
            radius: Theme.radiusPill
            color: mouse.pressed ? Theme.pillPress : mouse.containsMouse ? Theme.pillHover : Theme.pillBg
            Behavior on color { ColorAnimation { duration: mouse.containsMouse ? Theme.hoverIn : Theme.hoverOut } }

            Row {
                id: line
                anchors.centerIn: parent
                spacing: 7
                Item {
                    width: 12; height: 12
                    anchors.verticalCenter: parent.verticalCenter
                    // recording: red dot that breathes; hover: a stop square
                    Rectangle {
                        anchors.centerIn: parent
                        width: mouse.containsMouse ? 9 : 8; height: width
                        radius: mouse.containsMouse ? 2 : width / 2
                        color: pill.rec ? Theme.crit : Theme.fgTitle
                        visible: pill.rec || mouse.containsMouse
                        SequentialAnimation on opacity {
                            running: pill.rec && !mouse.containsMouse
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.35; duration: 900; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 1; duration: 900; easing.type: Easing.InOutSine }
                        }
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: !pill.rec && !mouse.containsMouse
                        text: "󱎫"
                        color: Theme.fgTitle
                        font { family: Theme.iconFont; pixelSize: 14 }
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Tasks.status(pill.modelData)
                    color: mouse.containsMouse ? Theme.fgStrong : Theme.fgTitle
                    font { family: Theme.font; pointSize: Theme.fontPx * 0.75; features: { "tnum": 1 } }
                }
            }
            MouseArea {
                id: mouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: Tasks.stop(pill.modelData.unit)
            }
        }
    }
}
