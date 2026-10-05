#!/bin/sh
# Copies a picture into the berri wallpaper library and prints the new path.
# The library folder is owner-only: folder mode 700, files mode 600.
# A name that exists already gets a number: name-1.ext, name-2.ext.
# Usage: add-wallpaper.sh SOURCE LIBRARY_FOLDER
set -e

src=$1 library=$2
umask 077
sh "$(dirname "$0")/private-folder.sh" "$library"
base=$(basename -- "$src")
name=${base%.*}
ext=${base##*.}
dest="$library/$base"
n=1
while [ -e "$dest" ]; do dest="$library/${name}-${n}.${ext}"; n=$((n + 1)); done
cp -- "$src" "$dest"
printf '%s' "$dest"
