import QtQuick
import QtTest
import Quickshell.Networking
import qs.services
import qs.tabs.system

// Value rules of the System tab lists and the process table, with fake system objects.
Item {
    id: host
    width: 800
    height: 600

    QtObject {
        id: adapter
        property bool enabled: true
        property bool discovering: false
        property var devices: ({ values: [] })
    }

    Component {
        id: networkType
        QtObject {
            property string name: ""
            property bool connected: false
            property bool known: false
            property bool stateChanging: false
            property real signalStrength: 0.5
            property int security: WifiSecurityType.Wpa2Psk
            property int pskCalls: 0
            property int connectCalls: 0
            signal connectionFailed
            function connect() { connectCalls += 1; }
            function connectWithPsk(psk) { pskCalls += 1; }
        }
    }

    // A Bluetooth device that pairs when the test says so.
    Component {
        id: deviceType
        QtObject {
            property string address: ""
            property bool paired: false
            property bool pairing: false
            property bool trusted: false
            property bool connected: false
            property int connectCalls: 0
            property bool pairThrows: false
            function pair() {
                if (pairThrows) throw new Error("pair failed");
                pairing = true;
            }
            function connect() { connectCalls += 1; }
        }
    }

    QtObject {
        id: wifi
        property bool scannerEnabled: false
        property var networks: ({ values: [] })
    }

    Item { width: 400; height: 300
        WifiList { id: wifiList; anchors.fill: parent; wifiDevice: wifi; open: false }
        BluetoothList { id: btList; anchors.fill: parent; adapter: adapter; open: false }
    }

    Item { width: 496; height: 177
        SystemProcessTable { id: table }
    }

    TestCase {
        name: "SystemLists"
        when: windowShown

        function init() {
            Networking.wifiEnabled = true;
            wifiList.open = false;
            wifiList.cancelEditing();
            btList.open = false;
            adapter.enabled = true;
            btList.adapter = adapter;
            SystemStats.processes = [];
        }

        function find(item, property) {
            for (const child of item.children) {
                if (child[property] !== undefined) return child;
                const found = find(child, property);
                if (found) return found;
            }
            return null;
        }

        // Every visible text in the tree below `item`.
        function texts(item, found) {
            for (const child of item.children) {
                if (child.text !== undefined && child.visible) found.push(child.text);
                texts(child, found);
            }
            return found;
        }

        function network(properties) {
            return createTemporaryObject(networkType, host, properties);
        }

        function test_password_row_closes_after_a_connection() {
            const cafe = network({ name: "Cafe" });
            wifi.networks = { values: [cafe] };
            wifiList.open = true;
            tryCompare(wifiList, "networks", [cafe]);
            wifiList.chooseNetwork(cafe);
            compare(wifiList.passwordActive, true);
            wifiList.passwordText = "secret";
            cafe.connected = true;
            compare(wifiList.passwordActive, false);
            compare(wifiList.passwordText, "");
        }

        function test_password_row_stays_after_a_failed_connection() {
            const cafe = network({ name: "Cafe" });
            wifi.networks = { values: [cafe] };
            wifiList.open = true;
            tryCompare(wifiList, "networks", [cafe]);
            wifiList.chooseNetwork(cafe);
            cafe.connectionFailed();
            compare(wifiList.passwordActive, true);
            compare(wifiList.passwordFailed, true);
        }

        function test_password_row_closes_when_wifi_is_switched_off() {
            const cafe = network({ name: "Cafe" });
            wifi.networks = { values: [cafe] };
            wifiList.open = true;
            tryCompare(wifiList, "networks", [cafe]);
            wifiList.chooseNetwork(cafe);
            compare(wifiList.passwordActive, true);
            Networking.wifiEnabled = false;
            compare(wifiList.passwordActive, false);
        }

        function test_password_flow_is_only_for_password_security_types() {
            const sent = network({ name: "Home" });
            wifi.networks = { values: [sent] };
            wifiList.open = true;
            for (const type of [WifiSecurityType.WpaPsk, WifiSecurityType.Wpa2Psk, WifiSecurityType.Sae]) {
                sent.security = type;
                wifiList.chooseNetwork(sent);
                compare(wifiList.passwordActive, true, "password types ask for a password");
                wifiList.cancelEditing();
            }
            for (const type of [WifiSecurityType.Wpa2Eap, WifiSecurityType.Owe]) {
                sent.security = type;
                wifiList.chooseNetwork(sent);
                compare(wifiList.passwordActive, false, "other types do not ask for a password");
            }
            wifiList.passwordText = "x";
            wifiList.submitPassword(sent);
            compare(sent.pskCalls, 1);
            sent.known = true;
            sent.security = WifiSecurityType.Wpa2Eap;
            wifiList.chooseNetwork(sent);
            compare(sent.connectCalls, 1, "a known network connects with its saved settings");
        }

        function test_wifi_scan_waits_for_wifi_to_be_on() {
            Networking.wifiEnabled = false;
            wifiList.open = true;
            compare(wifi.scannerEnabled, false);
            Networking.wifiEnabled = true;
            compare(wifi.scannerEnabled, true);
            Networking.wifiEnabled = false;
            compare(wifi.scannerEnabled, false);
        }

        function test_no_bluetooth_adapter_is_not_called_off() {
            btList.adapter = null;
            btList.open = true;
            const shown = texts(btList, []);
            verify(shown.some(t => t === "No Bluetooth adapter."), shown.join("|"));
            verify(!shown.some(t => t.indexOf("Bluetooth is off") === 0), shown.join("|"));
            btList.adapter = adapter;
            adapter.enabled = false;
            verify(texts(btList, []).some(t => t.indexOf("Bluetooth is off") === 0));
        }

        function test_pairing_finishes_after_the_list_closes() {
            const speaker = createTemporaryObject(deviceType, host, { address: "A" });
            btList.open = true;
            btList.chooseDevice(speaker);
            compare(speaker.pairing, true);
            btList.open = false;
            speaker.paired = true;
            compare(speaker.trusted, true);
            compare(speaker.connectCalls, 1);
        }

        function test_two_pairings_finish_independently() {
            const first = createTemporaryObject(deviceType, host, { address: "A" });
            const second = createTemporaryObject(deviceType, host, { address: "B" });
            btList.open = true;
            btList.chooseDevice(first);
            btList.chooseDevice(second);
            first.paired = true;
            compare([first.trusted, first.connectCalls], [true, 1]);
            compare([second.trusted, second.connectCalls], [false, 0]);
            second.paired = true;
            compare([second.trusted, second.connectCalls], [true, 1]);
        }

        function test_pairing_that_ends_before_paired_still_connects() {
            const speaker = createTemporaryObject(deviceType, host, { address: "A" });
            btList.chooseDevice(speaker);
            speaker.pairing = false;
            wait(50);
            speaker.paired = true;
            compare(speaker.trusted, true);
            compare(speaker.connectCalls, 1);
        }

        function test_failed_pair_call_is_dropped() {
            const speaker = createTemporaryObject(deviceType, host, { address: "A", pairThrows: true });
            BluetoothPairing.pair(speaker);
            compare(BluetoothPairing.pending.length, 0);
            speaker.paired = true;
            compare(speaker.connectCalls, 0);
            compare(speaker.trusted, false);
        }

        function test_destroyed_device_is_dropped() {
            const speaker = createTemporaryObject(deviceType, host, { address: "A" });
            const other = createTemporaryObject(deviceType, host, { address: "B" });
            BluetoothPairing.pair(speaker);
            BluetoothPairing.pair(other);
            compare(BluetoothPairing.pending.length, 2);
            speaker.destroy();
            wait(50);
            other.paired = true;
            compare(other.connectCalls, 1);
            compare(BluetoothPairing.pending.length, 0);
        }

        function test_process_rows_are_updated_in_place() {
            SystemStats.processes = [{ name: "a", cpu: 1, mem: 1 }, { name: "b", cpu: 0, mem: 2 }];
            const list = find(table, "flickableDirection");
            const repeater = find(list, "itemAt");
            tryVerify(() => repeater.itemAt(0) !== null);
            const row = repeater.itemAt(0);
            const other = repeater.itemAt(1);
            compare(row.name, "a");
            SystemStats.processes = [{ name: "b", cpu: 4, mem: 2 }, { name: "a", cpu: null, mem: 1 }];
            compare(repeater.itemAt(0), row);
            compare(repeater.itemAt(1), other);
            compare(row.name, "b");
            compare(row.cpu, 4);
            compare(other.cpu, null);
        }
    }
}
