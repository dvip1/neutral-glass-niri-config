// The polkit agent: asks for your password when an app needs admin rights (GNOME Software,
// `pkexec`, …). Nothing else under niri does this. A full-screen, blurred and dimmed backdrop
// (niri layer-rule "polkit") with a card: what is asking, the password field, Cancel /
// Authenticate. Enter submits, Esc cancels; a wrong password shakes the card a little.
import QtQuick
import Quickshell
import Quickshell.Services.Polkit
import Quickshell.Wayland

Scope {
    id: root
    property var screen

    PolkitAgent { id: agent }
    readonly property var flow: agent.flow

    PanelWindow {
        id: win
        screen: root.screen
        visible: root.flow !== null
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.namespace: "polkit"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        property real shown: 0
        onVisibleChanged: if (visible) { shown = 0; enter.restart(); field.text = ""; field.forceActiveFocus() }
        NumberAnimation { id: enter; target: win; property: "shown"; to: 1; duration: 160; easing.type: Easing.OutCubic }

        function submit() { if (root.flow && root.flow.isResponseRequired) { root.flow.submit(field.text); field.text = "" } }
        function cancel() { if (root.flow) root.flow.cancelAuthenticationRequest() }

        Connections {
            target: root.flow
            function onFailedChanged() { if (root.flow && root.flow.failed) shake.restart() }
            function onIsResponseRequiredChanged() { field.forceActiveFocus() }
        }

        // dim the blurred screen
        Rectangle {
            anchors.fill: parent
            color: "black"
            opacity: (Theme.mode === "dark" ? 0.35 : 0.2) * win.shown
        }

        Rectangle {
            id: card
            anchors.centerIn: parent
            width: 400
            height: body.implicitHeight + 40
            radius: Theme.radiusLarge
            color: Theme.tipBg
            border.color: Theme.barBorder
            border.width: 1
            opacity: win.shown
            scale: 0.97 + 0.03 * win.shown
            transform: Translate { id: nudge }

            SequentialAnimation {
                id: shake
                loops: 2
                NumberAnimation { target: nudge; property: "x"; to: -6; duration: 40 }
                NumberAnimation { target: nudge; property: "x"; to: 6; duration: 80 }
                NumberAnimation { target: nudge; property: "x"; to: 0; duration: 40 }
            }

            Column {
                id: body
                x: 20; y: 20
                width: parent.width - 40
                spacing: 12

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "󰌾"
                    color: Theme.fgTitle
                    font { family: Theme.iconFont; pixelSize: 30 }
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: "Authentication required"
                    color: Theme.fgStrong
                    font { family: Theme.font; pointSize: 15 * 0.75; weight: Font.DemiBold }
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    text: root.flow ? root.flow.message : ""
                    color: Theme.fgTitle
                    font { family: Theme.font; pointSize: 13 * 0.75 }
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    visible: root.flow !== null && root.flow.selectedIdentity !== null
                    text: root.flow && root.flow.selectedIdentity ? root.flow.selectedIdentity.displayName : ""
                    color: Theme.fgMuted
                    font { family: Theme.font; pointSize: 12 * 0.75 }
                }

                Rectangle {
                    width: parent.width
                    height: 40
                    radius: Theme.radiusSmall
                    color: Theme.pillHover
                    border.width: root.flow && root.flow.failed ? 1 : 0
                    border.color: Theme.crit
                    TextInput {
                        id: field
                        x: 12
                        width: parent.width - 24
                        anchors.verticalCenter: parent.verticalCenter
                        echoMode: root.flow && root.flow.responseVisible ? TextInput.Normal : TextInput.Password
                        color: Theme.fg
                        font { family: Theme.font; pointSize: 13 * 0.75 }
                        focus: true
                        onAccepted: win.submit()
                        Keys.onEscapePressed: win.cancel()
                        Text {
                            visible: !parent.text
                            text: root.flow && root.flow.inputPrompt ? root.flow.inputPrompt.replace(/:\s*$/, "") : "Password"
                            color: Theme.fgMuted
                            font: parent.font
                        }
                    }
                }
                Text {
                    width: parent.width
                    visible: text !== ""
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    text: !root.flow ? "" : root.flow.failed ? "Wrong password, try again" : root.flow.supplementaryMessage
                    color: root.flow && (root.flow.failed || root.flow.supplementaryIsError) ? Theme.crit : Theme.fgMuted
                    font { family: Theme.font; pointSize: 12 * 0.75 }
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 10
                    Btn {
                        implicitHeight: 34; padding: 22
                        color: hovered ? Theme.pillPress : Theme.pillHover
                        onClicked: win.cancel()
                        Text { anchors.verticalCenter: parent.verticalCenter; text: "Cancel"; color: Theme.fg; font { family: Theme.font; pointSize: 13 * 0.75 } }
                    }
                    Btn {
                        implicitHeight: 34; padding: 22
                        color: Theme.wsPill
                        opacity: hovered ? 0.85 : 1
                        onClicked: win.submit()
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Authenticate"
                            color: Qt.rgba(Theme.barBg.r, Theme.barBg.g, Theme.barBg.b, 1)
                            font { family: Theme.font; pointSize: 13 * 0.75; weight: Font.DemiBold }
                        }
                    }
                }
            }
        }
    }
}
