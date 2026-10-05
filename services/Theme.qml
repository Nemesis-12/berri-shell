pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../logic/Ease.js" as Ease
import "../logic/ThemeColors.js" as Colors
import qs.common
import qs.picker

/**
 * Holds the 9 berri palettes and the currently applied one. apply(key)
 * computes every token's target color once in JS (logic/ThemeColors.js,
 * including the OKLab mixes and alpha variants), then runs one
 * StandardColorMotion per token (450ms by default) that drives
 * each token property straight to its target in C++. Every token below is
 * a plain `property color`, not a binding on a rebuilt JS object, so a
 * theme switch never re-evaluates the ~190 bindings elsewhere in the shell
 * that read Theme tokens. The choice is saved to
 * ~/.local/state/berri-shell/theme.json and restored (with no animation)
 * on start.
 */
Singleton {
    id: root

    property var palettes: []

    /** Which dashboard look swatch strips (PaletteStrip.qml) should draw; "spine" is the only one built. */
    readonly property string dashboardStyle: "spine"

    /** Key of the applied (or in-flight target) theme. Set by apply(). */
    property string currentKey: ""

    /** The applied palette entry (key/name/c), for UI that needs to know which theme is picked. */
    readonly property var current: {
        if (palettes.length === 0) return null;
        if (root.currentKey !== "") {
            for (var i = 0; i < palettes.length; i++) {
                if (palettes[i].key === root.currentKey) return palettes[i];
            }
        }
        return palettes[0];
    }

    // fromRaw is a one-shot snapshot of the palette a transition started
    // from (the previous toRaw), used only by WallpaperLayer's shader to
    // pick its "old frame" colors when a transition begins; it is not
    // re-read per frame. toRaw is the raw map of the CURRENTLY APPLIED (or
    // in-flight target) palette, and colors mirrors it for readability;
    // both change once per apply(), never per animation frame.
    property var fromRaw: null
    property var toRaw: null
    readonly property var colors: toRaw || {}

    // True for the one JS statement that changes currentKey as part of a
    // transitioned apply(); WallpaperLayer's per-screen wallpaperPath binding
    // checks this to skip its own short cross-fade, since the wallpaper
    // transition shader is about to run instead (28a).
    property bool transitioning: false

    // --- Shared fade times ---
    // Color and opacity fades use these two values with Easing.OutCubic.
    /** Hover and press fades (ms). */
    readonly property int hoverMs: 180
    /** Selection and state fades (ms): active tab, selected item, on/off, enabled/disabled, checked. */
    readonly property int stateMs: 300
    /** Short fades, and list rows that enter, leave or move (ms). */
    readonly property int listMs: 220

    // --- Shared motion curves (BezierSpline control points) ---
    /** Spring-like curve of the pill and panel morphs, cubic-bezier(.32, .72, 0, 1). */
    readonly property var springCurve: Ease.springCurve
    /** The mock's standard curve, cubic-bezier(.4, 0, .2, 1). */
    readonly property var standardCurve: Ease.standardCurve
    /** Fast start and long soft stop, cubic-bezier(.2, 0, 0, 1): the Do not disturb switch knob. */
    readonly property var emphasizedCurve: Ease.emphasizedCurve

    /**
     * The standard curve of a straight-line phase 0..1. Open and close views
     * drive a linear phase and show this value, so close is exactly open
     * played backwards. Closed form, no search.
     */
    function easeOut(phase: real): real {
        return Ease.easeOut(phase);
    }

    // --- Font families ---
    readonly property string mono: "IBM Plex Mono"
    readonly property string sans: "IBM Plex Sans"
    readonly property string condensed: "IBM Plex Sans Condensed"

    // --- Shared fills ---
    /** Muted text (mock --t-mute). */
    readonly property color mute: {
        var c = root.current ? root.current.c : null;
        return (c && c.muted) ? root.hexToColor(c.muted) : root.dim;
    }

    /** Hover fill (mock --t-hover): 92% raised, 8% bright foreground. */
    readonly property color hover: root.oklabMix(root.raised, root.fg, 92)

    /** Soft selection fill (mock --t-selsoft): 82% card, 18% accent. */
    readonly property color selectionSoft: root.oklabMix(root.card, root.accent, 82)

    // --- Theme-switch wallpaper transition (28a) ---

    /** Duration (ms) for a full theme-switch transition: wallpaper shader + color blend together. */
    readonly property int transitionDurationMs: 700

    readonly property var transitionModeIds: ["A", "B", "C2", "D", "F"]

    /**
     * "random" picks one of transitionModeIds per switch (current behavior).
     * A future settings page will let the user pick a fixed id instead
     * (default there will be "A"). IPC's pickertest.theme() also uses this
     * to force one mode for a single switch.
     */
    property string transitionMode: "random"

    function pickTransitionMode() {
        if (root.transitionMode !== "random") return root.transitionMode;
        return root.transitionModeIds[Math.floor(Math.random() * root.transitionModeIds.length)];
    }

    /** Emitted right after currentKey/fromRaw/toRaw are set for a transitioned apply(); each WallpaperLayer screen runs its own shader transition off this. */
    signal wallpaperTransition(string mode, int durationMs)

    /** Raw color set for a palette key, or null if unknown. Always has all nine raw colors. */
    function paletteRaw(key) {
        for (var i = 0; i < palettes.length; i++) {
            if (palettes[i].key === key) return root.toQtColors(Colors.rawPalette(palettes[i].c));
        }
        return null;
    }

    /** Turns a map of { r, g, b, a } colors into a map of Qt colors. */
    function toQtColors(map) {
        var out = {};
        for (var name in map) out[name] = Qt.rgba(map[name].r, map[name].g, map[name].b, map[name].a);
        return out;
    }

    /**
     * Computes every exposed token's target value from a raw palette map
     * (raw palette key -> color), once. Called once per apply(), never per animation frame.
     */
    function computeTokens(raw) {
        return root.toQtColors(Colors.computeTokens(raw));
    }

    /**
     * Applies a theme by key. Options (all optional):
     *   animate     false switches with no blend or flash (used to restore the saved theme on start). Default true.
     *   persist     false does not save the choice. Default true.
     *   durationMs  length of the color blend, and of the wallpaper transition. Default 450.
     *   wallpaper   true also fires wallpaperTransition once, so each monitor's wallpaper runs a
     *               matching shader transition (28a). Default false; the duration never decides it.
     * ThemesCarousel, the notch and pickertest pass wallpaper: true with durationMs: transitionDurationMs.
     */
    function apply(key, options) {
        var plan = Colors.switchPlan(options);

        var newRaw = paletteRaw(key);
        if (!newRaw) return;

        var targets = root.computeTokens(newRaw);

        if (plan.animate) {
            // Snapshot the palette the shader is transitioning from (the
            // previous target); WallpaperLayer reads this once when its
            // own transition begins.
            root.fromRaw = root.toRaw || newRaw;
            root.toRaw = newRaw;
            root.transitioning = true;
            root.currentKey = key;
            root.transitioning = false;

            for (var name in tokenAnims) {
                var anim = tokenAnims[name];
                anim.stop();
                anim.to = targets[name];
                anim.duration = plan.durationMs;
                anim.start();
            }

            if (plan.wallpaper) root.wallpaperTransition(root.pickTransitionMode(), plan.durationMs);
        } else {
            for (var stopName in tokenAnims) tokenAnims[stopName].stop();
            root.fromRaw = newRaw;
            root.toRaw = newRaw;
            root.currentKey = key;
            for (var key2 in targets) root[key2] = targets[key2];
        }

        if (plan.persist) root.save(key);
    }

    // --- Exposed tokens: plain writable properties, driven by tokenAnims. ---
    // Each needs one entry in the token table of logic/ThemeColors.js, and the other way round.

    property color shell: "#0c0c10"
    property color fg: "#f2f1f5"
    property color fg2: "#d6d4dc"
    property color dim: "#a4a4b0"
    property color card: "#17141f"
    property color raised: "#241e2e"
    property color selection: "#3a2f52"
    property color accent: "#c28bf2"

    // QML forbids a property named "on<Upper...>" as a direct animation
    // target (ambiguous with signal-handler syntax), so onAccent is a
    // readonly alias over the writable onAccentValue, which tokenAnims
    // actually drive.
    property color onAccentValue: "#0c0c10"
    readonly property color onAccent: onAccentValue

    /** Animated raw darker_background, for consumers that need it mid-transition (WallpaperLayer's solid fallback). */
    property color darkerBackground: "#0c0c10"

    /** Accent at 18%/45% alpha, for an active control's fill/border (berri-theme.js apply()). */
    property color accentFill: "#2ec28bf2"
    property color accentLine: "#73c28bf2"

    /** Spine sunk (hover) background: 55% dark_background mixed with background. */
    property color sunk: "#131318"

    /** Active spine icon color: 70% accent mixed with bright_foreground. */
    property color accentLight: "#d3aef7"

    /** Second agent-ring accent (Codex), so it reads apart from Claude's accent but stays clear of the track: 70% accent mixed with darker_background. */
    property color accentSecondary: "#8a64b1"

    /** Panel border: 84% lighter_background mixed with 16% bright_foreground, in OKLab. */
    property color border: "#3a3550"

    /** token name -> its StandardColorMotion. One per entry of the token table, made once at start. */
    property var tokenAnims: ({})

    Component {
        id: tokenAnimFactory
        StandardColorMotion {}
    }

    Component.onCompleted: {
        var made = {};
        for (var i = 0; i < Colors.tokenTable.length; i++) {
            var name = Colors.tokenTable[i].name;
            made[name] = tokenAnimFactory.createObject(root, { target: root, property: name });
        }
        root.tokenAnims = made;
    }

    // --- Color helpers (the math is in logic/ThemeColors.js) ---

    function hexToColor(hex) {
        var c = Colors.hexToRgb(hex);
        return Qt.rgba(c.r, c.g, c.b, c.a);
    }

    /** Mixes colorA and colorB in OKLab space, pctA percent of colorA (CSS color-mix order). */
    function oklabMix(colorA, colorB, pctA) {
        var c = Colors.oklabMix(colorA, colorB, pctA);
        return Qt.rgba(c.r, c.g, c.b, 1);
    }

    /** Absolute path of this project's data/ folder, self-located. */
    readonly property string dataDir: {
        var s = String(Qt.resolvedUrl("../data"));
        if (s.indexOf("file://") === 0) {
            s = s.substring(7);
            try { s = decodeURIComponent(s); } catch (e) {}
        }
        return s;
    }

    property bool paletteListReady: false
    property bool savedStateChecked: false
    property string savedKey: ""
    property bool restored: false

    function save(key) {
        saved.save({ key: key });
    }

    FileView {
        id: themesFile
        path: root.dataDir + "/themes.json"
        onLoaded: {
            try {
                root.palettes = JSON.parse(text()) || [];
            } catch (e) {
                root.palettes = [];
            }
            root.paletteListReady = true;
            root.tryRestore();
        }
        onLoadFailed: {
            root.paletteListReady = true;
            root.tryRestore();
        }
    }

    SavedState {
        id: saved
        name: "theme"
        defaults: ({ key: "" })
        onLoaded: values => {
            if (values.key) root.savedKey = values.key;
            root.savedStateChecked = true;
            root.tryRestore();
        }
    }

    /** Applies the saved theme (or the default palette) once both files have been checked, with no animation. */
    function tryRestore() {
        if (root.restored) return;
        if (!root.paletteListReady || !root.savedStateChecked) return;
        if (root.palettes.length === 0) return;
        root.restored = true;
        var key = (root.savedKey && root.paletteRaw(root.savedKey)) ? root.savedKey : root.palettes[0].key;
        root.apply(key, { animate: false, persist: false });
    }
}
