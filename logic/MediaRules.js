.pragma library

// Rules for the media player that the Home and Media views share. The
// MediaPlayer service calls these; the views read the service only.

// Longest track length (seconds) that counts as real. Players send huge
// numbers (for example 2^63 microseconds) for streams without a length.
var MAX_SECONDS = 100 * 3600;

function usable(seconds) {
    return typeof seconds === "number" && isFinite(seconds) && seconds >= 0 && seconds <= MAX_SECONDS;
}

/** Track length in seconds, or 0 when the length is unknown, zero or not believable. */
function knownLength(player) {
    if (!player || !player.lengthSupported) return 0;
    return usable(player.length) ? player.length : 0;
}

/** Play position in seconds, or -1 when the player does not report it or the value is not believable. */
function knownPosition(player, seconds) {
    return player && player.positionSupported && usable(seconds) ? seconds : -1;
}

/** A seek bar works only with a known length. */
function canSeek(player) {
    return !!player && player.canSeek && player.positionSupported && knownLength(player) > 0;
}

function canShuffle(player) {
    return !!player && player.shuffleSupported && player.canControl;
}

function canRepeat(player) {
    return !!player && player.loopSupported && player.canControl;
}

/** "1:00 / 3:00" with a known length, "1:00" with only a position, "" with neither. */
function timeText(position, length) {
    if (position < 0) return "";
    var total = Math.floor(position);
    var text = Math.floor(total / 60) + ":" + (total % 60 < 10 ? "0" : "") + (total % 60);
    if (length <= 0) return text;
    var end = Math.floor(length);
    return text + " / " + Math.floor(end / 60) + ":" + (end % 60 < 10 ? "0" : "") + (end % 60);
}

/**
 * Picks the player to show: the first one that plays, else the remembered
 * one (the player that played last) if it is still in the list, else the
 * first. Returns { player, remembered }; the caller stores `remembered`.
 * Players are compared as objects: a track id is not a player id.
 */
function choosePlayer(players, remembered, playingState) {
    for (var i = 0; i < players.length; i++) {
        if (players[i].playbackState === playingState)
            return { player: players[i], remembered: players[i] };
    }
    // A Quickshell player list is not a real Array, so no indexOf here.
    for (var j = 0; j < players.length; j++) {
        if (remembered && players[j] === remembered)
            return { player: remembered, remembered: remembered };
    }
    return { player: players.length > 0 ? players[0] : null, remembered: null };
}
