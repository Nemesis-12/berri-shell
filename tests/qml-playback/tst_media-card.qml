import QtQuick
import QtTest
import qs.common
import qs.services
import qs.tabs.home
import qs.tabs.media
import Quickshell.Services.Mpris

// Tests the media card rules in Home and Media: length, seek, player choice, permissions and album art.
Item {
    width: 1000
    height: 640

    Component {
        id: fakePlayer
        QtObject {
            property string uniqueId: "0"
            property int playbackState: MprisPlaybackState.Paused
            property string trackTitle: "Track"
            property string trackArtist: ""
            property string trackAlbum: ""
            property string trackArtUrl: ""
            property bool lengthSupported: true
            property real length: 100
            property real position: 10
            property bool canSeek: true
            property bool positionSupported: true
            property bool canControl: true
            property bool shuffleSupported: true
            property bool shuffle: false
            property int loopState: MprisLoopState.None
            property bool loopSupported: true
            property bool canTogglePlaying: true
            property bool canGoPrevious: true
            property bool canGoNext: true
            property int toggles: 0
            function togglePlaying() {
                toggles += 1;
                playbackState = playbackState === MprisPlaybackState.Playing ? MprisPlaybackState.Paused : MprisPlaybackState.Playing;
            }
            function previous() {}
            function next() {}
        }
    }

    MediaTab { id: media; width: 1000; height: 430 }
    Media { id: homeMedia; width: 233; height: 430 }
    MediaTimeCard {
        id: timeCard
        width: 400
        displayPosition: -1
        length: 180
        progress: 0
        isPlaying: false
        canSeek: false
    }
    AlbumArt { id: art; x: 400; y: 450; width: 100; height: 100; dpr: 1 }

    TestCase {
        name: "MediaCard"
        when: windowShown

        // Finds a descendant by objectName.
        function find(item, name) {
            for (let child of item.children) {
                if (child.objectName === name) return child;
                const found = find(child, name);
                if (found) return found;
            }
            return null;
        }

        function setPlayers(list) {
            Mpris.players.values = list;
            Mpris.players.clear();
            for (let p of list) Mpris.players.append({ modelData: p });
        }

        function cleanup() {
            setPlayers([]);
            art.artUrl = "";
        }

        // A huge length gives no total, and the Home time stays left of the buttons.
        function test_huge_length_shows_no_total_and_no_overlap() {
            const p = createTemporaryObject(fakePlayer, this, { playbackState: MprisPlaybackState.Playing, length: 92233720368054, position: 10 });
            setPlayers([p]);
            tryCompare(MediaPlayer, "activePlayer", p);
            compare(MediaPlayer.length, 0);
            compare(MediaPlayer.timeText, "0:10");
            const label = find(homeMedia, "timeLabel");
            const buttons = find(homeMedia, "transport");
            verify(label.mapToItem(homeMedia, label.width, 0).x <= buttons.mapToItem(homeMedia, 0, 0).x,
                "time label ends before the buttons");
        }

        // A long text never reaches the buttons, even with a wide, known length.
        function test_time_label_is_bounded() {
            const p = createTemporaryObject(fakePlayer, this, { playbackState: MprisPlaybackState.Playing, length: 359000, position: 359000 });
            setPlayers([p]);
            tryCompare(MediaPlayer, "activePlayer", p);
            const label = find(homeMedia, "timeLabel");
            const buttons = find(homeMedia, "transport");
            verify(label.mapToItem(homeMedia, label.width, 0).x <= buttons.mapToItem(homeMedia, 0, 0).x);
        }

        // With an unknown position the card shows no total, even when the length is known.
        function test_total_needs_a_known_position() {
            const total = find(timeCard, "total");
            timeCard.displayPosition = -1;
            timeCard.length = 180;
            compare(total.visible, false);
            timeCard.displayPosition = 5;
            compare(total.visible, true);
            timeCard.length = 0;
            compare(total.visible, false);
        }

        // Seek is off, and does nothing, when the length is zero.
        function test_seek_needs_a_length() {
            const p = createTemporaryObject(fakePlayer, this, { playbackState: MprisPlaybackState.Playing, length: 0, position: 12 });
            setPlayers([p]);
            tryCompare(MediaPlayer, "activePlayer", p);
            compare(MediaPlayer.canSeek, false);
            MediaPlayer.seekToRatio(0.5);
            compare(p.position, 12);
            p.length = 100;
            compare(MediaPlayer.canSeek, true);
            MediaPlayer.seekToRatio(0.5);
            compare(p.position, 50);
        }

        // Two players with the same track id: pause acts on the player that played last.
        function test_pause_acts_on_the_remembered_player() {
            const a = createTemporaryObject(fakePlayer, this, { uniqueId: "0" });
            const b = createTemporaryObject(fakePlayer, this, { uniqueId: "0", playbackState: MprisPlaybackState.Playing });
            setPlayers([a, b]);
            tryCompare(MediaPlayer, "activePlayer", b);
            MediaPlayer.togglePlay();
            compare(b.playbackState, MprisPlaybackState.Paused);
            compare(MediaPlayer.activePlayer, b);
            MediaPlayer.togglePlay();
            compare(b.toggles, 2);
            compare(a.toggles, 0);
        }

        // A removed remembered player is forgotten.
        function test_removed_player_is_forgotten() {
            const a = createTemporaryObject(fakePlayer, this);
            const b = createTemporaryObject(fakePlayer, this, { playbackState: MprisPlaybackState.Playing });
            setPlayers([a, b]);
            tryCompare(MediaPlayer, "activePlayer", b);
            setPlayers([a]);
            tryCompare(MediaPlayer, "activePlayer", a);
            compare(MediaPlayer.lastPlayer, null);
        }

        // Shuffle and repeat need the player's control permission.
        function test_shuffle_and_repeat_need_control() {
            const p = createTemporaryObject(fakePlayer, this, { playbackState: MprisPlaybackState.Playing, canControl: false });
            setPlayers([p]);
            tryCompare(MediaPlayer, "activePlayer", p);
            compare(MediaPlayer.canShuffle, false);
            compare(MediaPlayer.canRepeat, false);
            MediaPlayer.toggleShuffle();
            MediaPlayer.cycleRepeat();
            compare(p.shuffle, false);
            compare(p.loopState, MprisLoopState.None);
            p.canControl = true;
            MediaPlayer.toggleShuffle();
            MediaPlayer.cycleRepeat();
            compare(p.shuffle, true);
            compare(p.loopState, MprisLoopState.Playlist);
        }

        // A new art link replaces the old image.
        function test_art_follows_the_track() {
            art.artUrl = Qt.resolvedUrl("art-a.png");
            const front = find(art, "front");
            tryCompare(front, "status", Image.Ready);
            compare(String(front.source), String(Qt.resolvedUrl("art-a.png")));
            art.artUrl = Qt.resolvedUrl("art-b.png");
            tryCompare(front, "source", Qt.resolvedUrl("art-b.png"));
            tryCompare(front, "status", Image.Ready);
        }

        // The fallback shows with no art or a broken link, never in the gap while new art loads.
        function test_fallback_has_no_blank_moment() {
            compare(art.showFallback, true);
            art.artUrl = Qt.resolvedUrl("art-a.png");
            compare(art.showFallback, true);
            const front = find(art, "front");
            tryCompare(front, "status", Image.Ready);
            compare(art.showFallback, false);
            art.artUrl = Qt.resolvedUrl("art-b.png");
            compare(art.showFallback, false);
            tryCompare(front, "status", Image.Ready);
            compare(art.showFallback, false);
            art.artUrl = Qt.resolvedUrl("missing.png");
            tryCompare(art, "showFallback", true);
            art.artUrl = "";
            compare(art.showFallback, true);
        }

        // A broken art link clears the old image and reports the failure.
        function test_failed_art_clears_the_old_image() {
            art.artUrl = Qt.resolvedUrl("art-a.png");
            const front = find(art, "front");
            const back = find(art, "back");
            tryCompare(front, "status", Image.Ready);
            art.artUrl = Qt.resolvedUrl("missing.png");
            tryCompare(art, "failed", true);
            compare(String(back.source), "");
            art.artUrl = Qt.resolvedUrl("art-b.png");
            tryCompare(art, "failed", false);
        }
    }
}
