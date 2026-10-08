import QtQuick
import "../../logic/ShownRows.js" as ShownRows
import "../../logic/Times.js" as Times
import qs.common
import qs.notifications
import qs.services

/**
 * Alerts tab body (mock 5C SPINE, Berri Notifications v2.dc.html): a filter
 * column on the left (unread count, do not disturb, All / Unread / one row per
 * app, READ ALL and CLEAR) and the grouped alert list on the right. Data comes
 * from the Notifications store. Filter and list are ListModels kept in step
 * with the store by ShownRows.js, so rows fade in and out and slide closed.
 * 1px gaps show the Theme.border backdrop.
 */
Item {
    id: root

    /** Filter key: "all", "unread" or "app:" followed by the sender name. */
    property string filter: "all"

    /** Clock for the relative times; set when the tab is shown, then every 30 s while it stays shown. */
    property real now: Date.now()

    readonly property int gap: 1
    readonly property int filterWidth: 210

    readonly property bool anyFilterApp: filter !== "all" && filter !== "unread"

    // Items the current filter shows.
    property var shown: []

    readonly property string viewName: filter === "all" ? "All notifications" : filter === "unread" ? "Unread" : filter.slice(4)
    readonly property string countText: shown.length + (shown.length === 1 ? " ITEM" : " ITEMS")

    function matches(item): bool {
        if (root.filter === "all") return true;
        if (root.filter === "unread") return !item.read;
        return "app:" + item.appName === root.filter;
    }

    // Rebuilds both models from the store. Called through callLater so a burst of changes runs once.
    function rebuild(): void {
        var items = Notifications.items;
        var visible = items.filter(root.matches);
        root.shown = visible;

        // Filter rows: All, Unread, then every app of the store.
        var apps = Notifications.apps;
        var rows = [
            { key: "all", label: "All", icon: "inbox", appName: "", appIcon: "", count: String(Notifications.totalCount) },
            { key: "unread", label: "Unread", icon: "circle-dot", appName: "", appIcon: "", count: String(Notifications.unreadCount) }
        ];
        for (var a = 0; a < apps.length; a++) {
            rows.push({ key: "app:" + apps[a].appName, label: apps[a].appName, icon: "", appName: apps[a].appName,
                appIcon: apps[a].appIcon, count: String(apps[a].count) });
        }
        ShownRows.matchRows(filterModel, rows);

        // A filtered app that has no alerts left goes back to All.
        if (root.anyFilterApp) {
            var found = false;
            for (var f = 0; f < apps.length; f++) if ("app:" + apps[f].appName === root.filter) found = true;
            if (!found) { root.filter = "all"; return; }
        }

        // List: one header per app (newest app first), then its alerts.
        var order = [];
        var byApp = Object.create(null);
        for (var i = 0; i < visible.length; i++) {
            var n = visible[i];
            if (!byApp[n.appName]) { byApp[n.appName] = []; order.push(n.appName); }
            byApp[n.appName].push(n);
        }
        var entries = [];
        for (var g = 0; g < order.length; g++) {
            var list = byApp[order[g]];
            entries.push({ key: "h:" + order[g], kind: "header", noteId: "", appName: order[g], appIcon: list[0].appIcon,
                title: "", body: "", stamp: 0, read: true, countText: String(list.length) });
            for (var k = 0; k < list.length; k++) {
                var it = list[k];
                entries.push({ key: "n:" + it.id, kind: "row", noteId: it.id, appName: it.appName, appIcon: it.appIcon,
                    title: it.summary, body: it.body, stamp: it.time, read: it.read, countText: "" });
            }
        }
        ShownRows.matchRows(listModel, entries);
    }

    // Marks every alert the filter shows as read.
    function readShown(): void {
        Notifications.markReadMany(root.shown.filter(function (n) { return !n.read; })
            .map(function (n) { return n.id; }));
    }

    // Dismisses every alert the filter shows.
    function clearShown(): void {
        Notifications.dismissMany(root.shown.map(function (n) { return n.id; }));
    }

    // Dismisses the alerts of one app that the filter shows.
    function clearApp(appName: string): void {
        Notifications.dismissMany(root.shown.filter(function (n) { return n.appName === appName; })
            .map(function (n) { return n.id; }));
    }

    onFilterChanged: Qt.callLater(root.rebuild)
    Component.onCompleted: {
        root.rebuild();
    }

    Connections {
        target: Notifications
        // Every store change sets a new items list; filter rows and counts derive from it.
        function onItemsChanged() { Qt.callLater(root.rebuild); }
    }

    // Runs only while this tab is shown. It fires once when it starts, so the
    // first age labels on reopen are right.
    Timer {
        interval: 30000
        running: root.visible
        repeat: true
        triggeredOnStart: true
        onTriggered: root.now = Date.now()
    }

    ListModel { id: filterModel }
    ListModel { id: listModel }

    Rectangle {
        anchors.fill: parent
        color: Theme.border
    }

    // ---------------- Filter column ----------------
    Item {
        id: filterColumn
        width: root.filterWidth
        height: parent.height

        AlertsUnreadCard {
            id: unreadCard
            width: parent.width
        }

        AlertsDndRow {
            id: dndRow
            y: unreadCard.height + root.gap
            width: parent.width
        }

        // All, Unread and the apps. Scrolls when there are more apps than fit.
        ListView {
            id: filterList
            y: dndRow.y + dndRow.height + root.gap
            width: parent.width
            height: Math.min(contentHeight, parent.height - y - root.gap - 34)
            interactive: contentHeight > height
            boundsBehavior: Flickable.StopAtBounds
            clip: true
            spacing: root.gap
            model: filterModel

            add: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.listMs } }
            remove: Transition { NumberAnimation { property: "opacity"; to: 0; duration: Theme.hoverMs } }
            displaced: Transition {
                StandardMotion {
                    property: "y"
                    duration: Theme.listMs
                }
            }

            delegate: AlertsFilterRow {
                id: filterRow

                required property var model

                width: ListView.view.width
                label: model.label
                icon: model.icon
                appName: model.appName
                appIcon: model.appIcon
                countText: model.count
                iconColor: model.key === "all" ? Theme.fg : model.key === "unread" ? Theme.accentLight : Theme.fg2
                selected: model.key === "all" ? root.filter === "all"
                    : model.key === "unread" ? root.filter === "unread"
                    : root.filter === model.key
                onClicked: root.filter = model.key
            }
        }

        // READ ALL and CLEAR fill the rest of the column.
        Row {
            y: filterList.y + filterList.height + root.gap
            width: parent.width
            height: parent.height - y
            spacing: root.gap

            HoverButton {
                width: (parent.width - root.gap) / 2
                height: parent.height
                fill: Theme.card
                label: "READ ALL"
                onClicked: root.readShown()
            }

            HoverButton {
                width: (parent.width - root.gap) / 2
                height: parent.height
                fill: Theme.card
                label: "CLEAR"
                onClicked: root.clearShown()
            }
        }
    }

    // ---------------- Alert list ----------------
    Item {
        id: listColumn
        x: root.filterWidth + root.gap
        width: parent.width - x
        height: parent.height

        // View name, item count, and the snoozed button.
        Rectangle {
            id: viewHeader
            width: parent.width
            height: 40
            color: Theme.card

            AlertsSwap {
                id: viewTitle
                x: 14
                anchors.verticalCenter: parent.verticalCenter
                text: root.viewName.toUpperCase()
                color: Theme.fg
                font.family: Theme.condensed
                font.pixelSize: 18
                font.weight: Font.Medium
                travel: 8
            }

            AlertsSwap {
                x: viewTitle.x + viewTitle.width + 12
                anchors.verticalCenter: parent.verticalCenter
                text: root.countText
                color: Theme.dim
                font.family: Theme.mono
                font.pixelSize: 9
                font.weight: Font.Medium
                font.letterSpacing: 0.72
                travel: 5
            }

            HoverButton {
                id: snoozedButton
                x: parent.width - 14 - width
                anchors.verticalCenter: parent.verticalCenter
                sidePadding: 8
                height: 24
                fill: Theme.raised
                textColor: Theme.dim
                letterSpacing: 0.54
                label: Notifications.snoozedCount + " SNOOZED · SHOW"
                opacity: Notifications.snoozedCount > 0 ? 1 : 0
                enabled: Notifications.snoozedCount > 0
                Fade on opacity  { duration: Theme.stateMs }
                onClicked: Notifications.unsnoozeAll()
            }
        }

        // Do not disturb banner. One progress value drives height and fade;
        // the list below follows the height, so closing plays opening backwards.
        AlertsDndBanner {
            id: dndBanner
            y: viewHeader.height + root.gap
            width: parent.width
            gap: root.gap
        }

        Rectangle {
            y: viewHeader.height + root.gap + dndBanner.height
            width: parent.width
            height: parent.height - y
            color: Theme.card
            clip: true

            ListView {
                id: list
                anchors.fill: parent
                model: listModel
                boundsBehavior: Flickable.StopAtBounds
                clip: true

                add: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.listMs } }
                remove: Transition {
                    ParallelAnimation {
                        NumberAnimation { property: "opacity"; to: 0; duration: Theme.listMs }
                        NumberAnimation { property: "x"; to: 32; duration: Theme.listMs }
                    }
                }
                displaced: Transition {
                    StandardMotion {
                        property: "y"
                        duration: 240
                    }
                }

                delegate: Item {
                    id: cell

                    required property string key
                    required property string kind
                    required property string noteId
                    required property string appName
                    required property string appIcon
                    required property string title
                    required property string body
                    required property real stamp
                    required property bool read
                    required property string countText

                    width: ListView.view.width
                    height: cell.kind === "header" ? headerItem.height : rowItem.height

                    AlertsGroupHeader {
                        id: headerItem
                        visible: cell.kind === "header"
                        width: parent.width
                        appName: cell.appName
                        appIcon: cell.appIcon
                        countText: cell.countText
                        onClear: root.clearApp(cell.appName)
                    }

                    AlertsRow {
                        id: rowItem
                        visible: cell.kind === "row"
                        width: parent.width
                        title: cell.title
                        body: cell.body
                        read: cell.read
                        timeText: Times.ageText(cell.stamp, root.now, "shortCaps")
                        onOpened: if (!cell.read) Notifications.markRead(cell.noteId)
                        onMarkRead: Notifications.markRead(cell.noteId)
                        onSnooze: Notifications.snooze(cell.noteId, Notifications.defaultSnoozeMinutes)
                        onDismiss: Notifications.dismiss(cell.noteId)
                    }
                }
            }

            // Shown when nothing is in view.
            Column {
                x: 14
                y: 16
                spacing: 7
                opacity: listModel.count === 0 ? 1 : 0
                visible: opacity > 0.001
                Fade on opacity  { duration: Theme.stateMs }

                Text {
                    textFormat: Text.PlainText
                    text: "ALL CAUGHT UP"
                    font.family: Theme.condensed
                    font.pixelSize: 18
                    font.weight: Font.Medium
                    color: Theme.fg
                }

                Text {
                    textFormat: Text.PlainText
                    text: root.filter === "all" ? "NOTHING NEW. NOTIFICATIONS WILL COLLECT HERE." : "NOTHING IN THIS FILTER."
                    font.family: Theme.mono
                    font.pixelSize: 9
                    font.weight: Font.Medium
                    font.letterSpacing: 0.54
                    color: Theme.dim
                }
            }
        }
    }
}
