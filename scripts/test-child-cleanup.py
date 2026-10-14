"""A stopped script takes its child programs down with it."""
import os
import signal
import subprocess
import sys
import tempfile
import textwrap
import time
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent


def alive(pid: int) -> bool:
    try:
        return Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()[0] != "Z"
    except OSError:
        return False


class ChildCleanupTests(unittest.TestCase):
    def test_sigterm_to_the_script_stops_its_running_child(self):
        with tempfile.TemporaryDirectory() as folder:
            script = Path(folder) / "script.py"
            script.write_text(textwrap.dedent(f"""
                import subprocess, sys, time
                sys.path.insert(0, {str(SCRIPTS)!r})
                from child_cleanup import stop_children_with_script
                stop_children_with_script()
                child = subprocess.Popen(["sleep", "60"])
                print(child.pid, flush=True)
                subprocess.run(["sleep", "60"])
            """), encoding="utf-8")
            proc = subprocess.Popen([sys.executable, "-I", str(script)], stdout=subprocess.PIPE, text=True)
            child = int(proc.stdout.readline())
            self.addCleanup(lambda: alive(child) and os.kill(child, signal.SIGKILL))
            time.sleep(0.3)
            proc.send_signal(signal.SIGTERM)
            self.assertEqual(proc.wait(timeout=5), -signal.SIGTERM)
            deadline = time.monotonic() + 5
            while alive(child) and time.monotonic() < deadline:
                time.sleep(0.05)
            self.assertFalse(alive(child))


if __name__ == "__main__":
    unittest.main()
