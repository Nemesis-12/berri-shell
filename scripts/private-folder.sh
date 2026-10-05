#!/bin/sh
# Makes each folder owner-only: folder mode 700, files inside mode 600.
# Missing parent folders are created with mode 700 too.
# Usage: private-folder.sh FOLDER...
set -eu

[ $# -ge 1 ] || { echo "Usage: private-folder.sh FOLDER..." >&2; exit 2; }
umask 077
for folder in "$@"; do
  mkdir -p -- "$folder"
  find "$folder" -type d -exec chmod 700 {} +
  find "$folder" -type f -exec chmod 600 {} +
done
