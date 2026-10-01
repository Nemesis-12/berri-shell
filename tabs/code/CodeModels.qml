import QtQuick
import "../../logic/CodeFormat.js" as Fmt
import qs.common
import qs.services

/**
 * Tokens this week per model for one agent (mock 5C "BY MODEL"): a name, a
 * thin bar scaled to the largest model, and the token count. Up to 4 rows
 * sit in fixed slots so a change of agent moves and fades the same rows.
 */
Rectangle {
    id: root

    /** Items of { name, tokens }, largest first. */
    property var rows: []
    property color tone: Theme.accentLight

    readonly property int slots: 4
    readonly property real rowHeight: 13
    readonly property real rowGap: 12
    readonly property real peak: rows.length > 0 ? Math.max(1, rows[0].tokens) : 1
    readonly property int shown: Math.min(rows.length, slots)

    color: Theme.card

    SideLabel {
        width: size
        textX: (width - lineHeight) / 2
        x: 10
        y: 10
        text: "BY MODEL"
    }

    Item {
        id: body
        x: 29
        y: 10
        width: parent.width - 29 - 14
        height: parent.height - 20

        Repeater {
            model: root.slots

            Item {
                id: row
                required property int index

                readonly property var entry: index < root.rows.length ? root.rows[index] : null

                width: body.width
                height: root.rowHeight
                y: (body.height - (root.shown * root.rowHeight + Math.max(0, root.shown - 1) * root.rowGap)) / 2
                    + index * (root.rowHeight + root.rowGap)
                opacity: entry ? 1 : 0
                Fade on opacity { duration: Theme.stateMs }
                Fade on y { duration: Theme.stateMs }

                // Keeps the last name and value on screen while the row fades out.
                property string lastName: ""
                property real lastTokens: 0
                // Animated share (0..1) of the bar; the width follows the live layout.
                property real share: Math.min(1, lastTokens / root.peak)
                Behavior on share { NumberAnimation { duration: 450; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.standardCurve } }
                onEntryChanged: if (entry) { lastName = entry.name; lastTokens = entry.tokens; }
                Component.onCompleted: if (entry) { lastName = entry.name; lastTokens = entry.tokens; }

                CodeValue {
                    width: 82
                    anchors.verticalCenter: parent.verticalCenter
                    value: row.lastName
                    font.pixelSize: 13
                    elide: Text.ElideRight
                }

                Rectangle {
                    x: 90
                    width: body.width - 90 - 48
                    height: 3
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.border
                    clip: true

                    Rectangle {
                        height: parent.height
                        width: Math.max(0, Math.min(parent.width, parent.width * row.share))
                        color: root.tone
                        ColorFade on color { duration: Theme.stateMs }
                    }
                }

                CodeValue {
                    x: body.width - 40
                    width: 40
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignRight
                    value: Fmt.tokens(row.lastTokens)
                    color: Theme.fg2
                    font.family: Theme.mono
                    font.pixelSize: 10
                }
            }
        }
    }
}
