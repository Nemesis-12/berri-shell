import QtQuick
import QtTest
import Quickshell.Io
import qs.services
import qs.notifications

TestCase {
    id: tests
    name: "SavedStateNotifications"
    when: windowShown

    property var notifier: ReminderNotifier

    // A good save clears the "already reported" state that earlier tests may leave.
    function init() { Wallpapers.saved(); }

    function test_wallpaper_save_failure_uses_the_existing_notification_path() {
        ProcessLog.reset();

        Wallpapers.saveFailed("Backup failed");

        tryVerify(() => ProcessLog.commands.length === 1);
        compare(ProcessLog.commands[0], ["notify-send", "-a", "berri", "-i", "dialog-error",
            "-u", "normal", "Wallpaper settings not saved", "Backup failed"]);
    }

    function test_repeated_wallpaper_save_failures_notify_once_until_a_save_works() {
        ProcessLog.reset();

        Wallpapers.saveFailed("Backup failed");
        Wallpapers.saveFailed("Backup failed");
        tryVerify(() => ProcessLog.commands.length === 1);
        wait(50);
        compare(ProcessLog.commands.length, 1);

        Wallpapers.saved();
        Wallpapers.saveFailed("Permission denied");
        tryVerify(() => ProcessLog.commands.length === 2);
        compare(ProcessLog.commands[1][8], "Permission denied");
    }
}
