#!/bin/sh
# Stops the running berri instance and starts it again, detached.
# Use after adding or moving QML files; live reload misses those changes.
# berri starts in its own systemd user scope. setsid leaves the session but not
# the systemd scope, so a berri started from an agent shell would stop when that
# scope stops. Without a working systemd user manager, a plain setsid start is used.
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
  if pgrep -f "$pattern" >/dev/null; then
    echo "restart-berri: old instance still running, not starting a new one" >&2
    exit 1
  fi
fi

# The probe shows whether a scope can be made. The real start runs in the
# background, so its exit code is not visible; a failed start must not run twice.
if command -v systemd-run >/dev/null 2>&1 \
  && systemd-run --user --scope --collect --quiet -- true >/dev/null 2>&1; then
  setsid systemd-run --user --scope --collect --quiet \
    --unit="berri-shell-$(date +%s)" --slice=app.slice \
    -- "$repo/tools/start-berri.sh" >/dev/null 2>&1 </dev/null &
else
  setsid "$repo/tools/start-berri.sh" >/dev/null 2>&1 </dev/null &
fi
