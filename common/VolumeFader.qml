import Quickshell.Services.Pipewire

/** Home and Media use this control for the current output's volume. */
Fader {
    id: root

    readonly property var sink: Pipewire.defaultAudioSink
    value: sink && sink.audio ? sink.audio.volume * 100 : 0
    iconName: !expanded && sink && sink.audio && sink.audio.muted ? "volume-x" : "volume-2"
    label: "VOLUME"

    PwObjectTracker {
        objects: root.sink ? [root.sink] : []
    }

    onValueEdited: newValue => {
        if (root.sink && root.sink.audio)
            root.sink.audio.volume = newValue / 100;
    }
}
