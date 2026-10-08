import QtQuick
import QtQuick.Window
import "../logic/PanelTimeline.js" as PanelTimeline
import "../logic/PixelGrid.js" as PixelGrid
import "../logic/ThemeColors.js" as Colors
import "../logic/Timeline.js" as Timeline
import qs.common
import qs.services

/**
 * The bottom-center theme notch: the current theme's palette as 6 small bars.
 * A click grows the notch into the theme and wallpaper picker
 * (mock's openPick/closeAll): first narrow (276 x 304) while the palette bars
 * morph into one strip that sits on the focused theme card, then wide (900)
 * with the header and body fading in. The strip fades out last, once the
 * header is fully opaque, so the card's own strip is never seen through it.
 *
 * The grow is one motion. `progress` goes straight from 0 to 1 over `totalMs`;
 * every part shows its own slice of the timeline below. Close runs `progress`
 * back to 0, so the parts run in reversed order, on both tabs. While closing,
 * each slice is eased the other way round (see Timeline.js): every part leaves
 * fast and settles slowly into rest, like it does when it opens.
 */
Item {
    id: root

    readonly property int restWidth: 96
    readonly property int hoverWidth: 118
    readonly property int restHeight: 22
    readonly property int hoverHeight: 28
    readonly property int restCornerRadius: 5
    readonly property int hoverCornerRadius: 6

    // Spine (TK.C) picker geometry from the mock.
    readonly property int pickerNarrowWidth: 276
    readonly property int pickerWideWidth: 900
    readonly property int pickerHeight: 304
    readonly property int pickerCornerRadius: 10

    // Open and close timelines, in ms after the click (see PanelTimeline.js).
    readonly property int narrowMs: PanelTimeline.picker.narrowMs
    readonly property int riseMs: PanelTimeline.picker.riseMs
    readonly property int shadowMs: PanelTimeline.picker.shadowMs
    readonly property int wideStartMs: PanelTimeline.picker.wideStartMs
    readonly property int wideMs: PanelTimeline.picker.wideMs
    readonly property int headerStartMs: PanelTimeline.picker.headerStartMs
    readonly property int headerMs: PanelTimeline.picker.headerMs
    readonly property int stripFadeStartMs: PanelTimeline.picker.stripFadeStartMs
    readonly property int stripFadeMs: PanelTimeline.picker.stripFadeMs
    /** The whole open motion. */
    readonly property int totalMs: PanelTimeline.picker.totalMs

    readonly property var closeTimes: PanelTimeline.pickerClose(paletteStrip.spanMs)
    /** The strip returns and the header fades out at once; the wide picker narrows 40 ms later. */
    readonly property int wideCloseAtMs: closeTimes.wideCloseAtMs
    /** The notch shrinks to its bar when the wide picker has narrowed 3/4. */
    readonly property int narrowCloseAtMs: closeTimes.narrowCloseAtMs
    /** The bars of the strip return with the shrinking. */
    readonly property int stripCloseAtMs: closeTimes.stripCloseAtMs
    /** The time at which every step of the close is at rest. */
    readonly property int closeEndMs: closeTimes.closeEndMs

    // Picker layout (see pickerHeader and headerRow below); named here too so
    // the strip's vertical offset can be computed to land exactly on the
    // focused card's own strip (the "handoff").
    readonly property int headerTopMargin: 14
    readonly property int headerBottomMargin: 4
    readonly property int headerRowHeight: 28
    readonly property int bodyTopMargin: 4

    /** Body (ThemesCarousel) viewport height once the header/tabs row is subtracted. */
    readonly property real bodyViewportHeight: pickerHeight - headerTopMargin - headerBottomMargin - headerRowHeight - bodyTopMargin

    // Wallpapers tab layout: the body sits wallsHeaderGap below the
    // header row and keeps an 18px bottom padding (headerBottomMargin 4 +
    // wallsBottomExtra 14). At pickerHeight 304 this divides exactly: 14 (top)
    // + 28 (header row) + 14 (wallsHeaderGap) + 191 (card) + 15 (wallsRowGap)
    // + 24 (WallpaperScreens) + 18 (bottom) = 304.
    readonly property int wallsHeaderGap: 14
    readonly property int wallsBottomExtra: 14
    readonly property int wallsRowGap: 15

    /** The focused card's own strip, mapped to (width, height, distance up from the panel's bottom edge). */
    readonly property real handoffStripWidth: themesCarousel.stripWidth
    readonly property real handoffStripHeight: themesCarousel.stripHeight
    readonly property real handoffStripBottom: headerBottomMargin
        + (bodyViewportHeight - themesCarousel.cardHeight) / 2
        + themesCarousel.stripBottomOffset

    /** Set by shell.qml (modelData.name); keys this monitor's PanelCoordinator entry. */
    property string screenName: ""

    /** True from the click until the picker is closed again: where the motion is going. */
    readonly property bool open: slide.open

    /** The open motion, 0 (notch) to 1 (wide picker), in a straight line over `totalMs`. */
    readonly property real progress: slide.progress

    /** Time since the open started, in ms. Every slice of the motion reads this. */
    readonly property real elapsedMs: slide.elapsedMs

    /** True while the motion runs toward the notch: every slice then eases out into rest. */
    readonly property bool closing: slide.closing

    /** True while the picker is open, opening or closing. */
    readonly property bool pickerOpen: slide.active

    /** True once the picker is meant to be open and has started to widen: the header may take input. */
    readonly property bool pickerWide: open && elapsedMs >= wideStartMs

    /** True while the pointer is on the notch. */
    readonly property bool pointerInside: hoverHandler.hovered

    readonly property bool hovered: pointerInside && !pickerOpen

    /** Which picker tab is showing: "themes" (ThemesCarousel) or "walls" (WallpapersCarousel + SHOW ON row). */
    property string pickerTab: "themes"
    /** The tab whose motion runs: the tab showing when the open or the close started. Only the Themes motion shows the palette strip. */
    property string motionTab: "themes"
    /** The notch bars return only after a Walls close has finished. */
    property real wallRestOpacity: 1
    // Refocuses the wallpapers carousel each time the walls tab is switched
    // into, on the wallpaper shown on this notch's own monitor (or index 0).
    onPickerTabChanged: if (root.pickerTab === "walls") wallsBody.carousel.focusToCurrent();

    /** Output scale (2 on eDP-2, 1 on HDMI-A-1); used to snap the notch to whole device pixels. */
    readonly property real dpr: PixelGrid.dpr(Screen.devicePixelRatio)

    /** Emitted on click, in addition to opening the picker directly. */
    signal clicked()

    implicitWidth: hoverWidth
    implicitHeight: hoverHeight

    // The one slide operation (see PanelSlide.qml): open, close, close at once, and dialog requests.
    PanelSlide {
        id: slide
        screenName: root.screenName
        kind: "picker"
        totalMs: root.totalMs
        closeEndMs: root.closeEndMs
        // The notch bars return after a Walls close has finished.
        onCloseFinished: if (root.motionTab === "walls") wallBarsReturn.start()
    }

    NumberAnimation {
        id: wallBarsReturn
        target: root
        property: "wallRestOpacity"
        to: 1
        duration: Theme.hoverMs
        easing.type: Easing.OutCubic
    }

    /** Starts the open motion; also while a close is running. */
    function openPicker() {
        if (root.open) return;
        wallBarsReturn.stop();
        root.wallRestOpacity = 1;
        root.motionTab = root.pickerTab;
        slide.openSlide();
        if (root.pickerTab === "walls") wallsBody.carousel.focusToCurrent();
        else themesCarousel.focusToCurrent();
    }

    /** Starts the close motion: the open steps in reversed order, each one easing out into rest. The tab showing now decides the steps (the strip returns only on Themes). No-op unless open. */
    function closePicker() {
        if (!root.open) return;
        wallBarsReturn.stop();
        if (root.pickerTab === "walls") root.wallRestOpacity = 0;
        root.motionTab = root.pickerTab;
        slide.closeSlide();
    }

    /** Stops the picker motion and closes at once when fullscreen starts. */
    function closeAtOnce() {
        wallBarsReturn.stop();
        slide.closeAtOnce();
        root.wallRestOpacity = 1;
    }

    // Add wallpaper: the file dialog is a normal window and would open under
    // this Overlay panel, so the picker closes first (normal animated close),
    // the dialog opens once the picker is at rest, and the picker reopens on
    // the Wallpapers tab when the dialog is done.
    property int focusBeforeAdd: 0

    // The shadow at rest or under the pointer; the open motion deepens it.
    PanelShadow {
        target: notchRect
        cornerRadius: notchRect.topLeftRadius
        hovered: root.pointerInside
        hoverMs: root.shadowMs
        openProgress: Timeline.fadeSlice(root.elapsedMs, 0, root.shadowMs, root.closing, root.narrowCloseAtMs)
        restOffset: -6
        restStrength: 0
        restBlur: 11
        hoverStrength: 0.3
        openOffset: -20
        openStrength: 0.45
        openBlur: 60
    }

    Rectangle {
        id: notchRect

        // Every size at rest follows the pointer with its own spring; the open
        // motion grows it to the picker. Both edges of the width come from the
        // rounded half-width, so they land on a whole device pixel.
        property real hoverProgress: root.pointerInside ? 1 : 0
        Behavior on hoverProgress {
            SpringMotion {
                duration: root.narrowMs
            }
        }
        property real restBodyHeight: root.pointerInside ? root.hoverHeight : root.restHeight
        property real restRadius: root.pointerInside ? root.hoverCornerRadius : root.restCornerRadius
        Behavior on restBodyHeight {
            SpringMotion { duration: root.riseMs }
        }
        Behavior on restRadius {
            SpringMotion { duration: root.riseMs }
        }

        readonly property real restHalfWidth: (root.restWidth + (root.hoverWidth - root.restWidth) * hoverProgress) / 2
        readonly property real narrowSlice: Timeline.springSlice(root.elapsedMs, 0, root.narrowMs, root.closing, root.narrowCloseAtMs)
        readonly property real wideSlice: Timeline.springSlice(root.elapsedMs, root.wideStartMs, root.wideMs, root.closing, root.wideCloseAtMs)
        readonly property real riseSlice: Timeline.springSlice(root.elapsedMs, 0, root.riseMs, root.closing, root.narrowCloseAtMs)

        readonly property real halfWidth: restHalfWidth
            + (root.pickerNarrowWidth / 2 - restHalfWidth) * narrowSlice
            + (root.pickerWideWidth - root.pickerNarrowWidth) / 2 * wideSlice

        width: PixelGrid.snap(halfWidth, root.dpr) * 2
        height: restBodyHeight + (root.pickerHeight - restBodyHeight) * riseSlice
        x: PixelGrid.snap(root.width / 2, root.dpr) - width / 2
        // Flush with the bottom edge: shifted 1px past the window's own
        // bottom so the bottom border row falls off-screen (clip below).
        anchors.bottom: parent.bottom
        anchors.bottomMargin: -1
        clip: true

        topLeftRadius: restRadius + (root.pickerCornerRadius - restRadius) * riseSlice
        topRightRadius: topLeftRadius
        bottomLeftRadius: 0
        bottomRightRadius: 0

        color: Theme.shell
        border.width: 1
        border.color: Theme.border
        ColorFade on color { duration: Theme.stateMs }
        ColorFade on border.color { duration: Theme.stateMs }

        HoverHandler {
            id: hoverHandler
        }

        MouseArea {
            id: openArea
            anchors.fill: parent
            cursorShape: root.pickerOpen ? Qt.ArrowCursor : Qt.PointingHandCursor
            onClicked: {
                if (!root.pickerOpen) {
                    root.openPicker();
                    root.clicked();
                }
                // Clicks inside the open picker (not on a button) do nothing.
            }
        }

        // The 6 current-theme swatches: ONE set of segments that morphs
        // between the notch-bar layout and the picker's merged strip layout,
        // sized/positioned (handoffStripWidth/Height/Bottom) to sit exactly
        // on the focused theme card's own strip (see PaletteStrip.qml), in
        // the same order as the mock's PALC: dark_background, background,
        // lighter_background, selection, accent, foreground.
        // It is drawn above the header (z: 1 against 0) and fades out last, so
        // the card's own strip underneath is never seen through it.
        PaletteStrip {
            id: paletteStrip
            z: 1
            anchors.fill: parent
            colors: Colors.swatches.map(swatch => Theme[swatch.token])
            progress: root.motionTab !== "themes" ? 0
                : (root.closing ? Timeline.closeSlice(root.elapsedMs, 0, paletteStrip.spanMs, root.stripCloseAtMs)
                                : Timeline.slice(root.elapsedMs, 0, paletteStrip.spanMs))
            closing: root.closing
            hoverProgress: notchRect.hoverProgress
            restContainerHeight: root.restHeight
            hoverContainerHeight: root.hoverHeight
            stripWidth: root.handoffStripWidth
            stripHeight: root.handoffStripHeight
            stripBottom: root.handoffStripBottom
            // Themes open: bars grow into the strip, then the strip fades out.
            // Walls open: no strip; the notch bars fade out as the notch widens.
            opacity: root.motionTab === "themes"
                ? 1 - Timeline.fadeSlice(root.elapsedMs, root.stripFadeStartMs, root.stripFadeMs, root.closing)
                : (!root.open ? (root.pickerOpen ? 0 : root.wallRestOpacity)
                              : 1 - Timeline.fadeSlice(root.elapsedMs, 0, root.narrowMs))
            visible: opacity > 0.001
        }

        // The header (tabs, sub line, hint, close) and the body. Fixed 900px
        // frame, centered, so it is already in place once the notch is wide.
        Item {
            id: pickerHeader
            z: 0
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: root.headerTopMargin
            anchors.bottom: parent.bottom
            anchors.bottomMargin: root.headerBottomMargin
            width: root.pickerWideWidth - 36
            opacity: Timeline.fadeSlice(root.elapsedMs, root.headerStartMs, root.headerMs, root.closing, root.totalMs)
            visible: opacity > 0.001
            enabled: root.pickerWide
            PickerHeaderRow {
                id: headerRow
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: root.headerRowHeight
                pickerTab: root.pickerTab
                onTabClicked: key => root.pickerTab = key
                onCloseClicked: root.closePicker()
            }

            // Body: switches per tab.
            Item {
                anchors.top: headerRow.bottom
                anchors.topMargin: root.bodyTopMargin
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom

                ThemesCarousel {
                    id: themesCarousel
                    anchors.fill: parent
                    visible: root.pickerTab === "themes"
                }

                // Wallpapers tab: the carousel above the SHOW ON
                // row, with its own extra bottom margin.
                PickerWallpapers {
                    id: wallsBody
                    visible: root.pickerTab === "walls"
                    screenName: root.screenName
                    shown: root.pickerOpen && root.pickerTab === "walls"
                    rowGap: root.wallsRowGap
                    // parent.top already sits bodyTopMargin (4) below
                    // headerRow (shared with the Themes tab); this adds the
                    // rest of wallsHeaderGap on top of that.
                    anchors.top: parent.top
                    anchors.topMargin: root.wallsHeaderGap - root.bodyTopMargin
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: root.wallsBottomExtra
                    onAddRequested: {
                        root.focusBeforeAdd = wallsBody.carousel.focusIndex;
                        slide.runAfterClose(() => wallsBody.carousel.chooseFile());
                        root.closePicker();
                    }
                    onAddDone: path => {
                        root.openPicker();
                        wallsBody.carousel.focusIndex = root.focusBeforeAdd;
                        wallsBody.carousel.focusPath(path);
                    }
                }
            }
        }

        // Grabs Escape while the picker is open; shell.qml grants real
        // keyboard focus to this window only while pickerOpen holds, mirroring
        // the Wi-Fi password row's WlrKeyboardFocus OnDemand/Exclusive pattern.
        Item {
            id: escCatcher
            anchors.fill: parent
            focus: root.pickerOpen
            Keys.onEscapePressed: root.closePicker()
            Keys.onPressed: (event) => {
                var carousel = root.pickerTab === "themes" ? themesCarousel
                    : root.pickerTab === "walls" ? wallsBody.carousel : null;
                if (carousel) {
                    if (event.key === Qt.Key_Left || event.key === Qt.Key_Right) {
                        carousel.moveFocus(event.key === Qt.Key_Left ? -1 : 1);
                        event.accepted = true;
                        return;
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        carousel.applyFocused();
                        event.accepted = true;
                        return;
                    }
                }
                if (root.pickerTab === "walls") {
                    if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
                        var digit = event.key - Qt.Key_0;
                        var hasMonitor = false;
                        for (var i = 0; i < Wallpapers.monitors.length; i++) {
                            if (Wallpapers.monitors[i].number === digit) { hasMonitor = true; break; }
                        }
                        if (hasMonitor) wallsBody.carousel.assignFocusedToMonitor(digit);
                        event.accepted = true;
                        return;
                    } else if (event.key === Qt.Key_A) {
                        wallsBody.carousel.assignFocusedToAll();
                        event.accepted = true;
                        return;
                    } else if (event.key === Qt.Key_I) {
                        Wallpapers.identify();
                        event.accepted = true;
                        return;
                    }
                }
                if (event.key === Qt.Key_Tab) {
                    root.pickerTab = root.pickerTab === "themes" ? "walls" : "themes";
                    event.accepted = true;
                }
            }
        }
    }

    /** Exposes the notch's on-screen rectangle for the window's input mask. */
    property alias maskX: notchRect.x
    property alias maskY: notchRect.y
    property alias maskWidth: notchRect.width
    property alias maskHeight: notchRect.height
}
