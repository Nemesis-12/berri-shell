"""Issue 70 checks use offscreen fixtures and files under scratchpad only."""
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import unittest
import zlib

REPO = Path(__file__).resolve().parent.parent
QS = shutil.which("qs")


# Write a real PNG without adding an image package to the tests.
def write_png(path, color=(90, 140, 190)):
    def chunk(kind, data):
        return struct.pack("!I", len(data)) + kind + data + struct.pack("!I", zlib.crc32(kind + data))

    path.write_bytes(b"\x89PNG\r\n\x1a\n"
                     + chunk(b"IHDR", struct.pack("!2I5B", 64, 36, 8, 2, 0, 0, 0))
                     + chunk(b"IDAT", zlib.compress((b"\0" + bytes(color) * 64) * 36))
                     + chunk(b"IEND", b""))


@unittest.skipUnless(QS, "Quickshell is required for isolated QML tests")
class PickerTests(unittest.TestCase):
    # Copy the real components into an isolated config with a fixed test theme.
    def setUp(self):
        scratch = REPO / "scratchpad"
        scratch.mkdir(exist_ok=True)
        self.temporary = tempfile.TemporaryDirectory(prefix="picker-70-", dir=scratch)
        self.addCleanup(self.temporary.cleanup)
        self.folder = Path(self.temporary.name)
        self.root = self.folder / "fixture"
        for name in ("picker", "common", "logic", "scripts", "shaders"):
            shutil.copytree(REPO / name, self.root / name,
                            ignore=shutil.ignore_patterns("__pycache__"))
        for path in ("tabs/home/Sticker.qml", "services/Wallpapers.qml", "services/SavedState.qml", "services/FolderRoots.qml"):
            target = self.root / path
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy(REPO / path, target)
        shutil.copy(REPO / "tests/fixtures/picker/Theme.qml", self.root / "services/Theme.qml")
        self.home = self.folder / "home"
        self.config = self.home / ".config/berri-shell"
        self.state = self.home / ".local/state/berri-shell"
        self.config.mkdir(parents=True)
        self.state.mkdir(parents=True)
        self.env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QPA_PLATFORMTHEME="",
                        QSG_RHI_BACKEND="software", HOME=str(self.home))
        for name in ("LD_LIBRARY_PATH", "DISPLAY", "WAYLAND_DISPLAY", "QS_CONFIG_PATH",
                     "QS_CONFIG_NAME", "QS_MANIFEST"):
            self.env.pop(name, None)
        for name in ("RUNTIME", "CONFIG", "CACHE", "STATE"):
            target = self.folder / name.lower()
            target.mkdir(mode=0o700)
            self.env[f"XDG_{name}_DIR" if name == "RUNTIME" else f"XDG_{name}_HOME"] = str(target)
        # Keep Unix socket names short while all runtime files stay in this worktree.
        self.env["XDG_RUNTIME_DIR"] = "/proc/self/cwd/runtime"

    # Run only the supplied QML fixture, with no desktop shell or live input.
    def run_qml(self, body):
        qml = self.root / "shell.qml"
        qml.write_text('''import QtQuick
import Quickshell
import Quickshell.Io
import qs.picker
import qs.tabs.home
import qs.services
Scope {
    function check(ok, message) {
        if (!ok) { console.error("TEST FAIL", message); Qt.quit(); }
        return ok;
    }
    function find(item, type) {
        if (item.toString().indexOf(type + "_") !== -1) return item;
        var children = item.children || [];
        for (var i = 0; i < children.length; i++) {
            var found = find(children[i], type);
            if (found) return found;
        }
        var resources = item.resources || [];
        for (var j = 0; j < resources.length; j++) {
            var resource = find(resources[j], type);
            if (resource) return resource;
        }
        return null;
    }
    function imageCount(item) {
        var count = item.toString().indexOf("QQuickImage") !== -1 && item.source ? 1 : 0;
        var children = item.children || [];
        for (var i = 0; i < children.length; i++) count += imageCount(children[i]);
        return count;
    }
    function findImage(item) {
        if (item.source !== undefined && item.status !== undefined && item.source.toString() !== "") return item;
        var children = item.children || [];
        for (var i = 0; i < children.length; i++) {
            var found = findImage(children[i]);
            if (found) return found;
        }
        return null;
    }
    Timer { interval: 5000; running: true; onTriggered: { console.error("TEST TIMEOUT"); Qt.quit(); } }
''' + body + "\n}")
        result = subprocess.run([QS, "--no-color", "-p", str(qml)], env=self.env,
                                cwd=self.folder, capture_output=True, text=True, timeout=10)
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output)
        self.assertIn("TEST PASS", output, output)
        self.assertNotIn("TEST FAIL", output, output)
        self.assertNotIn("TEST TIMEOUT", output, output)
        errors = [line for line in output.splitlines() if "ERROR" in line]
        self.assertEqual(errors, [], output)
        return output

    # Replace only the Wayland window boundary for the offscreen transition check.
    def use_offscreen_wallpaper_window(self):
        path = self.root / "picker/WallpaperLayer.qml"
        source = path.read_text().replace("import Quickshell.Wayland", "import QtQuick.Window as QtWindow")
        source = source.replace("PanelWindow {", "QtWindow.Window {")
        source = source.replace("screen: modelData", "width: 320; height: 180; visible: true")
        source = "\n".join(line for line in source.splitlines() if not any(
            setting in line for setting in ("exclusionMode:", "WlrLayershell.",
                                           "anchors { top: true", "mask: Region")))
        path.write_text(source)

    def test_closed_picker_creates_no_images_and_open_picker_loads_cards(self):
        image = self.folder / "wallpaper.png"
        write_png(image)
        (self.state / "wallpapers.json").write_text(json.dumps({"library": [str(image)] * 10}))
        self.run_qml('''
    FloatingWindow {
        implicitWidth: 1000; implicitHeight: 500
        ThemeNotch { id: notch; anchors.centerIn: parent; pickerTab: "walls" }
    }
    property int stage: 0
    Timer {
        interval: 100; running: true; repeat: true
        onTriggered: {
            if (!Wallpapers.loaded) return;
            if (stage === 0) {
                if (!check(imageCount(notch) === 0, "closed picker loaded card images")) return;
                notch.openPicker(); stage = 1;
            } else if (stage === 1 && imageCount(notch) === 10) {
                notch.closeAtOnce(); stage = 2;
            } else if (stage === 2) {
                if (!check(imageCount(notch) === 0, "closed picker kept card images")) return;
                console.log("TEST PASS"); Qt.quit();
            }
        }
    }
''')

    def test_unsupported_wallpaper_finishes_once_and_reopens_picker(self):
        invalid = self.folder / "choice.txt"
        invalid.write_text("unsupported")
        self.env["PICKER_CHOICE"] = str(invalid)
        self.run_qml('''
    FloatingWindow {
        implicitWidth: 1000; implicitHeight: 500
        ThemeNotch { id: notch; anchors.centerIn: parent; pickerTab: "walls" }
    }
    property int completions: 0
    property string addedPath: "unset"
    Timer {
        interval: 100; running: true
        onTriggered: {
            var carousel = find(notch, "WallpapersCarousel");
            var chooser = find(carousel, "ImagePicker");
            carousel.addDone.connect(function(path) { completions++; addedPath = path; });
            notch.openPicker(); notch.closeAtOnce();
            chooser.chosen(Quickshell.env("PICKER_CHOICE"));
            chooser.finished();
            verify.restart();
        }
    }
    Timer {
        id: verify; interval: 200
        onTriggered: {
            if (!check(completions === 1 && addedPath === "", "failed add did not finish exactly once")) return;
            if (!check(Wallpapers.library.length === 0 && notch.pickerOpen, "failed add did not reopen an empty picker")) return;
            console.log("TEST PASS"); Qt.quit();
        }
    }
''')

    def test_shared_removals_keep_the_other_picker_body_focused(self):
        library = self.home / ".local/share/berri-shell/wallpapers"
        library.mkdir(parents=True, exist_ok=True)
        paths = []
        for name, color in (("one.png", (190, 80, 30)), ("two.png", (10, 20, 30)),
                            ("three.png", (30, 160, 60))):
            path = library / name
            write_png(path, color)
            paths.append(str(path))
        (self.state / "wallpapers.json").write_text(json.dumps({
            "library": paths,
            "assignments": {"test": {"second": paths[2]}}
        }))
        self.env["PICKER_REMOVE_FIRST"] = paths[0]
        self.env["PICKER_REMOVE_SECOND"] = paths[1]
        self.run_qml('''
    FloatingWindow {
        implicitWidth: 1800; implicitHeight: 500
        ThemeNotch { id: first; x: 0; pickerTab: "walls"; screenName: "first" }
        ThemeNotch { id: second; x: 900; pickerTab: "walls"; screenName: "second" }
    }
    property int stage: 0
    Timer {
        interval: 20; running: true; repeat: true
        onTriggered: {
            if (!Wallpapers.loaded) return;
            if (stage === 0) {
                first.openPicker(); second.openPicker();
                var carousel = find(second, "WallpapersCarousel");
                if (!check(carousel.focusIndex === 2, "second picker did not focus its assigned wallpaper")) return;
                Wallpapers.remove(Quickshell.env("PICKER_REMOVE_FIRST"));
                Wallpapers.remove(Quickshell.env("PICKER_REMOVE_SECOND"));
                stage = 1;
            } else if (stage === 1 && Wallpapers.library.length === 1) {
                var carousel = find(second, "WallpapersCarousel");
                if (!check(carousel.focusIndex < carousel.count,
                           "shared library changes left the second picker focused outside its cards")) return;
                if (!check(carousel.focusIsAdd || carousel.focusedPath !== "",
                           "second picker has no wallpaper or Add card focused")) return;
                console.log("TEST PASS"); Qt.quit();
            }
        }
    }
''')

    def test_wallpaper_path_with_space_and_hash_loads_in_picker_and_background(self):
        self.use_offscreen_wallpaper_window()
        library = self.home / ".local/share/berri-shell/wallpapers"
        library.mkdir(parents=True, exist_ok=True)
        image = library / "wallpaper space # one.png"
        write_png(image, (40, 120, 210))
        (self.state / "wallpapers.json").write_text(json.dumps({"library": [str(image)]}))
        self.env["PICKER_SPECIAL_PATH"] = str(image)
        self.run_qml('''
    WallpaperLayer { id: wallpapers }
    FloatingWindow {
        implicitWidth: 1000; implicitHeight: 500
        ThemeNotch { id: notch; anchors.centerIn: parent; pickerTab: "walls" }
    }
    property bool started: false
    Timer {
        interval: 20; running: true; repeat: true
        onTriggered: {
            if (!Wallpapers.loaded || wallpapers.instances.length === 0) return;
            if (!started) {
                notch.openPicker();
                wallpapers.instances[0].show(Quickshell.env("PICKER_SPECIAL_PATH"));
                started = true;
            }
            var card = findImage(notch);
            var layer = wallpapers.instances[0];
            if (card && card.status === Image.Ready && layer.currentPath === Quickshell.env("PICKER_SPECIAL_PATH")) {
                if (!check(card.source.toString().indexOf("wallpaper space") !== -1
                           && card.source.toString().indexOf("%23") !== -1,
                           "picker image URL lost the space or did not encode #")) return;
                if (!check(layer.screenImage.status === Image.Ready
                           && layer.screenImage.source.toString().indexOf("%23") !== -1,
                           "desktop image URL did not load the encoded path")) return;
                console.log("TEST PASS"); Qt.quit();
            }
        }
    }
''')

    def test_wallpaper_body_exposes_selection_and_key_commands_without_its_carousel(self):
        library = self.home / ".local/share/berri-shell/wallpapers"
        library.mkdir(parents=True, exist_ok=True)
        paths = []
        for name in ("first.png", "second.png"):
            image = library / name
            write_png(image)
            paths.append(str(image))
        (self.state / "wallpapers.json").write_text(json.dumps({
            "library": paths,
            "assignments": {"test": {"test": paths[0]}}
        }))
        self.env["PICKER_EXPECTED_FIRST"] = paths[0]
        self.env["PICKER_EXPECTED_SECOND"] = paths[1]
        self.run_qml('''
    FloatingWindow {
        implicitWidth: 1000; implicitHeight: 400
        PickerWallpapers { id: body; anchors.fill: parent; screenName: "test"; shown: true }
    }
    Timer {
        interval: 20; running: true; repeat: true
        onTriggered: {
            if (!Wallpapers.loaded) return;
            if (!check(body.carousel === undefined,
                       "wallpaper body exposes its concrete carousel")) return;
            body.focusToCurrent();
            if (!check(body.focusedPath === Quickshell.env("PICKER_EXPECTED_FIRST"),
                       "wallpaper body did not expose the focused path")) return;
            if (!check(body.handleKey({ key: Qt.Key_Right, accepted: false })
                       && body.focusedPath === Quickshell.env("PICKER_EXPECTED_SECOND"),
                       "wallpaper body did not own keyboard focus movement")) return;
            console.log("TEST PASS"); Qt.quit();
        }
    }
''')

    def test_sticker_watcher_detects_changes_without_loading_bytes(self):
        write_png(self.config / "sticker.png")
        replacement = self.folder / "replacement.png"
        write_png(replacement, (190, 80, 30))
        self.env["PICKER_CHOICE"] = str(replacement)
        self.run_qml('''
    Sticker { id: sticker; visible: false }
    property int changes: 0
    Process {
        id: replace
        command: ["cp", Quickshell.env("PICKER_CHOICE"), sticker.configDirPath + "/sticker.png"]
    }
    Timer {
        interval: 100; running: true
        onTriggered: {
            var watcher = find(sticker, "FileView");
            if (!check(watcher && !watcher.loaded, "watcher loaded image bytes")) return;
            watcher.fileChanged.connect(function() { changes++; });
            replace.running = true; verify.restart();
        }
    }
    Timer {
        id: verify; interval: 200
        onTriggered: {
            var watcher = find(sticker, "FileView");
            if (!check(!watcher.loaded && changes > 0, "watcher did not detect the replacement without reading bytes")) return;
            console.log("TEST PASS"); Qt.quit();
        }
    }
''')

    def test_failed_sticker_choices_keep_old_file_and_png_replaces_it(self):
        old = self.config / "sticker.jpg"
        write_png(old)
        old_bytes = old.read_bytes()
        dotted_folder = self.folder / "folder.png"
        dotted_folder.mkdir()
        invalid_in_folder = dotted_folder / "choice"
        invalid_plain = self.folder / "choice"
        invalid_in_folder.write_text("invalid")
        invalid_plain.write_text("invalid")
        valid = self.folder / "replacement.PNG"
        write_png(valid, (190, 80, 30))
        for choice in (invalid_in_folder, invalid_plain, self.folder / "missing.png", valid):
            with self.subTest(choice=choice.name):
                self.env["PICKER_CHOICE"] = str(choice)
                self.env["PICKER_EXPECTED"] = str(self.config / "sticker.png" if choice == valid else old)
                self.run_qml('''
    Sticker { id: sticker; visible: false }
    Timer {
        interval: 100; running: true
        onTriggered: {
            find(sticker, "ImagePicker").chosen(Quickshell.env("PICKER_CHOICE"));
            verify.restart();
        }
    }
    Timer {
        id: verify; interval: 200
        onTriggered: {
            if (!check(sticker.stickerPath === Quickshell.env("PICKER_EXPECTED"),
                       "sticker view does not show the saved choice")) return;
            console.log("TEST PASS"); Qt.quit();
        }
    }
''')
                if choice == valid:
                    self.assertEqual((self.config / "sticker.png").read_bytes(), valid.read_bytes())
                    self.assertEqual(sorted(p.name for p in self.config.glob("sticker.*")), ["sticker.png"])
                else:
                    self.assertTrue(old.exists(), "failed choice deleted the old sticker")
                    self.assertEqual(old.read_bytes(), old_bytes)
                    self.assertEqual(sorted(p.name for p in self.config.glob("sticker.*")), ["sticker.jpg"])
                self.assertEqual(list(self.config.glob(".sticker-copy.*")), [])

    def test_second_wallpaper_choice_ends_idle_with_the_second_image(self):
        self.use_offscreen_wallpaper_window()
        for name, color in (("first.png", (190, 80, 30)), ("second.png", (10, 20, 30))):
            write_png(self.folder / name, color)
        self.env["PICKER_FIRST"] = str(self.folder / "first.png")
        self.env["PICKER_SECOND"] = str(self.folder / "second.png")
        self.run_qml('''
    WallpaperLayer { id: wallpapers }
    property int stage: 0
    Timer {
        interval: 20; running: true; repeat: true
        onTriggered: {
            if (!Wallpapers.loaded || wallpapers.instances.length === 0) return;
            var layer = wallpapers.instances[0];
            var items = layer.contentItem.children;
            var effect = null;
            for (var i = 0; i < items.length; i++) {
                if (items[i].modeIndex !== undefined) effect = items[i];
            }
            if (stage === 0) {
                Theme.transitioning = true;
                Wallpapers.assign(Quickshell.env("PICKER_FIRST"), [layer.modelData.name]);
                Theme.transitioning = false;
                Theme.wallpaperTransition("A", 1000); stage = 1;
            } else if (stage === 1 && effect.visible && effect.progress > 0) {
                Wallpapers.assign(Quickshell.env("PICKER_SECOND"), [layer.modelData.name]);
                stage = 2;
            } else if (stage === 2 && layer.currentPath === Quickshell.env("PICKER_SECOND")
                       && layer.screenImage.opacity === 1 && layer.hiddenImage.opacity === 0) {
                if (!check(!effect.visible && layer.pendingWallpaperChoice === null,
                           "transition did not end idle")) return;
                if (!check(layer.screenImage.source.toString().endsWith("/second.png")
                           && layer.hiddenImage.source.toString() === "",
                           "second image did not replace the first")) return;
                console.log("TEST PASS"); Qt.quit();
            }
        }
    }
''')
