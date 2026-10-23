import QtQuick
import QtTest
import qs.services
import qs.tabs.home
import Quickshell.Io
import Quickshell.Services.UPower

// Checks that a later refresh or a running process never drops the user choice.
Item {
    id: testItem
    width: 400
    height: 200

    Profile { id: profile; width: 300; height: 80 }
    // Created inside its test: loading it would start the power-mode service before the test that checks the start.
    Component { id: batteryCell; Battery { width: 300; height: 100 } }

    // A laptop battery that UPower reports as ready.
    QtObject {
        id: laptopBattery
        property bool ready: true
        property bool isLaptopBattery: true
        property bool isPresent: true
        property real percentage: 0.42
        property int state: UPowerDeviceState.Discharging
        property real timeToFull: 0
        property real timeToEmpty: 3600
    }

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
            tryCompare(ProcessLog, "temperature", 6500, 10000);
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
            tryCompare(ProcessLog, "temperature", 4000, 10000);
            tryCompare(Nightlight, "on", true, 10000);
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

        // A machine with no battery shows no level and no level bar. The power-mode buttons stay.
        // QtTest runs tests in name order. This name sorts after the power-mode start test, because the Battery cell starts that service.
        function test_without_a_battery_hides_the_reading_but_keeps_the_power_mode_buttons() {
            const battery = createTemporaryObject(batteryCell, testItem);
            const number = findChild(battery, "batteryNumberRow");
            const track = findChild(battery, "batteryLevelTrack");
            const modes = findChild(battery, "powerModes");
            UPower.displayDevice = laptopBattery;
            tryCompare(number, "visible", true);
            tryCompare(track, "visible", true);
            UPower.displayDevice = null;
            tryCompare(number, "visible", false);
            tryCompare(track, "visible", false);
            compare(modes.visible, true);
            compare(modes.children.length > 0, true);
            UPower.displayDevice = laptopBattery;
            tryCompare(number, "visible", true);
        }
    }
}
