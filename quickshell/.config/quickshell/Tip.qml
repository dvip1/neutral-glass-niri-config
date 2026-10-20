// Tooltip under an item, shown after a short hover: it fades in while dropping a few px into
// place, and fades out when the pointer leaves. (An xdg popup of the bar, not blurred.)
import QtQuick
import Quickshell

PopupWindow {
    id: tip
    property Item target
    property var window
    property string text: ""
    property bool mono: false
    property bool rich: false   // text is HTML (e.g. a <pre> calendar)
    property bool show: false

    readonly property int drop: 4

    anchor.item: target
    anchor.rect.x: 0
    anchor.rect.y: target ? target.height + 10 - drop : 0
    anchor.rect.width: target ? target.width : 0
    anchor.rect.height: 1
    anchor.edges: Edges.Top
    anchor.gravity: Edges.Bottom
    anchor.adjustment: PopupAdjustment.Slide

    implicitWidth: box.implicitWidth
    implicitHeight: box.implicitHeight + drop
    color: "transparent"
    visible: false

    Timer {
        id: delay
        interval: 350
        onTriggered: { leave.stop(); tip.visible = true; enter.restart() }
    }
    onShowChanged: {
        if (show && text !== "") delay.restart()
        else { delay.stop(); if (visible) { enter.stop(); leave.restart() } }
    }

    ParallelAnimation {
        id: enter
        NumberAnimation { target: box; property: "opacity"; from: 0; to: 1; duration: Theme.hoverIn * 1.6; easing.type: Easing.OutCubic }
        NumberAnimation { target: box; property: "y"; from: 0; to: tip.drop; duration: Theme.pillMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring }
    }
    SequentialAnimation {
        id: leave
        NumberAnimation { target: box; property: "opacity"; to: 0; duration: Theme.hoverOut * 0.6; easing.type: Easing.OutCubic }
        ScriptAction { script: tip.visible = false }
    }

    Rectangle {
        id: box
        opacity: 0
        implicitWidth: label.implicitWidth + 24
        implicitHeight: label.implicitHeight + 14
        width: implicitWidth
        height: implicitHeight
        color: Theme.tipBg
        border.color: Theme.tipBorder
        border.width: 1
        radius: Theme.radiusPill

        Text {
            id: label
            anchors.centerIn: parent
            text: tip.text
            color: Theme.fg
            font.family: tip.mono ? "monospace" : Theme.font
            font.pointSize: Theme.fontPx * 0.75
            textFormat: tip.rich ? Text.RichText : Text.PlainText
        }
    }
}
