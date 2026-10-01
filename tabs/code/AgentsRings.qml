import QtQuick
import qs.common
import qs.services

/**
 * Agents cell (ticket 22): a vertical "AGENTS" label plus three rings fed by
 * AgentUsage — Claude 5-hour, Codex 5-hour, and a double ring for the Claude
 * and Codex weekly resets. Mirrors SystemRings' layout so all ring centers
 * (Agents and System) sit on one line.
 */
Item {
    id: root

    WhileVisible { service: AgentUsage }

    /** Every ring sits centered in a box this tall, so captions line up
        under rings of different sizes (40 and 50). */
    readonly property real boxHeight: 50
    readonly property real claudeRingSize: 40
    readonly property real codexRingSize: 40
    readonly property real weeklyRingSize: 50

    Item {
        id: labelBox
        anchors.left: parent.left
        anchors.leftMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        width: label.height
        height: parent.height

        // Not SideLabel: its turned text lands on a different sub-pixel and
        // changes 23 edge pixels of this label.
        MonoText {
            id: label
            anchors.centerIn: parent
            text: "AGENTS"
            font.letterSpacing: 9 * 0.14
            rotation: -90
        }
    }

    // Rings area: fills the rest of the cell; 3 columns spaced like CSS
    // `justify-content: space-around` (edge gap g, between-gap 2g), same
    // pattern as SystemRings.
    Item {
        id: ringsArea
        anchors.left: labelBox.right
        anchors.leftMargin: 14
        anchors.right: parent.right
        anchors.rightMargin: 16
        anchors.top: parent.top
        anchors.bottom: parent.bottom

        readonly property real contentWidth: root.claudeRingSize + root.codexRingSize + root.weeklyRingSize
        readonly property real gap: Math.max(0, (width - contentWidth) / 6)

        Row {
            anchors.left: parent.left
            anchors.leftMargin: ringsArea.gap
            anchors.verticalCenter: parent.verticalCenter
            spacing: ringsArea.gap * 2

            // Claude 5-hour
            Column {
                width: root.claudeRingSize
                spacing: 6

                Item {
                    width: root.claudeRingSize
                    height: root.boxHeight

                    AgentRing {
                        anchors.centerIn: parent
                        size: root.claudeRingSize
                        radius: 17
                        valueColor: Theme.accent
                        value: AgentUsage.ringValue(AgentUsage.claudeSessionPercent)

                        BrandMark {
                            anchors.centerIn: parent
                            brand: "claude"
                            size: 15
                            color: Theme.fg
                        }
                    }
                }

                MonoText {
                    width: root.claudeRingSize
                    horizontalAlignment: Text.AlignHCenter
                    text: AgentUsage.claudeSessionLabel
                    font.letterSpacing: 9 * 0.08
                }
            }

            // Codex 5-hour
            Column {
                width: root.codexRingSize
                spacing: 6

                Item {
                    width: root.codexRingSize
                    height: root.boxHeight

                    AgentRing {
                        anchors.centerIn: parent
                        size: root.codexRingSize
                        radius: 17
                        valueColor: Theme.accentSecondary
                        value: AgentUsage.ringValue(AgentUsage.codexSessionPercent)

                        BrandMark {
                            anchors.centerIn: parent
                            brand: "codex"
                            size: 15
                            color: Theme.fg
                        }
                    }
                }

                MonoText {
                    width: root.codexRingSize
                    horizontalAlignment: Text.AlignHCenter
                    text: AgentUsage.codexSessionLabel
                    font.letterSpacing: 9 * 0.08
                }
            }

            // Weekly double ring: outer = Claude, inner = Codex
            Column {
                width: root.weeklyRingSize
                spacing: 6

                Item {
                    width: root.weeklyRingSize
                    height: root.boxHeight

                    Item {
                        anchors.centerIn: parent
                        width: root.weeklyRingSize
                        height: root.weeklyRingSize

                        AgentRing {
                            anchors.fill: parent
                            size: root.weeklyRingSize
                            radius: 15
                            valueColor: Theme.accentSecondary
                            value: AgentUsage.ringValue(AgentUsage.codexWeeklyPercent)
                        }

                        AgentRing {
                            anchors.fill: parent
                            size: root.weeklyRingSize
                            radius: 22
                            valueColor: Theme.accent
                            value: AgentUsage.ringValue(AgentUsage.claudeWeeklyPercent)

                            Icon {
                                anchors.centerIn: parent
                                name: "calendar"
                                size: 13
                                strokeWidth: 1.5
                                color: Theme.fg
                            }
                        }
                    }
                }

                MonoText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: AgentUsage.weeklyLabel
                    font.letterSpacing: 9 * 0.08
                }
            }
        }
    }
}
