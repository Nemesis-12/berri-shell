"""Calendar save checks use native FileView and files inside scratchpad only."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parent.parent
QS = shutil.which("qs")
ORIGINAL = ("BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Test//EN\r\n"
            "BEGIN:VEVENT\r\nUID:kept\r\nDTSTART;VALUE=DATE:20261005\r\n"
            "SUMMARY:Kept café\r\nX-BERRI-COLOR:red\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n")


@unittest.skipUnless(QS, "Quickshell is required for isolated native file tests")
class CalendarWriteTests(unittest.TestCase):
    # Copy only the calendar service into a config with all storage in this worktree.
    def setUp(self):
        scratch = REPO / "scratchpad"
        scratch.mkdir(exist_ok=True)
        self.temporary = tempfile.TemporaryDirectory(prefix="calendar-124-", dir=scratch)
        self.addCleanup(self.temporary.cleanup)
        self.folder = Path(self.temporary.name)
        self.root = self.folder / "fixture"
        shutil.copytree(REPO / "logic", self.root / "logic")
        (self.root / "services").mkdir()
        for name in ("Calendar", "CalendarDisk", "CalendarFiles", "CalendarLinks", "SavedState", "FolderRoots"):
            shutil.copy(REPO / f"services/{name}.qml", self.root / f"services/{name}.qml")
        self.test_home = self.folder / "home"
        self.calendar = self.test_home / ".local/share/berri-shell/calendar"
        self.calendar.mkdir(parents=True)
        self.path = self.calendar / "berri.ics"
        self.path.write_bytes(ORIGINAL.encode())
        self.env = dict(os.environ, HOME=str(self.test_home), QT_QPA_PLATFORM="offscreen",
                        QT_QPA_PLATFORMTHEME="", QSG_RHI_BACKEND="software", QML_DISABLE_DISK_CACHE="1")
        for name in ("LD_LIBRARY_PATH", "DISPLAY", "WAYLAND_DISPLAY", "QS_CONFIG_PATH", "QS_CONFIG_NAME", "QS_MANIFEST"):
            self.env.pop(name, None)
        for name in ("RUNTIME", "CONFIG", "CACHE", "STATE", "DATA"):
            target = self.folder / name.lower()
            target.mkdir(mode=0o700)
            self.env[f"XDG_{name}_DIR" if name == "RUNTIME" else f"XDG_{name}_HOME"] = str(target)
        self.env["XDG_RUNTIME_DIR"] = "/proc/self/cwd/runtime"

    # Start only this isolated fixture and stop after the checks, never the desktop shell.
    def run_qml(self, body):
        qml = self.root / "shell.qml"
        qml.write_text('''import QtQuick
import Quickshell
import qs.services
import "logic/CalendarItems.js" as Items
Scope {
    function check(ok, message) {
        if (!ok) { console.error("TEST FAIL", message); Qt.quit(); }
        return ok;
    }
    Timer { interval: 5000; running: true; onTriggered: { console.error("TEST TIMEOUT"); Qt.quit(); } }
    Timer {
        interval: 25; running: true; repeat: true
        onTriggered: {
            if (!Calendar.ready) return;
            stop();
''' + body + '''
        }
    }
}''')
        result = subprocess.run([QS, "--no-color", "-p", str(qml)], env=self.env,
                                cwd=self.folder, capture_output=True, text=True, timeout=10)
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output)
        self.assertIn("TEST PASS", output, output)
        self.assertNotIn("TEST FAIL", output, output)
        self.assertNotIn("TEST TIMEOUT", output, output)
        self.assertEqual([line for line in output.splitlines() if "ERROR" in line], [], output)

    def test_save_keeps_exact_previous_bytes_and_one_backup(self):
        self.run_qml('''
            if (!check(Calendar.add({ title: "New", date: "2026-10-06" }), "first save failed")) return;
            console.log("TEST PASS"); Qt.quit();
''')
        backup = self.path.with_name("berri.ics.bak")
        self.assertEqual(backup.read_bytes(), ORIGINAL.encode())
        previous = self.path.read_bytes()
        self.run_qml('''
            if (!check(Calendar.update(Items.itemKey("berri", "kept"), { title: "Changed" }), "second save failed")) return;
            if (!check(Calendar.calendars.length === 1, "backup was listed as a calendar")) return;
            if (!check(Calendar.importFile(Calendar.defaultPath + ".bak") === "", "backup was imported")) return;
            console.log("TEST PASS"); Qt.quit();
''')
        self.assertEqual(backup.read_bytes(), previous)
        self.assertIn(b"SUMMARY:Changed", self.path.read_bytes())
        self.assertEqual(sorted(path.name for path in self.calendar.iterdir()),
                         ["berri.ics", "berri.ics.bak", "subscriptions"])

    def test_backup_failure_keeps_file_and_shown_items(self):
        self.path.with_name("berri.ics.bak").mkdir()
        self.run_qml('''
            if (!check(!Calendar.add({ title: "Lost", date: "2026-10-06" }), "failed backup allowed a save")) return;
            if (!check(Calendar.itemsOn("2026-10-06").length === 0, "failed edit stayed on screen")) return;
            if (!check(Calendar.lastError.includes("backup"), "backup error was not reported")) return;
            console.log("TEST PASS"); Qt.quit();
''')
        self.assertEqual(self.path.read_bytes(), ORIGINAL.encode())

    def test_first_local_save_creates_no_empty_backup(self):
        self.path.unlink()
        self.run_qml('''
            if (!check(Calendar.add({ title: "First", date: "2026-10-06" }), "new local calendar failed")) return;
            console.log("TEST PASS"); Qt.quit();
''')
        self.assertIn(b"SUMMARY:First", self.path.read_bytes())
        self.assertFalse(self.path.with_name("berri.ics.bak").exists())

    def test_whole_calendar_color_save_keeps_the_previous_file(self):
        work = self.calendar / "work.ics"
        work.write_bytes(ORIGINAL.encode())
        self.run_qml('''
            const id = Calendar.calendars.find(calendar => calendar.kind === "file").id;
            if (!check(Calendar.applyColorToCalendar(id, "green"), "color save failed")) return;
            console.log("TEST PASS"); Qt.quit();
''')
        self.assertEqual(work.with_name("work.ics.bak").read_bytes(), ORIGINAL.encode())
        self.assertNotIn(b"X-BERRI-COLOR:red", work.read_bytes())
