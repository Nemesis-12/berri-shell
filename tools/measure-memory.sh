#!/bin/sh
# Measure only the running berri for this checkout. See tools/MEMORY.md.
repo=$(cd "$(dirname "$0")/.." && pwd) || exit 1
exec python3 "$repo/tools/measure-memory.py" "$@"
