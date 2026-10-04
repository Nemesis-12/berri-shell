import QtQuick
import Quickshell.Networking
import qs.common
import qs.services

/**
 * Wi-Fi network list (ticket 16): swaps into the toggle grid's cell when the
 * Wi-Fi tile's chevron is clicked. Header (PanelListHeader) has a back
 * button, the "WI-FI" title and an on/off switch; below it a scrolling list
 * of nearby networks (ListRow rows), connected first then by signal
 * strength. Clicking a known or open network connects at once; a new
 * secured network turns its row into a password field (Enter connects, Esc
 * cancels).
 */
Item {
    id: root

    /** The Quickshell.Networking WifiDevice this list reads and drives, or null. */
    property var wifiDevice: null

    /** True while this list is the active panel (drives scanning and focus). */
    property bool open: false

    /** True while a network's password row is being typed into, so the panel
     *  window can grab real keyboard focus only for that moment. */
    readonly property bool passwordActive: editingNetwork !== ""

    signal backClicked

    /** Snapshot of wifiDevice.networks, sorted connected-first then by
     *  strength. Refreshed on open and by scanPoll; each entry is the live
     *  WifiNetwork object, so its own properties stay reactive in the row. */
    property var networks: []

    property string editingNetwork: ""
    property string passwordText: ""
    property bool passwordFailed: false

    function refreshNetworks() {
        if (!root.wifiDevice) {
            root.networks = [];
            return;
        }
        var list = root.wifiDevice.networks.values.slice();
        list.sort(function (a, b) {
            if (a.connected !== b.connected) return a.connected ? -1 : 1;
            return b.signalStrength - a.signalStrength;
        });
        root.networks = list;
    }

    function cancelEditing() {
        root.editingNetwork = "";
        root.passwordText = "";
        root.passwordFailed = false;
    }

    function chooseNetwork(network) {
        if (network.known || network.security === WifiSecurityType.Open) {
            network.connect();
            return;
        }
        root.editingNetwork = network.name;
        root.passwordText = "";
        root.passwordFailed = false;
    }

    function submitPassword(network) {
        if (root.passwordText.length === 0) return;
        network.connectWithPsk(root.passwordText);
    }

    /** strength is WifiNetwork.signalStrength, a 0-1 fraction. */
    function signalIcon(strength) {
        if (strength >= 0.67) return "wifi";
        if (strength >= 0.34) return "wifi-high";
        if (strength > 0) return "wifi-low";
        return "wifi-zero";
    }

    onWifiDeviceChanged: if (open) refreshNetworks()

    onOpenChanged: {
        if (open) {
            refreshNetworks();
        } else {
            cancelEditing();
        }
        if (wifiDevice) wifiDevice.scannerEnabled = open;
    }

    Timer {
        id: scanPoll
        interval: 2000
        repeat: true
        running: root.open && root.wifiDevice !== null
        onTriggered: root.refreshNetworks()
    }

    Column {
        anchors.fill: parent
        spacing: 2

        PanelListHeader {
            id: header
            width: parent.width
            title: "WI-FI"
            checked: Networking.wifiEnabled
            onBackClicked: root.backClicked()
            onToggled: Networking.wifiEnabled = !Networking.wifiEnabled
        }

        // --- Body: network rows, or the off-state message. ---
        Item {
            width: parent.width
            height: parent.height - header.height - 2

            Text {
                textFormat: Text.PlainText
                visible: !Networking.wifiEnabled
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.leftMargin: 6
                anchors.rightMargin: 6
                anchors.topMargin: 14
                text: "Wi-Fi is off. Switch it on to see networks."
                font.family: Theme.condensed
                font.weight: Font.Medium
                font.pixelSize: 12
                color: Theme.dim
                wrapMode: Text.WordWrap
            }

            ListView {
                id: listView
                visible: Networking.wifiEnabled
                anchors.fill: parent
                clip: true
                model: root.networks
                boundsBehavior: Flickable.StopAtBounds

                delegate: ListRow {
                    id: row
                    required property var modelData

                    readonly property bool editing: root.editingNetwork === modelData.name
                    readonly property bool joining: modelData.stateChanging && !modelData.connected
                    readonly property bool secured: modelData.security !== WifiSecurityType.Open

                    width: listView.width
                    active: modelData.connected
                    rowEnabled: !editing
                    tagText: row.editing && root.passwordFailed ? "FAILED"
                        : modelData.connected ? "CONNECTED"
                        : row.joining ? "JOINING…" : row.secured ? "SECURED" : "OPEN"
                    tagColor: (row.editing && root.passwordFailed) ? Theme.dim
                        : (modelData.connected || row.joining) ? Theme.accentLight : Theme.dim

                    onClicked: root.chooseNetwork(row.modelData)

                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: root.signalIcon(row.modelData.signalStrength)
                        size: 15
                        strokeWidth: 1.8
                        color: row.modelData.connected ? Theme.accentLight : Theme.fg2
                    }

                    Text {
                        textFormat: Text.PlainText
                        visible: !row.editing
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(0, parent.width - 25)
                        text: row.modelData.name
                        font.family: Theme.condensed
                        font.weight: Font.Medium
                        font.pixelSize: 13
                        color: Theme.fg
                        elide: Text.ElideRight
                    }

                    Rectangle {
                        visible: row.editing
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(0, parent.width - 25)
                        height: 22
                        radius: 2
                        color: Theme.shell
                        border.width: 1
                        border.color: Theme.accentLine

                        Text {
                            textFormat: Text.PlainText
                            anchors.left: parent.left
                            anchors.leftMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            visible: passwordInput.text.length === 0
                            text: "Password"
                            font.family: Theme.condensed
                            font.pixelSize: 12
                            color: Theme.dim
                        }

                        TextInput {
                            id: passwordInput
                            anchors.fill: parent
                            anchors.leftMargin: 6
                            anchors.rightMargin: 6
                            verticalAlignment: TextInput.AlignVCenter
                            font.family: Theme.condensed
                            font.pixelSize: 12
                            color: Theme.fg
                            echoMode: TextInput.Password
                            focus: row.editing
                            text: row.editing ? root.passwordText : ""
                            onTextChanged: if (row.editing) root.passwordText = text
                            Keys.onReturnPressed: root.submitPassword(row.modelData)
                            Keys.onEnterPressed: root.submitPassword(row.modelData)
                            Keys.onEscapePressed: root.cancelEditing()
                        }
                    }

                    Connections {
                        target: row.modelData
                        function onConnectionFailed() {
                            if (root.editingNetwork === row.modelData.name) root.passwordFailed = true;
                        }
                    }
                }
            }

            // Thin Spine-style scrollbar, shown only while the list is moving.
            Rectangle {
                visible: Networking.wifiEnabled && listView.contentHeight > listView.height
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
