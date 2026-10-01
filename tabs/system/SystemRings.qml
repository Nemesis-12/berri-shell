import QtQuick
import qs.common
import qs.services

/**
 * System cell: a vertical "SYSTEM" label plus three usage rings (CPU, RAM,
 * disk) fed by SystemUsage, each with a live-value caption below it.
 * Mirrors the mock's 5C system cell (Berri Dashboard v2.dc.html, ~line 438).
 */
Item {
    id: root

    readonly property real ringSize: 40
    /** Each ring sits centered in a box this tall; the caption follows 6px below. */
    readonly property real ringBoxHeight: 50
    /** Column width captions center within; wide enough for "148 GB". */
    readonly property real columnWidth: 54

    /** Unused now that ring tooltips are gone; kept so HomeTab's binding stays valid. */
    property Item tooltipLayer: null

    Item {
        id: labelBox
        anchors.left: parent.left
        anchors.leftMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        width: label.height
        height: parent.height

        MonoText {
            id: label
            anchors.centerIn: parent
            text: "SYSTEM"
            font.letterSpacing: 9 * 0.14
            rotation: -90
        }
    }

    // Rings area: fills the rest of the cell; 3 columns spaced like
    // CSS `justify-content: space-around` (edge gap g, between-gap 2g).
    Item {
        id: ringsArea
        anchors.left: labelBox.right
        anchors.leftMargin: 14
        anchors.right: parent.right
        anchors.rightMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        height: root.ringBoxHeight + 6 + captionMetrics.height

        readonly property real gap: Math.max(0, (width - 3 * root.columnWidth) / 6)

        // Off-screen probe for the caption row height, shared by all 3 columns.
        MonoText {
            id: captionMetrics
            visible: false
            font.weight: Font.Medium
            font.pixelSize: 9
            text: "0"
        }

        Row {
            anchors.left: parent.left
            anchors.leftMargin: ringsArea.gap
            anchors.verticalCenter: parent.verticalCenter
            spacing: ringsArea.gap * 2

            Column {
                spacing: 6

                Item {
                    width: root.columnWidth
                    height: root.ringBoxHeight

                    UsageRing {
                        anchors.centerIn: parent
                        size: root.ringSize
                        iconName: "cpu"
                        value: SystemUsage.cpuPercent
                    }
                }

                MonoText {
                    width: root.columnWidth
                    horizontalAlignment: Text.AlignHCenter
                    text: Math.round(SystemUsage.cpuPercent) + "%"
                    font.weight: Font.Medium
                    font.pixelSize: 9
                    font.letterSpacing: 9 * 0.08
                    color: Theme.dim
                }
            }

            Column {
                spacing: 6

                Item {
                    width: root.columnWidth
                    height: root.ringBoxHeight

                    UsageRing {
                        anchors.centerIn: parent
                        size: root.ringSize
                        iconName: "memory-stick"
                        value: SystemUsage.ramPercent
                    }
                }

                MonoText {
                    width: root.columnWidth
                    horizontalAlignment: Text.AlignHCenter
                    text: SystemUsage.ramUsedGb.toFixed(1) + " GB"
                    font.weight: Font.Medium
                    font.pixelSize: 9
                    font.letterSpacing: 9 * 0.08
                    color: Theme.dim
                }
            }

            Column {
                spacing: 6

                Item {
                    width: root.columnWidth
                    height: root.ringBoxHeight

                    UsageRing {
                        anchors.centerIn: parent
                        size: root.ringSize
                        iconName: "database"
                        value: SystemUsage.diskPercent
                    }
                }

                MonoText {
                    width: root.columnWidth
                    horizontalAlignment: Text.AlignHCenter
                    text: Math.round(SystemUsage.diskUsedGb) + " GB"
                    font.weight: Font.Medium
                    font.pixelSize: 9
                    font.letterSpacing: 9 * 0.08
                    color: Theme.dim
                }
            }
        }
    }
}
