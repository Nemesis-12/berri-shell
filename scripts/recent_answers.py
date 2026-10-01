"""Recent answers of the data scripts: where they are kept, how to read and save them."""
import os
import time
from pathlib import Path


def answer_path(name: str) -> Path:
    """Return the file for a recent answer under the user's cache directory."""
    return Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache") / "berri-shell" / name


def read_recent_answer(path: Path, max_age: float | None = None) -> str | None:
    """Read the recent answer, or return None when missing or too old."""
    try:
        if max_age is not None and time.time() - path.stat().st_mtime >= max_age:
            return None
        return path.read_text(encoding="utf-8")
    except OSError:
        return None


def save_answer(path: Path, text: str) -> None:
    """Save text; a failed cache write must not stop a script."""
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
    except OSError:
        pass
