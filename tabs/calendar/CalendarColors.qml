pragma Singleton
import QtQuick
import qs.services

/**
 * Item colors of the calendar (presets and custom hex). They come from the
 * applied palette (Theme.current.c), so a theme switch updates them.
 */
QtObject {
    id: root

    readonly property var palette: Theme.current ? Theme.current.c : ({})

    function paletteColor(key, fallback) {
        return root.palette[key] ? Theme.hexToColor(root.palette[key]) : fallback;
    }

    /** The 8 preset colors in picker order. Keys are what items store; the palette gives the live color. */
    readonly property var presets: [
        { key: "accent", name: "Accent" }, { key: "blue", name: "Blue" },
        { key: "green", name: "Green" }, { key: "yellow", name: "Yellow" },
        { key: "red", name: "Red" }, { key: "cyan", name: "Cyan" },
        { key: "magenta", name: "Magenta" }, { key: "orange", name: "Orange" }
    ]

    /** Color the add line gives to the next item (a preset key or "#rrggbb"). Kept while the shell runs. */
    property string lastColor: "accent"

    /** "#rrggbb" (lowercase) for text like "e93", "#e93" or "EE9933"; "" when the text is not a hex color. */
    function normHex(text: string): string {
        var m = /^#?([0-9a-f]{3}|[0-9a-f]{6})$/i.exec(String(text).trim());
        if (!m) return "";
        var h = m[1].toLowerCase();
        if (h.length === 3) h = h.charAt(0) + h.charAt(0) + h.charAt(1) + h.charAt(1) + h.charAt(2) + h.charAt(2);
        return "#" + h;
    }

    function isPreset(color: string): bool {
        return root.presets.some(function (p) { return p.key === color; });
    }

    /** Preset name ("Blue") or the hex text, for labels. */
    function colorName(color: string): string {
        var found = root.presets.filter(function (p) { return p.key === color; })[0];
        return found ? found.name : color;
    }

    /** Hex digits for the picker's text field: empty for a preset. */
    function hexDigits(color: string): string {
        return root.isPreset(color) ? "" : String(color).replace("#", "");
    }

    /** QML color of an item color: a preset key follows the live theme, "#rrggbb" is fixed. Missing means accent. */
    function resolve(color: string): color {
        if (!color || color === "accent") return Theme.accent;
        if (color.charAt(0) === "#") return Theme.hexToColor(color);
        return root.paletteColor(color, Theme.accent);
    }
}
