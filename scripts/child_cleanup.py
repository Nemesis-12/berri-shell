"""Lets a script take its child programs (git, gh, curl) down with it when it is stopped."""
import contextlib
import os
import signal


def stop_children_with_script() -> None:
    """Put the script and its future children in one process group. SIGTERM to the script then stops the whole group."""
    with contextlib.suppress(OSError):
        os.setpgrp()

    def stop_group(number, frame) -> None:
        # The default action ends the script itself when the group signal reaches it.
        signal.signal(signal.SIGTERM, signal.SIG_DFL)
        os.killpg(os.getpgrp(), signal.SIGTERM)

    signal.signal(signal.SIGTERM, stop_group)
