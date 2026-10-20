// Frosted tooltip under an item, shown after a short hover (an xdg popup: niri blurs it via
// the "bar" layer-rule's popups block).
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

    anchor.item: target
    anchor.rect.x: 0
    anchor.rect.y: target ? target.height + 10 : 0
    anchor.rect.width: target ? target.width : 0
    anchor.rect.height: 1
    anchor.edges: Edges.Top
    anchor.gravity: Edges.Bottom
    anchor.adjustment: PopupAdjustment.Slide

    implicitWidth: box.implicitWidth
    implicitHeight: box.implicitHeight
    color: "transparent"
    visible: false

    Timer {
        id: delay
        interval: 450
        onTriggered: tip.visible = true
    }
    onShowChanged: {
        if (show && text !== "") delay.restart()
        else { delay.stop(); visible = false }
    }

    Rectangle {
        id: box
        implicitWidth: label.implicitWidth + 24
        implicitHeight: label.implicitHeight + 14
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
