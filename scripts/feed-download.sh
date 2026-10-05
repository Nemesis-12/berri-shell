#!/bin/sh
# Downloads one calendar feed and converts it to compact records.
# Usage: BERRI_FEED_URL=URL feed-download.sh PARSER DEST_BASE TEMP_PARENT EXIT_PARSER_MISSING EXIT_NOT_CALENDAR EXIT_SAVE_FAILED
# The link is private (it can hold a token). It comes in the environment and goes to curl on its
# standard input, so it is in no argument list that other users can read with ps.
# DEST_BASE "" (a link check): prints the path of the new .json file in a temporary folder.
# DEST_BASE set: replaces DEST_BASE.ics and DEST_BASE.json together and prints DEST_BASE.json.
# If either replacement fails, both files go back to their old content.
url=${BERRI_FEED_URL-} parser=$1 dest=$2 parent=$3 missing=$4 notcalendar=$5 savefailed=$6
unset BERRI_FEED_URL

[ -x "$parser" ] || exit "$missing"
# Feeds are private: new files get mode 600 and the folder mode 700.
umask 077
sh "$(dirname "$0")/private-folder.sh" "$parent" || exit "$savefailed"
d=$(mktemp -d "$parent/.feed.XXXXXX") || exit 1
cleanup() { rm -f "$d/feed.ics" "$d/feed.json"; rmdir "$d" 2>/dev/null; }

# Only HTTPS, also after a redirect, and at most 5 redirects. A line break would end the quoted link.
case $url in ''|*'
'*) cleanup; exit 3 ;; esac
# printf is part of the shell, so the link is not in any argument list. The sed escapes \ and " for the curl config.
printf 'url = "%s"\n' "$(printf '%s' "$url" | sed 's/\\/\\\\/g; s/"/\\"/g')" |
  curl -fsSL -K - --proto '=https' --proto-redir '=https' --max-redirs 5 --max-time 15 --max-filesize 10485760 -o "$d/feed.ics" ||
  { c=$?; cleanup; exit $c; }
[ "$(wc -c <"$d/feed.ics")" -gt 10485760 ] && { cleanup; exit 63; }
"$parser" "$d/feed.ics" "$d/feed.json" || { cleanup; exit "$notcalendar"; }

if [ -z "$dest" ]; then
  printf '%s\n' "$d/feed.json"
  exit 0
fi

# Copies keep the old files in place until the new ones are moved over them.
for ext in ics json; do
  rm -f "$dest.$ext.bak"
  [ ! -e "$dest.$ext" ] || cp -p "$dest.$ext" "$dest.$ext.bak" || { rm -f "$dest.ics.bak" "$dest.json.bak"; cleanup; exit "$savefailed"; }
done
if mv "$d/feed.ics" "$dest.ics" && mv "$d/feed.json" "$dest.json"; then
  rm -f "$dest.ics.bak" "$dest.json.bak"
  cleanup
  printf '%s\n' "$dest.json"
else
  for ext in ics json; do
    if [ -e "$dest.$ext.bak" ]; then mv -f "$dest.$ext.bak" "$dest.$ext"; else rm -f "$dest.$ext"; fi
  done
  cleanup
  exit "$savefailed"
fi
