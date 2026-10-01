"""The Code service can read a version without changing the normal script output."""
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("local-commits.py")


class LocalCommitsOutputTests(unittest.TestCase):
    def test_cached_commits_have_a_stable_version(self):
        with tempfile.TemporaryDirectory() as folder:
            cache = Path(folder) / "berri-shell" / "commits.json"
            cache.parent.mkdir()
            commits = [{"sha": "abc1234", "message": "Fix", "repo": "shell", "date": "2026-09-30T12:00:00Z"}]
            cache.write_text(json.dumps(commits), encoding="utf-8")
            env = {**os.environ, "XDG_CACHE_HOME": folder}

            def run(*args):
                result = subprocess.run([sys.executable, str(SCRIPT), *args],
                                        capture_output=True, text=True, check=True, env=env)
                return json.loads(result.stdout)

            self.assertEqual(run(), commits)
            first = run("--with-version")
            self.assertEqual(first, {"version": cache.stat().st_mtime_ns // 1_000_000, "commits": commits})
            self.assertEqual(run("--with-version"), first)

    def test_fresh_commits_keep_the_same_version_on_the_next_run(self):
        with tempfile.TemporaryDirectory() as folder:
            cache = Path(folder) / "berri-shell" / "commits.json"
            empty_root = Path(folder) / "repos"
            empty_root.mkdir()
            for name in ("git", "gh"):
                command = Path(folder) / name
                command.write_text("#!/bin/sh\nexit 1\n", encoding="utf-8")
                command.chmod(0o755)
            env = {**os.environ, "XDG_CACHE_HOME": folder,
                   "BERRI_PROGRAMMING_ROOT": str(empty_root), "PATH": folder}

            def run():
                result = subprocess.run([sys.executable, str(SCRIPT), "--with-version"],
                                        capture_output=True, text=True, check=True, env=env)
                return json.loads(result.stdout)

            first = run()
            self.assertEqual(first, {"version": cache.stat().st_mtime_ns // 1_000_000, "commits": []})
            self.assertEqual(run(), first)


if __name__ == "__main__":
    unittest.main()
