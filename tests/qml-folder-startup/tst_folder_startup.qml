import QtQuick
import QtTest
import Quickshell.Io
import qs.services

// Starts the real folder users with a fake disk. No desktop shell runs.
TestCase {
    id: tests
    name: "FolderStartup"
    when: windowShown

    // Reading the library path also loads its saved settings.
    readonly property string wallpapers: Wallpapers.wallpapersDir
    CalendarFiles { id: calendar; folder: "/home/tester/.local/share/berri-shell/calendar"; active: true }
    Component { id: settings; SavedState { waitMs: 5 } }

    function folderCommands() {
        return Disk.commands().filter(command => command[0] === "mkdir" || command[0] === "chmod"
            || String(command[1]).endsWith("private-folder.sh"));
    }

    function test_required_roots_are_created_once_for_all_saved_files() {
        const states = [];
        for (let i = 0; i < 8; i++) states.push(createTemporaryObject(settings, tests, { name: "settings" + i }));
        for (const state of states) tryCompare(state, "folderExists", true);
        tryCompare(calendar, "folderReady", true);
        const commands = folderCommands();
        // The runner checks these real commands on temporary files with known permissions.
        console.log("STARTUP_FOLDER_COMMANDS " + JSON.stringify(commands));
        for (const command of commands) {
            verify(command[0] !== "chmod", JSON.stringify(command));
            verify(!String(command[1]).endsWith("private-folder.sh"), JSON.stringify(command));
        }
        verify(commands.length <= 3, JSON.stringify(commands));
        const folders = [].concat.apply([], commands.map(command => command.slice(command.indexOf("--") + 1)));
        compare(folders.slice().sort(), [
            "/home/tester/.local/state/berri-shell",
            "/home/tester/.local/share/berri-shell/calendar",
            "/home/tester/.local/share/berri-shell/calendar/subscriptions",
            "/home/tester/.local/share/berri-shell/wallpapers"
        ].sort());
        // A later saved file uses the ready folder without starting another process.
        const later = createTemporaryObject(settings, tests, { name: "later" });
        tryCompare(later, "folderExists", true);
        compare(folderCommands().length, commands.length);
        later.save({ enabled: true });
        tryVerify(() => Disk.files[later.folder + "/later.json"] !== undefined);
        compare(JSON.parse(Disk.files[later.folder + "/later.json"]), { enabled: true });
    }
}
