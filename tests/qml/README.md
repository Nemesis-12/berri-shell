# Calendar checks

Run `node --test tests/` or only `node --test tests/calendar-subscribe.test.mjs`.
The Node runner starts Qt's `qmltestrunner` with an offscreen window and software
rendering. It requires Qt Quick Test. The default executable is
`/usr/lib/qt6/bin/qmltestrunner`; set `QMLTESTRUNNER` to use another path.
A missing executable fails the test. The check does not start Quickshell.

The runner copies complete calendar services, components, and logic files to a
unique folder in `scratchpad/`. It makes QML module definitions for the copy.
Qt loads the complete files and their actual imports. No test extracts function
text. The month service and subscribe checks that used function text now run in
Qt. Pure JavaScript checks use `fixtures/calendar-code.mjs` to load full modules.

The test replaces Quickshell's object containers, process access, file access,
and SavedState with the small files in `fixtures/calendar-qml/`. File contents
and settings stay in memory. A test emits a process exit signal to finish a
download. Calendar, CalendarFiles, Theme, Clock, and the calendar components are
real project files. These replacements do not test the Quickshell plugin,
network downloads, native dialogs, disk watches, or rendered appearance.

The component check loads the full Calendar tab with nonempty source and day
rows. It opens the form and checks a service signal. Qt warnings also fail the
check because an unknown Connections handler can warn while Qt returns success.
Mutation tests prove that comment braces pass, renamed component and service
signals fail, and an added required row property fails. Each mutation changes
only its test copy. The runner removes the copy after the test.

The call-order check (`tst_calendar_order.qml`) reads `TestIo.events`. The fake file
view logs each write there, and the check logs each `revisionChanged` and `saveFailed`
signal with the titles the views read at that moment. It proves the order: save,
rebuild, signal. A failed save is undone and rebuilt before `saveFailed`.
