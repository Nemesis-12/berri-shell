import QtQuick
import Quickshell.Bluetooth
import qs.common
import qs.services

/**
 * Bluetooth device list (ticket 17): swaps into the toggle grid's cell when
 * the Bluetooth tile's chevron is clicked. Same layout as WifiList: a
 * PanelListHeader with a back button, title and on/off switch, then a
 * scrolling list of devices - paired devices first (connected first), then
 * nearby devices found while the list is open. Clicking a connected device
 * disconnects it; clicking a paired device connects it; clicking an
 * unpaired device pairs, trusts and connects it (shown as "PAIRING…").
 */
Item {
    id: root

    /** The Quickshell.Bluetooth adapter this list reads and drives, or null. */
    property var adapter: null

    /** True while this list is the active panel (drives discovery). */
    property bool open: false

    signal backClicked

    /** Snapshot of adapter.devices, sorted paired-and-connected first, then
     *  other paired devices, then discovered ones. Each entry is the live
     *  BluetoothDevice object, so its own properties stay reactive in the row. */
    property var devices: []

    /** Address of the device this list is pairing, so a pairedChanged signal
     *  knows to trust and connect it once BlueZ finishes pairing. */
    property string pendingPairAddress: ""

    function isBareMacAddress(name) {
        // Match six hex pairs separated by : or -
        // e.g. "AA:BB:CC:DD:EE:FF" or "AA-BB-CC-DD-EE-FF"
        return /^([0-9a-fA-F]{2}[:-]){5}([0-9a-fA-F]{2})$/.test(name);
    }

    function refreshDevices() {
        if (!root.adapter) {
            root.devices = [];
            return;
        }
        var list = root.adapter.devices ? root.adapter.devices.values.slice() : [];
        // Filter out unpaired devices with no name or bare MAC address
        list = list.filter(function (device) {
            if (device.paired) return true;
            var name = device.name || "";
            if (name === "" || root.isBareMacAddress(name)) return false;
            return true;
        });
        list.sort(function (a, b) {
            if (a.paired !== b.paired) return a.paired ? -1 : 1;
            if (a.paired && a.connected !== b.connected) return a.connected ? -1 : 1;
            return a.name.localeCompare(b.name);
        });
        root.devices = list;
    }

    function chooseDevice(device) {
        if (device.connected) {
            device.disconnect();
        } else if (device.paired) {
            device.connect();
        } else {
            root.pendingPairAddress = device.address;
            device.pair();
        }
    }

    /** Maps BlueZ's freedesktop icon name to the short kind label a row
     *  shows when the device is neither connected nor pairing. */
    function deviceKind(icon) {
        switch (icon) {
        case "audio-headset":
        case "audio-headphones":
            return "HEADPHONES";
        case "input-mouse":
            return "MOUSE";
        case "input-keyboard":
            return "KEYBOARD";
        case "input-gaming":
            return "CONTROLLER";
        case "input-tablet":
            return "TABLET";
        case "phone":
            return "PHONE";
        case "computer":
            return "COMPUTER";
        case "audio-card":
        case "audio-speakers":
            return "SPEAKER";
        default:
            return "DEVICE";
        }
    }

    onAdapterChanged: if (open) refreshDevices()

    onOpenChanged: {
        if (open) {
            refreshDevices();
        } else {
            root.pendingPairAddress = "";
        }
        if (adapter) adapter.discovering = open && adapter.enabled;
    }

    Timer {
        id: scanPoll
        interval: 2000
        repeat: true
        running: root.open && root.adapter !== null
        onTriggered: root.refreshDevices()
    }

    Column {
        anchors.fill: parent
        spacing: 2

        PanelListHeader {
            id: header
            width: parent.width
            title: "BLUETOOTH"
            checked: root.adapter ? root.adapter.enabled : false
            onBackClicked: root.backClicked()
            onToggled: if (root.adapter) root.adapter.enabled = !root.adapter.enabled
        }

        // --- Body: device rows, or the off-state message. ---
        Item {
            width: parent.width
            height: parent.height - header.height - 2

            Text {
                visible: !root.adapter || !root.adapter.enabled
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.leftMargin: 6
                anchors.rightMargin: 6
                anchors.topMargin: 14
                text: "Bluetooth is off. Switch it on to find devices."
                font.family: Theme.condensed
                font.weight: Font.Medium
                font.pixelSize: 12
                color: Theme.dim
                wrapMode: Text.WordWrap
            }

            ListView {
                id: listView
                visible: root.adapter && root.adapter.enabled
                anchors.fill: parent
                clip: true
                model: root.devices
                boundsBehavior: Flickable.StopAtBounds

                delegate: ListRow {
                    id: row
                    required property var modelData

                    width: listView.width
                    active: modelData.connected
                    tagText: modelData.connected ? "CONNECTED"
                        : modelData.pairing ? "PAIRING…" : root.deviceKind(modelData.icon)
                    tagColor: (modelData.connected || modelData.pairing) ? Theme.accentLight : Theme.dim

                    onClicked: root.chooseDevice(row.modelData)

                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "bluetooth"
                        size: 15
                        strokeWidth: 1.8
                        color: row.modelData.connected ? Theme.accentLight : Theme.dim
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(0, parent.width - 25)
                        text: row.modelData.name || row.modelData.deviceName
                        font.family: Theme.condensed
                        font.weight: Font.Medium
                        font.pixelSize: 13
                        color: Theme.fg
                        elide: Text.ElideRight
                    }

                    Connections {
                        target: row.modelData
                        function onPairedChanged() {
                            if (row.modelData.paired && root.pendingPairAddress === row.modelData.address) {
                                root.pendingPairAddress = "";
                                row.modelData.trusted = true;
                                row.modelData.connect();
                            }
                        }
                    }
                }
            }

            // Thin Spine-style scrollbar, shown only while the list is moving.
            Rectangle {
                visible: root.adapter && root.adapter.enabled && listView.contentHeight > listView.height
                anchors.right: parent.right
                width: 3
                radius: 1.5
                color: Theme.border
                opacity: listView.moving ? 1 : 0
                y: listView.visibleArea.yPosition * listView.height
                height: listView.visibleArea.heightRatio * listView.height

                Fade on opacity { duration: Theme.stateMs }
            }
        }
    }
}
