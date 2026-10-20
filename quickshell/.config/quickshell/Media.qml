// Media pill = album art + title + play/pause + cava bars; prev/next slide out next to the title
// on hover. Follows playerctld (the most recently active player), like the playerctl bindings.
// Hidden while nothing is playing or paused.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Widgets

Rectangle {
    id: root
    property var window

    readonly property var player: {
        const all = Mpris.players.values
        return all.find(p => p.dbusName === "org.mpris.MediaPlayer2.playerctld") || all[0] || null
    }
    readonly property bool active: player !== null && player.trackTitle !== ""
        && player.playbackState !== MprisPlaybackState.Stopped
    property string viz: ""

    visible: active
    implicitWidth: row.implicitWidth
    implicitHeight: 26
    radius: Theme.radiusPill
    color: Theme.pillBg

    function run(...args) { Quickshell.execDetached(["playerctl", ...args]) }

    Row {
        id: row
        height: parent.height

        // album art (click: play/pause)
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
                }
            }
            MouseArea { anchors.fill: parent; onClicked: root.run("play-pause") }
        }

        // title + the prev/next drawer
        Item {
            id: drawer
            readonly property bool open: titleMouse.containsMouse || prev.hovered || next.hovered
            width: title.width + (open ? buttons.implicitWidth : 0)
            height: parent.height
            clip: true
            Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring } }

            Text {
                id: title
                x: 0
                rightPadding: 10
                leftPadding: 4
                anchors.verticalCenter: parent.verticalCenter
                text: {
                    const t = root.player ? root.player.trackTitle : ""
                    return t.length > 26 ? t.slice(0, 25) + "…" : t
                }
                color: root.player && root.player.isPlaying ? Theme.fgTitle : Theme.fgMuted
                font { family: Theme.font; pointSize: Theme.fontPx * 0.75 }
                Behavior on color { ColorAnimation { duration: Theme.hoverOut } }

                MouseArea {
                    id: titleMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    onClicked: m => {
                        if (m.button === Qt.LeftButton) Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/nowplaying"])
                        else if (m.button === Qt.RightButton) root.run("next")
                        else root.run("previous")
                    }
                    onWheel: w => root.run("position", w.angleDelta.y > 0 ? "5+" : "5-")
                }
            }

            Row {
                id: buttons
                x: title.width
                anchors.verticalCenter: parent.verticalCenter
                opacity: drawer.open ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 200 } }

                Btn {
                    id: prev
                    padding: 7
                    onClicked: root.run("previous")
                    Icon { text: "󰒮"; color: prev.hovered ? Theme.fgStrong : Theme.fgTitle }
                }
                Btn {
                    id: next
                    padding: 7
                    onClicked: root.run("next")
                    Icon { text: "󰒭"; color: next.hovered ? Theme.fgStrong : Theme.fgTitle }
                }
            }
        }

        Btn {
            id: toggle
            padding: 7
            anchors.verticalCenter: parent.verticalCenter
            onClicked: root.run("play-pause")
            Icon {
                text: root.player && root.player.isPlaying ? "󰏤" : "󰐊"
                color: toggle.hovered ? Theme.fgStrong : Theme.fgTitle
            }
        }

        // cava bars: the one moving thing on the bar, kept quiet in colour
        Text {
            visible: root.viz !== ""
            anchors.verticalCenter: parent.verticalCenter
            leftPadding: 5
            rightPadding: 12
            text: root.viz
            color: Theme.fgMuted
            font { family: Theme.iconFont; pixelSize: 16; letterSpacing: 2 }
            MouseArea { anchors.fill: parent; onClicked: root.run("play-pause") }
        }
        Item { width: 3; height: 1; visible: root.viz === "" }
    }

    Process {
        running: root.active
        command: [Quickshell.env("HOME") + "/.local/bin/media-viz", "8"]
        stdout: SplitParser { onRead: line => root.viz = line }
        onRunningChanged: if (!running) root.viz = ""
    }
}
