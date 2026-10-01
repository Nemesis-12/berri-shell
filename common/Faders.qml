import QtQuick
import Quickshell.Io
import Quickshell.Services.Pipewire

/**
 * Brightness and volume faders cell (ticket 19). Brightness reads/sets
 * brightnessctl; volume binds Pipewire's default sink. Mirrors the mock's
 * 5C faders cell (Berri Dashboard v2.dc.html, ~line 397).
 */
Item {
    id: root

    // --- Brightness: brightnessctl, polled every 2s while visible so key presses show up. ---
    property real brightnessValue: 0
    property bool brightnessDragging: false
    property real pendingBrightnessSet: -1

    // Which backlight device to drive. brightnessctl with no -d picks the
    // first one it finds, which on a laptop with a discrete/NVIDIA GPU can
    // be that GPU's own (non-functional) backlight instead of the screen's.
    // Resolved once at start: the right device is the one whose
    // /sys/class/backlight/<name>/device path sits under a connected
    // internal DRM connector (eDP/LVDS/DSI). Empty means "let brightnessctl
    // pick its own default" (detection found no match).
    property string backlightDevice: ""

    /** brightnessctl args to target the resolved backlight, or none if unresolved. */
    function deviceArgs() {
        return root.backlightDevice.length > 0 ? ["-d", root.backlightDevice] : [];
    }

    Component.onCompleted: backlightDetectProc.running = true

    // Read once when the cell shows again. The first read comes from the detection.
    onVisibleChanged: {
        if (visible && !backlightDetectProc.running)
            brightnessReadProc.running = true;
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
                brightnessReadProc.running = true;
            }
        }
    }

    Timer {
        interval: 2000
        running: root.visible && !root.brightnessDragging
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
                if (parts.length >= 5 && !root.brightnessDragging) {
                    var current = parseInt(parts[2]);
                    var max = parseInt(parts[4]);
                    if (max > 0)
                        root.brightnessValue = Math.round(current / max * 100);
                }
            }
        }
    }

    // Rate-limits `brightnessctl set` to at most once per 50ms while dragging.
    Timer {
        id: brightnessSetLimiter
        interval: 50
        repeat: false
        onTriggered: {
            if (root.pendingBrightnessSet >= 0) {
                brightnessSetProc.command = ["brightnessctl", "set"].concat(root.deviceArgs()).concat([Math.round(root.pendingBrightnessSet) + "%"]);
                brightnessSetProc.running = true;
                root.pendingBrightnessSet = -1;
            }
        }
    }

    Process {
        id: brightnessSetProc
    }

    function setBrightness(newValue) {
        root.brightnessValue = newValue;
        root.pendingBrightnessSet = newValue;
        if (!brightnessSetLimiter.running)
            brightnessSetLimiter.start();
    }

    // --- Volume: Pipewire's default sink. ---
    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink]
    }

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property real volumeValue: (sink && sink.audio) ? sink.audio.volume * 100 : 0
    readonly property bool volumeMuted: (sink && sink.audio) ? sink.audio.muted : false

    function setVolume(newValue) {
        if (sink && sink.audio)
            sink.audio.volume = newValue / 100;
    }

    Row {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 6

        Fader {
            width: (parent.width - 6) / 2
            height: parent.height
            value: root.brightnessValue
            iconName: "sun"
            label: "BRIGHT"
            onValueEdited: newValue => root.setBrightness(newValue)
            onDraggingChanged: root.brightnessDragging = dragging
        }

        Fader {
            width: (parent.width - 6) / 2
            height: parent.height
            value: root.volumeValue
            iconName: root.volumeMuted ? "volume-x" : "volume-2"
            label: "VOLUME"
            onValueEdited: newValue => root.setVolume(newValue)
        }
    }
}
