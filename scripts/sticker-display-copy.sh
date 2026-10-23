#!/bin/sh
# Make the still sticker at the size the Home cell needs. Keep the source file intact.
# Then remove display copies in the target folder that are older than the source
# (made from an earlier picture) and the old unsized name. A copy for another
# monitor is newer than the source, so it stays.
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

folder=$(dirname -- "$target")
find "$folder" -maxdepth 1 -type f -name 'sticker-display*.png' \
    ! -path "$source" ! -path "$target" \
    \( -name 'sticker-display.png' -o ! -newer "$source" \) -delete 2>/dev/null || true
