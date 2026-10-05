import QtQuick
import qs.common
import qs.services

/**
 * Crossfades between two copies of `content` when `day` changes. The hidden
 * copy takes the new day, then one progress value (`blend`) fades the two.
 * Each copy needs a `day` property; it is set from here.
 */
Item {
    id: root

    /** Day index shown: 0 is now, 1..6 later days. */
    property int day: 0

    /** What to draw for one day: an item with a `day` property. */
    property Component content

    property int dayA: 0
    property int dayB: 0
    property bool showB: false

    /** 0 shows copy A only, 1 shows copy B only. */
    property real blend: showB ? 1 : 0

    Behavior on blend {
        StandardMotion {
            duration: 260
        }
    }

    onDayChanged: {
        if (root.showB) root.dayA = root.day;
        else root.dayB = root.day;
        root.showB = !root.showB;
    }

    Loader {
        anchors.fill: parent
        sourceComponent: root.content
        opacity: 1 - root.blend
        visible: opacity > 0.001
        onLoaded: item.day = Qt.binding(() => root.dayA)
    }

    Loader {
        anchors.fill: parent
        sourceComponent: root.content
        opacity: root.blend
        visible: opacity > 0.001
        onLoaded: item.day = Qt.binding(() => root.dayB)
    }
}
