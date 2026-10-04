#!/bin/sh
# Save a supported sticker choice before removing older sticker copies.
set -eu

config_dir=$1
choice=$2
name=${choice##*/}
case "$name" in
    *.*) extension=$(printf '%s' "${name##*.}" | tr '[:upper:]' '[:lower:]') ;;
    *) exit 2 ;;
esac
case "$extension" in
    png|jpg|jpeg|gif|webp) ;;
    *) exit 2 ;;
esac

mkdir -p -- "$config_dir"
replacement=$(mktemp "$config_dir/.sticker-copy.XXXXXX")
trap 'rm -f -- "$replacement"' EXIT HUP INT TERM
cp -- "$choice" "$replacement"
mv -fT -- "$replacement" "$config_dir/sticker.$extension"
find "$config_dir" -maxdepth 1 -name 'sticker.*' ! -type d \
    ! -name "sticker.$extension" -delete
