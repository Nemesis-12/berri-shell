import QtQuick
import "../logic/ThemeColors.js" as Colors
import qs.services
import qs.common

/**
 * The Themes tab body (ticket 26): a horizontal carousel of the 9 palettes
 * as cards, sliding so the focused card stays centered. Mirrors the mock's
 * Themes tab body (Berri Desktop v2.dc.html: cards ~338-343, thOff ~359,
 * card markup ~91-95).
 *
 * Hosted by ThemeNotch.qml's picker body. ThemeNotch owns keyboard input
 * (Left/Right/Enter/Tab, gated to while the picker is open) and calls
 * focusToCurrent()/moveFocus()/applyFocused() here.
 */
CardCarousel {
    id: root

    // focusIndex is an index into Theme.palettes (the focused card is scaled up and centered).
    count: Theme.palettes.length
    cardWidth: 236
    cardGap: 12
    trackHeight: cardHeight
    readonly property int cardHeight: 200

    // Card color-strip layout, shared with ThemeNotch.qml so the phase-1
    // picker strip can land exactly on the focused card's own strip (the
    // "handoff" crossfade). Keep these in sync with the card delegate below
    // (headerRow/frameOuter anchors and margins) if that layout changes.
    readonly property int titleTopMargin: 14
    readonly property int titleFontPixelSize: 16
    readonly property int titleFontWeight: Font.Medium
    readonly property string titleFontFamily: Theme.condensed
    readonly property int frameTopMargin: 12
    readonly property int frameSideMargin: 18
    readonly property int frameBottomMargin: 16
    // The 3 nested inset margins (1 + 2 + 1) between frameOuter's own edge
    // and the visible strip, on every side.
    readonly property int frameInnerInset: 4

    FontMetrics {
        id: titleMetrics
        font.family: root.titleFontFamily
        font.weight: root.titleFontWeight
        font.pixelSize: root.titleFontPixelSize
    }
    /** Height of the title row (headerRow), driven by the title font's own metrics. */
    readonly property real titleHeight: titleMetrics.height

    /** The focused card's own color strip, in card-local coordinates. */
    readonly property real stripWidth: cardWidth - 2 * (frameSideMargin + frameInnerInset)
    readonly property real stripHeight: cardHeight
        - (titleTopMargin + titleHeight + frameTopMargin + frameInnerInset)
        - (frameBottomMargin + frameInnerInset)
    /** Distance from the card's own bottom edge up to the strip's bottom edge. */
    readonly property real stripBottomOffset: frameBottomMargin + frameInnerInset

    /** Sets focus to the applied theme; called when the picker opens. */
    function focusToCurrent() {
        var palettes = Theme.palettes;
        var key = Theme.current ? Theme.current.key : "";
        for (var i = 0; i < palettes.length; i++) {
            if (palettes[i].key === key) {
                root.focusIndex = i;
                return;
            }
        }
        root.focusIndex = 0;
    }

    /** Applies the currently focused theme (Enter key). */
    function applyFocused() {
        var p = Theme.palettes[root.focusIndex];
        if (p) Theme.apply(p.key, { wallpaper: true, durationMs: Theme.transitionDurationMs });
    }

    Repeater {
        model: Theme.palettes

        delegate: Rectangle {
            id: card
            required property var modelData
            required property int index

            readonly property var c: modelData.c
            readonly property bool focused: index === root.focusIndex
            readonly property bool applied: Theme.current && Theme.current.key === modelData.key

            width: root.cardWidth
            height: root.cardHeight
            radius: 8
            color: c.background
            border.width: 2
            border.color: focused ? c.accent : "transparent"
            scale: focused ? 1 : 0.92
            opacity: focused ? 1 : 0.72

            Behavior on scale {
                SpringMotion {
                    duration: 450
                }
            }
            Fade on opacity { duration: Theme.stateMs }
            ColorFade on border.color { duration: Theme.stateMs }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root.focusIndex = card.index;
                    Theme.apply(card.modelData.key, { wallpaper: true, durationMs: Theme.transitionDurationMs });
                }
            }

            // Name + APPLIED badge row.
            Item {
                id: headerRow
                anchors.top: parent.top
                anchors.topMargin: root.titleTopMargin
                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.right: parent.right
                anchors.rightMargin: 14
                height: root.titleHeight

                Text {
                    textFormat: Text.PlainText
                    id: nameLabel
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: card.modelData.name
                    font.family: root.titleFontFamily
                    font.weight: root.titleFontWeight
                    font.pixelSize: root.titleFontPixelSize
                    color: card.c.bright_foreground
                }

                Rectangle {
                    visible: card.applied
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: appliedLabel.implicitWidth + 12
                    height: appliedLabel.implicitHeight + 8
                    radius: 5
                    color: card.c.accent

                    Text {
                        textFormat: Text.PlainText
                        id: appliedLabel
                        anchors.centerIn: parent
                        text: "APPLIED"
                        font.family: Theme.mono
                        font.weight: Font.DemiBold
                        font.pixelSize: 9
                        font.letterSpacing: 0.72
                        color: card.c.darker_background
                    }
                }
            }

            // 6-color strip with the thin double frame (mock's box-shadow
            // stack: 1px bright_foreground@30%, 2px card background,
            // 1px bright_foreground@10%; approximated with nested insets).
            // The strip itself is radius 10 (mock line 95); the frame rings
            // around it grow the radius by each shadow's spread: 10+1, 10+3,
            // 10+4 for the 1px/3px/4px spreads.
            Rectangle {
                id: frameOuter
                anchors.top: headerRow.bottom
                anchors.topMargin: root.frameTopMargin
                anchors.left: parent.left
                anchors.leftMargin: root.frameSideMargin
                anchors.right: parent.right
                anchors.rightMargin: root.frameSideMargin
                anchors.bottom: parent.bottom
                anchors.bottomMargin: root.frameBottomMargin
                radius: 14
                color: Qt.rgba(card.c.bright_foreground.r, card.c.bright_foreground.g, card.c.bright_foreground.b, 0.10)

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 1
                    radius: 13
                    color: card.c.background

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 2
                        radius: 11
                        color: Qt.rgba(card.c.bright_foreground.r, card.c.bright_foreground.g, card.c.bright_foreground.b, 0.30)

                        Row {
                            id: strip
                            anchors.fill: parent
                            anchors.margins: 1
                            spacing: 0
                            clip: true

                            Repeater {
                                id: stripRepeater
                                model: Colors.swatches.map(swatch => card.c[swatch.raw])

                                delegate: Rectangle {
                                    required property var modelData
                                    required property int index
                                    width: strip.width / 6
                                    height: strip.height
                                    color: modelData
                                    // Only the outer edges of the first/last column are
                                    // rounded, so the strip clips to a radius-10 rounded
                                    // rect without an OpacityMask layer.
                                    topLeftRadius: index === 0 ? 10 : 0
                                    bottomLeftRadius: index === 0 ? 10 : 0
                                    topRightRadius: index === stripRepeater.count - 1 ? 10 : 0
                                    bottomRightRadius: index === stripRepeater.count - 1 ? 10 : 0
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
