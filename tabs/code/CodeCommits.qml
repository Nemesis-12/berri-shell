import QtQuick
import "../../logic/CodeFormat.js" as Fmt
import qs.common
import qs.services

/**
 * The last commits (mock 5C): a vertical COMMITS label, then one two-line
 * entry per commit spread over the full height: short hash and message,
 * then repository and age.
 */
Rectangle {
    id: root

    /** Items of { sha, message, repo, date } (date is an ISO string). */
    property var commits: []
    property date now: new Date()

    color: Theme.card

    SideLabel {
        width: size
        textX: (width - lineHeight) / 2
        x: 10
        y: 12
        text: "COMMITS"
    }

    Item {
        id: list
        x: 29
        y: 12
        width: parent.width - 29 - 14
        height: parent.height - 24

        readonly property int count: root.commits.length
        readonly property real entryHeight: 4 + 15.5 + 9

        Repeater {
            model: root.commits

            Item {
                id: entry
                required property var modelData
                required property int index

                y: list.count > 1 ? index * (list.height - list.entryHeight) / (list.count - 1) : 0
                width: list.width
                height: list.entryHeight

                MonoText {
                    x: 0
                    y: 0
                    height: 16
                    verticalAlignment: Text.AlignVCenter
                    width: 50
                    text: entry.modelData.sha
                    color: Theme.accentLight
                }

                CondensedText {
                    x: 58
                    y: 0
                    height: 16
                    verticalAlignment: Text.AlignVCenter
                    width: parent.width - 58
                    text: entry.modelData.message
                    elide: Text.ElideRight
                }

                MonoText {
                    x: 58
                    y: 16 + 4
                    height: 9
                    verticalAlignment: Text.AlignVCenter
                    width: parent.width - 58
                    text: (entry.modelData.repo + " · " + Fmt.ago(new Date(entry.modelData.date), root.now)).toUpperCase()
                    font.letterSpacing: 0.36
                    elide: Text.ElideRight
                }
            }
        }
    }
}
