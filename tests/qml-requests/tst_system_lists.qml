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
        // Like the real device model: setting `values` sends `valuesChanged`.
        property QtObject devices: QtObject { property var values: [] }
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

    // A Bluetooth device that pairs when the test says so. BlueZ removes a
    // forgotten device: the test does that part (see `bluezRemoves`).
    // Like Quickshell, connect() on a connected device only logs an error and
    // sends nothing to BlueZ (`ignoredConnectCalls`).
    Component {
        id: deviceType
        QtObject {
            property string address: ""
            property string name: ""
            property string icon: ""
            property bool paired: false
            property bool pairing: false
            property bool trusted: false
            property bool connected: false
            property int connectCalls: 0
            property int ignoredConnectCalls: 0
            property int disconnectCalls: 0
            property int cancelCalls: 0
            property int forgetCalls: 0
            property bool pairThrows: false
            property bool cancelThrows: false
            function pair() {
                if (pairThrows) throw new Error("pair failed");
                pairing = true;
            }
            function cancelPair() {
                cancelCalls += 1;
                if (cancelThrows) throw new Error("cancel failed");
                pairing = false;
            }
            function forget() { forgetCalls += 1; }
            function connect() {
                if (connected) {
                    ignoredConnectCalls += 1;
                    return;
                }
                connectCalls += 1;
            }
            function disconnect() { disconnectCalls += 1; }
        }
    }

    QtObject {
        id: wifi
        property bool scannerEnabled: false
        property var networks: ({ values: [] })
    }

    // z: the process table and the core meter below sit on the same corner; clicks must reach the lists.
    Item { width: 400; height: 300; z: 1
        WifiList { id: wifiList; anchors.fill: parent; wifiDevice: wifi; open: false }
        BluetoothList { id: btList; anchors.fill: parent; adapter: adapter; open: false }
    }

    Item { width: 496; height: 177
        SystemProcessTable { id: table }
    }

    Item { width: 60; height: 150
        SystemCore { id: core; anchors.fill: parent; core: 3 }
    }

    TestCase {
        name: "SystemLists"
        when: windowShown

        // A test that shortens the follow window gets the real one back after it.
        property int normalFollowMs: 0

        function initTestCase() { normalFollowMs = BluetoothPairing.followMs; }

        function cleanup() { BluetoothPairing.followMs = normalFollowMs; }

        function init() {
            Networking.wifiEnabled = true;
            wifiList.open = false;
            wifiList.cancelEditing();
            btList.open = false;
            adapter.enabled = true;
            btList.adapter = adapter;
            listDevices([]);
            SystemStats.processes = [];
        }

        // Every item below `item` with this objectName.
        function findAll(item, objectName, found) {
            for (const child of item.children) {
                if (child.objectName === objectName) found.push(child);
                findAll(child, objectName, found);
            }
            return found;
        }

        function listDevices(devices) {
            adapter.devices.values = devices;
        }

        // What BlueZ does after a forget: the adapter lists `after`, then the device object is destroyed.
        function bluezRemoves(device, after) {
            listDevices(after);
            device.destroy();
            waitForDestroyed(device);
        }

        function waitForDestroyed(object) {
            tryVerify(() => !Qt.isQtObject(object), 1000);
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

        // The Text items of the list whose text is `value`.
        function textItems(item, value, found) {
            for (const child of item.children) {
                if (child.text === value && child.visible) found.push(child);
                textItems(child, value, found);
            }
            return found;
        }

        function test_network_name_color_fades_when_it_becomes_choosable() {
            const secured = network({ name: "Fade", security: WifiSecurityType.Wpa2Eap });
            wifi.networks = { values: [secured] };
            wifiList.open = true;
            tryCompare(wifiList, "networks", [secured]);
            tryVerify(() => textItems(wifiList, "Fade", []).length === 1);
            const label = textItems(wifiList, "Fade", [])[0];
            compare(label.color, Theme.dim);
            secured.known = true;
            tryVerify(() => label.color != Theme.dim, 10000);
            verify(label.color != Theme.fg, "Color jumped: " + label.color);
            tryCompare(label, "color", Theme.fg);
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
            compare([speaker.connectCalls, speaker.ignoredConnectCalls], [1, 0]);
            compare(BluetoothPairing.following.length, 0);
        }

        // The pairing link makes BlueZ report `connected` before `paired`. Quickshell
        // ignores connect() then, so the service connects when that link drops.
        function test_pairing_link_that_drops_after_pairing_is_followed_by_a_connect() {
            const buds = createTemporaryObject(deviceType, host, { address: "A" });
            btList.open = true;
            btList.chooseDevice(buds);
            buds.connected = true;
            buds.paired = true;
            compare(buds.trusted, true);
            compare([buds.connectCalls, buds.ignoredConnectCalls], [0, 0]);
            compare(BluetoothPairing.following.length, 1);
            buds.connected = false;
            compare([buds.connectCalls, buds.ignoredConnectCalls], [1, 0]);
            compare(BluetoothPairing.following.length, 0);
            // The device is followed no more: later link changes send nothing.
            buds.connected = true;
            buds.connected = false;
            compare(buds.connectCalls, 1);
        }

        function test_link_that_stays_up_after_pairing_is_never_connected_again() {
            const buds = createTemporaryObject(deviceType, host, { address: "A" });
            BluetoothPairing.pair(buds);
            buds.connected = true;
            buds.paired = true;
            wait(100);
            compare([buds.connectCalls, buds.ignoredConnectCalls], [0, 0]);
        }

        function test_link_that_drops_after_the_window_is_not_connected_by_surprise() {
            BluetoothPairing.followMs = 300;
            const buds = createTemporaryObject(deviceType, host, { address: "A" });
            BluetoothPairing.pair(buds);
            buds.connected = true;
            buds.paired = true;
            compare(BluetoothPairing.following.length, 1);
            wait(500);
            compare(BluetoothPairing.following.length, 0);
            buds.connected = false;
            compare([buds.connectCalls, buds.ignoredConnectCalls], [0, 0]);
        }

        function test_forget_during_the_window_stops_the_follow() {
            const buds = createTemporaryObject(deviceType, host, { address: "A" });
            BluetoothPairing.pair(buds);
            buds.connected = true;
            buds.paired = true;
            compare(BluetoothPairing.following.length, 1);
            BluetoothPairing.forget(buds);
            compare(BluetoothPairing.following.length, 0);
            buds.connected = false;
            compare([buds.connectCalls, buds.forgetCalls], [0, 1]);
        }

        function test_pairing_again_during_the_window_restarts_the_follow() {
            const buds = createTemporaryObject(deviceType, host, { address: "A" });
            BluetoothPairing.pair(buds);
            buds.connected = true;
            buds.paired = true;
            BluetoothPairing.pair(buds);
            compare(BluetoothPairing.following.length, 0);
            buds.connected = false;
            compare(buds.connectCalls, 0);
        }

        function test_destroyed_device_during_the_window_is_safe() {
            failOnWarning(/.*/);
            const gone = createTemporaryObject(deviceType, host, { address: "A" });
            const other = createTemporaryObject(deviceType, host, { address: "B" });
            BluetoothPairing.pair(gone);
            gone.connected = true;
            gone.paired = true;
            compare(BluetoothPairing.following.length, 1);
            gone.destroy();
            waitForDestroyed(gone);
            // The next call drops the destroyed device.
            BluetoothPairing.pair(other);
            compare(BluetoothPairing.following.length, 0);
            other.paired = true;
            compare(other.connectCalls, 1);
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

        function test_failed_pairing_does_not_connect_later() {
            const speaker = createTemporaryObject(deviceType, host, { address: "A" });
            BluetoothPairing.pair(speaker);
            speaker.pairing = false;
            wait(BluetoothPairing.graceMs + 300);
            compare(BluetoothPairing.pending.length, 0);
            speaker.paired = true;
            compare(speaker.trusted, false);
            compare(speaker.connectCalls, 0);
        }

        function test_only_paired_rows_have_a_forget_button() {
            const pad = createTemporaryObject(deviceType, host, { address: "A", name: "Pad", paired: true });
            const buds = createTemporaryObject(deviceType, host, { address: "B", name: "Buds" });
            listDevices([buds, pad]);
            btList.open = true;
            const buttons = findAll(btList, "forgetButton", []);
            compare(buttons.length, 2);
            compare(buttons[0].enabled, true);
            compare(buttons[1].enabled, false);
            compare(buttons[0].Accessible.name, "Forget Pad");
            tryCompare(buttons[0], "opacity", 1);
            tryCompare(buttons[1], "opacity", 0);
        }

        // A screen reader must not find the hidden button of an unpaired row.
        function test_forget_button_is_ignored_by_screen_readers_on_unpaired_rows() {
            const pad = createTemporaryObject(deviceType, host, { address: "A", name: "Pad", paired: true });
            const buds = createTemporaryObject(deviceType, host, { address: "B", name: "Buds" });
            listDevices([buds, pad]);
            btList.open = true;
            const buttons = findAll(btList, "forgetButton", []);
            compare(buttons.length, 2);
            compare(buttons[0].Accessible.ignored, false);
            compare(buttons[1].Accessible.ignored, true);
        }

        // A forget needs no wait for the 2 s scan poll: the row goes when the device model changes.
        function test_forget_button_forgets_the_device_and_the_row_goes() {
            const pad = createTemporaryObject(deviceType, host, { address: "A", name: "Pad", paired: true });
            listDevices([pad]);
            btList.open = true;
            tryCompare(findAll(btList, "forgetButton", [])[0], "opacity", 1);
            mouseClick(findAll(btList, "forgetButton", [])[0]);
            compare(pad.forgetCalls, 1);
            bluezRemoves(pad, []);
            compare(btList.devices.length, 0);
        }

        // Paired rows sort connected first, so the first button is the connected device's.
        function test_forget_button_click_does_not_reach_the_row() {
            const phone = createTemporaryObject(deviceType, host, { address: "A", name: "Phone", paired: true, connected: true });
            const pad = createTemporaryObject(deviceType, host, { address: "B", name: "Pad", paired: true });
            listDevices([pad, phone]);
            btList.open = true;
            const buttons = findAll(btList, "forgetButton", []);
            tryCompare(buttons[0], "opacity", 1);
            tryCompare(buttons[1], "opacity", 1);
            mouseClick(buttons[0]);
            mouseClick(buttons[1]);
            compare([phone.forgetCalls, phone.disconnectCalls], [1, 0]);
            compare([pad.forgetCalls, pad.connectCalls], [1, 0]);
        }

        // The hidden button of an unpaired row must not eat the click.
        function test_click_at_the_forget_button_of_an_unpaired_row_starts_a_pair() {
            const buds = createTemporaryObject(deviceType, host, { address: "A", name: "Buds" });
            listDevices([buds]);
            btList.open = true;
            const button = findAll(btList, "forgetButton", [])[0];
            compare(button.enabled, false);
            mouseClick(button);
            compare(buds.pairing, true);
            compare(BluetoothPairing.pending.length, 1);
            compare(buds.forgetCalls, 0);
        }

        // BlueZ destroys the device object a moment before the list refreshes. The row must ignore a click in between.
        function test_row_clicked_after_its_device_is_destroyed_does_nothing() {
            failOnWarning(/.*/);
            const pad = createTemporaryObject(deviceType, host, { address: "A", name: "Pad", paired: true });
            listDevices([pad]);
            btList.open = true;
            const button = findAll(btList, "forgetButton", [])[0];
            tryCompare(button, "opacity", 1);
            const row = button.parent.parent;
            mouseClick(button);
            compare(pad.forgetCalls, 1);
            pad.destroy();
            waitForDestroyed(pad);
            mouseClick(row, 20, row.height / 2);
        }

        function test_refresh_skips_a_device_that_is_destroyed() {
            failOnWarning(/.*/);
            const gone = createTemporaryObject(deviceType, host, { address: "A", name: "Gone", paired: true });
            const buds = createTemporaryObject(deviceType, host, { address: "B", name: "Buds" });
            listDevices([gone, buds]);
            btList.open = true;
            compare(btList.devices.length, 2);
            gone.destroy();
            waitForDestroyed(gone);
            btList.refreshDevices();
            compare(btList.devices, [buds]);
        }

        function test_forget_while_pairing_cancels_the_pair() {
            const pad = createTemporaryObject(deviceType, host, { address: "A", name: "Pad" });
            BluetoothPairing.pair(pad);
            BluetoothPairing.forget(pad);
            compare([pad.cancelCalls, pad.forgetCalls], [1, 1]);
            compare(BluetoothPairing.pending.length, 0);
            pad.paired = true;
            compare([pad.trusted, pad.connectCalls], [false, 0]);
        }

        function test_forget_still_runs_when_the_pair_cannot_be_cancelled() {
            const pad = createTemporaryObject(deviceType, host, { address: "A", name: "Pad", cancelThrows: true });
            BluetoothPairing.pair(pad);
            BluetoothPairing.forget(pad);
            compare([pad.cancelCalls, pad.forgetCalls], [1, 1]);
            compare(BluetoothPairing.pending.length, 0);
        }

        function test_forget_of_a_paired_device_does_not_cancel_a_pair_that_is_not_running() {
            const pad = createTemporaryObject(deviceType, host, { address: "A", name: "Pad", paired: true });
            BluetoothPairing.forget(pad);
            compare([pad.cancelCalls, pad.forgetCalls], [0, 1]);
        }

        function test_forget_of_a_destroyed_device_is_ignored() {
            failOnWarning(/.*/);
            const pad = createTemporaryObject(deviceType, host, { address: "A", name: "Pad", paired: true });
            pad.destroy();
            waitForDestroyed(pad);
            BluetoothPairing.forget(pad);
            compare(BluetoothPairing.pending.length, 0);
        }

        function test_forgotten_device_found_again_pairs_and_connects_like_a_new_one() {
            const old = createTemporaryObject(deviceType, host, { address: "A", name: "Pad" });
            btList.open = true;
            btList.chooseDevice(old);
            old.paired = true;
            compare([old.trusted, old.connectCalls], [true, 1]);
            BluetoothPairing.forget(old);
            bluezRemoves(old, []);
            // The scan finds the same address as a new, unpaired object.
            const again = createTemporaryObject(deviceType, host, { address: "A", name: "Pad" });
            listDevices([again]);
            btList.chooseDevice(again);
            compare(again.pairing, true);
            compare(BluetoothPairing.pending.length, 1);
            again.paired = true;
            compare([again.trusted, again.connectCalls], [true, 1]);
            compare(BluetoothPairing.pending.length, 0);
        }

        function test_core_meter_shows_a_dash_until_its_load_is_known() {
            core.load = null;
            verify(texts(core, []).includes("-"), texts(core, []).join("|"));
            verify(!texts(core, []).includes("0"), texts(core, []).join("|"));
            compare(core.level, 0);
            core.load = 42.4;
            verify(texts(core, []).includes("42"), texts(core, []).join("|"));
            verify(!texts(core, []).includes("-"), texts(core, []).join("|"));
        }

        function test_staggered_failed_pairings_each_keep_their_own_deadline() {
            const first = createTemporaryObject(deviceType, host, { address: "A" });
            const second = createTemporaryObject(deviceType, host, { address: "B" });
            BluetoothPairing.pair(first);
            BluetoothPairing.pair(second);
            first.pairing = false;
            wait(BluetoothPairing.graceMs / 2);
            second.pairing = false;
            wait(BluetoothPairing.graceMs * 0.65);
            first.paired = true;
            compare([first.trusted, first.connectCalls], [false, 0]);
            second.paired = true;
            compare([second.trusted, second.connectCalls], [true, 1]);
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
