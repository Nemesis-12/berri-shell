import QtQuick
import QtTest
import Quickshell.Io
import qs.services

// Removing a wallpaper deletes only our own copy.
TestCase {
    id: tests
    name: "WallpaperRemove"
    when: windowShown

    readonly property string dir: "/home/tester/.local/share/berri-shell/wallpapers"

    function init() { Disk.reset(); }

    // Delete commands that were started.
    function deletes() { return Disk.commands().filter(c => c[0] === "rm"); }

    function test_only_a_file_inside_the_library_folder_is_deleted() {
        var inside = dir + "/a.png";
        var bad = ["/home/tester/outside.png", dir, dir + "/", dir + "/../outside.png", dir + "/link-to-outside/x.png"];
        Wallpapers.library = [inside].concat(bad);
        for (var i = 0; i < bad.length; i++) {
            Wallpapers.remove(bad[i]);
            wait(20);
            compare(deletes().length, 0, bad[i]);
        }
        Wallpapers.remove(inside);
        tryCompare(Disk.commands().filter(c => c[0] === "rm"), "length", 1);
        compare(deletes()[0], ["rm", "-f", "--", inside]);
        // The unsafe entries still leave the saved list when the user removes them.
        compare(Wallpapers.library.length, 0);
    }
}
