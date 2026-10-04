# Notification limits

Issue #66 uses one policy in `logic/NotificationLogic.js`.

| Value | Limit |
| --- | ---: |
| Stored history, including snoozed items | 200 |
| Tracked sender objects, including critical and transient items | 200 |
| Waiting pop-ups per monitor, including critical and transient items | 20 |
| Open pop-up per monitor | 1 |
| Stored item id | 128 UTF-16 code units |
| Sender name | 256 UTF-16 code units |
| Icon path or name | 1,024 UTF-16 code units |
| Summary | 512 UTF-16 code units |
| Body | 4,096 UTF-16 code units |
| Actions examined per notification | 16 |
| Action id | 128 UTF-16 code units |
| Action label | 256 UTF-16 code units |

Text above a limit is cut in the shell's snapshot. An action with an id above
128 code units is omitted. Its id is never cut because that could invoke a
different action. Extra actions are omitted. Saved files use the same text
limits and store no actions. Transient items are never saved.

The saved JSON is below 8 MiB, including pretty printing and the largest JSON
escape expansion of the bounded text. The 1,000-item ASCII traffic test saves
about 851 KiB. This is a bound on the notification file, not the file cache.

When live senders reach 200, the oldest tracked sender is dismissed before
another is stored. Both live indexes and expiry entries lose closed senders.
The waiting queue drops the oldest non-critical item first. If all waiting
items are critical, it drops the oldest critical item. Sender updates replace
the current or waiting snapshot in place.

History changes are immediate. Derived lists update once after a burst.
Serialization and the atomic file write run after 300 ms without a save request.
READ ALL and CLEAR each use one history operation. Snooze uses
`Notifications.defaultSnoozeMinutes`.

## Repeat the checks

Run `node --test tests/notification-logic.test.mjs tests/notification-qml.test.mjs`.
The QML test needs `/usr/lib/qt6/bin/qmltestrunner`, or a path in
`QMLTESTRUNNER`. The Node test reports a skip if this tool is absent.

The test loads the real store, pop-up and Alerts components in an offscreen
Qt engine. It replaces the shell container, D-Bus sender/server, saved-state
file, monitor, theme and app-icon services. It starts no shell instance and
opens no user state file. Each run leaves its source copies and output under
`scratchpad/notification-qml-*`.

It sends 1,000 critical items with distinct 100 KiB bodies, then checks 200
live senders, 200 stored items, 20 waiting pop-ups and one serialization. It
also sends 1,000 transient items. The tests check replacement text and actions,
sender names, filtered bulk actions, and the row's snooze connection.

The timing test uses nine samples of ten consecutive updates with 200 stored
items. It includes the final list refresh. Serialization runs after the
300 ms wait and is checked separately. The median must be below 3 ms.
The first baseline probe took 8 ms. Repeating the original store through the
same nine-sample test gave a median of 16 ms and ten serializations per sample.
The final test measured 1 ms and one delayed serialization. This measurement
uses test sender objects, not native D-Bus objects.

## Maintainer checks

The native Quickshell sender owns the original strings, action objects, hints
and image data. The shell can bound its snapshots and the number of tracked
senders. It cannot change those read-only native fields. A bound on whole-process
memory therefore needs a native D-Bus stress run. The offscreen sender replacement
has different allocation and destruction behavior and cannot prove that bound.
See the [Quickshell Notification API](https://quickshell.org/docs/v0.3.0/types/Quickshell.Services.Notifications/Notification/).

In an authorized isolated native shell instance, send 1,000 critical items with
100 KiB bodies. Check live and queue counts, peak and settled RSS, and the actual
saved file size. Repeat with transient items. Record a memory budget for that
native instance before accepting the memory part of issue #66.

On the maintainer's screen, check the open pop-up changing from Before to After
with its new action buttons. Check the Alerts list for constructor, toString,
__proto__, all and unread. Check READ ALL, CLEAR and snooze, and check the existing
pop-up motion on both monitors. These live and visual checks are still open.
