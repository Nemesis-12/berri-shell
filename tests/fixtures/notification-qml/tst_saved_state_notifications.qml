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

    function test_wallpaper_save_failure_uses_the_existing_notification_path() {
        ProcessLog.reset();

        Wallpapers.saveFailed("Backup failed");

        tryVerify(() => ProcessLog.commands.length === 1);
        compare(ProcessLog.commands[0], ["notify-send", "-a", "berri", "-i", "dialog-error",
            "-u", "normal", "Wallpaper settings not saved", "Backup failed"]);
    }
}
