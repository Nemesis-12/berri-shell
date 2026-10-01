import QtQuick
import qs.services
import qs.common

/**
 * One tab's body inside the panel's content area. Shows only while its
 * `tabId` equals `current`; fading in and out gives the tab switch a
 * crossfade. Put the tab's content in as children. Hidden pages are
 * not visible and do not take input.
 */
Item {
    id: page

    /** Name of this tab: "home", "media", "system", "code", "calendar", "weather" or "alerts". */
    property string tabId: ""

    /** Name of the tab that is active now. */
    property string current: ""

    default property alias content: holder.data

    readonly property bool shown: tabId === current

    anchors.fill: parent
    opacity: shown ? 1 : 0
    visible: opacity > 0.001
    enabled: shown

    Fade on opacity { duration: Theme.stateMs }

    Item {
        id: holder
        anchors.fill: parent
    }
}
