import QtQuick
import "../logic/Timeline.js" as Timeline

/**
 * The one slide operation of a panel that grows out of a screen edge (the pill
 * dashboard, the theme picker). The panel sets `totalMs` and `closeEndMs` from
 * its timeline (see PanelTimeline.js) and derives every size from `elapsedMs`.
 *
 * `progress` goes in a straight line over `totalMs`. Close runs it back, so
 * the steps run in reversed order. A close from fully open ends at `closeEndMs`
 * (all steps at rest) and cuts the slow tail; a close from mid-way plays the
 * open back to 0 so nothing jumps.
 *
 * It also keeps the per-monitor rule: opening asks PanelCoordinator to close the
 * other panel of the same monitor (`screenName`), with that panel's normal close.
 * And it runs a dialog request after the panel is closed (see closeThenRun), so
 * a normal window never opens under the Overlay panel.
 */
QtObject {
    id: root

    /** Monitor name and the coordinator kind of this panel: "pill" or "picker". */
    property string screenName: ""
    property string kind: ""

    /** Length of the whole open motion, in ms. */
    property int totalMs: 1
    /** The time (ms of the open motion) at which every close step is at rest. */
    property int closeEndMs: 0

    /** True from the open call until the close call: where the motion is going. */
    property bool open: false
    /** The open motion, 0 (rest) to 1 (fully open), in a straight line over `totalMs`. */
    property real progress: 0
    /** True when the close started from fully open: the steps ease out into rest. A close that starts mid-way plays the open back in a straight line. */
    property bool closeFromOpen: false

    /** Time since the open started, in ms. Every step of the motion reads this. */
    readonly property real elapsedMs: progress * totalMs
    /** True while the motion runs toward rest and its steps ease out. */
    readonly property bool closing: !open && closeFromOpen
    /** True while the panel is open, opening or closing. */
    readonly property bool active: open || progress > 0

    /** The close motion has reached rest (not sent by closeAtOnce). */
    signal closeFinished()

    // The dialog request that waits for the panel to be closed.
    property var pendingDialog: null

    /** Starts the open motion; also while a close is running. */
    function openSlide() {
        if (root.open) return;
        PanelCoordinator.requestOpen(root.screenName, root.kind);
        root.open = true;
        root.slideTo(1);
    }

    /** Starts the close motion. No-op unless open. */
    function closeSlide() {
        if (!root.open) return;
        const close = Timeline.startClose(root.progress, root.closeEndMs, root.totalMs);
        root.closeFromOpen = close.fromOpen;
        root.open = false;
        root.slideTo(close.target);
    }

    /** Stops the motion and closes at once (fullscreen starts). A waiting dialog request still runs, as the panel is closed. */
    function closeAtOnce() {
        slide.stop();
        root.open = false;
        root.progress = 0;
        root.closeFromOpen = false;
    }

    /** Runs `openDialog` once the panel is at rest; at once if it is at rest now. The caller starts the close. */
    function runAfterClose(openDialog: var): void {
        if (root.active) root.pendingDialog = openDialog;
        else openDialog();
    }

    /**
     * A tab asks for a dialog (a normal window, so it would open under the Overlay
     * panel). With the panel at rest, `openDialog` runs at once. Otherwise the panel
     * closes with its normal motion; `afterClose` true waits for rest before
     * `openDialog` runs, false runs it as the close starts.
     */
    function closeThenRun(openDialog: var, afterClose: bool): void {
        if (afterClose) root.runAfterClose(openDialog);
        root.closeSlide();
        if (!afterClose) openDialog();
    }

    onActiveChanged: {
        if (root.active) return;
        PanelCoordinator.notifyClosed(root.screenName, root.kind);
        if (root.pendingDialog) {
            const openDialog = root.pendingDialog;
            root.pendingDialog = null;
            openDialog();
        }
    }

    // Moves `progress` to `to` in a straight line, at the speed of the full
    // motion, from where it is now (also when it is mid-way).
    function slideTo(to: real): void {
        slide.stop();
        slide.to = to;
        slide.duration = Timeline.slideDurationMs(root.totalMs, root.progress, to);
        slide.start();
    }

    property NumberAnimation slide: NumberAnimation {
        id: slide
        target: root
        property: "progress"
        easing.type: Easing.Linear
        // A smooth close ends where all steps are at rest: the last part of the timeline is cut.
        onFinished: {
            if (root.open) return;
            root.progress = 0;
            root.closeFromOpen = false;
            root.closeFinished();
        }
    }

    property Connections coordinator: Connections {
        target: PanelCoordinator
        function onCloseRequested(screenName, kind) {
            if (screenName === root.screenName && kind === root.kind)
                root.closeSlide();
        }
    }
}
