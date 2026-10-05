#!/bin/sh
# Makes the compact records (.json) of a subscription again from its .ics file.
# The records file is owner-only: mode 600, whatever the caller's creation mask is.
# Usage: refresh-records.sh PARSER ICS JSON EXIT_PARSER_MISSING
# Nothing happens when ICS is missing. Exit code EXIT_PARSER_MISSING: the parser is missing.
parser=$1 ics=$2 json=$3 missing=$4

[ -f "$ics" ] || exit 0
[ -x "$parser" ] || exit "$missing"
umask 077
"$parser" "$ics" "$json"
