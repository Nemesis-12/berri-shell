pragma Singleton
import QtQuick

// Supplies fake output devices without connecting to system audio.
QtObject {
    property var defaultAudioSink: null
    property var preferredDefaultAudioSink: null
    property QtObject nodes: QtObject { property var values: [] }
}
