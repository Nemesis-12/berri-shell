pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../logic/Ease.js" as Ease
import qs.common
import qs.picker

/**
 * Holds the 9 berri palettes and the currently applied one. apply(key)
 * computes every token's target color once in JS (including the OKLab
 * mixes and alpha variants), then runs one ParallelAnimation of
 * ColorAnimations (450ms, cubic-bezier(.4,0,.2,1) by default) that drives
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

    // The 9 raw palette tokens Theme derives everything else from.
    readonly property var rawKeys: ["dark_background", "bright_foreground", "foreground",
        "dark_foreground", "background", "lighter_background", "selection", "accent", "darker_background"]

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

    /** Raw color set for a palette key, or null if unknown. */
    function paletteRaw(key) {
        for (var i = 0; i < palettes.length; i++) {
            if (palettes[i].key === key) {
                var c = palettes[i].c;
                var out = {};
                for (var j = 0; j < rawKeys.length; j++) {
                    var k = rawKeys[j];
                    out[k] = c[k] ? hexToColor(c[k]) : defaultColor(k);
                }
                return out;
            }
        }
        return null;
    }

    function defaultColor(key) {
        var fallback = {
            dark_background: "#0c0c10", bright_foreground: "#f2f1f5", foreground: "#d6d4dc",
            dark_foreground: "#a4a4b0", background: "#17141f", lighter_background: "#241e2e",
            selection: "#3a2f52", accent: "#c28bf2", darker_background: "#0c0c10"
        };
        return hexToColor(fallback[key] || "#0c0c10");
    }

    /**
     * Computes every exposed token's target value from a raw palette map
     * (rawKeys -> color), once. Includes the OKLab mixes and the accent
     * alpha variants. Called once per apply(), never per animation frame.
     */
    function computeTokens(raw) {
        var t = {};
        t.shell = raw.dark_background || root.defaultColor("dark_background");
        t.fg = raw.bright_foreground || root.defaultColor("bright_foreground");
        t.fg2 = raw.foreground || root.defaultColor("foreground");
        t.dim = raw.dark_foreground || root.defaultColor("dark_foreground");
        t.card = raw.background || root.defaultColor("background");
        t.raised = raw.lighter_background || root.defaultColor("lighter_background");
        t.selection = raw.selection || root.defaultColor("selection");
        t.accent = raw.accent || root.defaultColor("accent");
        t.onAccentValue = raw.darker_background || root.defaultColor("darker_background");
        t.darkerBackground = raw.darker_background || root.defaultColor("darker_background");

        t.accentFill = Qt.rgba(t.accent.r, t.accent.g, t.accent.b, 0.18);
        t.accentLine = Qt.rgba(t.accent.r, t.accent.g, t.accent.b, 0.45);

        t.sunk = (raw.dark_background && raw.background)
            ? oklabMix(raw.dark_background, raw.background, 55) : t.shell;
        t.accentLight = (raw.accent && raw.bright_foreground)
            ? oklabMix(raw.accent, raw.bright_foreground, 70) : t.accent;
        t.accentSecondary = (raw.accent && raw.darker_background)
            ? oklabMix(raw.accent, raw.darker_background, 70) : t.accent;
        t.border = (raw.lighter_background && raw.bright_foreground)
            ? oklabMix(raw.lighter_background, raw.bright_foreground, 84) : t.raised;

        return t;
    }

    /**
     * Applies a theme by key: switches every token, animating the blend
     * unless animate is false (used only to restore the saved theme on
     * start, with no flash). duration defaults to 450ms; a real theme
     * switch (ThemesCarousel, the notch, pickertest) passes
     * transitionDurationMs, which also fires wallpaperTransition so each
     * monitor's wallpaper runs a matching shader transition (28a).
     * Persists the choice by default.
     */
    function apply(key, animate, persist, duration) {
        if (animate === undefined) animate = true;
        if (persist === undefined) persist = true;
        if (duration === undefined) duration = 450;

        var newRaw = paletteRaw(key);
        if (!newRaw) return;

        var targets = root.computeTokens(newRaw);

        if (animate) {
            // Snapshot the palette the shader is transitioning from (the
            // previous target); WallpaperLayer reads this once when its
            // own transition begins.
            root.fromRaw = root.toRaw || newRaw;
            root.toRaw = newRaw;
            root.transitioning = true;
            root.currentKey = key;
            root.transitioning = false;

            tokenAnim.stop();
            for (var name in tokenAnims) {
                var anim = tokenAnims[name];
                anim.to = targets[name];
                anim.duration = duration;
                anim.easing.type = Easing.BezierSpline;
                anim.easing.bezierCurve = root.standardCurve;
            }
            tokenAnim.start();

            if (duration !== 450) {
                root.wallpaperTransition(root.pickTransitionMode(), duration);
            }
        } else {
            tokenAnim.stop();
            root.fromRaw = newRaw;
            root.toRaw = newRaw;
            root.currentKey = key;
            for (var key2 in targets) root[key2] = targets[key2];
        }

        if (persist) root.save(key);
    }

    // --- Exposed tokens: plain writable properties, driven by tokenAnim. ---

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
    // readonly alias over the writable onAccentValue, which tokenAnim
    // actually drives.
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

    /** One ColorAnimation per token above, all started/stopped together by apply(). */
    ParallelAnimation {
        id: tokenAnim
        ColorAnimation { id: shellAnim; target: root; property: "shell" }
        ColorAnimation { id: fgAnim; target: root; property: "fg" }
        ColorAnimation { id: fg2Anim; target: root; property: "fg2" }
        ColorAnimation { id: dimAnim; target: root; property: "dim" }
        ColorAnimation { id: cardAnim; target: root; property: "card" }
        ColorAnimation { id: raisedAnim; target: root; property: "raised" }
        ColorAnimation { id: selectionAnim; target: root; property: "selection" }
        ColorAnimation { id: accentAnim; target: root; property: "accent" }
        ColorAnimation { id: onAccentAnim; target: root; property: "onAccentValue" }
        ColorAnimation { id: darkerBackgroundAnim; target: root; property: "darkerBackground" }
        ColorAnimation { id: accentFillAnim; target: root; property: "accentFill" }
        ColorAnimation { id: accentLineAnim; target: root; property: "accentLine" }
        ColorAnimation { id: sunkAnim; target: root; property: "sunk" }
        ColorAnimation { id: accentLightAnim; target: root; property: "accentLight" }
        ColorAnimation { id: accentSecondaryAnim; target: root; property: "accentSecondary" }
        ColorAnimation { id: borderAnim; target: root; property: "border" }
    }

    /** name -> ColorAnimation, keyed the same as computeTokens()'s return, so apply() can set .to/.duration/.easing in a loop. */
    readonly property var tokenAnims: ({
        shell: shellAnim, fg: fgAnim, fg2: fg2Anim, dim: dimAnim, card: cardAnim, raised: raisedAnim,
        selection: selectionAnim, accent: accentAnim, onAccentValue: onAccentAnim, darkerBackground: darkerBackgroundAnim,
        accentFill: accentFillAnim, accentLine: accentLineAnim, sunk: sunkAnim, accentLight: accentLightAnim,
        accentSecondary: accentSecondaryAnim, border: borderAnim
    })

    // --- Color helpers ---

    function hexToColor(hex) {
        hex = String(hex).replace("#", "");
        return Qt.rgba(
            parseInt(hex.substring(0, 2), 16) / 255,
            parseInt(hex.substring(2, 4), 16) / 255,
            parseInt(hex.substring(4, 6), 16) / 255,
            1
        );
    }

    // --- OKLab color-mix helper, mirroring CSS color-mix(in oklab, a p%, b) ---
    // sRGB <-> linear <-> LMS <-> OKLab, per Björn Ottosson's reference formulas.
    function srgbToLinear(c) { return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4); }
    function linearToSrgb(c) {
        c = Math.max(0, Math.min(1, c));
        return c <= 0.0031308 ? c * 12.92 : 1.055 * Math.pow(c, 1 / 2.4) - 0.055;
    }

    function rgbToOklab(r, g, b) {
        var lr = srgbToLinear(r), lg = srgbToLinear(g), lb = srgbToLinear(b);
        var l = 0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb;
        var m = 0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb;
        var s = 0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb;
        var l_ = Math.cbrt(l), m_ = Math.cbrt(m), s_ = Math.cbrt(s);
        return {
            L: 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
            a: 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
            b: 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_
        };
    }

    function oklabToRgb(lab) {
        var l_ = lab.L + 0.3963377774 * lab.a + 0.2158037573 * lab.b;
        var m_ = lab.L - 0.1055613458 * lab.a - 0.0638541728 * lab.b;
        var s_ = lab.L - 0.0894841775 * lab.a - 1.2914855480 * lab.b;
        var l = l_ * l_ * l_, m = m_ * m_ * m_, s = s_ * s_ * s_;
        return {
            r: linearToSrgb(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
            g: linearToSrgb(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
            b: linearToSrgb(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
        };
    }

    /** Mixes colorA and colorB in OKLab space, pctA percent of colorA (CSS color-mix order). */
    function oklabMix(colorA, colorB, pctA) {
        var la = rgbToOklab(colorA.r, colorA.g, colorA.b), lb = rgbToOklab(colorB.r, colorB.g, colorB.b);
        var t = pctA / 100;
        var mixed = { L: la.L * t + lb.L * (1 - t), a: la.a * t + lb.a * (1 - t), b: la.b * t + lb.b * (1 - t) };
        var rgb = oklabToRgb(mixed);
        return Qt.rgba(rgb.r, rgb.g, rgb.b, 1);
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
        root.apply(key, false, false);
    }
}
