import QtQuick
import QtTest
import qs.services
import qs.tabs.home
import Quickshell.Io
import Quickshell.Services.UPower

// Checks that a later refresh or a running process never drops the user choice.
Item {
    width: 400
    height: 200

    Profile { id: profile; width: 300; height: 80 }

    TestCase {
        name: "SettingsPersist"
        when: windowShown

        readonly property string facePath: "/home/tester/.face"
        readonly property string accountsPath: "/var/lib/AccountsService/icons/tester"

        // Starts each test with the screen at normal color.
        function init() {
            ProcessLog.temperature = 6500;
            Nightlight.on = false;
        }

        // The saved mode applies as soon as the service exists. No view is needed.
        function test_saved_power_mode_applies_without_a_view() {
            compare(PowerProfiles.profile, PowerProfile.Balanced);
            compare(PowerModes.activeMode, "saver");
            tryCompare(PowerProfiles, "profile", PowerProfile.PowerSaver);
        }

        // Two quick night-light actions end at the second requested state.
        function test_two_quick_night_light_actions_end_at_the_second() {
            const before = ProcessLog.commands.length;
            Nightlight.toggle();
            wait(100);
            Nightlight.toggle();
            tryCompare(ProcessLog, "temperature", 6500, 3000);
            wait(900);
            compare(ProcessLog.temperature, 6500);
            compare(Nightlight.on, false);
            const sets = ProcessLog.commands.slice(before).filter(command => command[0] === "bash");
            compare(sets.length, 2);
        }

        // A request during a running write waits, then the latest one is written.
        function test_request_during_active_write_is_applied_after_it() {
            Nightlight.setOn(true);
            wait(50);
            Nightlight.setOn(false);
            Nightlight.setOn(true);
            tryCompare(ProcessLog, "temperature", 4000, 3000);
            tryCompare(Nightlight, "on", true, 3000);
            wait(400);
        }

        function openProfile() {
            profile.visible = false;
            profile.visible = true;
            wait(50);
        }

        // The chosen picture stays after a minute passes and after Home opens again.
        function test_chosen_picture_beats_the_system_icon() {
            ProcessLog.files = [accountsPath];
            openProfile();
            tryCompare(profile, "pictureSource", "file://" + accountsPath);

            profile.openPictureChooser();
            tryVerify(() => profile.pictureSource.indexOf("file://" + facePath) === 0);
            for (let i = 0; i < 3; i++) {
                Clock.minuteChanged();
                wait(50);
                verify(profile.pictureSource.indexOf("file://" + facePath) === 0, "after minute " + (i + 1));
                openProfile();
                verify(profile.pictureSource.indexOf("file://" + facePath) === 0, "after reopen " + (i + 1));
            }
        }
    }
}
