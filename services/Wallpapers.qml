pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

/**
 * One shared wallpaper library for every theme (28). Each theme remembers
 * which wallpaper each monitor shows; a monitor with no assignment falls
 * back to a solid color (WallpaperLayer draws Theme.darkerBackground
 * for it). Library files live in ~/.local/share/berri-shell/wallpapers/
 * (our own copies, so the source picked in the file dialog can move or be
 * deleted without breaking anything); the library list and per-theme
 * assignments are saved with SavedState in
 * ~/.local/state/berri-shell/wallpapers.json.
 */
Singleton {
    id: root

    readonly property var imageExtensions: ["png", "jpg", "jpeg", "webp"]

    /** Absolute paths of our own copies, in added order. Shared by every theme. */
    property var library: []

    /** { themeKey: { screenName: path } } - the saved choice per theme per monitor. */
    property var assignments: ({})

    /**
     * Connected screens as { name, number }. Internal panels (eDP/LVDS/DSI)
     * come first, then the rest by x position; numbering starts at 1.
     */
    readonly property var monitors: {
        var screens = Quickshell.screens || [];
        var internal = [];
        var external = [];
        for (var i = 0; i < screens.length; i++) {
            var s = screens[i];
            if (root.isInternal(s.name)) internal.push(s);
            else external.push(s);
        }
        internal.sort(function(a, b) { return a.x - b.x; });
        external.sort(function(a, b) { return a.x - b.x; });
        var ordered = internal.concat(external);
        var out = [];
        for (var j = 0; j < ordered.length; j++) {
            out.push({
                name: ordered[j].name,
                number: j + 1
            });
        }
        return out;
    }

    function isInternal(name) {
        return name.indexOf("eDP") === 0 || name.indexOf("LVDS") === 0 || name.indexOf("DSI") === 0;
    }

    /** Path shown on screenName for the current theme, or "" for a solid color. */
    function wallpaperFor(screenName) {
        var key = Theme.currentKey;
        if (!key || !root.assignments[key]) return "";
        return root.assignments[key][screenName] || "";
    }

    /** Emitted when an add finishes: the library path of the new copy, or "" if the copy failed. */
    signal addFinished(string path)

    /** Sorted monitor numbers currently showing path, for the applied theme. */
    function numbersShowing(path) {
        var key = Theme.currentKey;
        var forTheme = (key && root.assignments[key]) ? root.assignments[key] : {};
        var out = [];
        for (var i = 0; i < root.monitors.length; i++) {
            var m = root.monitors[i];
            if (forTheme[m.name] === path) out.push(m.number);
        }
        out.sort(function(a, b) { return a - b; });
        return out;
    }

    /** True when the current theme has no wallpaper assigned to any monitor. */
    function currentThemeUnassigned() {
        var key = Theme.currentKey;
        var forTheme = (key && root.assignments[key]) ? root.assignments[key] : {};
        return Object.keys(forTheme).length === 0;
    }

    /**
     * Copies path into our wallpapers folder (PNG/JPG/JPEG/WEBP only) and
     * appends the copy to the library. If this is the first wallpaper ever
     * added and the current theme has no assignment yet, assigns it to
     * every monitor.
     */
    function add(path) {
        var name = String(path).split("/").pop();
        var dot = name.lastIndexOf(".");
        var ext = dot === -1 ? "" : name.substring(dot + 1).toLowerCase();
        if (root.imageExtensions.indexOf(ext) === -1) {
            console.warn("Wallpapers.add: unsupported file type: " + path);
            // Finish after ImagePicker.finished(), as a copy process would.
            Qt.callLater(function() { root.addFinished(""); });
            return;
        }
        addProc.wasEmpty = root.library.length === 0;
        addProc.srcPath = path;
        addProc.command = ["bash", "-c",
            'set -e; mkdir -p "$1"; base="$(basename -- "$0")"; name="${base%.*}"; ext="${base##*.}"; ' +
            'dest="$1/$base"; n=1; while [ -e "$dest" ]; do dest="$1/${name}-${n}.${ext}"; n=$((n+1)); done; ' +
            'cp -- "$0" "$dest"; printf "%s" "$dest"',
            path, root.wallpapersDir];
        addProc.running = true;
    }

    property string wallpapersDir: (Quickshell.env("HOME") || "") + "/.local/share/berri-shell/wallpapers"

    Process {
        id: addProc
        property string srcPath: ""
        property bool wasEmpty: false
        stdout: StdioCollector { id: addStdout }
        onExited: (exitCode) => {
            if (exitCode !== 0) {
                console.warn("Wallpapers.add: copy failed for " + addProc.srcPath);
                root.addFinished("");
                return;
            }
            var dest = addStdout.text.trim();
            if (!dest) { root.addFinished(""); return; }
            root.library = root.library.concat([dest]);
            if (addProc.wasEmpty && root.currentThemeUnassigned()) {
                var names = [];
                for (var i = 0; i < root.monitors.length; i++) names.push(root.monitors[i].name);
                root.assign(dest, names);
            } else {
                root.save();
            }
            root.addFinished(dest);
        }
    }

    /** Removes path from the library, deletes our copy, and clears every
     *  assignment (in every theme) that used it. */
    function remove(path) {
        var next = [];
        for (var i = 0; i < root.library.length; i++) {
            if (root.library[i] !== path) next.push(root.library[i]);
        }
        root.library = next;

        var nextAssignments = {};
        for (var themeKey in root.assignments) {
            var forTheme = root.assignments[themeKey];
            var cleaned = {};
            for (var screenName in forTheme) {
                if (forTheme[screenName] !== path) cleaned[screenName] = forTheme[screenName];
            }
            nextAssignments[themeKey] = cleaned;
        }
        root.assignments = nextAssignments;
        root.save();

        removeProc.command = ["rm", "-f", path];
        removeProc.running = true;
    }

    Process { id: removeProc }

    /** For the current theme, points every screen in screenNames at path. Other screens keep their own wallpaper. */
    function assign(path, screenNames) {
        root.changeCurrentTheme(function(forTheme) {
            for (var i = 0; i < screenNames.length; i++) forTheme[screenNames[i]] = path;
        });
    }

    /** For the current theme, clears every screen in screenNames that shows path (they fall back to the solid color). */
    function unassign(path, screenNames) {
        root.changeCurrentTheme(function(forTheme) {
            for (var i = 0; i < screenNames.length; i++) {
                if (forTheme[screenNames[i]] === path) delete forTheme[screenNames[i]];
            }
        });
    }

    /** Copies the assignments, lets change() edit the current theme's copy, then swaps in the new objects so bindings update. */
    function changeCurrentTheme(change) {
        var key = Theme.currentKey;
        if (!key) return;
        var nextAssignments = {};
        for (var themeKey in root.assignments) nextAssignments[themeKey] = root.assignments[themeKey];
        var forTheme = {};
        var existing = nextAssignments[key] || {};
        for (var screenName in existing) forTheme[screenName] = existing[screenName];
        change(forTheme);
        nextAssignments[key] = forTheme;
        root.assignments = nextAssignments;
        root.save();
    }

    signal identifyRequested()
    function identify() { root.identifyRequested(); }

    // --- Persistence ---

    property bool loaded: false

    function save() {
        saved.save({ library: root.library, assignments: root.assignments });
    }

    SavedState {
        id: saved
        name: "wallpapers"
        onLoaded: values => {
            if (Array.isArray(values.library)) root.library = values.library;
            if (values.assignments) root.assignments = values.assignments;
            root.loaded = true;
        }
    }
}
