#!/bin/sh
# Make the still sticker at the size the Home cell needs. Keep the source file intact.
set -eu

source=$1
target=$2
width=$3
height=$4

case "$width:$height" in
    *[!0-9:]*|0:*|*:0) exit 2 ;;
esac

temporary=$(mktemp "${target}.tmp.XXXXXX.png")
trap 'rm -f "$temporary"' EXIT HUP INT TERM

magick "${source}[0]" -auto-orient -resize "${width}x${height}^" \
    -gravity center -extent "${width}x${height}" "$temporary"
mv -f "$temporary" "$target"
