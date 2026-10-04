import QtQuick
import qs.common
import qs.services

/**
 * The SHOW ON row of the wallpaper picker: "All", one button per monitor
 * (from Wallpapers.monitors), and Identify on the right. A button shows the
 * monitors that the focused wallpaper of `carousel` is on; a click puts that
 * wallpaper on the monitor (or on all of them).
 */
Item {
    id: root

    /** The wallpaper carousel whose focused wallpaper this row assigns. */
    required property WallpapersCarousel carousel

    implicitHeight: 24

    // Measures every button label ("All", "1", "2", ...) so every button
    // can share one width: the widest label plus the same padding.
    FontMetrics {
        id: labelMetrics
        font.family: Theme.mono
        font.weight: Font.DemiBold
        font.pixelSize: 11
    }
    readonly property real buttonWidth: {
        var w = labelMetrics.advanceWidth("All");
        for (var i = 0; i < Wallpapers.monitors.length; i++)
            w = Math.max(w, labelMetrics.advanceWidth(String(Wallpapers.monitors[i].number)));
        return w + 16;
    }

    /** One All or monitor button: outlined, filled in the accent when active. */
    component ScreenButton: Rectangle {
        id: button
        property bool active: false
        property alias text: label.text
        signal clicked()

        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        width: root.buttonWidth
        height: root.height
        radius: 4
        color: active ? Theme.accentFill : "transparent"
        border.width: 1
        border.color: active ? Theme.accent : Theme.border
        ColorFade on color { duration: Theme.stateMs }
        ColorFade on border.color { duration: Theme.stateMs }

        Text {
            textFormat: Text.PlainText
            id: label
            anchors.centerIn: parent
            font.family: Theme.mono
            font.weight: Font.DemiBold
            font.pixelSize: 11
            color: button.active ? Theme.accentLight : Theme.dim
            ColorFade on color { duration: Theme.stateMs }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: button.clicked()
        }
    }

    Row {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8

        MonoText {
            anchors.verticalCenter: parent.verticalCenter
            text: "SHOW ON"
            font.weight: Font.DemiBold
            font.letterSpacing: 0.9
            font.capitalization: Font.AllUppercase
        }

        // "All": active when the focused wallpaper is on every monitor.
        ScreenButton {
            text: "All"
            active: !root.carousel.focusIsAdd
                && Wallpapers.numbersShowing(root.carousel.focusedPath).length === Wallpapers.monitors.length
                && Wallpapers.monitors.length > 0
            onClicked: root.carousel.assignFocusedToAll()
        }

        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10

            Repeater {
                model: Wallpapers.monitors

                delegate: ScreenButton {
                    required property var modelData
                    text: String(modelData.number)
                    active: !root.carousel.focusIsAdd
                        && Wallpapers.numbersShowing(root.carousel.focusedPath).indexOf(modelData.number) !== -1
                    onClicked: root.carousel.assignFocusedToMonitor(modelData.number)
                }
            }
        }
    }

    Rectangle {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: identifyRow.implicitWidth + 16
        height: root.height
        radius: 4
        color: identifyArea.containsMouse ? Theme.raised : "transparent"
        ColorFade on color {}
        border.width: 1
        border.color: Theme.border

        Row {
            id: identifyRow
            anchors.centerIn: parent
            spacing: 4

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                name: "monitor"
                size: 11
                strokeWidth: 2
                color: identifyArea.containsMouse ? Theme.fg : Theme.dim
                ColorFade on color {}
            }

            Text {
                textFormat: Text.PlainText
                anchors.verticalCenter: parent.verticalCenter
                text: "Identify"
                font.family: Theme.mono
                font.weight: Font.DemiBold
                font.pixelSize: 10
                color: identifyArea.containsMouse ? Theme.fg : Theme.dim
                ColorFade on color {}
            }
        }

        MouseArea {
            id: identifyArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Wallpapers.identify()
        }
    }
}
