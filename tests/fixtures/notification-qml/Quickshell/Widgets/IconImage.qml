import QtQuick
// Test replacement that loads the file at once, so a missing file gives Image.Error.
Image {
    asynchronous: false
}
