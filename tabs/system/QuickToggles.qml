import QtQuick
import Quickshell.Networking
import Quickshell.Bluetooth
import qs.common
import qs.notifications
import qs.services

/**
 * Toggle grid cell (tickets 15-18): 3x2 tiles - Wi-Fi, Bluetooth, DND on the
 * top row, Caffeine, Night, Airplane on the bottom. This item only shows
 * state and sends clicks: Caffeine is Caffeine.qml, Night is Nightlight.qml,
 * DND is Notifications, Airplane is AirplaneMode.qml (remember/restore/clear
 * logic), Wi-Fi and Bluetooth are the Quickshell services. Night light is
 * read again only while this item is visible.
 *
 * The chevron on the Wi-Fi and Bluetooth tiles swaps this whole cell's grid
 * for WifiList or BluetoothList, cross-fading in place; the back button in
 * that list swaps back. True while the panel is closed keeps the grid state
 * exposed to the container (Pill.qml) reset to grid when the dashboard closes.
 */
Item {
    id: root

    readonly property int pad: 10
    readonly property int gap: 6
    readonly property real tileWidth: (width - pad * 2 - gap * 2) / 3
    readonly property real tileHeight: (height - pad * 2 - gap) / 2

    /** True while the dashboard panel is open; passed down from Pill so the
     *  Wi-Fi list resets to the grid whenever the panel closes. */
    property bool panelOpen: false

    property bool wifiListOpen: false
    property bool btListOpen: false
    onPanelOpenChanged: if (!panelOpen) { wifiListOpen = false; btListOpen = false; }

    /** True while the Wi-Fi list's password row wants real keyboard focus;
     *  bubbled up to Pill/shell.qml so the overlay layer can grab it. */
    readonly property bool wifiPasswordActive: wifiList.passwordActive

    // The Quickshell.Networking Wi-Fi device. It is taken when the device list
    // changes, with a limited retry while this item is visible (see below).
    property var wifiDevice: null

    function findWifiDevice() {
        var list = Networking.devices ? Networking.devices.values : [];
        for (var i = 0; i < list.length; i++) {
            if (list[i].type === DeviceType.Wifi) return list[i];
        }
        return null;
    }

    /** "Home-5G" while connected, "Joining…" while connecting, else "Off"
     *  ("Airplane" instead, while airplane mode is what turned it off). */
    readonly property string wifiSubText: {
        if (!Networking.wifiEnabled) return AirplaneMode.on ? "Airplane" : "Off";
        if (!root.wifiDevice) return "Off";
        var nets = root.wifiDevice.networks ? root.wifiDevice.networks.values : [];
        for (var i = 0; i < nets.length; i++) {
            if (nets[i].connected) return nets[i].name;
        }
        for (var j = 0; j < nets.length; j++) {
            if (nets[j].stateChanging) return "Joining…";
        }
        return "Not connected";
    }

    // Night light is read again only while this item is on screen.
    WhileVisible { service: Nightlight }

    // ---------------------------------------------------------------------
    // Bluetooth: Quickshell.Bluetooth's default adapter, read directly - it
    // updates on its own defaultAdapterChanged signal, unlike the Wi-Fi
    // device above which this shell resolves by hand.
    // ---------------------------------------------------------------------
    readonly property var btAdapter: Bluetooth.defaultAdapter

    readonly property int btConnectedCount: {
        if (!root.btAdapter || !root.btAdapter.devices) return 0;
        var list = root.btAdapter.devices.values;
        var n = 0;
        for (var i = 0; i < list.length; i++) if (list[i].connected) n++;
        return n;
    }

    /** "N connected" while devices are connected, "On" while on with none,
     *  else "Off" ("Airplane" instead, while airplane mode is what turned it off). */
    readonly property string btSubText: {
        if (!root.btAdapter || !root.btAdapter.enabled) return AirplaneMode.on ? "Airplane" : "Off";
        if (root.btConnectedCount > 0) return root.btConnectedCount + " connected";
        return "On";
    }

    // Networking.devices can still be empty right after startup (NetworkManager
    // backend populates it asynchronously). The Wi-Fi device is taken when the
    // device list changes. The retry timer is a fallback: it runs only while
    // this item is visible, stops after wifiDeviceRetryLimit tries, and gets
    // its tries back each time this item is shown again.
    readonly property int wifiDeviceRetryLimit: 20
    property int wifiDeviceTries: 0

    Connections {
        target: Networking.devices
        function onValuesChanged() {
            if (root.wifiDevice === null) root.wifiDevice = root.findWifiDevice();
        }
    }

    onVisibleChanged: if (visible) wifiDeviceTries = 0

    Timer {
        id: wifiDevicePoll
        interval: 500
        repeat: true
        running: root.wifiDevice === null && root.visible && root.wifiDeviceTries < root.wifiDeviceRetryLimit
        onTriggered: {
            root.wifiDeviceTries += 1;
            root.wifiDevice = root.findWifiDevice();
        }
    }

    Component.onCompleted: {
        root.wifiDevice = root.findWifiDevice();
    }

    // ---------------------------------------------------------------------
    // Layout: 3 columns x 2 rows, gap 6, inside a 10px pad. The grid and the
    // Wi-Fi list occupy the same cell and cross-fade between each other.
    // ---------------------------------------------------------------------

    readonly property bool listOpen: wifiListOpen || btListOpen

    Item {
        id: grid
        anchors.fill: parent
        opacity: root.listOpen ? 0 : 1
        visible: opacity > 0
        enabled: !root.listOpen

        Behavior on opacity {
            StandardMotion { duration: 250 }
        }

        QuickToggleTile {
            x: root.pad
            y: root.pad
            width: root.tileWidth
            height: root.tileHeight
            iconName: "wifi"
            label: "WI-FI"
            sub: root.wifiSubText
            on: Networking.wifiEnabled
            showChevron: true
            onToggled: Networking.wifiEnabled = !Networking.wifiEnabled
            onChevronClicked: root.wifiListOpen = true
        }

        QuickToggleTile {
            x: root.pad + root.tileWidth + root.gap
            y: root.pad
            width: root.tileWidth
            height: root.tileHeight
            iconName: "bluetooth"
            label: "BLUETOOTH"
            sub: root.btSubText
            on: root.btAdapter ? root.btAdapter.enabled : false
            showChevron: true
            onToggled: if (root.btAdapter) root.btAdapter.enabled = !root.btAdapter.enabled
            onChevronClicked: root.btListOpen = true
        }

        QuickToggleTile {
            x: root.pad + (root.tileWidth + root.gap) * 2
            y: root.pad
            width: root.tileWidth
            height: root.tileHeight
            iconName: "circle-minus"
            label: "DND"
            // DND works only because berri is the notification server
            // (Notifications.dnd); with another server running, it does nothing.
            sub: Notifications.dnd ? "On" : "Off"
            on: Notifications.dnd
            onToggled: Notifications.setDnd(!Notifications.dnd)
        }

        QuickToggleTile {
            x: root.pad
            y: root.pad + root.tileHeight + root.gap
            width: root.tileWidth
            height: root.tileHeight
            iconName: "coffee"
            label: "CAFFEINE"
            sub: Caffeine.on ? "Awake" : "Off"
            on: Caffeine.on
            onToggled: Caffeine.toggle()
        }

        QuickToggleTile {
            x: root.pad + root.tileWidth + root.gap
            y: root.pad + root.tileHeight + root.gap
            width: root.tileWidth
            height: root.tileHeight
            iconName: "moon"
            label: "NIGHT"
            sub: Nightlight.on ? "4000K" : "Off"
            on: Nightlight.on
            onToggled: Nightlight.toggle()
        }

        QuickToggleTile {
            x: root.pad + (root.tileWidth + root.gap) * 2
            y: root.pad + root.tileHeight + root.gap
            width: root.tileWidth
            height: root.tileHeight
            iconName: "plane"
            label: "AIRPLANE"
            sub: AirplaneMode.on ? "On" : "Off"
            on: AirplaneMode.on
            onToggled: AirplaneMode.toggle()
        }
    }

    WifiList {
        id: wifiList
        anchors.fill: parent
        anchors.margins: root.pad
        wifiDevice: root.wifiDevice
        open: root.wifiListOpen
        opacity: root.wifiListOpen ? 1 : 0
        visible: opacity > 0
        enabled: root.wifiListOpen

        Behavior on opacity {
            StandardMotion { duration: 250 }
        }

        onBackClicked: root.wifiListOpen = false
    }

    BluetoothList {
        id: btList
        anchors.fill: parent
        anchors.margins: root.pad
        adapter: root.btAdapter
        open: root.btListOpen
        opacity: root.btListOpen ? 1 : 0
        visible: opacity > 0
        enabled: root.btListOpen

        Behavior on opacity {
            StandardMotion { duration: 250 }
        }

        onBackClicked: root.btListOpen = false
    }
}
