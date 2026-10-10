"""The start helper disables THP across exec and still starts on failure."""
import subprocess
import sys
import unittest
from pathlib import Path

HELPER = Path(__file__).resolve().parents[1] / "tools/start-nothp.py"


class StartTests(unittest.TestCase):
    def test_exec_inherits_thp_disable_and_arguments(self):
        result = subprocess.run(
            [sys.executable, str(HELPER), sys.executable, "-c",
             "import ctypes,sys; print(ctypes.CDLL(None).prctl(42,0,0,0,0),sys.argv[1])",
             "argument with spaces"], capture_output=True, text=True, check=True)
        self.assertEqual(result.stdout.strip(), "1 argument with spaces")

    def test_failed_prctl_still_executes_command(self):
        code = (
            "import ctypes,runpy,sys; from unittest.mock import patch; "
            "libc=ctypes.CDLL(None); libc.prctl=lambda *args: -1; "
            "sys.argv=sys.argv[1:]; "
            "p=patch('ctypes.CDLL',return_value=libc); p.start(); "
            "runpy.run_path(sys.argv[0],run_name='__main__')"
        )
        result = subprocess.run(
            [sys.executable, "-c", code, str(HELPER), sys.executable, "-c",
             "print('started despite failure')"], capture_output=True, text=True, check=True)
        self.assertEqual(result.stdout.strip(), "started despite failure")
        self.assertIn("starting anyway", result.stderr)
