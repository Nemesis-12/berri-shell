"""Test notification ownership offscreen, without loading the desktop shell."""
import contextlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[1]
NAME = "org.freedesktop.Notifications"
OBJECT = "/org/freedesktop/Notifications"


# Poll a real interface until it is ready, with a fixed deadline.
def wait_for(read, ready):
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        value = read()
        if ready(value):
            return value
        time.sleep(0.05)
    raise AssertionError(f"Timed out; last result: {value}")


# Keep every D-Bus call on the private session bus created by the parent test.
def bus_call(destination, path, interface, method, *args):
    result = subprocess.run(
        ["busctl", "--address=" + os.environ["DBUS_SESSION_BUS_ADDRESS"],
         "call", destination, path, interface, method, *args],
        capture_output=True, text=True, timeout=3,
    )
    return result.stdout.strip() if result.returncode == 0 else ""


# Read the process that owns the notification name from D-Bus itself.
def owner_pid():
    owner = bus_call("org.freedesktop.DBus", "/org/freedesktop/DBus",
                     "org.freedesktop.DBus", "GetNameOwner", "s", NAME)
    if not owner:
        return ""
    return bus_call("org.freedesktop.DBus", "/org/freedesktop/DBus",
                    "org.freedesktop.DBus", "GetConnectionUnixProcessID", "s",
                    json.loads(owner[2:]))


# A critical notification must reach the store even with do not disturb on.
def send_notification(logs):
    assert bus_call(NAME, OBJECT, NAME, "Notify", "susssasa{sv}i",
                    "Ownership test", "0", "", "Issue 63", "Private bus", "0",
                    "1", "urgency", "y", "2", "0").startswith("u ")
    text = wait_for(logs, lambda text: "notification-after-receive " in text)
    return json.loads(text.split("notification-after-receive ", 1)[1].splitlines()[0])


# Run only an offscreen fixture. Close it before deleting its temporary files.
@contextlib.contextmanager
def server(folder, name, source):
    config = folder / name
    config.mkdir()
    (config / "shell.qml").write_text(source, encoding="utf-8")
    for path in ("notifications/Notifications.qml", "services/SavedState.qml"):
        destination = config / path
        destination.parent.mkdir(exist_ok=True)
        shutil.copyfile(ROOT / path, destination)
    (config / "logic").symlink_to(ROOT / "logic", target_is_directory=True)
    with (config / "output.txt").open("w+") as output:
        process = subprocess.Popen(["qs", "--no-color", "-p", str(config)],
                                   stdout=output, stderr=subprocess.STDOUT)
        try:
            def logs():
                output.seek(0)
                return output.read()
            yield process, logs
        finally:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=3)


# Exercise the default through D-Bus with fresh or old saved state.
def check_default(folder, legacy=False):
    if legacy:
        saved = folder / "home/.local/state/berri-shell/notifications.json"
        saved.parent.mkdir(parents=True)
        saved.write_text(json.dumps({
            "serverEnabled": False, "dnd": True,
            "items": [{"id": "saved", "time": 5, "summary": "Saved history", "read": True}],
        }), encoding="utf-8")
    source = (ROOT / "tests/fixtures/notification-owner.qml").read_text(encoding="utf-8")
    with server(folder, "owner", source) as (process, logs):
        state_log = wait_for(logs, lambda text: "notification-state " in text)
        state = json.loads(state_log.split("notification-state ", 1)[1].splitlines()[0])
        assert state["dnd"] is legacy
        if legacy:
            assert [(item["id"], item["summary"], item["read"]) for item in state["items"]] == [
                ("saved", "Saved history", True)]
        wait_for(owner_pid, lambda value: value == f"u {process.pid}")
        assert bus_call(NAME, OBJECT, NAME, "GetServerInformation").startswith(
            'ssss "quickshell" "quickshell"')
        state = send_notification(logs)
        assert state["dnd"] is legacy
        assert sorted(item["summary"] for item in state["items"]) == (
            ["Issue 63", "Saved history"] if legacy else ["Issue 63"])
        assert "Could not register notification server" not in logs(), logs()


# Keep an existing test owner, then verify recovery after only that test owner exits.
def check_conflict(folder):
    blocker_source = """import Quickshell
import Quickshell.Services.Notifications
Scope { NotificationServer {} }
"""
    source = (ROOT / "tests/fixtures/notification-owner.qml").read_text(encoding="utf-8")
    with server(folder, "blocker", blocker_source) as (blocker, _):
        wait_for(owner_pid, lambda value: value == f"u {blocker.pid}")
        with server(folder, "owner", source) as (owner, logs):
            wait_for(logs, lambda text: "notification-state " in text)
            assert "Could not register notification server" in logs(), logs()
            assert "Registration will be attempted again" in logs(), logs()
            assert blocker.poll() is None
            assert owner_pid() == f"u {blocker.pid}"
            blocker.terminate()
            blocker.wait(timeout=3)
            wait_for(owner_pid, lambda value: value == f"u {owner.pid}")
            state = send_notification(logs)
            assert [item["summary"] for item in state["items"]] == ["Issue 63"]


# Run the ownership checks with the repository's Python test suite.
class NotificationOwnershipTests(unittest.TestCase):
    # Create a bus with no desktop services and put all writable paths in scratchpad.
    def check_isolated(self, scenario):
        for command in ("qs", "dbus-run-session", "busctl"):
            if shutil.which(command) is None:
                self.skipTest(f"{command} is required for the isolated QML test")
        scratchpad = ROOT / "scratchpad"
        scratchpad.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="notification-ownership-", dir=scratchpad) as temporary:
            folder = Path(temporary)
            runtime = folder / "runtime"
            runtime.mkdir(mode=0o700)
            bus_config = folder / "bus.conf"
            bus_config.write_text("""<busconfig>
  <type>session</type>
  <listen>unix:tmpdir=/proc/self/cwd/runtime</listen>
  <auth>EXTERNAL</auth>
  <policy context="default">
    <allow own="*"/><allow send_destination="*"/><allow receive_sender="*"/>
  </policy>
</busconfig>
""", encoding="utf-8")
            env = {**os.environ, "HOME": str(folder / "home"),
                   # Keep Unix socket paths short while all writes stay in scratchpad.
                   "XDG_RUNTIME_DIR": "/proc/self/cwd/runtime", "XDG_CONFIG_HOME": str(folder / "config"),
                   "XDG_CACHE_HOME": str(folder / "cache"), "XDG_DATA_HOME": str(folder / "data"),
                   "XDG_STATE_HOME": str(folder / "state"), "QT_QPA_PLATFORM": "offscreen",
                   "QT_QPA_PLATFORMTHEME": "generic", "QT_QUICK_CONTROLS_STYLE": "Basic"}
            for key in ("WAYLAND_DISPLAY", "DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE"):
                env.pop(key, None)
            result = subprocess.run(
                ["dbus-run-session", "--config-file=" + str(bus_config), "--",
                 sys.executable, str(Path(__file__).resolve()),
                 "--private-bus", str(folder), scenario],
                env=env, cwd=folder, capture_output=True, text=True, timeout=20,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_berri_owns_the_name_by_default(self):
        self.check_isolated("fresh")

    def test_old_disabled_state_keeps_history_and_do_not_disturb(self):
        self.check_isolated("legacy")

    def test_conflict_keeps_the_owner_and_retries_after_it_exits(self):
        self.check_isolated("conflict")


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--private-bus":
        folder = Path(sys.argv[2])
        if sys.argv[3] == "conflict":
            check_conflict(folder)
        else:
            check_default(folder, legacy=sys.argv[3] == "legacy")
    else:
        unittest.main()
