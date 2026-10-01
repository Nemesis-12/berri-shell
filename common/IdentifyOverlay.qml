import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services

/**
 * "Identify monitors" overlay (28): on Wallpapers.identifyRequested, shows
 * each screen's berri monitor number, centered, for 2s, then fades out.
 * Not mapped at all while hidden - only appears for the identify flash.
 */
Item {
    id: root

    property bool showing: false

    Connections {
        target: Wallpapers
        function onIdentifyRequested() {
            root.showing = true;
            hideTimer.restart();
        }
    }

    Timer {
        id: hideTimer
        interval: 2000
        onTriggered: root.showing = false
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: overlay
            required property var modelData
            property bool mapped: false

            screen: modelData
            color: "transparent"
            visible: overlay.mapped
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "berri-identify"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            anchors { top: true; left: true; right: true; bottom: true }

            // No input, ever.
            mask: Region {}

            Connections {
                target: root
                function onShowingChanged() {
                    if (root.showing) overlay.mapped = true;
                }
            }

            readonly property var mon: {
                var list = Wallpapers.monitors;
                for (var i = 0; i < list.length; i++) {
                    if (list[i].name === modelData.name) return list[i];
                }
                return null;
            }

            Text {
                id: number
                anchors.centerIn: parent
                text: overlay.mon ? String(overlay.mon.number) : ""
                color: Theme.fg
                font.family: Theme.condensed
                font.weight: Font.Bold
                font.pixelSize: 220
                opacity: root.showing ? 1 : 0

                Behavior on opacity {
                    NumberAnimation {
                        duration: Theme.stateMs
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Theme.standardCurve
                    }
                }

                onOpacityChanged: if (opacity === 0 && !root.showing) overlay.mapped = false
            }
        }
    }
}
