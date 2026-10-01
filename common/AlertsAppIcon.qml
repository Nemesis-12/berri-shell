import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.services

/**
 * The icon of one app: the notification's own icon when it resolves, else a
 * Lucide icon picked from the app name (bell when the name is unknown).
 */
Item {
    id: root

    property string appName: ""
    property string appIcon: ""
    property real size: 14
    property color color: Theme.fg2
    property real strokeWidth: 1.6

    // Absolute paths and file URLs load directly; names go through the icon theme.
    readonly property string resolved: {
        if (root.appIcon === "") return "";
        if (root.appIcon.indexOf("/") === 0 || root.appIcon.indexOf("file:") === 0) return root.appIcon;
        return Quickshell.iconPath(root.appIcon, true);
    }

    readonly property string fallbackName: {
        var n = root.appName.toLowerCase();
        if (n.indexOf("signal") >= 0 || n.indexOf("telegram") >= 0 || n.indexOf("whatsapp") >= 0) return "message-circle";
        if (n.indexOf("slack") >= 0) return "hash";
        if (n.indexOf("discord") >= 0) return "gamepad-2";
        if (n.indexOf("mail") >= 0 || n.indexOf("thunderbird") >= 0) return "mail";
        if (n.indexOf("github") >= 0) return "git-pull-request";
        if (n.indexOf("system") >= 0 || n.indexOf("notify") >= 0 || n.indexOf("pacman") >= 0) return "package";
        return "bell";
    }

    implicitWidth: size
    implicitHeight: size

    IconImage {
        anchors.fill: parent
        source: root.resolved
        visible: root.resolved !== ""
    }

    Icon {
        anchors.fill: parent
        visible: root.resolved === ""
        name: root.fallbackName
        size: root.size
        strokeWidth: root.strokeWidth
        color: root.color
    }
}
