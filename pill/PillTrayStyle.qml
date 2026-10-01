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

    /** Mock --c-hover: raised mixed 8% toward the foreground. */
    readonly property color hoverFill: Qt.rgba(
        Theme.raised.r * 0.92 + Theme.fg.r * 0.08,
        Theme.raised.g * 0.92 + Theme.fg.g * 0.08,
        Theme.raised.b * 0.92 + Theme.fg.b * 0.08, 1)

    /** The hover fill at zero alpha, so a fade in or out keeps the same hue. */
    readonly property color hoverFillClear: Qt.rgba(hoverFill.r, hoverFill.g, hoverFill.b, 0)
}
