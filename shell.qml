import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import "logic/PixelGrid.js" as PixelGrid
import qs.common
import qs.picker
import qs.pill
import qs.services
import qs.notifications

/**
 * berri-shell entry: one pill and dashboard per monitor, with the theme
 * picker, wallpaper, tray, and notification views.
 */
ShellRoot {
    id: root

    readonly property int topMargin: 10

    /** Recheck fullscreen state on Hyprland fullscreen toggles. */
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "fullscreen" || event.name === "fullscreenv2")
                Hyprland.refreshToplevels();
        }
    }

    // Keep these services active while the shell runs, also when a view is closed.
    readonly property var notificationService: Notifications
    readonly property var lowBatteryService: LowBatteryAlert
    readonly property var reminderService: ReminderNotifier
    // The saved power mode applies at start, before any view creates PowerModes.
    readonly property var powerModesService: PowerModes

    // berri's own desktop background (28), on every monitor, and the
    // "identify monitors" number flash. Both are self-contained Variants
    // components (one PanelWindow per screen inside each).
    WallpaperLayer {}
    IdentifyOverlay {}

    // Caffeine: a Wayland idle inhibitor needs a window to attach to, so one
    // tiny invisible layer-shell surface hosts it. It exists once for the
    // whole shell (not per monitor) and follows the Caffeine singleton.
    PanelWindow {
        id: idleHost
        visible: true
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Background
        WlrLayershell.namespace: "berri-shell-idle-inhibit"
        implicitWidth: 1
        implicitHeight: 1
        mask: Region {}
        anchors { top: true; left: true }

        IdleInhibitor {
            window: idleHost
            enabled: Caffeine.on
        }
    }

    // One overlay window per monitor (see EdgeWindow.qml): the top pill with its
    // notification card, and the bottom-center theme notch. The notch fades out on
    // its own in fullscreen (ticket 29) and returns while the cursor touches the
    // bottom edge strip.
    Variants {
        id: overlayVariants
        model: Quickshell.screens

        EdgeWindow {
            id: overlay
            required property var modelData

            property alias pill: pill
            property alias popup: popup
            property alias themeNotch: notch

            screen: modelData
            layerName: "berri-shell"
            // Wide enough for the hovered pill, its shadow and the 380 px card; an even width keeps the center on a whole pixel.
            restWidth: 2 * Math.ceil((Math.max(pill.hoverWidth, popup.cardMaxWidth) + 128) / 2)
            topPanel: Qt.rect(pill.x + pill.maskX, pill.y + pill.maskY, pill.maskWidth, pill.maskHeight)
            bottomPanel: Qt.rect(notch.x + notch.maskX, notch.y + notch.maskY, notch.maskWidth, notch.maskHeight)
            panelOpen: pill.panelOpen || pill.trayLayerOpen || notch.pickerOpen
            topKeepShown: pill.panelOpen || pill.hovered
            bottomKeepShown: notch.pickerOpen || notch.hovered
            dimmed: pill.panelOpen || notch.pickerOpen
            card: popup
            // The Wi-Fi password row and text fields need the keyboard while used; the picker needs it for Esc.
            wantsKeyboard: pill.wifiPasswordActive || pill.textEntryActive || pill.panelOpen || pill.trayLayerOpen || notch.pickerOpen

            onDimClicked: {
                pill.closePanel();
                notch.closePicker();
            }
            onFullscreenStarted: {
                pill.closeAtOnce();
                notch.closeAtOnce();
            }

            ThemeNotch {
                id: notch
                screenName: modelData.name
                opacity: overlay.bottomHidden ? 0 : 1
                Behavior on opacity {
                    NumberAnimation { duration: Theme.stateMs; easing.type: Easing.OutCubic }
                }
                // Slides in from the bottom edge with the fade (same progress: opacity).
                transform: Translate { y: PixelGrid.snap((1 - notch.opacity) * 8, notch.dpr) }
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
            }

            Pill {
                id: pill
                suppressed: overlay.topHidden
                popupActive: popup.active
                screenName: modelData.name

                anchors.horizontalCenter: parent.horizontalCenter
                y: root.topMargin
            }

            // Notification card that grows out of the pill (52); above the pill and the dim layer.
            PillPopup {
                id: popup
                anchors.fill: parent
                pill: pill
                screenName: modelData.name
                blocked: FullscreenState.modeOn(modelData) === 2
            }
        }
    }

    // TEMP: the window of the laptop monitor from a Variants, or null (for pickertest).
    function laptopWindow(variants: var): var {
        for (var i = 0; i < variants.instances.length; i++) {
            if (variants.instances[i].modelData.name === "eDP-2") return variants.instances[i];
        }
        return null;
    }

    // TEMP pickertest: remove after visual check
    IpcHandler {
        target: "pickertest"

        // Reveals the notch first if fullscreen hides it (hide timer stays off while open).
        function open(tab: string): void {
            var window = root.laptopWindow(overlayVariants);
            if (!window) return;
            window.bottomRevealed = true;
            window.themeNotch.openPicker();
            window.themeNotch.pickerTab = tab;
        }

        function close(): void {
            var window = root.laptopWindow(overlayVariants);
            if (window) window.themeNotch.closePicker();
        }

        // Opens the dashboard on one tab like a pill click; reveals the pill
        // first if fullscreen hides it (hide timer stays off while open).
        function dash(tab: string): void {
            var window = root.laptopWindow(overlayVariants);
            if (!window) return;
            window.topRevealed = true;
            window.pill.activeTab = window.pill.tabIds.indexOf(tab);
            window.pill.openPanel();
        }

        function dashClose(): void {
            var window = root.laptopWindow(overlayVariants);
            if (window) window.pill.closePanel();
        }

        // TEMP: collect garbage for the visual check.
        function collectGarbage(): void {
            gc();
        }

        // Forces one transition mode ("A"/"B"/"C2"/"D"/"F") for this single
        // switch, then applies the theme (28a visual check).
        function theme(key: string, mode: string): void {
            Theme.transitionMode = mode;
            Theme.apply(key, true, true, Theme.transitionDurationMs);
            Theme.transitionMode = "random";
        }
    }
}
