pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/** Shared home and storage folders. All saved files wait for the same state folder. */
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string state: home + "/.local/state/berri-shell"
    readonly property string calendar: home + "/.local/share/berri-shell/calendar"
    readonly property string wallpapers: home + "/.local/share/berri-shell/wallpapers"
    readonly property string weatherSettings: home + "/.local/state/omarchy/settings/weather.json"
    property bool stateReady: false

    // Makes the state root private once for all SavedState objects.
    Process {
        running: true
        command: ["sh", Quickshell.shellPath("scripts/private-folder.sh"), root.state]
        onExited: root.stateReady = true
    }

    // The library root is ready before the first wallpaper copy.
    Process {
        running: true
        command: ["sh", Quickshell.shellPath("scripts/private-folder.sh"), root.wallpapers]
    }
}
