#!/bin/sh
# Keeps the last stored text of a saved file in FILE.bak (mode 600) before the file is replaced.
# A missing file needs no backup. Any other failure gives a non-zero exit code.
# Usage: backup-saved.sh FILE
set -eu

[ $# -eq 1 ] || { echo "Usage: backup-saved.sh FILE" >&2; exit 2; }
file=$1
[ -e "$file" ] || [ -L "$file" ] || exit 0
umask 077
tmp="$file.bak.tmp"
trap 'rm -f -- "$tmp"' EXIT
cp -- "$file" "$tmp"
chmod 600 -- "$tmp"
mv -f -- "$tmp" "$file.bak"
