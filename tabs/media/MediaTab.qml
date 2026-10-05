import QtQuick
import QtQuick.Window
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import "../../logic/ArtUrl.js" as ArtUrl
import "../../logic/PixelGrid.js" as PixelGrid
import "../../logic/Times.js" as Times
import qs.common
import qs.services
import qs.tabs.home

/**
 * Media tab body (mock 5C SPINE, Berri Media v2.dc.html): album art with the
 * output devices under it, the big title and time readouts, shuffle/repeat,
 * a transport tile row and a full-height volume meter. 1px gaps show the
 * Theme.border backdrop. Data: Mpris (player choice in MediaPlayer.qml) and
 * Pipewire (output devices and the default output volume). Lyrics and queue
 * have no Mpris source, so the mock has none of them either.
 */
Item {
    id: root

    readonly property real dpr: PixelGrid.dpr(Screen.devicePixelRatio)

    readonly property int gap: 1
    readonly property int artSize: 363
    readonly property int volumeWidth: 92
    readonly property int middleWidth: width - artSize - volumeWidth - 2 * gap
    readonly property int middleX: artSize + gap

    // The player and its play position come from MediaPlayer; this view only reads them.
    readonly property var activePlayer: MediaPlayer.activePlayer
    readonly property real displayPosition: MediaPlayer.displayPosition
    WhileVisible { service: MediaPlayer }

    // While the seek bar is dragged, the shown position is not overwritten.
    WhileVisible { service: MediaPlayer; counter: "seekers"; when: scrub.pressed }

    readonly property bool hasPlayer: activePlayer !== null
    readonly property bool isPlaying: MediaPlayer.isPlaying
    readonly property string titleText: MediaPlayer.titleText
    readonly property string subtitleText: {
        if (!hasPlayer) return "";
        const parts = [];
        if (activePlayer.trackArtist) parts.push(activePlayer.trackArtist);
        if (activePlayer.trackAlbum) parts.push(activePlayer.trackAlbum);
        return parts.join(" · ").toUpperCase();
    }
    readonly property string artUrl: ArtUrl.safeArtUrl(hasPlayer ? activePlayer.trackArtUrl : "")
    readonly property real length: hasPlayer ? activePlayer.length : 0
    readonly property bool canSeek: hasPlayer && activePlayer.canSeek && activePlayer.positionSupported

    readonly property real progress: length > 0 ? Math.max(0, Math.min(1, displayPosition / length)) : 0

    // --- Output devices and volume (Pipewire). ---
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

    Rectangle {
        anchors.fill: parent
        color: Theme.border
    }

    // ---------- Left column: art and output devices ----------
    Rectangle {
        id: art
        x: 0
        y: 0
        width: root.artSize
        height: root.artSize
        color: Theme.raised

        Icon {
            anchors.centerIn: parent
            name: "disc-3"
            size: 28
            strokeWidth: 1.5
            color: Theme.dim
            visible: root.artUrl === ""
        }

        AlbumArt {
            anchors.fill: parent
            artUrl: root.artUrl
            dpr: root.dpr
        }

    }

    Row {
        x: 0
        y: root.artSize + root.gap
        width: root.artSize
        height: root.height - y
        spacing: root.gap

        Repeater {
            model: 3

            Item {
                id: slot
                required property int index
                readonly property var node: root.outputs[index] || null
                readonly property string kind: node ? root.outputKind(node) : ""

                width: (parent.width - 2 * root.gap) / 3
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

    // ---------- Middle column ----------
    // Now playing card.
    Rectangle {
        x: root.middleX
        y: 0
        width: root.middleWidth
        height: 150
        color: Theme.card

        SideLabel {
            x: 12
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 16
            text: "NOW PLAYING"
        }

        MediaTitle {
            x: 12 + 9 + 12 - bleed
            width: parent.width - x - 16
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 16 + 10 + 10
            text: root.titleText
            playing: MediaPlayer.isPlaying
        }

        MonoText {
            x: 12 + 9 + 12
            width: parent.width - x - 16
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 16
            text: root.subtitleText
            color: Theme.dim
            font.pixelSize: 10
            font.letterSpacing: 1.4
            lineHeightMode: Text.FixedHeight
            lineHeight: 10
            elide: Text.ElideRight
        }
    }

    // Time card.
    Rectangle {
        x: root.middleX
        y: 151
        width: root.middleWidth
        height: 150
        color: Theme.card

        SideLabel {
            x: 12
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 14
            text: "TIME"
        }

        Item {
            id: readout
            x: 12 + 9 + 12
            width: parent.width - x - 16
            height: 61
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 14 + 14 + 14

            Text {
                textFormat: Text.PlainText
                id: elapsed
                width: implicitWidth
                height: 61
                text: Times.minutesSeconds(root.displayPosition)
                color: Theme.fg
                font.family: Theme.condensed
                font.weight: Font.Medium
                font.pixelSize: 76
                font.letterSpacing: -2.28
                lineHeightMode: Text.FixedHeight
                lineHeight: 61
                verticalAlignment: Text.AlignVCenter
            }

            MonoText {
                x: elapsed.width + 8
                anchors.baseline: elapsed.baseline
                anchors.baselineOffset: -19
                text: "/ " + Times.minutesSeconds(root.length)
                color: Theme.dim
                font.pixelSize: 12
            }
        }

        // Scrubber: 4px track, 12px square handle. Press or drag to seek.
        Item {
            id: scrub
            x: readout.x
            width: readout.width
            height: 14
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 14

            property bool pressed: seekArea.pressed

            Rectangle {
                id: track
                anchors.left: parent.left
                anchors.right: parent.right
                y: 8
                height: 4
                color: Theme.border

                Rectangle {
                    id: trackFill
                    height: parent.height
                    width: parent.width * root.progress
                    color: Theme.accentLight

                    Behavior on width {
                        enabled: root.isPlaying && !scrub.pressed
                        NumberAnimation { duration: 1000; easing.type: Easing.Linear }
                    }
                }

                Rectangle {
                    x: trackFill.width - width / 2
                    anchors.verticalCenter: parent.verticalCenter
                    width: 12
                    height: 12
                    color: Theme.fg
                }
            }

            MouseArea {
                id: seekArea
                anchors.fill: parent
                anchors.topMargin: -6
                anchors.bottomMargin: -6
                enabled: root.canSeek
                cursorShape: root.canSeek ? Qt.PointingHandCursor : Qt.ArrowCursor

                function seek(mouseX) {
                    const ratio = Math.max(0, Math.min(1, mouseX / width));
                    MediaPlayer.seekTo(ratio * root.length);
                }
                onPressed: mouse => seek(mouse.x)
                onPositionChanged: mouse => { if (pressed) seek(mouse.x); }
            }
        }
    }

    // Shuffle and repeat.
    Row {
        x: root.middleX
        y: 302
        width: root.middleWidth
        height: 64
        spacing: root.gap

        MediaTile {
            id: shuffleTile
            width: (parent.width - root.gap) / 2
            height: parent.height
            available: root.hasPlayer && root.activePlayer.shuffleSupported
            on: root.hasPlayer && root.activePlayer.shuffle
            onClicked: root.activePlayer.shuffle = !root.activePlayer.shuffle

            Row {
                x: 14
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10

                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "shuffle"
                    size: 17
                    strokeWidth: 1.6
                    color: shuffleTile.iconColor
                }

                MonoText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "SHUFFLE"
                    color: shuffleTile.labelColor
                    font.pixelSize: 10
                    font.letterSpacing: 1.2
                }
            }
        }

        MediaTile {
            id: repeatTile
            width: (parent.width - root.gap) / 2
            height: parent.height
            available: root.hasPlayer && root.activePlayer.loopSupported
            on: root.hasPlayer && root.activePlayer.loopState !== MprisLoopState.None

            // Off, then all tracks, then this track, then off again.
            onClicked: {
                const state = root.activePlayer.loopState;
                root.activePlayer.loopState = state === MprisLoopState.None ? MprisLoopState.Playlist
                    : state === MprisLoopState.Playlist ? MprisLoopState.Track : MprisLoopState.None;
            }

            Row {
                x: 14
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10

                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: root.hasPlayer && root.activePlayer.loopState === MprisLoopState.Track ? "repeat-1" : "repeat"
                    size: 17
                    strokeWidth: 1.6
                    color: repeatTile.iconColor
                }

                MonoText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "REPEAT"
                    color: repeatTile.labelColor
                    font.pixelSize: 10
                    font.letterSpacing: 1.2
                }
            }
        }
    }

    // Transport: previous, play/pause, next.
    Item {
        id: transport
        x: root.middleX
        y: 367
        width: root.middleWidth
        height: root.height - y

        readonly property real unit: (width - 2 * root.gap) / 3.4

        Row {
            spacing: root.gap

            Repeater {
                model: [
                    { kind: "prev", icon: "skip-back", label: "PREV", span: 1 },
                    { kind: "play", icon: "", label: "", span: 1.4 },
                    { kind: "next", icon: "skip-forward", label: "NEXT", span: 1 }
                ]

                Item {
                    id: cell
                    required property var modelData
                    readonly property bool isPlay: modelData.kind === "play"
                    readonly property bool usable: root.hasPlayer && (isPlay ? root.activePlayer.canTogglePlaying
                        : modelData.kind === "prev" ? root.activePlayer.canGoPrevious : root.activePlayer.canGoNext)

                    width: transport.unit * modelData.span
                    height: transport.height
                    opacity: usable ? 1 : 0.4

                    Fade on opacity { duration: Theme.stateMs }

                    Rectangle {
                        anchors.fill: parent
                        color: cell.isPlay ? (cellMouse.containsMouse && cell.usable ? Qt.lighter(Theme.accentLight, 1.12) : Theme.accentLight)
                            : (cellMouse.containsMouse && cell.usable ? Theme.raised : Theme.card)

                        ColorFade on color {}
                    }

                    Column {
                        anchors.centerIn: parent
                        spacing: 9

                        Item {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: cell.isPlay ? 22 : 17
                            height: width

                            Icon {
                                anchors.fill: parent
                                name: cell.isPlay ? "pause" : cell.modelData.icon
                                size: parent.width
                                strokeWidth: cell.isPlay ? 2.4 : 2
                                color: cell.isPlay ? Theme.onAccent : Theme.fg2
                                opacity: !cell.isPlay || root.isPlaying ? 1 : 0

                                Fade on opacity { duration: Theme.stateMs }
                            }

                            Icon {
                                anchors.fill: parent
                                visible: cell.isPlay
                                name: "play"
                                size: parent.width
                                strokeWidth: 2.4
                                color: Theme.onAccent
                                opacity: root.isPlaying ? 0 : 1

                                Fade on opacity { duration: Theme.stateMs }
                            }
                        }

                        MonoText {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: cell.isPlay ? (root.isPlaying ? "PAUSE" : "PLAY") : cell.modelData.label
                            color: cell.isPlay ? Theme.onAccent : Theme.dim
                            font.weight: cell.isPlay ? Font.DemiBold : Font.Medium
                            font.pixelSize: 9
                            font.letterSpacing: 1.26
                        }
                    }

                    MouseArea {
                        id: cellMouse
                        anchors.fill: parent
                        enabled: cell.usable
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (cell.isPlay) root.activePlayer.togglePlaying();
                            else if (cell.modelData.kind === "prev") root.activePlayer.previous();
                            else root.activePlayer.next();
                        }
                    }
                }
            }
        }
    }

    // ---------- Volume meter ----------
    VolumeFader {
        x: root.middleX + root.middleWidth + root.gap
        y: 0
        width: root.volumeWidth
        height: root.height
        expanded: true
    }
}
