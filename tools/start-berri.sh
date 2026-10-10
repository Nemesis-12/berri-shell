#!/bin/sh
# Starts berri for this repo folder. Every start method calls this script,
# so the allocator and process THP settings live here only. Extra flags go to qs.
# Usage: tools/start-berri.sh [qs flags]

repo=$(cd "$(dirname "$0")/.." && pwd) || exit 1

export MALLOC_CONF="background_thread:true,dirty_decay_ms:100,muzzy_decay_ms:100"
if command -v python3 >/dev/null 2>&1; then
  exec python3 "$repo/tools/start-nothp.py" qs -p "$repo" "$@"
fi
echo "start-berri: python3 missing; starting without disabling THP" >&2
exec qs -p "$repo" "$@"
