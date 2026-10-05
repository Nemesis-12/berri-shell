#!/bin/sh
# One-time setup in a fresh clone: builds the calendar parser and turns on the pre-push hook.
# Run again after the parser source changes.
# Usage: tools/setup.sh
set -eu

cd "$(dirname "$0")/.."
command -v cargo >/dev/null 2>&1 || { echo "setup: cargo not found, install Rust first" >&2; exit 1; }
cargo build --release --manifest-path tools/feed-to-records/Cargo.toml
cp tools/feed-to-records/target/release/feed-to-records tools/feed-to-records/feed-to-records
if git rev-parse --git-dir >/dev/null 2>&1; then git config core.hooksPath .githooks; fi
echo "setup: calendar parser built"
