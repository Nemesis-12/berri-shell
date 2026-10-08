import QtQuick
import Quickshell.Services.Pipewire
import qs.common
import qs.services
import qs.tabs.home

/**
 * Row of up to three output devices (Pipewire sinks) under the album art.
 * A click on a tile makes that sink the default output. The tab sets
 * `x`, `y`, `width` and `height`.
 */
Row {
    id: root

    spacing: 1

    readonly property var outputs: Pipewire.nodes.values.filter(n => n.isSink && !n.isStream && n.audio).slice(0, 3)
    readonly property var defaultSink: Pipewire.defaultAudioSink

    PwObjectTracker {
        objects: root.outputs.concat(root.defaultSink ? [root.defaultSink] : [])
    }

    function outputKind(node) {
        const text = (node.name + " " + node.description + " " + node.nickname).toLowerCase();
        if (/headphone|headset|bluez|bluetooth/.test(text)) return "HEADPHONES";
        if (/hdmi|displayport|display port/.test(text)) return "HDMI";
        if (/speaker|analog|built-in|hd audio/.test(text)) return "SPEAKERS";
        return "OUTPUT";
    }

    function outputIcon(kind) {
        return kind === "HEADPHONES" ? "headphones" : kind === "HDMI" ? "monitor" : "volume-2";
    }

    Repeater {
        model: 3

        Item {
            id: slot
            required property int index
            readonly property var node: root.outputs[index] || null
            readonly property string kind: node ? root.outputKind(node) : ""

            width: (parent.width - 2 * root.spacing) / 3
            height: parent.height

            Rectangle {
                anchors.fill: parent
                color: Theme.card
                visible: !slot.node
            }

            MediaTile {
                id: deviceTile
                anchors.fill: parent
                visible: slot.node !== null
                on: slot.node !== null && slot.node === root.defaultSink
                onClicked: Pipewire.preferredDefaultAudioSink = slot.node

                Icon {
                    x: 14
                    y: 12
                    name: root.outputIcon(slot.kind)
                    size: 18
                    strokeWidth: 1.6
                    color: deviceTile.iconColor
                }

                Column {
                    x: 14
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 14
                    width: parent.width - 28
                    spacing: 5

                    MonoText {
                        width: parent.width
                        text: slot.kind
                        color: deviceTile.labelColor
                        font.pixelSize: 10
                        font.letterSpacing: 1.2
                        lineHeightMode: Text.FixedHeight
                        lineHeight: 10
                        height: 10
                        elide: Text.ElideRight
                    }

                    Text {
                        textFormat: Text.PlainText
                        width: parent.width
                        text: slot.node ? (slot.node.nickname || slot.node.description) : ""
                        color: deviceTile.subColor
                        font.family: Theme.condensed
                        font.weight: Font.Medium
                        font.pixelSize: 12
                        lineHeightMode: Text.FixedHeight
                        lineHeight: 12
                        height: 12
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }
}
