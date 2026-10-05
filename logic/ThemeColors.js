.pragma library

/**
 * The one definition of the theme colors. A color here is a plain
 * { r, g, b, a } object with channels from 0 to 1, so Node tests can read it;
 * Theme.qml turns each one into a Qt color. Add a token with one entry in
 * `tokenTable`.
 */

/** The nine raw colors every palette must give. */
var rawKeys = ["dark_background", "bright_foreground", "foreground",
    "dark_foreground", "background", "lighter_background", "selection", "accent", "darker_background"];

/** Used for each raw color that a palette does not give. */
var fallbackHex = {
    dark_background: "#0c0c10", bright_foreground: "#f2f1f5", foreground: "#d6d4dc",
    dark_foreground: "#a4a4b0", background: "#17141f", lighter_background: "#241e2e",
    selection: "#3a2f52", accent: "#c28bf2", darker_background: "#0c0c10"
};

/** "#rrggbb" -> color. */
function hexToRgb(hex) {
    hex = String(hex).replace("#", "");
    return {
        r: parseInt(hex.substring(0, 2), 16) / 255,
        g: parseInt(hex.substring(2, 4), 16) / 255,
        b: parseInt(hex.substring(4, 6), 16) / 255,
        a: 1
    };
}

/** The nine raw colors of a palette (a map of name -> "#rrggbb"); a missing or empty map gives the fallbacks. */
function rawPalette(hexes) {
    var out = {};
    for (var i = 0; i < rawKeys.length; i++) {
        var key = rawKeys[i];
        out[key] = hexToRgb(hexes && hexes[key] ? hexes[key] : fallbackHex[key]);
    }
    return out;
}

// --- OKLab mix, as CSS color-mix(in oklab, a p%, b). Björn Ottosson's reference formulas. ---

function srgbToLinear(c) { return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4); }

function linearToSrgb(c) {
    c = Math.max(0, Math.min(1, c));
    return c <= 0.0031308 ? c * 12.92 : 1.055 * Math.pow(c, 1 / 2.4) - 0.055;
}

function rgbToOklab(color) {
    var lr = srgbToLinear(color.r), lg = srgbToLinear(color.g), lb = srgbToLinear(color.b);
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
        b: linearToSrgb(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s),
        a: 1
    };
}

/** Mixes colorA and colorB in OKLab space, pctA percent of colorA (CSS color-mix order). */
function oklabMix(colorA, colorB, pctA) {
    var la = rgbToOklab(colorA), lb = rgbToOklab(colorB);
    var t = pctA / 100;
    return oklabToRgb({ L: la.L * t + lb.L * (1 - t), a: la.a * t + lb.a * (1 - t), b: la.b * t + lb.b * (1 - t) });
}

/** The color with another alpha. */
function withAlpha(color, alpha) {
    return { r: color.r, g: color.g, b: color.b, a: alpha };
}

/**
 * Every theme token and how it follows from the nine raw colors, in order.
 * `make(raw, made)` gets the raw colors and the tokens made before it.
 * Theme.qml needs one `property color <name>` line for each entry.
 */
var tokenTable = [
    { name: "shell", make: function (raw) { return raw.dark_background; } },
    { name: "fg", make: function (raw) { return raw.bright_foreground; } },
    { name: "fg2", make: function (raw) { return raw.foreground; } },
    { name: "dim", make: function (raw) { return raw.dark_foreground; } },
    { name: "card", make: function (raw) { return raw.background; } },
    { name: "raised", make: function (raw) { return raw.lighter_background; } },
    { name: "selection", make: function (raw) { return raw.selection; } },
    { name: "accent", make: function (raw) { return raw.accent; } },
    { name: "onAccentValue", make: function (raw) { return raw.darker_background; } },
    { name: "darkerBackground", make: function (raw) { return raw.darker_background; } },
    /** Accent at 18% / 45% alpha: an active control's fill and border. */
    { name: "accentFill", make: function (raw) { return withAlpha(raw.accent, 0.18); } },
    { name: "accentLine", make: function (raw) { return withAlpha(raw.accent, 0.45); } },
    /** Spine sunk (hover) background: 55% dark_background mixed with background. */
    { name: "sunk", make: function (raw) { return oklabMix(raw.dark_background, raw.background, 55); } },
    /** Active spine icon color: 70% accent mixed with bright_foreground. */
    { name: "accentLight", make: function (raw) { return oklabMix(raw.accent, raw.bright_foreground, 70); } },
    /** Second agent-ring accent (Codex): 70% accent mixed with darker_background. */
    { name: "accentSecondary", make: function (raw) { return oklabMix(raw.accent, raw.darker_background, 70); } },
    /** Panel border: 84% lighter_background mixed with 16% bright_foreground. */
    { name: "border", make: function (raw) { return oklabMix(raw.lighter_background, raw.bright_foreground, 84); } }
];

/** Every token (name -> color) of a raw palette; a missing raw color uses its fallback. `table` defaults to tokenTable. */
function computeTokens(raw, table) {
    var full = rawPalette({});
    for (var i = 0; i < rawKeys.length; i++) {
        if (raw && raw[rawKeys[i]]) full[rawKeys[i]] = raw[rawKeys[i]];
    }
    var tokens = {};
    var list = table || tokenTable;
    for (var j = 0; j < list.length; j++) tokens[list[j].name] = list[j].make(full, tokens);
    return tokens;
}

/** Shown time of a theme switch when the caller names none. */
var defaultSwitchMs = 450;

/**
 * Reads the options of a theme switch. A wallpaper transition runs only when
 * `wallpaper` is true; the duration never decides it.
 */
function switchPlan(options) {
    var o = options || {};
    var animate = o.animate !== false;
    return {
        animate: animate,
        persist: o.persist !== false,
        durationMs: o.durationMs === undefined ? defaultSwitchMs : o.durationMs,
        wallpaper: animate && o.wallpaper === true
    };
}
