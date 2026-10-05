pragma Singleton
import QtQuick

// Stand-in for the minute clock: the test sets `minute` by hand.
QtObject {
    property int viewers: 0
    property date minute: new Date()
}
