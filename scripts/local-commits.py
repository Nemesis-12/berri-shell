#!/usr/bin/env python3
"""Print the 5 newest commits of the user, from local git folders and GitHub.

Local folders: every git repo under $BERRI_PROGRAMMING_ROOT (default
~/Programming, depth 4 at most). Only the user's own commits of the last 90 days are read (author matches
the global git email or name, or the logged-in GitHub account). Only hash, subject, repo
folder name and time are kept. GitHub commits come from the cache of
github-stats.py. The two lists merge by hash, newest first.

The result is cached in $XDG_CACHE_HOME/berri-shell/commits.json for 10 minutes.
Output: [{"sha": 7 chars, "message": str, "repo": str, "date": iso8601}, ...]
With --with-version: {"version": cache file time in milliseconds, "commits": output array}
"""
import json
import os
import subprocess
import sys
import time
from pathlib import Path

from recent_answers import answer_path, read_recent_answer, save_answer

ROOT = Path(os.path.expandvars(os.environ.get("BERRI_PROGRAMMING_ROOT") or str(Path.home() / "Programming"))).expanduser()
MAX_DEPTH = 4
SKIP = {"node_modules", ".cache", "target", "build", "dist", ".venv", "venv", "__pycache__", ".next", "vendor"}
CACHE_PATH = answer_path("commits.json")
GITHUB_PATH = answer_path("github.json")
CACHE_FRESH_S = 10 * 60
SEP = "\x1f"


def git(repo: Path, *args: str) -> str:
    out = subprocess.run(["git", "-C", str(repo), *args], capture_output=True, text=True, timeout=15)
    return out.stdout.strip() if out.returncode == 0 else ""


def find_repos(folder: Path, depth: int = 0):
    """Yield folders that hold a .git entry; repos nested in a repo are found too."""
    try:
        entries = list(os.scandir(folder))
    except OSError:
        return
    if any(e.name == ".git" for e in entries):
        yield folder
    if depth >= MAX_DEPTH:
        return
    for e in entries:
        if e.is_dir(follow_symlinks=False) and e.name not in SKIP and e.name != ".git":
            yield from find_repos(Path(e.path), depth + 1)


def author_patterns() -> list[str]:
    """Names and emails that mark a commit as the user's: git config, then the GitHub account."""
    found = []
    for key in ("user.email", "user.name"):
        found.append(git(Path.home(), "config", "--global", key))
    try:
        out = subprocess.run(["gh", "api", "user", "--jq", "[.login,.id,.name]|@tsv"],
                             capture_output=True, text=True, timeout=15, check=True)
        login, uid, name = (out.stdout.strip().split("\t") + ["", "", ""])[:3]
        found += [f"{uid}+{login}@users.noreply.github.com" if uid and login else "", login, name]
    except Exception:
        pass
    return sorted({a for a in found if a})


def local_commits() -> list[dict]:
    authors = author_patterns()
    if not authors:
        return []
    found = []
    for repo in find_repos(ROOT):
        args = ["log", "--all", "--since=90.days", "-n", "20", "--regexp-ignore-case",
                f"--format=%H{SEP}%s{SEP}%aI"]
        for a in authors:
            args.append(f"--author={a}")
        for line in git(repo, *args).splitlines():
            parts = line.split(SEP)
            if len(parts) == 3:
                found.append({"sha": parts[0], "message": parts[1], "repo": repo.name, "date": parts[2]})
    return found


def github_commits() -> list[dict]:
    try:
        return json.loads(read_recent_answer(GITHUB_PATH) or "{}").get("commits", [])
    except (OSError, ValueError):
        return []


def merged() -> list[dict]:
    from datetime import datetime
    by_hash: dict[str, dict] = {}
    # Local first: its full hash and folder name win over GitHub's short hash.
    for c in local_commits() + github_commits():
        by_hash.setdefault(c["sha"][:7], {**c, "sha": c["sha"][:7]})
    def when(c: dict) -> float:
        try:
            return datetime.fromisoformat(c["date"].replace("Z", "+00:00")).timestamp()
        except ValueError:
            return 0.0
    return sorted(by_hash.values(), key=when, reverse=True)[:5]


def main() -> None:
    cached = read_recent_answer(CACHE_PATH, CACHE_FRESH_S) if "--force" not in sys.argv else None
    text = cached
    if text is None:
        text = json.dumps(merged())
        save_answer(CACHE_PATH, text)
    if "--with-version" in sys.argv:
        try:
            version = CACHE_PATH.stat().st_mtime_ns // 1_000_000
        except OSError:
            version = int(time.time() * 1000)
        print(json.dumps({"version": version, "commits": json.loads(text)}))
    else:
        print(text)


if __name__ == "__main__":
    main()
