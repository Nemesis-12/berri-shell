import QtQuick
import "../logic/ArtUrl.js" as ArtUrl
import qs.services

/** Shows album art and releases decoded images when hidden. */
Item {
    id: root

    property string artUrl: ""
    readonly property string safeUrl: ArtUrl.safeArtUrl(artUrl)
    property real dpr: 1

    function loadArt() {
        if (!root.visible || !root.safeUrl) {
            back.source = "";
            front.source = "";
            front.opacity = 0;
            return;
        }
        if (front.source === root.safeUrl) return;
        back.source = front.status === Image.Ready ? front.source : "";
        front.opacity = 0;
        front.source = root.safeUrl;
        if (front.status === Image.Ready) front.opacity = 1;
    }

    onArtUrlChanged: loadArt()
    onVisibleChanged: loadArt()
    Component.onCompleted: loadArt()

    // Keep the previous art only until the new art has faded in.
    Image {
        id: back
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        sourceSize: Qt.size(width * root.dpr, height * root.dpr)
        smooth: true
        mipmap: true
        asynchronous: true
        cache: false
        visible: front.opacity < 1
    }

    Image {
        id: front
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        sourceSize: Qt.size(width * root.dpr, height * root.dpr)
        smooth: true
        mipmap: true
        asynchronous: true
        cache: false
        opacity: 0
        visible: source !== ""

        onStatusChanged: if (status === Image.Ready) opacity = 1
        onOpacityChanged: if (opacity >= 1) back.source = ""

        Fade on opacity { duration: Theme.stateMs }
    }
}
