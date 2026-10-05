pragma Singleton
import QtQuick
import qs.services

/**
 * Shared sizes and hover fill of the pill tray (mock "Tray B", Spine style).
 */
QtObject {
    /** Button size, icon size, and the "+N" chip's minimum width. */
    readonly property int buttonSize: 20
    readonly property int iconSize: 13
    readonly property int chipMinWidth: 24
    readonly property int gap: 2
    readonly property int popoverRadius: 8

    /** Icons shown in the pill before the "+N" chip. */
    readonly property int shownCount: 3

    /** Hover fill: the same theme color as every other hover (Theme.hover). */
    readonly property color hoverFill: Theme.hover

    /** The hover fill at zero alpha, so a fade in or out keeps the same hue. */
    readonly property color hoverFillClear: Qt.rgba(hoverFill.r, hoverFill.g, hoverFill.b, 0)
}
