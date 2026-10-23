pragma Singleton
import QtQuick

// Keeps the started commands and the sticker file the fake `ls` finds.
QtObject {
    property var commands: []
    property string stickerFile: "/home/tester/.config/berri-shell/sticker.png"
}
