import QtQuick
import QtTest
import qs.common

// Tests that the real app icon falls back to the Lucide icon when the file is missing.
TestCase {
    name: "AppIconFallback"
    when: windowShown
    visible: true
    width: 100
    height: 100

    AppIconUnderTest {
        id: icon
        size: 22
    }

    function test_missingFileShowsFallback() {
        icon.appName = "Signal";
        icon.appIcon = "/nonexistent/berri-icon.png";
        tryVerify(function () { return icon.showsFallback; }, 10000);
        compare(icon.fallbackName, "message-circle");
    }

    function test_existingFileHidesFallback() {
        icon.appIcon = Qt.resolvedUrl("pixel.png");
        tryVerify(function () { return !icon.showsFallback; }, 10000);
    }

    function test_noIconShowsFallback() {
        icon.appIcon = "";
        verify(icon.showsFallback);
    }
}
