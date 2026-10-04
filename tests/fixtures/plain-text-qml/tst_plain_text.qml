import QtQuick
import QtTest
import qs.common

// BASE is replaced by the node runner with the local test server address.
TestCase {
    id: test
    name: "PlainText"
    when: windowShown
    width: 200
    height: 200

    Component {
        id: textHolder
        Item {
            MonoText { text: "<b>bold</b><img src=\"BASE/text-mono.png\">" }
            CondensedText { text: "<b>bold</b><img src=\"BASE/text-condensed.png\">" }
            AlbumArt { width: 50; height: 50; artUrl: "BASE/art-http.png" }
        }
    }

    // Control: the same markup as rich text must reach the server.
    Component {
        id: richHolder
        Text { textFormat: Text.RichText; text: "<img src=\"BASE/control-rich.png\">" }
    }

    function test_outside_text_makes_no_request() {
        createTemporaryObject(textHolder, test);
        wait(800);
    }

    function test_control_rich_text_requests() {
        createTemporaryObject(richHolder, test);
        wait(800);
    }
}
