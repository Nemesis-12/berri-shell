import QtQuick
import Quickshell.Hyprland
import "../logic/Times.js" as Times
import "../logic/PixelGrid.js" as PixelGrid
import "../logic/NotificationLogic.js" as NotificationLogic
import qs.common
import qs.notifications
import qs.services

/**
 * Notification pop-up of one monitor (ticket 52, Spine style). The pill's own
 * rectangle grows into a 380 px card and shrinks back as the exact reverse.
 * One progress value (0 pill, 1 card) drives width, height, border, content
 * fade and shadow; the curve is the pill-hover curve.
 *
 * Rules: shown only on the focused monitor, never while the dashboard is
 * open or a real fullscreen window (mode 2) covers the monitor. A maximized
 * window (mode 1) does not block; critical items always show. The newest item shows;
 * older ones wait (count "+N") and show one after the other. Normal items
 * close after 5 s (hover pauses unless the sender timeout ends first), critical
 * ones stay until dismissed.
 * A click on the card opens the Alerts tab. Place this item above the Pill
 * in the same window and add cardX/cardY/cardWidth/cardHeight to the mask.
 */
Item {
    id: root

    /** The Pill of this monitor: start rectangle, dashboard state, tab list. */
    required property var pill
    property string screenName: ""
    /** True while a real fullscreen window (not maximized) covers this monitor; holds back non-critical items. */
    property bool blocked: false

    readonly property int cardMaxWidth: 380
    readonly property int cardPadding: 12

    /** True from the moment a card grows until it has fully shrunk (the pill hides its content). */
    readonly property bool active: open || queue.length > 0

    /** Card rectangle in this item's coordinates; zero size while nothing shows. */
    readonly property real cardX: card.visible ? card.x : 0
    readonly property real cardY: card.visible ? card.y : 0
    readonly property real cardWidth: card.visible ? card.width : 0
    readonly property real cardHeight: card.visible ? card.height : 0

    readonly property real dpr: pill.dpr

    property var current: null
    property bool open: false
    property bool hovered: false
    /** Items that wait, newest last. */
    property var queue: []
    readonly property int maxQueued: NotificationLogic.limits.queued
    /** Width of the pill when the card started to grow; the card shrinks back to it. */
    property real startWidth: 124
    property real progress: 0

    readonly property bool critical: current !== null && current.urgency === "critical"
    readonly property bool focusedHere: Hyprland.focusedMonitor !== null
        && Hyprland.focusedMonitor.name === screenName

    // Moves progress to `to` from where it is now (also when it is mid-way).
    SpringMotion {
        id: slide
        target: root
        property: "progress"
        duration: 500
        // The shrink has ended: the next waiting item may grow.
        onFinished: if (!root.open && root.current !== null) root.showNext()
    }

    function slideTo(to: real): void {
        slide.stop();
        slide.to = to;
        slide.start();
    }

    /** Takes a new notification from the store. */
    function receive(item) {
        if (root.pill.panelOpen || (root.blocked && item.urgency !== "critical") || !root.focusedHere) return;
        if (root.current === null) {
            root.showNow(item);
        } else if (root.open) {
            root.queue = NotificationLogic.queuePopup(root.queue, root.current, root.maxQueued);
            root.showNow(item);
        } else {
            root.queue = NotificationLogic.queuePopup(root.queue, item, root.maxQueued);
        }
    }

    /** Replaces the same pop-up in place, including its actions. Never adds a queued copy. */
    function update(item) {
        if (root.current !== null && root.current.id === item.id) {
            root.current = item;
            root.armTimer();
        }
        root.queue = root.queue.map(function (n) { return n.id === item.id ? item : n; });
    }

    function showNow(item) {
        if (!root.open) root.startWidth = root.pill.maskWidth;
        root.current = item;
        root.clock = Date.now();
        root.open = true;
        root.slideTo(1);
        root.armTimer();
    }

    /** Shrinks the card; the next waiting item grows after it has settled. */
    function close() {
        if (!root.open) return;
        root.open = false;
        root.hovered = false;
        dismissTimer.stop();
        root.slideTo(0);
    }

    /** Drops everything at once (dashboard opens, fullscreen starts, card clicked). */
    function hideNow() {
        dismissTimer.stop();
        root.queue = [];
        root.open = false;
        root.hovered = false;
        slide.stop();
        root.progress = 0;
        root.current = null;
    }

    function armTimer() {
        dismissTimer.stop();
        if (root.open && !root.critical && !root.hovered) dismissTimer.start();
    }

    onHoveredChanged: armTimer()

    /** Forgets an item that left the store: shrinks its card and cuts it from the queue. */
    function drop(id: string): void {
        root.queue = root.queue.filter(function (n) { return n.id !== id; });
        if (root.open && root.current !== null && root.current.id === id) root.close();
    }

    /** Clock for the age text; a timer refreshes it while a card shows. */
    property real clock: Date.now()

    // Refreshes the age text while a card shows.
    Timer {
        interval: 30000
        running: root.current !== null
        repeat: true
        onTriggered: root.clock = Date.now()
    }

    function openAlerts() {
        if (root.current === null) return;
        Notifications.markRead(root.current.id);
        root.hideNow();
        root.pill.activeTab = root.pill.tabIds.indexOf("alerts");
        root.pill.openPanel();
    }

    Connections {
        target: Notifications
        function onArrived(item) { root.receive(item); }
        function onUpdated(item) { root.update(item); }
        function onRemoved(id) { root.drop(id); }
    }

    Connections {
        target: root.pill
        function onPanelOpenChanged() { if (root.pill.panelOpen) root.hideNow(); }
    }

    onBlockedChanged: if (blocked && !critical) hideNow()

    Timer {
        id: dismissTimer
        interval: 5000
        onTriggered: root.close()
    }

    /** After a shrink: shows the next waiting item, or lets go of the card. */
    function showNext() {
        while (root.queue.length > 0) {
            var next = root.queue[root.queue.length - 1];
            root.queue = root.queue.slice(0, -1);
            if (root.blocked && next.urgency !== "critical") continue;
            root.showNow(next);
            return;
        }
        root.current = null;
    }

    // Layout numbers of the card content.
    readonly property int actionCount: current && current.actions ? Math.min(2, current.actions.length) : 0
    readonly property real contentHeight: 24 + 8 + 18 + (bodyText.text !== "" ? 4 + bodyText.implicitHeight : 0)
        + (actionCount > 0 ? 10 + 30 : 0)
    readonly property real fullHeight: PixelGrid.snap(2 + 2 * cardPadding + contentHeight, dpr)

    PanelShadow {
        target: card
        visible: card.visible
        opacity: card.opacity
        openProgress: root.progress
        restOffset: 4
        restBlur: 14
        openOffset: 24
        openStrength: 0.45
        openBlur: 32
    }

    Rectangle {
        id: card

        // Fixed rounded center, so both edges land on whole device pixels.
        readonly property real halfWidth: PixelGrid.snap((root.startWidth + (root.cardMaxWidth - root.startWidth) * root.progress) / 2, root.dpr)
        readonly property real centerX: root.pill.x + PixelGrid.snap(root.pill.width / 2, root.dpr)

        visible: root.current !== null
        width: halfWidth * 2
        x: centerX - halfWidth
        y: root.pill.y
        height: PixelGrid.snap(root.pill.pillHeight + (root.fullHeight - root.pill.pillHeight) * root.progress, root.dpr)
        radius: 8
        color: Theme.shell
        border.width: 1
        border.color: Qt.alpha(Theme.border, root.progress)
        clip: true
        // Over the last part of the shrink the card fades, so the pill's clock beneath shows through.
        opacity: Math.min(1, root.progress / 0.12)

        HoverHandler {
            onHoveredChanged: root.hovered = hovered && root.open
        }

        MouseArea {
            anchors.fill: parent
            enabled: root.open
            cursorShape: Qt.PointingHandCursor
            onClicked: root.openAlerts()
        }

        // Laid out from the card's fixed center; the card clips it while it grows.
        Item {
            id: content
            x: card.width / 2 - root.cardMaxWidth / 2 + root.cardPadding
            y: root.cardPadding
            width: root.cardMaxWidth - 2 * root.cardPadding
            height: root.contentHeight
            opacity: Math.max(0, Math.min(1, (root.progress - 0.3) / 0.4))

            readonly property color lineColor: root.critical ? Theme.accentLight : Theme.dim

            Item {
                id: header
                width: parent.width
                height: 24

                Rectangle {
                    id: tile
                    width: 22
                    height: 22
                    anchors.verticalCenter: parent.verticalCenter
                    radius: 2
                    color: root.critical ? Theme.accentFill : Theme.raised
                    ColorFade on color  { duration: Theme.stateMs }

                    AlertsAppIcon {
                        anchors.centerIn: parent
                        size: 13
                        strokeWidth: 2
                        appName: root.current ? root.current.appName : ""
                        appIcon: root.current ? root.current.appIcon : ""
                        color: root.critical ? Theme.accentLight : Theme.fg2
                        ColorFade on color  { duration: Theme.stateMs }
                    }
                }

                Text {
                    textFormat: Text.PlainText
                    id: appName
                    x: tile.width + 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.current ? root.current.appName : ""
                    font.family: Theme.condensed
                    font.weight: Font.Medium
                    font.pixelSize: 12
                    color: content.lineColor
                }

                Text {
                    textFormat: Text.PlainText
                    id: timeText
                    anchors.left: appName.right
                    anchors.leftMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.current ? Times.ageText(root.current.time, root.clock, "short") : ""
                    font.family: Theme.mono
                    font.weight: Font.Medium
                    font.pixelSize: 10
                    color: content.lineColor
                }

                Text {
                    textFormat: Text.PlainText
                    anchors.left: timeText.right
                    anchors.leftMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.queue.length > 0
                    text: "+" + root.queue.length
                    font.family: Theme.mono
                    font.weight: Font.Medium
                    font.pixelSize: 10
                    color: Theme.dim
                }

                // Dismiss button, shown while the card is hovered.
                Rectangle {
                    width: 22
                    height: 22
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    radius: 2
                    color: closeArea.containsMouse ? Theme.border : "transparent"
                    opacity: root.hovered ? 1 : 0
                    Fade on opacity {}
                    ColorFade on color {}

                    Icon {
                        anchors.centerIn: parent
                        name: "x"
                        size: 12
                        strokeWidth: 2.2
                        color: closeArea.containsMouse ? Theme.fg : Theme.dim
                        ColorFade on color {}
                    }

                    MouseArea {
                        id: closeArea
                        anchors.fill: parent
                        enabled: root.open && root.hovered
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Notifications.dismiss(root.current.id);
                            root.close();
                        }
                    }
                }
            }

            Text {
                textFormat: Text.PlainText
                id: titleText
                y: 32
                width: parent.width
                text: root.current ? root.current.summary : ""
                elide: Text.ElideRight
                maximumLineCount: 1
                font.family: Theme.condensed
                font.weight: Font.Medium
                font.pixelSize: 16
                lineHeight: 18
                lineHeightMode: Text.FixedHeight
                color: Theme.fg
            }

            Text {
                id: bodyText
                y: 32 + 18 + 4
                width: parent.width
                text: root.current ? root.current.body : ""
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                font.family: Theme.condensed
                font.pixelSize: 12
                lineHeight: 17
                lineHeightMode: Text.FixedHeight
                color: Theme.dim
            }

            Row {
                y: 32 + 18 + (bodyText.text !== "" ? 4 + bodyText.implicitHeight : 0) + 10
                spacing: 6
                visible: root.actionCount > 0

                Repeater {
                    model: root.current && root.current.actions ? root.current.actions.slice(0, 2) : []

                    Rectangle {
                        id: button
                        required property var modelData
                        width: label.implicitWidth + 28
                        height: 30
                        radius: 5
                        color: buttonArea.containsMouse ? Theme.hover : Theme.raised
                        ColorFade on color {}

                        Text {
                            textFormat: Text.PlainText
                            id: label
                            anchors.centerIn: parent
                            text: button.modelData.label
                            font.family: Theme.condensed
                            font.weight: Font.Medium
                            font.pixelSize: 12
                            color: buttonArea.containsMouse ? Theme.fg : Theme.fg2
                            ColorFade on color {}
                        }

                        MouseArea {
                            id: buttonArea
                            anchors.fill: parent
                            enabled: root.open
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                Notifications.invokeAction(root.current.id, button.modelData.id);
                                root.close();
                            }
                        }
                    }
                }
            }
        }
    }
}
