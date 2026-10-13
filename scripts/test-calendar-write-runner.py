"""Check that the pre-push test runner explains missing native test tools."""
from pathlib import Path
import subprocess
import sys
import unittest


class CalendarWriteRunnerTests(unittest.TestCase):
    # Run the hook's unittest command with Quickshell unavailable.
    def test_unittest_reports_missing_quickshell_once(self):
        result = subprocess.run(
            [sys.executable, "-c", '''
import runpy
import sys
from unittest.mock import patch
sys.argv = ["unittest", "test-calendar-writes.py"]
with patch("shutil.which", return_value=None):
    runpy.run_module("unittest", run_name="__main__")
'''], cwd=Path(__file__).resolve().parent, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("OK (skipped=7)", result.stderr)
        self.assertEqual(result.stderr.count(
            "Calendar write tests skipped: Quickshell is required for isolated native file tests"), 1,
            result.stderr)
