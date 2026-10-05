#!/usr/bin/env bash
set -euo pipefail

# Get the directory this script is in
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHELL_DIR="$SCRIPT_DIR"

# Check if berri-shell is running
if qs list --all 2>/dev/null | grep -q "Config path: ${SHELL_DIR}/shell.qml"; then
    # berri-shell is running, kill it
    qs kill -p "$SHELL_DIR"
    echo "berri-shell: OFF"
else
    # berri-shell is not running, start it
    "$SHELL_DIR/tools/start-berri.sh" -d
    echo "berri-shell: ON"
fi
