import QtQuick
import QtTest
import qs.common
import qs.services
import qs.tabs.home
import qs.tabs.media
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris
import Quickshell.Io

// Tests the rendered numbers, fills, and system command boundary offscreen.
Item {
    width: 1000
    height: 640

    QtObject { id: firstAudio; property real volume: 0.4; property bool muted: false }
    QtObject { id: secondAudio; property real volume: 0.2; property bool muted: false }
    QtObject { id: firstSink; property var audio: firstAudio }
    QtObject { id: secondSink; property var audio: secondAudio }
    QtObject {
        id: player
        property string uniqueId: "fixture-player"
        property int playbackState: MprisPlaybackState.Playing
        property string trackTitle: ""
        property string trackArtist: ""
        property string trackAlbum: ""
        property string trackArtUrl: ""
        property real length: 100
        property real position: 0
        property bool canSeek: false
        property bool positionSupported: false
        property bool shuffleSupported: false
        property bool shuffle: false
        property int loopState: MprisLoopState.None
        property bool loopSupported: false
        property bool canTogglePlaying: false
        property bool canGoPrevious: false
        property bool canGoNext: false
    }

    MediaTab { id: media; width: 1000; height: 430 }
    Media { id: homeMedia; visible: false; width: 200; height: 430 }
    Faders { id: home; y: 440; width: 160; height: 190 }
    Faders { id: secondHome; x: 180; y: 440; width: 160; height: 190; visible: false }

    TestCase {
        name: "PlaybackControls"
        when: windowShown

        // Finds the normal-color volume number by its displayed size and position.
        function volumeNumber(view, item) {
            for (let child of item.children) {
                if (child.font && child.color === Theme.fg
                        && child.font.pixelSize === (view === media ? 40 : 22)
                        && child.mapToItem(view, 0, 0).x > view.width / 2)
                    return child;
                const found = volumeNumber(view, child);
                if (found) return found;
            }
            return null;
        }

        // The coordinates are inside the volume track, away from its labels.
        function volumeX(view) {
            return view === media ? view.width - 46 : 120;
        }

        // Home has a 10px inset around its meter. Media fills the view height.
        function volumeY(view, percent) {
            return view === media ? view.height * (1 - percent / 100)
                : 10 + (view.height - 20) * (1 - percent / 100);
        }

        // Restores the system inputs and visible views before each test.
        function init() {
            firstAudio.volume = 0.4;
            secondAudio.volume = 0.2;
            Pipewire.defaultAudioSink = firstSink;
            player.trackTitle = "";
            player.playbackState = MprisPlaybackState.Playing;
            Mpris.players.values = [];
            Mpris.players.clear();
            media.visible = true;
            home.visible = true;
            secondHome.visible = false;
            tryCompare(volumeNumber(media, media), "text", "40");
            tryCompare(volumeNumber(home, home), "text", "40");
        }

        // Releases the fake pointer and restores views after each test.
        function cleanup() {
            // Also release a press if an assertion stopped an interaction early.
            mouseRelease(media, volumeX(media), volumeY(media, 50));
            mouseRelease(home, volumeX(home), volumeY(home, 50));
            media.visible = true;
            home.visible = true;
            secondHome.visible = false;
            Mpris.players.values = [];
            Mpris.players.clear();
        }

        // Runs the same drag checks in Home and Media.
        function test_volume_follows_system_after_drag_data() {
            return [{ tag: "Media", view: media }, { tag: "Home", view: home }];
        }

        // Checks the dragged value and later external updates in the rendered control.
        function test_volume_follows_system_after_drag(data) {
            const view = data.view;
            const number = volumeNumber(view, view);
            mousePress(view, volumeX(view), volumeY(view, 30));
            tryCompare(number, "text", "30");
            firstAudio.volume = 0.6;
            wait(350);
            compare(number.text, "30", "The dragged value stays visible during an external update");
            mouseRelease(view, volumeX(view), volumeY(view, 30));
            tryCompare(number, "text", "60");
            firstAudio.volume = 0.8;
            tryCompare(number, "text", "80");
            wait(Theme.stateMs + 50);
            waitForRendering(view);
            const image = grabImage(view);
            compare(image.pixel(volumeX(view), volumeY(view, 75)),
                    view === media ? Theme.accentLight : Theme.accent,
                    "The fill also follows the external value");

            Pipewire.defaultAudioSink = secondSink;
            tryCompare(number, "text", "20");
            mousePress(view, volumeX(view), volumeY(view, 50));
            tryCompare(number, "text", "50");
            mouseRelease(view, volumeX(view), volumeY(view, 50));
            secondAudio.volume = 0.8;
            tryCompare(number, "text", "80");
            firstAudio.volume = 0.1;
            wait(350);
            compare(number.text, "80", "The old output cannot change the meter");
        }

        // Checks the empty output state and a later output connection.
        function test_volume_without_output_and_after_reconnect() {
            Pipewire.defaultAudioSink = null;
            tryCompare(volumeNumber(media, media), "text", "0");
            mouseClick(media, volumeX(media), volumeY(media, 50));
            tryCompare(volumeNumber(media, media), "text", "0");
            secondAudio.volume = 0.8;
            Pipewire.defaultAudioSink = secondSink;
            tryCompare(volumeNumber(media, media), "text", "80");
            tryCompare(volumeNumber(home, home), "text", "80");
        }

        // Runs the same canceled drag checks in Home and Media.
        function test_volume_resumes_after_canceled_drag_data() {
            return [{ tag: "Media", view: media }, { tag: "Home", view: home }];
        }

        // Checks that hiding a pressed control restores system updates.
        function test_volume_resumes_after_canceled_drag(data) {
            const view = data.view;
            mousePress(view, volumeX(view), volumeY(view, 30));
            tryCompare(volumeNumber(view, view), "text", "30");
            view.visible = false;
            mouseRelease(view, volumeX(view), volumeY(view, 30));
            firstAudio.volume = 0.8;
            view.visible = true;
            tryCompare(volumeNumber(view, view), "text", "80");
        }

        // Checks both views as the active player's title and state change.
        function test_playback_and_title_are_shared() {
            Mpris.players.values = [player];
            Mpris.players.append({ modelData: player });
            tryCompare(MediaPlayer, "activePlayer", player);
            compare(homeMedia.titleText, "Unknown title");
            compare(media.titleText, "Unknown title");
            compare(homeMedia.isPlaying, true);
            compare(media.isPlaying, true);
            player.trackTitle = "A track";
            player.playbackState = MprisPlaybackState.Paused;
            compare(homeMedia.titleText, "A track");
            compare(media.titleText, "A track");
            compare(homeMedia.isPlaying, false);
            compare(media.isPlaying, false);
            Mpris.players.values = [];
            Mpris.players.clear();
            tryCompare(homeMedia, "titleText", "Nothing playing");
            compare(media.titleText, "Nothing playing");
        }

        // Checks shared detection and read commands at the process boundary.
        function test_brightness_has_one_owner_and_stops_hidden_sampling() {
            wait(250);
            ProcessLog.brightness = 40;
            home.visible = false;
            home.visible = true;
            secondHome.visible = true;
            tryCompare(Brightness, "viewers", 2);
            tryCompare(Brightness, "value", 40);
            const detections = ProcessLog.commands.filter(command => command[0] === "sh");
            compare(detections.length, 1);
            compare(ProcessLog.commands.filter(command => command[0] === "brightnessctl")[0],
                    ["brightnessctl", "-m", "-d", "panel"]);
            home.visible = false;
            secondHome.visible = false;
            compare(Brightness.viewers, 0);
            const commandCount = ProcessLog.commands.length;
            wait(2200);
            compare(ProcessLog.commands.length, commandCount);
            ProcessLog.brightness = 80;
            home.visible = true;
            tryCompare(Brightness, "value", 80);
        }

        // Checks the final command and brightness after a slow write.
        function test_brightness_keeps_latest_value_while_write_runs() {
            const commandCount = ProcessLog.commands.length;
            Brightness.setValue(60);
            wait(80);
            Brightness.setValue(65);
            tryCompare(ProcessLog, "brightness", 65);
            compare(Brightness.value, 65);
            const writes = ProcessLog.commands.slice(commandCount).filter(command => command.indexOf("set") >= 0);
            compare(writes, [["brightnessctl", "set", "-d", "panel", "60%"],
                             ["brightnessctl", "set", "-d", "panel", "65%"]]);
        }
    }
}
