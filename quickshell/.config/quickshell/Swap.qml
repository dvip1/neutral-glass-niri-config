// Text that changes softly: the old value fades out while the new one fades in. With `slide`,
// numbers roll (up when the value grows, down when it shrinks); icons just crossfade.
import QtQuick

Item {
    id: root
    property string text: ""
    property color color: Theme.fg
    property string family: Theme.font
    property real pointSize: Theme.fontPx * 0.75
    property bool tnum: false
    property real slide: 0        // px the text travels while changing (0 = crossfade only)
    property int duration: 280

    property Text cur: a
    property bool ready: false

    implicitWidth: cur.implicitWidth
    implicitHeight: cur.implicitHeight
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined

    component Face: Text {
        color: root.color
        font.family: root.family
        font.pointSize: root.pointSize
        font.features: root.tnum ? { "tnum": 1 } : {}
        anchors.horizontalCenter: parent.horizontalCenter
    }
    Face { id: a }
    Face { id: b; opacity: 0 }

    Component.onCompleted: { a.text = text; ready = true }

    onTextChanged: {
        if (!ready || cur.text === text) return
        swap.complete()
        const prev = cur, next = cur === a ? b : a
        const grow = parseFloat(text) >= parseFloat(prev.text)
        swap.dir = isNaN(parseFloat(text)) || isNaN(parseFloat(prev.text)) ? 0 : grow ? 1 : -1
        next.text = text
        cur = next
        swap.out = prev
        swap.into = next
        swap.start()
    }

    ParallelAnimation {
        id: swap
        property Item out: b
        property Item into: a
        property int dir: 0
        readonly property real dist: root.slide * dir

        NumberAnimation { target: swap.out; property: "opacity"; to: 0; duration: root.duration * 0.6; easing.type: Easing.OutCubic }
        NumberAnimation { target: swap.out; property: "y"; from: 0; to: -swap.dist; duration: root.duration; easing.type: Easing.OutCubic }
        NumberAnimation { target: swap.into; property: "opacity"; from: 0; to: 1; duration: root.duration; easing.type: Easing.OutCubic }
        NumberAnimation { target: swap.into; property: "y"; from: swap.dist; to: 0; duration: root.duration; easing.type: Easing.OutCubic }
    }
}
