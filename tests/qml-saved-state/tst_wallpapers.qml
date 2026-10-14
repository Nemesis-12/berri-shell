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
    property var addResults: []

    function init() { Disk.reset(); addResults = []; }
    function initTestCase() {
        Wallpapers.addFinished.connect(path => tests.addResults = tests.addResults.concat([path]));
    }

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

    function test_rapid_removals_delete_every_library_copy() {
        var paths = [dir + "/a.png", dir + "/b.png", dir + "/c.png"];
        Wallpapers.library = paths.slice();

        for (var i = 0; i < paths.length; i++) Wallpapers.remove(paths[i]);

        tryVerify(() => deletes().length === paths.length);
        compare(deletes(), paths.map(path => ["rm", "-f", "--", path]));
    }

    function test_adds_requested_during_a_copy_are_both_kept() {
        var first = "/tmp/berri-wallpaper-test/first.png";
        var second = "/tmp/berri-wallpaper-test/second.png";
        Wallpapers.add(first);
        Wallpapers.add(second);

        tryVerify(() => addResults.length === 2);
        var added = Disk.commands().filter(command => command[1]
            && command[1].endsWith("add-wallpaper.sh"));
        compare(added.length, 2);
        compare(added.map(command => command[2]), [first, second]);
        compare(addResults, [dir + "/first.png", dir + "/second.png"]);
        compare(Wallpapers.library, [dir + "/first.png", dir + "/second.png"]);
    }
}
