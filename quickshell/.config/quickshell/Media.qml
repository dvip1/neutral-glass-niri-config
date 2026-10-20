// Media pill = album art + title + play/pause + cava bars; prev/next slide out next to the title
// on hover. Follows playerctld (the most recently active player), like the playerctl bindings.
// Fades in/out with playback; its width springs when the title changes.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Widgets

Rectangle {
    id: root
    property var window
    signal panel()                // title clicked: open / close the now-playing sheet

    readonly property var player: {
        const all = Mpris.players.values
        return all.find(p => p.dbusName === "org.mpris.MediaPlayer2.playerctld") || all[0] || null
    }
    readonly property bool active: player !== null && player.trackTitle !== ""
        && player.playbackState !== MprisPlaybackState.Stopped
    property var levels: []       // cava, 0-12 per bar; empty while silent

    visible: opacity > 0
    opacity: active ? 1 : 0
    scale: active ? 1 : 0.92
    Behavior on opacity { NumberAnimation { duration: Theme.hoverOut; easing.type: Easing.OutCubic } }
    Behavior on scale { NumberAnimation { duration: Theme.pillMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring } }

    implicitWidth: row.implicitWidth
    implicitHeight: 26
    Behavior on implicitWidth { NumberAnimation { duration: Theme.pillMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring } }
    clip: true
    radius: Theme.radiusPill
    color: Theme.pillBg

    function run(...args) { Quickshell.execDetached(["playerctl", ...args]) }

    Glide { id: hoverGlide }

    Row {
        id: row
        height: parent.height

        // album art (click: play/pause); the new cover fades in
        Item {
            visible: art.status === Image.Ready
            width: visible ? 22 + 10 : 0
            height: parent.height
            ClippingRectangle {
                x: 6
                anchors.verticalCenter: parent.verticalCenter
                width: 22; height: 22
                radius: 5.5
                color: "transparent"
                Image {
                    id: art
                    anchors.fill: parent
                    source: root.player ? root.player.trackArtUrl : ""
                    sourceSize: Qt.size(66, 66)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    onStatusChanged: if (status === Image.Ready) fadeIn.restart()
                    NumberAnimation on opacity { id: fadeIn; from: 0; to: 1; duration: 220; easing.type: Easing.OutCubic }
                }
            }
            MouseArea { anchors.fill: parent; onClicked: root.run("play-pause") }
        }

        // title + the prev/next drawer
        Item {
            id: drawer
            readonly property bool open: titleMouse.containsMouse || prev.hovered || next.hovered
            width: titleBox.width + (open ? buttons.implicitWidth : 0)
            height: parent.height
            clip: true
            Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring } }

            Item {
                id: titleBox
                width: title.implicitWidth + 4 + 10
                height: parent.height
                Swap {
                    id: title
                    x: 4
                    text: {
                        const t = root.player ? root.player.trackTitle : ""
                        return t.length > 26 ? t.slice(0, 25) + "…" : t
                    }
                    color: root.player && root.player.isPlaying ? Theme.fgTitle : Theme.fgMuted
                    Behavior on color { ColorAnimation { duration: Theme.hoverOut } }
                }
                MouseArea {
                    id: titleMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    onClicked: m => {
                        if (m.button === Qt.LeftButton) root.panel()
                        else if (m.button === Qt.RightButton) root.run("next")
                        else root.run("previous")
                    }
                    onDoubleClicked: m => clicked(m)
                    onWheel: w => root.run("position", w.angleDelta.y > 0 ? "5+" : "5-")
                }
            }

            Row {
                id: buttons
                x: titleBox.width
                anchors.verticalCenter: parent.verticalCenter
                opacity: drawer.open ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 200 } }

                Btn {
                    id: prev
                    glide: hoverGlide
                    padding: 7
                    onClicked: root.run("previous")
                    Icon { text: "󰒮"; color: prev.hovered ? Theme.fgStrong : Theme.fgTitle }
                }
                Btn {
                    id: next
                    glide: hoverGlide
                    padding: 7
                    onClicked: root.run("next")
                    Icon { text: "󰒭"; color: next.hovered ? Theme.fgStrong : Theme.fgTitle }
                }
            }
        }

        Btn {
            id: toggle
            glide: hoverGlide
            padding: 7
            anchors.verticalCenter: parent.verticalCenter
            onClicked: root.run("play-pause")
            Icon {
                text: root.player && root.player.isPlaying ? "󰏤" : "󰐊"
                color: toggle.hovered ? Theme.fgStrong : Theme.fgTitle
            }
        }

        // cava: small rounded bars, the one moving thing on the bar, kept quiet in colour
        Item {
            id: viz
            readonly property bool on: root.levels.length > 0
            width: on ? bars.implicitWidth + 5 + 12 : 3
            height: parent.height
            Behavior on width { NumberAnimation { duration: Theme.pillMs; easing.type: Easing.OutCubic } }

            Row {
                id: bars
                x: 5
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                opacity: viz.on ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.hoverOut } }
                Repeater {
                    model: 8
                    Rectangle {
                        required property int index
                        anchors.verticalCenter: parent.verticalCenter
                        width: 3
                        radius: 1.5
                        height: 3 + 11 * Math.min(1, (root.levels[index] || 0) / 12)
                        color: Theme.fgMuted
                        Behavior on height { NumberAnimation { duration: 60 } }
                    }
                }
            }
            MouseArea { anchors.fill: parent; onClicked: root.run("play-pause") }
        }
    }

    Process {
        running: root.active
        command: [Quickshell.env("HOME") + "/.local/bin/media-viz", "8", "raw"]
        stdout: SplitParser {
            onRead: line => root.levels = line === "" ? [] : line.split(";").map(Number)
        }
        onRunningChanged: if (!running) root.levels = []
    }
}
