pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/** Owns backlight detection, visible-view sampling, and brightness writes. */
Singleton {
    id: root

    property int viewers: 0

    // Reads brightnessctl every 2 seconds while a view is visible.
    property real value: 0
    property bool dragging: false

    /** Lowest value the screen accepts. Zero would turn the backlight off. */
    readonly property int minimumPercent: 1
    property real pendingBrightnessSet: -1

    // Which backlight device to drive. brightnessctl with no -d picks the
    // first one it finds, which on a laptop with a discrete/NVIDIA GPU can
    // be that GPU's own (non-functional) backlight instead of the screen's.
    // Resolved when the first view opens: the right device is the one whose
    // /sys/class/backlight/<name>/device path sits under a connected
    // internal DRM connector (eDP/LVDS/DSI). Empty means "let brightnessctl
    // pick its own default" (detection found no match).
    property string backlightDevice: ""

    /** brightnessctl args to target the resolved backlight, or none if unresolved. */
    function deviceArgs() {
        return root.backlightDevice.length > 0 ? ["-d", root.backlightDevice] : [];
    }

    property bool backlightDetected: false

    // Start reads only when a view needs them. Hidden views stop sampling.
    onViewersChanged: {
        if (viewers > 0) {
            if (!backlightDetected)
                backlightDetectProc.running = true;
            else
                brightnessReadProc.running = true;
        } else {
            brightnessReadProc.running = false;
        }
    }

    // Finds the backlight under a connected internal (eDP/LVDS/DSI) display.
    Process {
        id: backlightDetectProc
        command: ["sh", "-c",
            "for bl in /sys/class/backlight/*; do " +
            "  name=$(basename \"$bl\"); dev=$(readlink -f \"$bl/device\"); " +
            "  for c in /sys/class/drm/card*-eDP-* /sys/class/drm/card*-LVDS-* /sys/class/drm/card*-DSI-*; do " +
            "    [ -e \"$c\" ] || continue; cdev=$(readlink -f \"$c\"); " +
            "    case \"$dev\" in \"$cdev\"|\"$cdev\"/*) " +
            "      [ \"$(cat \"$c/status\" 2>/dev/null)\" = connected ] && echo \"$name\" && exit 0 ;; " +
            "    esac; " +
            "  done; " +
            "done"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                root.backlightDevice = text.trim();
                root.backlightDetected = true;
                brightnessReadProc.running = root.viewers > 0;
            }
        }
    }

    Timer {
        interval: 2000
        running: root.viewers > 0 && !root.dragging
        repeat: true
        onTriggered: brightnessReadProc.running = true
    }

    Process {
        id: brightnessReadProc
        command: ["brightnessctl", "-m"].concat(root.deviceArgs())
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                // Format: device,class,current,percent%,max
                var parts = text.trim().split(",");
                if (parts.length >= 5 && !root.dragging && root.pendingBrightnessSet < 0 && !brightnessSetProc.running) {
                    var current = parseInt(parts[2]);
                    var max = parseInt(parts[4]);
                    if (max > 0)
                        root.value = Math.round(current / max * 100);
                }
            }
        }
    }

    // Rate-limits `brightnessctl set` to at most once per 50ms while dragging.
    Timer {
        interval: 50
        repeat: true
        running: root.pendingBrightnessSet >= 0
        onTriggered: {
            if (!brightnessSetProc.running) {
                brightnessSetProc.command = ["brightnessctl", "set"].concat(root.deviceArgs()).concat([Math.max(root.minimumPercent, Math.round(root.pendingBrightnessSet)) + "%"]);
                brightnessSetProc.running = true;
                root.pendingBrightnessSet = -1;
            }
        }
    }

    Process {
        id: brightnessSetProc
    }

    /** Queues the latest drag value (at least minimumPercent) while a previous write finishes. */
    function setValue(newValue) {
        var wanted = Math.max(root.minimumPercent, newValue);
        root.value = wanted;
        root.pendingBrightnessSet = wanted;
    }
}
