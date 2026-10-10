#!/usr/bin/env python3
"""Disable THP for the command's process tree, then replace this process."""
import ctypes
import os
import sys


# Apply the process setting only; unsupported kernels must still start the command.
def main():
    try:
        libc = ctypes.CDLL(None, use_errno=True)
        libc.prctl.argtypes = [ctypes.c_int] + [ctypes.c_ulong] * 4
        libc.prctl.restype = ctypes.c_int
        if libc.prctl(41, 1, 0, 0, 0) != 0:  # PR_SET_THP_DISABLE
            raise OSError(ctypes.get_errno(), os.strerror(ctypes.get_errno()))
    except (OSError, AttributeError) as error:
        print(f"start-berri: cannot disable THP: {error}; starting anyway", file=sys.stderr)
    os.execvp(sys.argv[1], sys.argv[1:])


if __name__ == "__main__":
    main()
