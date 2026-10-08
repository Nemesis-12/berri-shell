import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import qs.common
import qs.picker
import qs.services
import "../../logic/PixelGrid.js" as PixelGrid
import "../../logic/Times.js" as Times

/**
 * Profile cell: account picture on the left, username and
 * uptime on the right. Mirrors the mock's 5C profile row (Berri Dashboard
 * v2.dc.html, ~line 342). Picture source, in order: ~/.face (the picture the
 * user chose, or put there), then AccountsService's icon for this user, then
 * a solid Theme.accent square. The chosen picture is never replaced by the
 * system icon. Both files
 * are re-checked every minute so a newly added ~/.face appears without a
 * restart. SystemUsage supplies the same uptime snapshot as the System tab.
 * Picture checks run only while visible, and once when it shows again.
 *
 * Clicking the picture opens ImagePicker's portable chooser to
 * ~/.face, then reloads it at once. Pill closes the panel first via
 * pictureClicked(), since the panel's own Overlay layer would otherwise sit
 * above a normal dialog window.
 */
Item {
    id: root

    readonly property string userName: Quickshell.env("USER") || ""
    readonly property string homePath: Quickshell.env("HOME") || ""
    readonly property string accountsIconPath: "/var/lib/AccountsService/icons/" + userName
    readonly property string facePath: homePath + "/.face"
    readonly property string picturesDirPath: homePath + "/Pictures"

    /** "" means no picture file was found; show the solid fallback square. */
    property string pictureSource: ""
    readonly property string uptimeText: "UP " + Times.duration(SystemUsage.uptimeSeconds)

    /** Output scale of the screen this cell is on; used to decode images at native sharpness. */
    readonly property real dpr: PixelGrid.dpr(Screen.devicePixelRatio)

    /** Click on the picture; Pill closes the panel then calls openPictureChooser(). */
    signal pictureClicked()

    function openPictureChooser() {
        picker.open();
    }

    ImagePicker {
        id: picker
        dialogTitle: "Choose Profile Picture"
        nameFilters: ["Images (*.png *.jpg *.jpeg *.webp)"]
        startDir: root.picturesDirPath
        fallbackDir: root.homePath
        onChosen: (path) => copyToFace.copyFrom(path)
    }

    Process {
        id: copyToFace

        function copyFrom(path) {
            copyToFace.command = ["cp", "-f", path, root.facePath];
            copyToFace.running = true;
        }

        onExited: (exitCode) => {
            if (exitCode === 0) root.reloadFace();
        }
    }

    /** Re-points pictureSource at ~/.face with a cache-busting query so the Image reloads at once. */
    function reloadFace() {
        root.pictureSource = "file://" + root.facePath + "?" + Date.now();
    }

    function checkPicture() {
        faceCheck.running = true;
    }

    Process {
        id: faceCheck
        command: ["test", "-f", root.facePath]
        onExited: (exitCode) => {
            if (exitCode === 0) root.pictureSource = "file://" + root.facePath;
            else accountsIconCheck.running = true;
        }
    }

    Process {
        id: accountsIconCheck
        command: ["test", "-f", root.accountsIconPath]
        onExited: (exitCode) => {
            root.pictureSource = exitCode === 0 ? ("file://" + root.accountsIconPath) : "";
        }
    }

    Component.onCompleted: {
        checkPicture();
    }

    WhileVisible { service: Clock }

    /** Refreshes the picture on each new minute, while visible. */
    Connections {
        target: Clock
        enabled: root.visible
        function onMinuteChanged() {
            root.checkPicture();
        }
    }

    onVisibleChanged: {
        if (!visible) return;
        checkPicture();
    }

    Row {
        anchors.fill: parent

        // Picture: 80x80 square, flush to the cell edges, cropped to fill.
        // Solid Theme.accent fallback when no picture file exists. Clickable
        // either way, opening the picture chooser.
        Rectangle {
            id: pictureCell
            width: 80
            height: 80
            color: Theme.accent
            clip: true

            Image {
                anchors.fill: parent
                visible: root.pictureSource.length > 0
                source: root.pictureSource
                fillMode: Image.PreserveAspectCrop
                sourceSize: Qt.size(width * root.dpr, height * root.dpr)
                smooth: true
                mipmap: true
                asynchronous: true
                cache: false
            }

            // Hover hint: a dark veil that fades in/out to show the picture is clickable.
            Rectangle {
                anchors.fill: parent
                color: "black"
                opacity: pictureHover.hovered ? 0.3 : 0
                Behavior on opacity {
                    NumberAnimation {
                        duration: Theme.hoverMs
                        easing.type: Easing.OutCubic
                    }
                }
            }

            HoverHandler {
                id: pictureHover
                cursorShape: Qt.PointingHandCursor
            }

            TapHandler {
                onTapped: root.pictureClicked()
            }
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            leftPadding: 14
            rightPadding: 14
            spacing: 7

            // lineHeightMode/lineHeight/height pin each line's box to exactly
            // its font size (Qt's default line box is taller than the pixel
            // size), so the 7px spacing above is the only gap between lines.
            Text {
                textFormat: Text.PlainText
                text: root.userName
                font.family: Theme.condensed
                font.weight: Font.DemiBold
                font.pixelSize: 16
                lineHeightMode: Text.FixedHeight
                lineHeight: 16
                height: 16
                verticalAlignment: Text.AlignVCenter
                color: Theme.fg
            }

            Text {
                textFormat: Text.PlainText
                text: root.uptimeText
                font.family: Theme.mono
                font.weight: Font.Medium
                font.pixelSize: 10
                font.letterSpacing: 1.0
                font.capitalization: Font.AllUppercase
                lineHeightMode: Text.FixedHeight
                lineHeight: 10
                height: 10
                verticalAlignment: Text.AlignVCenter
                color: Theme.dim
            }
        }
    }
}
