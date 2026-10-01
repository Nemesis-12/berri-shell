#!/bin/sh
# Stops the running berri instance and starts it again, detached.
# Use after editing files: live reload is off (QS_DISABLE_FILE_WATCHER=1).
# Usage: tools/restart-berri.sh

repo=$(cd "$(dirname "$0")/.." && pwd) || exit 1

# The berri instance is the qs process whose config path is this repo.
# Escape regex characters in the path. Match qs bare or with a folder before it.
safe_repo=$(printf '%s' "$repo" | sed 's/[][\.*^$+?(){}|]/\\&/g')
pattern="(^|/)qs .*-p $safe_repo(/shell\.qml)?( |\$)"
pids=$(pgrep -f "$pattern")
if [ -n "$pids" ]; then
  # shellcheck disable=SC2086
  kill $pids
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    pgrep -f "$pattern" >/dev/null || break
    sleep 0.3
  done
fi

QSG_RENDER_LOOP=basic QS_DISABLE_FILE_WATCHER=1 \
  setsid qs -p "$repo" >/dev/null 2>&1 </dev/null &
