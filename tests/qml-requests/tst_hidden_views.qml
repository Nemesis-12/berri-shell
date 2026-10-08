import QtQuick
import QtTest
import Quickshell.Io
import qs.common
import qs.services
import qs.tabs.code
import qs.tabs.system

// Hidden views stop work. Shared requests stay on until the last owner lets go.
Item {
    id: host
    width: 800
    height: 600

    // Fake Bluetooth adapter. Reading `devices.values` counts one list refresh.
    QtObject {
        id: adapter
        property bool enabled: true
        property bool discovering: false
        property int reads: 0
        property var devices: ({ get values() { adapter.reads += 1; return []; } })
    }

    // Fake Wi-Fi networks and device.
    Component {
        id: networkType
        QtObject {
            property string name: ""
            property bool connected: false
            property bool known: false
            property bool stateChanging: false
            property real signalStrength: 0.5
            property int security: 1
            signal connectionFailed
            function connect() {}
            function connectWithPsk(psk) {}
        }
    }
    QtObject {
        id: wifi
        property bool scannerEnabled: false
        property var networks: ({ values: [] })
    }

    // Two monitors: two Bluetooth lists on the same adapter, two Wi-Fi lists on the same device.
    Item { id: monitorA; width: 400; height: 300
        BluetoothList { id: btA; anchors.fill: parent; adapter: adapter }
        WifiList { id: wifiA; anchors.fill: parent; wifiDevice: wifi }
    }
    Item { id: monitorB; x: 400; width: 400; height: 300
        BluetoothList { id: btB; anchors.fill: parent; adapter: adapter }
        WifiList { id: wifiB; anchors.fill: parent; wifiDevice: wifi }
    }

    // Two seek bars and two calendar-error views that count in the same service.
    QtObject { id: fakeCalendar; property int saveErrorViewers: 0; readonly property bool saveErrorShown: saveErrorViewers > 0 }
    property bool dragA: false
    property bool dragB: false
    Item { id: seekViewA
        WhileVisible { service: MediaPlayer; counter: "seekers"; when: host.dragA }
        WhileVisible { id: errorA; service: fakeCalendar; counter: "saveErrorViewers" }
    }
    Item { id: seekViewB
        WhileVisible { service: MediaPlayer; counter: "seekers"; when: host.dragB }
        WhileVisible { id: errorB; service: fakeCalendar; counter: "saveErrorViewers" }
    }

    Item { id: codeHost; width: 800; height: 500; visible: false
        CodeTab { id: codeTab; anchors.fill: parent }
    }

    TestCase {
        name: "HiddenViews"
        when: windowShown

        function init() {
            for (const list of [btA, btB, wifiA, wifiB]) { list.open = false; list.visible = true; }
            adapter.enabled = true;
            wifi.networks = { values: [] };
        }

        // Finds the first item that has `property` in the tree below `item`.
        function find(item, property) {
            for (const child of item.children) {
                if (child[property] !== undefined) return child;
                const found = find(child, property);
                if (found) return found;
            }
            return null;
        }

        // Counts running timers owned by a service singleton.
        function runningTimers(service) {
            return Array.from(service.data).filter(o => o.toString().indexOf("QQmlTimer") === 0 && o.running).length;
        }

        function test_hidden_list_stops_discovery_but_visible_list_keeps_it() {
            btA.open = true;
            btB.open = true;
            compare(adapter.discovering, true);
            btA.visible = false;
            compare(adapter.discovering, true);
            const reads = adapter.reads;
            wait(2300);
            verify(adapter.reads > reads, "The visible list still polls");
            btB.visible = false;
            compare(adapter.discovering, false);
            const hiddenReads = adapter.reads;
            wait(2300);
            compare(adapter.reads, hiddenReads);
            btA.visible = true;
            compare(adapter.discovering, true);
        }

        function test_hidden_wifi_list_stops_scanning_but_visible_list_keeps_it() {
            wifiA.open = true;
            wifiB.open = true;
            compare(wifi.scannerEnabled, true);
            wifiA.visible = false;
            compare(wifi.scannerEnabled, true);
            wifiB.open = false;
            compare(wifi.scannerEnabled, false);
        }

        function test_discovery_starts_when_bluetooth_turns_on_with_the_list_open() {
            adapter.enabled = false;
            btA.open = true;
            compare(adapter.discovering, false);
            adapter.enabled = true;
            compare(adapter.discovering, true);
            adapter.enabled = false;
            compare(adapter.discovering, false);
        }

        function test_refresh_keeps_a_password_row_and_its_text() {
            const network = createTemporaryObject(networkType, host, { name: "Cafe", security: 1 });
            const other = createTemporaryObject(networkType, host, { name: "Home", signalStrength: 0.9, security: 1 });
            wifi.networks = { values: [network, other] };
            wifiA.open = true;
            tryCompare(wifiA, "networks", [other, network]);
            wifiA.chooseNetwork(network);
            const view = find(wifiA, "itemAtIndex");
            const row = view.itemAtIndex(1);
            verify(row);
            const input = find(row, "echoMode");
            verify(input, "The password field exists");
            for (const character of ["a", "b", "c"]) input.insert(input.cursorPosition, character);
            compare(input.text, "abc");
            // A new strong signal would re-sort the list if it were refreshed.
            network.signalStrength = 1.0;
            wait(6000);
            compare(input.text, "abc");
            compare(wifiA.passwordText, "abc");
            verify(view.itemAtIndex(0) !== null && view.itemAtIndex(1) === row, "The row object is not rebuilt");
        }

        function test_refresh_without_changes_does_not_rebuild_rows() {
            const network = createTemporaryObject(networkType, host, { name: "Cafe" });
            wifi.networks = { values: [network] };
            wifiA.open = true;
            tryCompare(wifiA, "networks", [network]);
            const view = find(wifiA, "itemAtIndex");
            const row = view.itemAtIndex(0);
            verify(row);
            wait(4500);
            verify(view.itemAtIndex(0) === row, "An equal list keeps the same row");
        }

        function test_code_views_return_counts_to_zero_and_stop_timers() {
            for (let round = 0; round < 3; round++) {
                codeHost.visible = true;
                compare(CodeData.viewers, 1);
                compare(AgentUsage.viewers, 1);
                verify(runningTimers(CodeData) >= 1, "The minute timer runs while the tab shows");
                codeHost.visible = false;
                compare(CodeData.viewers, 0);
                compare(AgentUsage.viewers, 0);
                compare(runningTimers(CodeData), 0);
                compare(runningTimers(AgentUsage), 0);
            }
        }

        function test_first_code_viewer_starts_each_source_once() {
            compare(CodeData.viewers, 0);
            wait(100); // Let fake scripts from earlier tests end.
            ProcessLog.commands = [];
            CodeData.viewers = 1;
            const started = name => ProcessLog.commands.filter(c => c.some(part => String(part).endsWith(name))).length;
            // Stats keep their cache time after a hide, so an earlier test may have made them fresh.
            verify(started("code-stats.py") <= 1);
            compare(started("github-stats.py"), 1);
            // Commits wait for GitHub. The fake process never reports its end, so they do not start here.
            compare(started("local-commits.py"), 0);
            wait(200);
            verify(started("code-stats.py") <= 1);
            compare(started("github-stats.py"), 1);
            compare(started("local-commits.py"), 0);
            CodeData.viewers = 0;
        }

        function test_shared_requests_stay_until_the_last_owner_releases() {
            host.dragA = true;
            host.dragB = true;
            compare(MediaPlayer.seeking, true);
            seekViewA.visible = false;
            compare(MediaPlayer.seeking, true);
            host.dragB = false;
            compare(MediaPlayer.seeking, false);
            seekViewA.visible = true;
            host.dragA = false;
            compare(MediaPlayer.seekers, 0);

            compare(fakeCalendar.saveErrorShown, true);
            seekViewA.visible = false;
            compare(fakeCalendar.saveErrorShown, true);
            seekViewB.visible = false;
            compare(fakeCalendar.saveErrorShown, false);
            seekViewA.visible = true;
            seekViewB.visible = true;
        }
    }
}
