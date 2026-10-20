// Centre clock: the quiet anchor. Date dimmed, time carries the weight; month calendar on hover.
import QtQuick
import Quickshell

Item {
    id: root
    property var window
    implicitWidth: row.implicitWidth + 20
    implicitHeight: 26

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 12

        Text {
            text: Qt.formatDateTime(clock.date, "ddd dd MMM")
            color: Theme.fgStrong
            opacity: 0.55
            font { family: Theme.font; pointSize: Theme.fontPx * 0.75; weight: Font.DemiBold; features: { "tnum": 1 } }
        }
        Text {
            text: Qt.formatDateTime(clock.date, "HH:mm")
            color: Theme.fgStrong
            font { family: Theme.font; pointSize: Theme.fontPx * 0.75; weight: Font.DemiBold; features: { "tnum": 1 } }
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
    }

    Tip {
        target: root
        window: root.window
        rich: true
        show: mouse.containsMouse
        text: root.calendar(clock.date)
    }

    // A month grid like `cal`, Monday first, today in bold (rich text inside <pre>).
    function calendar(d) {
        const y = d.getFullYear(), m = d.getMonth()
        const title = Qt.formatDate(d, "MMMM yyyy")
        let out = " ".repeat(Math.max(0, Math.floor((20 - title.length) / 2))) + title + "\nMo Tu We Th Fr Sa Su\n"
        const lead = (new Date(y, m, 1).getDay() + 6) % 7
        const days = new Date(y, m + 1, 0).getDate()
        const cells = Array(lead).fill("  ")
        for (let day = 1; day <= days; day++) {
            const c = String(day).padStart(2)
            cells.push(day === d.getDate() ? "<b><u>" + c + "</u></b>" : c)
        }
        for (let i = 0; i < cells.length; i += 7) out += cells.slice(i, i + 7).join(" ") + "\n"
        return "<pre>" + out.replace(/\n$/, "") + "</pre>"
    }
}
