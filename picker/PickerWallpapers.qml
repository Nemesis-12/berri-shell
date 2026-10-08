import QtQuick
import qs.common
import qs.services

/**
 * Wallpapers tab body of the open picker: the wallpaper carousel above the
 * SHOW ON row. `shown` is true while this tab is open. The notch decides
 * what an add does (it closes the picker around the file dialog), so this
 * part only forwards `addRequested` and `addDone`. `carousel` is the
 * WallpapersCarousel, for the key handler.
 */
Item {
    id: root

    property string screenName: ""
    property bool shown: false
    /** Space between the carousel and the SHOW ON row. */
    property int rowGap: 15

    property alias carousel: wallpapersCarousel

    signal addRequested
    signal addDone(string path)

    WallpapersCarousel {
        id: wallpapersCarousel
        visible: root.shown
        screenName: root.screenName
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: showOnRow.top
        anchors.bottomMargin: root.rowGap
        onAddRequested: root.addRequested()
        onAddDone: path => root.addDone(path)
    }

    WallpaperScreens {
        id: showOnRow
        carousel: wallpapersCarousel
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
    }
}
