"""Tests for the Lucide icon generator and the static icon-name scan."""
import importlib.util
import signal
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def load_tool(file_name: str):
    spec = importlib.util.spec_from_file_location(file_name.replace("-", "_"), ROOT / "tools" / file_name)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


generator = load_tool("lucide-to-qml.py")
scan = load_tool("check-icon-names.py")

SVG = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="{d}"/></svg>'


class GeneratorTests(unittest.TestCase):
    def setUp(self):
        # A looping tokenizer must fail this test instead of hanging the run.
        signal.signal(signal.SIGALRM, lambda *_: self.fail("generator did not stop"))
        signal.alarm(5)
        self.addCleanup(signal.alarm, 0)

    def test_unsupported_character_fails_fast_with_position_and_input_name(self):
        with tempfile.TemporaryDirectory() as folder:
            (Path(folder) / "broken.svg").write_text(SVG.format(d="M1 1L5 5?"))
            started = time.perf_counter()
            with self.assertRaises(generator.UnsupportedPathError) as caught:
                generator.build_icons_js(Path(folder))
            elapsed = time.perf_counter() - started
        self.assertLess(elapsed, 0.1)
        message = str(caught.exception)
        self.assertIn("'?'", message)
        self.assertIn("position 9", message)
        self.assertIn("broken.svg", message)

    def test_bundled_icons_match_the_committed_icons_file(self):
        text, count = generator.build_icons_js(generator.ICONS_DIR)
        self.assertEqual(text, generator.OUT_FILE.read_text())
        self.assertEqual(count, len(list(generator.ICONS_DIR.glob("*.svg"))))


class IconNameScanTests(unittest.TestCase):
    def scan_source(self, qml: str, icons=("check", "x")) -> list:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            icons_dir = root / "assets" / "icons" / "lucide"
            icons_dir.mkdir(parents=True)
            for name in icons:
                (icons_dir / f"{name}.svg").write_text(SVG.format(d="M1 1L2 2"))
            (root / "View.qml").write_text(qml)
            return scan.find_unknown(root, icons_dir)

    def test_known_names_pass(self):
        qml = 'Item {\n  Icon { name: "check"; size: 12 }\n  Row { icon: "x" }\n}\n'
        self.assertEqual(self.scan_source(qml), [])

    def test_unknown_name_in_icon_block_fails_once(self):
        qml = 'Item {\n  Icon {\n    name: "nope"\n    size: 12\n  }\n}\n'
        self.assertEqual(self.scan_source(qml), ["View.qml:3: unknown icon 'nope'"])

    def test_unknown_name_in_icon_property_and_ternary_fails(self):
        qml = 'Item {\n  Btn { icon: on ? "check" : "nope" }\n  Btn { iconName: "also-nope" }\n}\n'
        self.assertEqual(
            self.scan_source(qml),
            ["View.qml:2: unknown icon 'nope'", "View.qml:3: unknown icon 'also-nope'"],
        )

    def test_name_outside_icon_block_and_comparison_literals_are_ignored(self):
        qml = (
            'Item {\n  Text { name: "label" }\n  function outputIcon(kind) {\n'
            '    return kind === "HDMI" ? "check" : "x";\n  }\n}\n'
        )
        self.assertEqual(self.scan_source(qml), [])

    def test_real_source_uses_only_bundled_icons(self):
        self.assertEqual(scan.find_unknown(ROOT, ROOT / "assets" / "icons" / "lucide"), [])

    def test_calendar_files_draw_no_inline_svg_path(self):
        for path in (ROOT / "tabs" / "calendar").glob("*.qml"):
            self.assertNotIn("PathSvg", path.read_text(), path.name)


if __name__ == "__main__":
    unittest.main()
