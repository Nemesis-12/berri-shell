#!/bin/sh
# Starts berri for this repo folder. Every start method calls this script,
# so the allocator setting lives here only. Extra flags go to qs.
# Usage: tools/start-berri.sh [qs flags]

repo=$(cd "$(dirname "$0")/.." && pwd) || exit 1

export MALLOC_CONF="background_thread:true,dirty_decay_ms:100,muzzy_decay_ms:100"
exec qs -p "$repo" "$@"
