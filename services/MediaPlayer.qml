pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import "../logic/MediaRules.js" as MediaRules

/**
 * The media player the shell shows: the one that is playing, else the last
 * one that played, else the first in the list. Media.qml (Home) and
 * MediaTab.qml only read this and call its commands; the rules for length,
 * seek and permissions are in logic/MediaRules.js. The choice follows player
 * changes and needs no timer. Only the play position needs a 1 s timer, because Mpris does not
 * push the position while a track plays. That timer runs only while a view is
 * visible (`viewers` > 0) and a track plays. When a view opens, the current
 * player and position are read at once, so a change made while all views were
 * hidden shows right. When a track pauses, the position is read once more.
 */
Singleton {
    id: root

    /** How many views are visible now (see WhileVisible.qml). */
    property int viewers: 0

    property var activePlayer: null
    /** The player that played last (an object, not a track id). */
    property var lastPlayer: null

    /** Play position in seconds, as shown. */
    property real displayPosition: 0

    /** How many seek bars are being dragged now (see WhileVisible.qml, counter "seekers"). */
    property int seekers: 0

    /** True while the user drags a seek bar; the position is then not overwritten. */
    readonly property bool seeking: seekers > 0

    readonly property bool isPlaying: activePlayer !== null && activePlayer.playbackState === MprisPlaybackState.Playing
    readonly property string titleText: activePlayer ? (activePlayer.trackTitle || "Unknown title") : "Nothing playing"

    /** Track length in seconds; 0 when unknown (live stream) or not believable. */
    readonly property real length: MediaRules.knownLength(activePlayer)

    /** Shown play position in seconds; -1 when the player does not report one. */
    readonly property real shownPosition: MediaRules.knownPosition(activePlayer, displayPosition)

    /** How far the track has played, 0 to 1; 0 when the position or length is unknown. */
    readonly property real progress: MediaRules.progress(shownPosition, length)

    /** "1:00 / 3:00", "1:00" when the length is unknown, "" when nothing is known. */
    readonly property string timeText: MediaRules.timeText(shownPosition, length)

    readonly property bool canSeek: MediaRules.canSeek(activePlayer)
    readonly property bool canShuffle: MediaRules.canShuffle(activePlayer)
    readonly property bool canRepeat: MediaRules.canRepeat(activePlayer)
    readonly property bool canPrevious: activePlayer !== null && activePlayer.canGoPrevious
    readonly property bool canNext: activePlayer !== null && activePlayer.canGoNext
    readonly property bool canTogglePlay: activePlayer !== null && activePlayer.canTogglePlaying
    readonly property bool shuffleOn: activePlayer !== null && activePlayer.shuffle
    readonly property int repeatState: activePlayer !== null ? activePlayer.loopState : MprisLoopState.None

    function previous(): void { if (root.canPrevious) root.activePlayer.previous(); }
    function next(): void { if (root.canNext) root.activePlayer.next(); }
    function togglePlay(): void { if (root.canTogglePlay) root.activePlayer.togglePlaying(); }

    function toggleShuffle(): void {
        if (root.canShuffle) root.activePlayer.shuffle = !root.activePlayer.shuffle;
    }

    /** Off, then all tracks, then this track, then off again. */
    function cycleRepeat(): void {
        if (!root.canRepeat) return;
        const state = root.activePlayer.loopState;
        root.activePlayer.loopState = state === MprisLoopState.None ? MprisLoopState.Playlist
            : state === MprisLoopState.Playlist ? MprisLoopState.Track : MprisLoopState.None;
    }

    /** Moves the play position to `ratio` (0 to 1) of the track length (seek bar). */
    function seekToRatio(ratio: real): void {
        if (!root.canSeek) return;
        const seconds = Math.max(0, Math.min(1, ratio)) * root.length;
        root.displayPosition = seconds;
        root.activePlayer.position = seconds;
    }

    function choosePlayer() {
        const choice = MediaRules.choosePlayer(Mpris.players.values, root.lastPlayer, MprisPlaybackState.Playing);
        root.lastPlayer = choice.remembered;
        return choice.player;
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

    // The timer stops on pause, so read the position once for the last second.
    onIsPlayingChanged: if (!isPlaying && viewers > 0) refreshPosition()

    // A seek or a track change moves the position at once.
    Connections {
        target: root.activePlayer
        function onPositionChanged() { root.refreshPosition(); }
        function onTrackTitleChanged() {
            if (root.activePlayer) root.displayPosition = root.activePlayer.position;
        }
    }
}
