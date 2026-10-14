#!/bin/sh
# Keeps the last stored text of a saved file in TARGET (mode 600) before the file is replaced.
# TARGET is FILE.bak when not given. A missing file needs no backup.
# Any other failure gives a non-zero exit code.
# Usage: backup-saved.sh FILE [TARGET]
set -eu

[ $# -ge 1 ] && [ $# -le 2 ] || { echo "Usage: backup-saved.sh FILE [TARGET]" >&2; exit 2; }
file=$1
target=${2:-$file.bak}
[ -e "$file" ] || [ -L "$file" ] || exit 0
umask 077
tmp="$target.tmp"
trap 'rm -f -- "$tmp"' EXIT
cp -- "$file" "$tmp"
chmod 600 -- "$tmp"
mv -f -- "$tmp" "$target"
