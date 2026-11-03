import QtQuick
import QtTest
import Quickshell.Io
import qs.services
import "../logic/CalendarCatalog.js" as Catalog

// SavedState with a fake disk: load results, failed writes and the backup before a write.
TestCase {
    id: tests
    name: "SavedState"
    when: windowShown

    readonly property string file: "/home/tester/.local/state/berri-shell/theme.json"
    Component { id: stateComponent; SavedState { name: "theme"; defaults: ({ a: 0 }); waitMs: 5 } }
    SignalSpy { id: failures; signalName: "saveFailed" }
    SignalSpy { id: successes; signalName: "saved" }

    /**
     * A receiver like the shell services: it reads the saved values the moment `loaded` fires
     * and records what it saw. `facts` says whether each list was a real JS array.
     */
    Component {
        id: receiverComponent
        Item {
            property var facts: null
            property var restored: null
            SavedState {
                name: "calendars"
                defaults: ({ calendars: [] })
                waitMs: 5
                onLoaded: values => {
                    parent.facts = {
                        list: Array.isArray(values.calendars),
                        listInObject: Array.isArray(values.nested.list),
                        listInListItem: Array.isArray(values.calendars[0].tags)
                    };
                    parent.restored = Catalog.restoreCalendars("/home/tester/calendar", values);
                }
            }
        }
    }

    readonly property string linkedCalendars: JSON.stringify({
        calendars: [
            { id: "l-one", kind: "link", name: "One", file: "subscriptions/l-one.ics", url: "https://invalid.invalid/one.ics", tags: ["x"] },
            { id: "l-two", kind: "link", name: "Two", file: "subscriptions/l-two.ics", url: "https://invalid.invalid/two.ics" }
        ],
        nested: { list: [1, 2] }
    })

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

    function test_save_after_a_bad_read_keeps_the_last_good_backup() {
        Disk.files[file] = '{"a": 1, broken';
        Disk.files[file + ".bak"] = '{"a": 0}';
        var state = open();
        compare(state.loadResult, "invalid");
        state.save({ a: 4 });
        tryCompare(successes, "count", 1);
        compare(Disk.files[file + ".bak"], '{"a": 0}');
        compare(Disk.files[file], JSON.stringify({ a: 4 }, null, 2));
        // The bad text goes to .bad, not to .bak.
        compare(Disk.files[file + ".bad"], '{"a": 1, broken');
        // After a good save, the next save backs up the good file again.
        state.save({ a: 5 });
        tryCompare(successes, "count", 2);
        compare(Disk.files[file + ".bak"], JSON.stringify({ a: 4 }, null, 2));
    }

    function test_failed_bad_copy_stops_the_save_after_a_bad_read() {
        Disk.files[file] = '{"a": 1, broken';
        Disk.files[file + ".bak"] = '{"a": 0}';
        Disk.failBackup = true;
        var state = open();
        state.save({ a: 4 });
        tryCompare(failures, "count", 1);
        compare(failures.signalArguments[0][0], "Backup failed");
        compare(writes().length, 0);
        compare(Disk.files[file], '{"a": 1, broken');
        compare(Disk.files[file + ".bak"], '{"a": 0}');
        compare(state.hasWaitingWrite, true);
    }

    function test_save_after_an_unreadable_file_keeps_the_last_good_backup() {
        Disk.files[file] = "[1";
        Disk.unreadable[file] = true;
        Disk.files[file + ".bak"] = '{"a": 0}';
        var state = open();
        compare(state.loadResult, "unreadable");
        Disk.unreadable = ({});
        state.save({ a: 4 });
        tryCompare(successes, "count", 1);
        compare(Disk.files[file + ".bak"], '{"a": 0}');
    }

    function test_failed_backup_stops_the_replacement_and_keeps_the_change_pending() {
        Disk.files[file] = '{"a": 1}';
        Disk.failBackup = true;
        var state = open();
        state.save({ a: 5 });
        tryCompare(failures, "count", 1);
        compare(failures.signalArguments[0][0], "Backup failed");
        compare(writes().length, 0);
        compare(Disk.files[file], '{"a": 1}');
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

    function test_saved_lists_reach_the_receiver_as_real_arrays() {
        Disk.files["/home/tester/.local/state/berri-shell/calendars.json"] = linkedCalendars;
        var receiver = createTemporaryObject(receiverComponent, tests);
        tryVerify(() => receiver.facts !== null);
        compare(receiver.facts.list, true, "a list at the top");
        compare(receiver.facts.listInObject, true, "a list inside an object");
        compare(receiver.facts.listInListItem, true, "a list inside a list item");
    }

    function test_linked_calendars_survive_a_load() {
        Disk.files["/home/tester/.local/state/berri-shell/calendars.json"] = linkedCalendars;
        var receiver = createTemporaryObject(receiverComponent, tests);
        tryVerify(() => receiver.restored !== null);
        compare(receiver.restored.order, ["berri", "l-one", "l-two"]);
        compare(receiver.restored.calendars["l-two"].url, "https://invalid.invalid/two.ics");
    }
}
