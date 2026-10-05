pragma Singleton
import QtQuick

/**
 * Per-monitor arbiter between the dashboard (Pill.qml) and the theme picker
 * (ThemeNotch.qml): the mock never shows both open on one monitor at once.
 * Keyed by screen name (e.g. "eDP-2"), so each monitor's pill/picker pair is
 * independent of every other monitor's.
 */
QtObject {
    id: root

    /** screenName -> "pill" | "picker" | null; which panel currently owns that monitor. */
    property var openKind: ({})

    /** Fired when a monitor's other panel must close because this one is opening. */
    signal closeRequested(string screenName, string kind)

    /** Call before opening; forces the other kind closed on that monitor if it's open. */
    function requestOpen(screenName, kind) {
        var cur = root.openKind[screenName];
        if (cur && cur !== kind)
            root.closeRequested(screenName, cur);
        var next = root.openKind;
        next[screenName] = kind;
        root.openKind = next;
    }

    /** Call once a panel has finished closing, so a later requestOpen sees it's free. */
    function notifyClosed(screenName, kind) {
        if (root.openKind[screenName] !== kind)
            return;
        var next = root.openKind;
        next[screenName] = null;
        root.openKind = next;
    }
}
