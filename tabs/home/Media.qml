import QtQuick
import QtQuick.Window
import "../../logic/ArtUrl.js" as ArtUrl
import "../../logic/PixelGrid.js" as PixelGrid
import qs.common
import qs.services

/**
 * Media column: the current player's album art, title/artist,
 * a live progress bar and prev/play-pause/next transport buttons, driven
 * by Quickshell's Mpris service. Shows a placeholder art icon and a
 * "Nothing playing" empty state when no player is available.
 */
Item {
    id: root

    /** Output scale of the screen this cell is on; used to decode art at native sharpness. */
    readonly property real dpr: PixelGrid.dpr(Screen.devicePixelRatio)

    // The player and its play position come from MediaPlayer; this view only reads them.
    readonly property var activePlayer: MediaPlayer.activePlayer
    WhileVisible { service: MediaPlayer }

    readonly property bool isPlaying: MediaPlayer.isPlaying
    readonly property string titleText: MediaPlayer.titleText
    readonly property string artistText: activePlayer ? activePlayer.trackArtist.toUpperCase() : ""
    readonly property string artUrl: ArtUrl.safeArtUrl(activePlayer ? activePlayer.trackArtUrl : "")

    // --- Album art, flush and square at the top. ---
    Item {
        id: artArea
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: width

        Rectangle {
            anchors.fill: parent
            color: Theme.raised
        }

        Icon {
            anchors.centerIn: parent
            name: "disc-3"
            size: 28
            strokeWidth: 1.5
            color: Theme.dim
            opacity: root.artUrl === "" || art.failed ? 1 : 0

            Fade on opacity { duration: Theme.stateMs }
        }

        AlbumArt {
            id: art
            anchors.fill: parent
            artUrl: root.artUrl
            dpr: root.dpr
        }

    }

    // --- Title, progress and transport, below the art. ---
    Item {
        id: infoArea
        anchors.top: artArea.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.topMargin: 12
        anchors.bottomMargin: 12
        anchors.leftMargin: 14
        anchors.rightMargin: 14

        Column {
            id: textBlock
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 5

            // lineHeightMode/lineHeight/height pin each line's box to exactly
            // its font size (Qt's default line box is taller than the pixel
            // size), matching Profile's title/uptime rows so the visible
            // glyph top lands 12px below the art, not a few px lower.
            Text {
                textFormat: Text.PlainText
                width: parent.width
                text: root.titleText
                font.family: Theme.condensed
                font.weight: Font.DemiBold
                font.pixelSize: 18
                lineHeightMode: Text.FixedHeight
                lineHeight: 18
                height: 18
                verticalAlignment: Text.AlignVCenter
                color: Theme.fg
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            MonoText {
                width: parent.width
                text: root.artistText
                font.pixelSize: 10
                font.letterSpacing: 1.0
                lineHeightMode: Text.FixedHeight
                lineHeight: 10
                height: 10
                verticalAlignment: Text.AlignVCenter
                color: Theme.dim
                elide: Text.ElideRight
                maximumLineCount: 1
            }
        }

        Rectangle {
            id: progressTrack
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.right: parent.right
            height: 2
            color: Theme.border

            Rectangle {
                height: parent.height
                // Snapped to device pixels, no animation.
                // Redraws only when the snapped width changes.
                width: PixelGrid.snap(parent.width * MediaPlayer.progress, root.dpr)
                color: Theme.accent
            }
        }

        Item {
            id: controlsRow
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: 28

            MonoText {
                objectName: "timeLabel"
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: transportRow.left
                anchors.rightMargin: 8
                text: MediaPlayer.timeText
                elide: Text.ElideRight
                font.pixelSize: 10
                color: Theme.dim
            }

            Row {
                id: transportRow
                objectName: "transport"
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4

                MediaButton {
                    id: prevButton
                    icon: "skip-back"
                    enabled: MediaPlayer.canPrevious
                    onActivated: MediaPlayer.previous()
                }

                MediaButton {
                    id: playButton
                    icon: root.isPlaying ? "pause" : "play"
                    filled: true
                    enabled: MediaPlayer.canTogglePlay
                    onActivated: MediaPlayer.togglePlay()
                }

                MediaButton {
                    id: nextButton
                    icon: "skip-forward"
                    enabled: MediaPlayer.canNext
                    onActivated: MediaPlayer.next()
                }
            }
        }
    }
}
