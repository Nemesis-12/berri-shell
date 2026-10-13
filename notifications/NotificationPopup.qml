import QtQuick
import Quickshell.Hyprland
import "../logic/Times.js" as Times
import "../logic/PixelGrid.js" as PixelGrid
import "../logic/NotificationLogic.js" as NotificationLogic
import qs.common
import qs.services

/**
 * Notification pop-up of one monitor (Spine style). The pill's own
 * rectangle grows into a 380 px card and shrinks back as the exact reverse.
 * One progress value (0 pill, 1 card) drives width, height, border, content
 * fade and shadow; the curve is the pill-hover curve.
 *
 * Rules: shown only on the focused monitor, never while the dashboard is
 * open or a real fullscreen window (mode 2) covers the monitor. A maximized
 * window (mode 1) does not block; critical items always show. The newest item shows;
 * older ones wait (count "+N") and show one after the other. Normal items
 * close after 5 s (hover pauses the time and keeps what is left; the sender timeout can still end it), critical
 * ones stay until dismissed.
 * A click on the card opens the Alerts tab. Place this item above the Pill
 * in the same window. Pass its anchor in this item's coordinates and add
 * cardX/cardY/cardWidth/cardHeight to the mask.
 */
Item {
    id: root

    /** Rest shape to grow from, in this item's coordinates. Its width is captured at the start. */
    required property rect anchorRect
    /** Monitor scale used to round card sizes to device pixels. */
    required property real dpr
    /** True while the dashboard is open, opening or closing. */
    required property bool dashboardOpen
    /** The host opens Alerts after the pop-up has marked its item read and hidden. */
    signal openAlertsRequested()
    property string screenName: ""
    /** True while a real fullscreen window (not maximized) covers this monitor; holds back non-critical items. */
    property bool blocked: false

    readonly property int cardMaxWidth: 380
    readonly property int _cardPadding: 12

    /** True from the moment a card grows until it has fully shrunk (the pill hides its content). */
    readonly property bool active: _open || (_current !== null && _queue.length > 0)

    /** Card rectangle in this item's coordinates; zero size while nothing shows. */
    readonly property real cardX: card.visible ? card.x : 0
    readonly property real cardY: card.visible ? card.y : 0
    readonly property real cardWidth: card.visible ? card.width : 0
    readonly property real cardHeight: card.visible ? card.height : 0

    property var _current: null
    property bool _open: false
    property bool _hovered: false
    /** How long a normal card stays open. */
    property int _showMs: 5000
    /** Time left on the timeout while hover pauses it. */
    property int _remainingMs: 5000
    property real _timeoutStartedAt: 0
    /** Items that wait, newest last. */
    property var _queue: []
    readonly property int _maxQueued: NotificationLogic.limits.queued
    /** Width of the pill when the card started to grow; the card shrinks back to it. */
    property real _startWidth: 124
    property real _progress: 0

    readonly property bool _critical: _current !== null && _current.urgency === "critical"
    readonly property bool _focusedHere: Hyprland.focusedMonitor !== null
        && Hyprland.focusedMonitor.name === screenName

    // Moves progress to `to` from where it is now (also when it is mid-way).
    SpringMotion {
        id: slide
        target: root
        property: "_progress"
        duration: 500
        // The shrink has ended: the next waiting item may grow.
        onFinished: if (!root._open && root._current !== null) root._showNext()
    }

    /** Starts or redirects the existing card motion. */
    function _slideTo(to: real): void {
        slide.stop();
        slide.to = to;
        slide.start();
    }

    /** Takes a new notification from the store. */
    function _receive(item) {
        if ((root.blocked && item.urgency !== "critical") || !root._focusedHere) return;
        if (root.dashboardOpen) {
            if (NotificationLogic.popupWaits(item)) root._queue = NotificationLogic.queuePopup(root._queue, item, root._maxQueued);
        } else if (root._current === null) {
            root._showNow(item);
        } else if (root._open) {
            root._queue = NotificationLogic.queuePopup(root._queue, root._current, root._maxQueued);
            root._showNow(item);
        } else {
            root._queue = NotificationLogic.queuePopup(root._queue, item, root._maxQueued);
        }
    }

    /** Replaces the same pop-up in place, including its actions. Never adds a queued copy. */
    function _update(item) {
        if (root._current !== null && root._current.id === item.id) {
            root._current = item;
            root._restartTimeout();
        }
        root._queue = root._queue.map(function (n) { return n.id === item.id ? item : n; });
    }

    /** Shows one snapshot and keeps the captured rest width until the shrink ends. */
    function _showNow(item) {
        if (!root._open) root._startWidth = root.anchorRect.width;
        root._current = item;
        root._clock = Date.now();
        root._open = true;
        root._slideTo(1);
        root._restartTimeout();
    }

    /** Shrinks the card; the next waiting item grows after it has settled. */
    function _close() {
        if (!root._open) return;
        root._open = false;
        root._hovered = false;
        dismissTimer.stop();
        root._slideTo(0);
    }

    /** Hides the card at once (dashboard opens, fullscreen starts, card clicked). Waiting critical and transient items stay. */
    function _hideNow() {
        dismissTimer.stop();
        root._queue = root._queue.filter(NotificationLogic.popupWaits);
        root._open = false;
        root._hovered = false;
        slide.stop();
        root._progress = 0;
        root._current = null;
    }

    /** Starts the full normal-item timeout again (a new or replaced card). */
    function _restartTimeout() {
        root._remainingMs = root._showMs;
        root._resumeTimeout();
    }

    /** Runs the timeout for the time that is left, unless the card is critical, closed or hovered. */
    function _resumeTimeout() {
        dismissTimer.stop();
        if (!root._open || root._critical || root._hovered) return;
        dismissTimer.interval = Math.max(1, root._remainingMs);
        root._timeoutStartedAt = Date.now();
        dismissTimer.start();
    }

    /** Sets hover. Hover pauses the timeout; leaving continues with the time that was left. */
    function _setHovered(on: bool): void {
        if (on && dismissTimer.running) {
            root._remainingMs = Math.max(1, root._remainingMs - (Date.now() - root._timeoutStartedAt));
            dismissTimer.stop();
        }
        root._hovered = on;
        if (!on) root._resumeTimeout();
    }

    /** Forgets an item that left the store: shrinks its card and cuts it from the queue. */
    function _drop(id: string): void {
        root._queue = root._queue.filter(function (n) { return n.id !== id; });
        if (root._open && root._current !== null && root._current.id === id) root._close();
    }

    /** Clock for the age text; a timer refreshes it while a card shows. */
    property real _clock: Date.now()

    // Refreshes the age text while a card shows.
    Timer {
        interval: 30000
        running: root._current !== null
        repeat: true
        onTriggered: root._clock = Date.now()
    }

    /** Marks the current item read, hides the card, then asks the host to open Alerts. */
    function _openAlerts() {
        // The pill is hidden in fullscreen, so nothing would reveal the dashboard.
        if (root._current === null || root.blocked) return;
        Notifications.markRead(root._current.id);
        root._hideNow();
        root.openAlertsRequested();
    }

    Connections {
        target: Notifications
        function onArrived(item) { root._receive(item); }
        function onHandedOver(item) { root._receive(item); }
        function onUpdated(item) { root._update(item); }
        function onRemoved(id) { root._drop(id); }
    }

    // Focus moved to another monitor: waiting cards go there. The card on screen finishes here.
    Connections {
        target: Hyprland
        function onFocusedMonitorChanged() {
            if (root._focusedHere || Hyprland.focusedMonitor === null || root._queue.length === 0) return;
            var waiting = root._queue;
            root._queue = [];
            // The other monitor's focus binding may not have updated yet.
            Qt.callLater(function () { Notifications.handOver(waiting); });
        }
    }

    onDashboardOpenChanged: {
        if (dashboardOpen) _hideNow();
        else _showNext();
    }

    // Fullscreen starts: only critical cards stay, the current one and the waiting ones.
    onBlockedChanged: {
        if (!blocked) return;
        if (!_critical) _hideNow();
        root._queue = root._queue.filter(function (n) { return n.urgency === "critical"; });
        if (_current === null) _showNext();
    }

    Timer {
        id: dismissTimer
        onTriggered: root._close()
    }

    /** After a shrink: shows the next waiting item, or lets go of the card. */
    function _showNext() {
        while (root._queue.length > 0) {
            var next = root._queue[root._queue.length - 1];
            root._queue = root._queue.slice(0, -1);
            if (root.blocked && next.urgency !== "critical") continue;
            root._showNow(next);
            return;
        }
        root._current = null;
    }

    // Layout numbers of the card content.
    readonly property int _actionCount: _current && _current.actions ? Math.min(2, _current.actions.length) : 0
    readonly property real _contentHeight: 24 + 8 + 18 + (bodyText.text !== "" ? 4 + bodyText.implicitHeight : 0)
        + (_actionCount > 0 ? 10 + 30 : 0)
    readonly property real _fullHeight: PixelGrid.snap(2 + 2 * _cardPadding + _contentHeight, dpr)

    PanelShadow {
        target: card
        visible: card.visible
        opacity: card.opacity
        openProgress: root._progress
        restOffset: 4
        restBlur: 14
        openOffset: 24
        openStrength: 0.45
        openBlur: 32
    }

    Rectangle {
        id: card

        // Fixed rounded center, so both edges land on whole device pixels.
        readonly property real halfWidth: PixelGrid.snap((root._startWidth + (root.cardMaxWidth - root._startWidth) * root._progress) / 2, root.dpr)
        readonly property real centerX: root.anchorRect.x + root.anchorRect.width / 2

        visible: root._current !== null
        width: halfWidth * 2
        x: centerX - halfWidth
        y: root.anchorRect.y
        height: PixelGrid.snap(root.anchorRect.height + (root._fullHeight - root.anchorRect.height) * root._progress, root.dpr)
        radius: 8
        color: Theme.shell
        border.width: 1
        border.color: Qt.alpha(Theme.border, root._progress)
        clip: true
        // Over the last part of the shrink the card fades, so the pill's clock beneath shows through.
        opacity: Math.min(1, root._progress / 0.12)

        HoverHandler {
            onHoveredChanged: root._setHovered(hovered && root._open)
        }

        MouseArea {
            anchors.fill: parent
            enabled: root._open && !root.blocked
            cursorShape: Qt.PointingHandCursor
            onClicked: root._openAlerts()
        }

        // Laid out from the card's fixed center; the card clips it while it grows.
        Item {
            id: content
            x: card.width / 2 - root.cardMaxWidth / 2 + root._cardPadding
            y: root._cardPadding
            width: root.cardMaxWidth - 2 * root._cardPadding
            height: root._contentHeight
            opacity: Math.max(0, Math.min(1, (root._progress - 0.3) / 0.4))

            readonly property color lineColor: root._critical ? Theme.accentLight : Theme.dim

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
                    color: root._critical ? Theme.accentFill : Theme.raised
                    ColorFade on color  { duration: Theme.stateMs }

                    AlertsAppIcon {
                        anchors.centerIn: parent
                        size: 13
                        strokeWidth: 2
                        appName: root._current ? root._current.appName : ""
                        appIcon: root._current ? root._current.appIcon : ""
                        color: root._critical ? Theme.accentLight : Theme.fg2
                        ColorFade on color  { duration: Theme.stateMs }
                    }
                }

                Text {
                    textFormat: Text.PlainText
                    id: appName
                    x: tile.width + 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: root._current ? root._current.appName : ""
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
                    text: root._current ? Times.ageText(root._current.time, root._clock, "short") : ""
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
                    visible: root._queue.length > 0
                    text: "+" + root._queue.length
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
                    opacity: root._hovered ? 1 : 0
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
                        enabled: root._open && root._hovered
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Notifications.dismiss(root._current.id);
                            root._close();
                        }
                    }
                }
            }

            Text {
                textFormat: Text.PlainText
                id: titleText
                y: 32
                width: parent.width
                text: root._current ? root._current.summary : ""
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
                text: root._current ? root._current.body : ""
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
                visible: root._actionCount > 0

                Repeater {
                    model: root._current && root._current.actions ? root._current.actions.slice(0, 2) : []

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
                            enabled: root._open
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                Notifications.invokeAction(root._current.id, button.modelData.id);
                                root._close();
                            }
                        }
                    }
                }
            }
        }
    }
}
