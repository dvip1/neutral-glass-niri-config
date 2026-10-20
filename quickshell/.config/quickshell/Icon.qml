// A Nerd Font glyph at waybar's "large" icon size.
import QtQuick

Text {
    font.family: Theme.iconFont
    font.pointSize: Theme.iconPx * 0.75
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
}
