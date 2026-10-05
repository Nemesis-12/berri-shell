import QtQuick
import QtTest
import Quickshell.Io
import qs.common

// SavedState with a fake disk: load results, failed writes and the backup before a write.
TestCase {
    id: tests
    name: "SavedState"
    when: windowShown

    readonly property string file: "/home/tester/.local/state/berri-shell/theme.json"
    Component { id: stateComponent; SavedState { name: "theme"; defaults: ({ a: 0 }); waitMs: 5 } }
    SignalSpy { id: failures; signalName: "saveFailed" }
    SignalSpy { id: successes; signalName: "saved" }

    function init() { Disk.reset(); }

    // Creates the state after the disk holds the test data, and waits for the folder step.
    function open() {
        var state = createTemporaryObject(stateComponent, tests);
        failures.target = state;
        successes.target = state;
        failures.clear();
        successes.clear();
        tryCompare(state, "folderExists", true);
        return state;
    }

    function writes() { return Disk.events.filter(e => e.kind === "write"); }

    function test_load_results_are_separate() {
        compare(open().loadResult, "missing");
        Disk.reset();
        Disk.files[file] = '{"a": 1}';
        var good = open();
        compare(good.loadResult, "ok");
        Disk.reset();
        Disk.files[file] = "{broken";
        compare(open().loadResult, "invalid");
        Disk.reset();
        Disk.files[file] = "[1";
        Disk.unreadable[file] = true;
        compare(open().loadResult, "unreadable");
    }

    function test_missing_file_loads_defaults_and_first_save_needs_no_backup() {
        var state = open();
        var got = null;
        state.loaded.connect(v => got = v);
        state.save({ a: 2 });
        tryCompare(successes, "count", 1);
        compare(Disk.files[file], JSON.stringify({ a: 2 }, null, 2));
        compare(Disk.files[file + ".bak"], undefined);
        compare(state.hasWaitingWrite, false);
    }

    function test_denied_write_reports_failure_and_stays_pending() {
        var state = open();
        Disk.unwritable[file] = true;
        state.save({ a: 3 });
        tryCompare(failures, "count", 1);
        compare(failures.signalArguments[0][0], "Permission denied");
        compare(state.saveError, "Permission denied");
        compare(state.hasWaitingWrite, true);
        compare(successes.count, 0);
        // The next try writes the same pending change.
        Disk.unwritable = ({});
        state.writeWaiting();
        tryCompare(successes, "count", 1);
        compare(state.hasWaitingWrite, false);
        compare(state.saveError, "");
        compare(Disk.files[file], JSON.stringify({ a: 3 }, null, 2));
    }

    function test_broken_json_is_backed_up_before_the_first_replacement() {
        Disk.files[file] = '{"a": 1, broken';
        var state = open();
        compare(state.loadResult, "invalid");
        state.save({ a: 4 });
        tryCompare(successes, "count", 1);
        compare(Disk.files[file + ".bak"], '{"a": 1, broken');
        // The backup command ran before the file was written.
        var order = Disk.events.filter(e => e.kind === "write" || (e.kind === "run" && e.value[1].indexOf("backup-saved.sh") >= 0));
        compare(order.map(e => e.kind), ["run", "write"]);
        compare(order[0].value[2], file);
    }

    function test_failed_backup_stops_the_replacement_and_keeps_the_change_pending() {
        Disk.files[file] = "old";
        Disk.failBackup = true;
        var state = open();
        state.save({ a: 5 });
        tryCompare(failures, "count", 1);
        compare(failures.signalArguments[0][0], "Backup failed");
        compare(writes().length, 0);
        compare(Disk.files[file], "old");
        compare(state.hasWaitingWrite, true);
    }

    function test_save_during_a_write_is_written_after_it() {
        var state = open();
        state.save({ a: 6 });
        tryVerify(() => writes().length === 1);
        state.save({ a: 7 });
        tryCompare(successes, "count", 2);
        compare(Disk.files[file], JSON.stringify({ a: 7 }, null, 2));
        compare(state.hasWaitingWrite, false);
    }
}
