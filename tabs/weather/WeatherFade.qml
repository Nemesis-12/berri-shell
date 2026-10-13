import QtQuick
import qs.common
import qs.services
import "../../logic/WeatherParse.js" as WeatherParse

/**
 * Crossfades between two copies of `content` when the chosen date changes. The hidden
 * copy takes the new day, then one progress value (`blend`) fades the two.
 * Each copy needs a `day` property; it is set from here.
 */
Item {
    id: root

    /** Empty means now; forecast selections keep their calendar date. */
    property string date: ""

    /** What to draw for one day: an item with a `day` property. */
    property Component content

    property string dateA: ""
    property string dateB: ""
    property bool showB: false

    /** 0 shows copy A only, 1 shows copy B only. */
    property real blend: showB ? 1 : 0

    Behavior on blend {
        StandardMotion {
            duration: 260
        }
    }

    onDateChanged: {
        if (root.showB) root.dateA = root.date;
        else root.dateB = root.date;
        root.showB = !root.showB;
    }

    Loader {
        anchors.fill: parent
        sourceComponent: root.content
        opacity: 1 - root.blend
        visible: opacity > 0.001
        onLoaded: item.day = Qt.binding(() => WeatherParse.selectedDay(Weather.days, root.dateA))
    }

    Loader {
        anchors.fill: parent
        sourceComponent: root.content
        opacity: root.blend
        visible: opacity > 0.001
        onLoaded: item.day = Qt.binding(() => WeatherParse.selectedDay(Weather.days, root.dateB))
    }
}
