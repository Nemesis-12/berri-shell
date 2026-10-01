import QtQuick
import qs.common

/** One agent usage ring with a center slot for a BrandMark or Icon. */
ArcRing {
    id: root

    fadeValueColor: true
    default property alias content: centerSlot.data

    Item {
        id: centerSlot
        anchors.centerIn: parent
    }
}
