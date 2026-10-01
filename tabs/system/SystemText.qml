import QtQuick
import "../../logic/PixelGrid.js" as PixelGrid
import qs.services

/**
 * One line of System tab text placed by its CSS line box: `lineTop` is where
 * the line box starts and `lineBox` its height in font sizes (the mock's
 * line-height). The text baseline lands where a browser would put it, so
 * sizes and positions copy straight from the mock. Condensed sans by
 * default; `mono` gives the mono font.
 */
Text {
    id: root

    property bool mono: false
    property real lineTop: 0
    property real lineBox: 1

    readonly property real dpr: PixelGrid.dpr(Screen.devicePixelRatio)

    textFormat: Text.PlainText
    font.family: mono ? Theme.mono : Theme.condensed
    font.weight: Font.Medium
    color: Theme.fg

    // Plex ascent is 1.025 em and descent 0.275 em. The browser rounds each to
    // whole pixels and centres that content area in the line box.
    readonly property real ascent: Math.round(1.025 * font.pixelSize)
    readonly property real descent: Math.round(0.275 * font.pixelSize)
    y: Math.round((lineTop + (lineBox * font.pixelSize - ascent - descent) / 2 + ascent - baselineOffset) * dpr - 0.5) / dpr
}
