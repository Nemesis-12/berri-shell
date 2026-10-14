"""Recent answers of the data scripts: where they are kept, how to read and save them."""
import contextlib
import json
import os
import tempfile
import time
from pathlib import Path


def answer_path(name: str) -> Path:
    """Return the file for a recent answer under the user's cache directory."""
    return Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache") / "berri-shell" / name


def read_recent_answer(path: Path, max_age: float | None = None) -> str | None:
    """Read the recent answer, or return None when missing, too old or not valid JSON."""
    try:
        if max_age is not None and time.time() - path.stat().st_mtime >= max_age:
            return None
        text = path.read_text(encoding="utf-8")
        json.loads(text)
        return text
    except (OSError, ValueError):
        return None


def save_answer(path: Path, text: str) -> None:
    """Save JSON text. The old answer stays until the new one is complete; a failed write must not stop a script."""
    temp = None
    try:
        json.loads(text)
        path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        os.chmod(path.parent, 0o700)
        # Answers are private: the file is owner-only, whatever the creation mask is.
        fd, temp = tempfile.mkstemp(dir=path.parent, prefix=path.name + ".")
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            os.fchmod(f.fileno(), 0o600)
            f.write(text)
        os.replace(temp, path)
        temp = None
    except (OSError, ValueError):
        pass
    finally:
        if temp is not None:
            with contextlib.suppress(OSError):
                os.unlink(temp)
