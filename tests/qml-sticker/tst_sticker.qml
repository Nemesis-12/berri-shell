import QtQuick
import QtQuick.Window
import QtTest
import Quickshell.Io
import qs.tabs.home

// Runs the real Home sticker cell on a screen with scale 2 (see sticker-sharp.test.mjs).
Item {
    id: host
    width: 400
    height: 400

    Sticker { id: sticker; width: 250; height: 300; restSize: Qt.size(250, 300) }

    TestCase {
        name: "StickerSharp"
        when: windowShown

        // The cell made a copy at its own size and shows it at the same size in image pixels.
        function test_cell_copy_and_image_use_the_displayed_size_times_the_screen_scale() {
            compare(Screen.devicePixelRatio, 2);
            const copy = () => ProcessLog.commands.filter(c => c.some(part => String(part).endsWith("sticker-display-copy.sh")))[0];
            tryVerify(() => copy() !== undefined);
            compare(copy().slice(2), [
                "/home/tester/.config/berri-shell/sticker.png",
                "/home/tester/.config/berri-shell/sticker-display-500x600.png",
                "500",
                "600"
            ]);
            tryVerify(() => sticker.stickerSource.length > 0);
            const picture = findChild(sticker, "stickerPicture").item;
            verify(picture !== null, "The cell loads its picture");
            tryVerify(() => picture.source.toString().indexOf("sticker-display-500x600.png") >= 0);
            compare(picture.sourceSize, Qt.size(500, 600));
            compare(picture.mipmap, true);
        }
    }
}
