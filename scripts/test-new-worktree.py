"""The worktree helper starts from the commit the caller names, not from HEAD."""
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

HELPER = Path(__file__).resolve().parents[1] / "tools/new-worktree.sh"
IDENTITY = ["-c", "user.name=t", "-c", "user.email=t@example.test"]


def clean_env():
    """The environment without GIT_* variables; a git hook sets them, and they point git at the wrong repository."""
    return {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}


def git(repo, *args):
    return subprocess.run(["git", "-C", str(repo), *args], capture_output=True, text=True, check=True,
                          env=clean_env()).stdout.strip()


class WorktreeBaseTests(unittest.TestCase):
    def setUp(self):
        self.folder = Path(tempfile.mkdtemp(prefix="berri-wt-test-"))
        self.addCleanup(shutil.rmtree, self.folder, True)
        self.repo = self.folder / "main"
        (self.repo / "tools").mkdir(parents=True)
        shutil.copy(HELPER, self.repo / "tools/new-worktree.sh")
        (self.repo / ".gitignore").write_text("AGENTS.md\n", encoding="utf-8")
        (self.repo / "AGENTS.md").write_text("rules\n", encoding="utf-8")
        git(self.repo, "init", "-q", "-b", "main")
        git(self.repo, "add", ".")
        git(self.repo, *IDENTITY, "commit", "-q", "-m", "first")
        self.first = git(self.repo, "rev-parse", "HEAD")
        git(self.repo, "tag", "first-tag")
        git(self.repo, "checkout", "-q", "-b", "current")
        git(self.repo, *IDENTITY, "commit", "-q", "--allow-empty", "-m", "second")
        self.second = git(self.repo, "rev-parse", "HEAD")

    def run_helper(self, *args):
        return subprocess.run(["sh", "tools/new-worktree.sh", *args], cwd=self.repo,
                              capture_output=True, text=True, env=clean_env())

    def test_local_branch_tag_and_hash_bases_are_used(self):
        for index, base in enumerate(("main", "first-tag", self.first)):
            with self.subTest(base=base):
                target = self.folder / f"wt{index}"
                result = self.run_helper(f"topic{index}", str(target), base)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(git(target, "rev-parse", "HEAD"), self.first)

    def test_unknown_base_stops_instead_of_using_head(self):
        target = self.folder / "wt"
        result = self.run_helper("topic", str(target), "no-such-base")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("no-such-base", result.stderr)
        self.assertFalse(target.exists())

    def test_base_that_starts_with_a_dash_is_not_read_as_an_option(self):
        target = self.folder / "wt"
        result = self.run_helper("topic", str(target), "--all")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("is not a branch, tag or commit", result.stderr)
        self.assertFalse(target.exists())

    def test_missing_default_base_stops_instead_of_using_head(self):
        target = self.folder / "wt"
        result = self.run_helper("topic", str(target))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("origin/main", result.stderr)
        self.assertFalse(target.exists())


if __name__ == "__main__":
    unittest.main()
