import QtQuick
import qs.services

/** Owns wallpaper selection, assignment, keyboard input, and the file dialog request. */
Item {
    id: root

    property string screenName: ""
    property bool shown: false
    property int rowGap: 15

    readonly property string focusedPath: wallpapersCarousel.focusedPath
    readonly property bool focusIsAdd: wallpapersCarousel.focusIsAdd

    signal addRequested
    signal addDone(string path)

    /** Focuses the wallpaper assigned to this monitor, or the first card. */
    function focusToCurrent() {
        wallpapersCarousel.focusToCurrent();
    }

    /** Opens the file dialog after the notch has closed. */
    function chooseFile() {
        wallpapersCarousel.chooseFile();
    }

    /** Assigns the focused wallpaper to one monitor, or clears it if that monitor already shows it. */
    function assignFocusedToMonitor(number) {
        if (root.focusIsAdd) return;
        var monitors = Wallpapers.monitors;
        for (var i = 0; i < monitors.length; i++) {
            if (monitors[i].number !== number) continue;
            if (Wallpapers.numbersShowing(root.focusedPath).indexOf(number) !== -1)
                Wallpapers.unassign(root.focusedPath, [monitors[i].name]);
            else
                Wallpapers.assign(root.focusedPath, [monitors[i].name]);
            return;
        }
    }

    /** Assigns the focused wallpaper to every monitor unless all already show it. */
    function assignFocusedToAll() {
        if (root.focusIsAdd) return;
        var monitors = Wallpapers.monitors;
        if (Wallpapers.numbersShowing(root.focusedPath).length === monitors.length) return;
        var names = [];
        for (var i = 0; i < monitors.length; i++) names.push(monitors[i].name);
        Wallpapers.assign(root.focusedPath, names);
    }

    /** Handles wallpaper-tab keys and returns true when the event belongs to this body. */
    function handleKey(event) {
        if (event.key === Qt.Key_Left || event.key === Qt.Key_Right) {
            wallpapersCarousel.moveFocus(event.key === Qt.Key_Left ? -1 : 1);
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (root.focusIsAdd) root.addRequested();
            else root.assignFocusedToAll();
        } else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
            root.assignFocusedToMonitor(event.key - Qt.Key_0);
        } else if (event.key === Qt.Key_A) {
            root.assignFocusedToAll();
        } else if (event.key === Qt.Key_I) {
            Wallpapers.identify();
        } else {
            return false;
        }
        event.accepted = true;
        return true;
    }

    WallpapersCarousel {
        id: wallpapersCarousel
        visible: root.shown
        screenName: root.screenName
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: showOnRow.top
        anchors.bottomMargin: root.rowGap
        onAddRequested: root.addRequested()
        onAddDone: path => {
            if (path) wallpapersCarousel.focusPath(path);
            root.addDone(path);
        }
    }

    WallpaperScreens {
        id: showOnRow
        focusedPath: root.focusedPath
        focusIsAdd: root.focusIsAdd
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        onAssignAllRequested: root.assignFocusedToAll()
        onAssignMonitorRequested: number => root.assignFocusedToMonitor(number)
        onIdentifyRequested: Wallpapers.identify()
    }
}
