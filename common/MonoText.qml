import QtQuick
import qs.services

/** Small mono label (mock: 500 9px Plex Mono, dim). Set font.pixelSize, color or letterSpacing to change it. */
Text {
    textFormat: Text.PlainText
    color: Theme.dim
    font.family: Theme.mono
    font.weight: Font.Medium
    font.pixelSize: 9
}
