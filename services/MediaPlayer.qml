pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import qs.common

/**
 * The media player the shell shows: the one that is playing, else the last
 * one that played, else the first in the list. Media.qml (Home) and
 * MediaTab.qml only read this. The choice follows player changes and needs
 * no timer. Only the play position needs a 1 s timer, because Mpris does not
 * push the position while a track plays. That timer runs only while a view is
 * visible (`viewers` > 0) and a track plays. When a view opens, the current player and position
 * are read at once, so a change made while all views were hidden shows right.
 */
Singleton {
    id: root

    /** How many views are visible now (see WhileVisible.qml). */
    property int viewers: 0

    property var activePlayer: null
    property string lastPlayingId: ""

    /** Play position in seconds, as shown. */
    property real displayPosition: 0

    /** True while the user drags the seek bar; the position is then not overwritten. */
    property bool seeking: false

    readonly property bool isPlaying: activePlayer !== null && activePlayer.playbackState === MprisPlaybackState.Playing

    /** Moves the play position to `seconds` (seek bar). */
    function seekTo(seconds: real): void {
        if (!root.activePlayer) return;
        root.displayPosition = seconds;
        root.activePlayer.position = seconds;
    }

    function choosePlayer() {
        const list = Mpris.players.values;
        for (let i = 0; i < list.length; i++) {
            if (list[i].playbackState === MprisPlaybackState.Playing) {
                root.lastPlayingId = String(list[i].uniqueId);
                return list[i];
            }
        }
        if (root.lastPlayingId !== "") {
            for (let i = 0; i < list.length; i++) {
                if (String(list[i].uniqueId) === root.lastPlayingId)
                    return list[i];
            }
        }
        return list.length > 0 ? list[0] : null;
    }

    /** Picks the player again; a new player resets the position to its own. */
    function refreshPlayer() {
        const chosen = root.choosePlayer();
        if (chosen === root.activePlayer) return;
        root.activePlayer = chosen;
        root.displayPosition = chosen ? chosen.position : 0;
    }

    function refreshPosition() {
        if (root.activePlayer && !root.seeking)
            root.displayPosition = root.activePlayer.position;
    }

    onViewersChanged: {
        if (viewers !== 1) return;
        root.refreshPlayer();
        root.refreshPosition();
    }

    // Keeps the choice current: a player starts or stops, appears or leaves.
    Instantiator {
        model: Mpris.players
        delegate: QtObject {
            required property var modelData
            readonly property int playback: modelData.playbackState
            onPlaybackChanged: root.refreshPlayer()
        }
        onObjectAdded: root.refreshPlayer()
        onObjectRemoved: root.refreshPlayer()
    }

    Component.onCompleted: root.refreshPlayer()

    Timer {
        interval: 1000
        running: root.viewers > 0 && root.isPlaying
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refreshPosition()
    }

    // A seek or a track change moves the position at once.
    Connections {
        target: root.activePlayer
        function onPositionChanged() { root.refreshPosition(); }
        function onTrackTitleChanged() {
            if (root.activePlayer) root.displayPosition = root.activePlayer.position;
        }
    }
}
