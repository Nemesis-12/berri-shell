#!/bin/sh
# Creates a worktree on a new branch and copies the private AGENTS.md into it.
# AGENTS.md is git-ignored, so git does not copy it to a new worktree.
# Usage: tools/new-worktree.sh BRANCH PATH [BASE]   (BASE defaults to origin/main)
set -eu

[ $# -ge 2 ] || { echo "Usage: tools/new-worktree.sh BRANCH PATH [BASE]" >&2; exit 2; }
branch=$1 target=$2 base=${3:-origin/main}
repo=$(cd "$(dirname "$0")/.." && pwd)

[ -f "$repo/AGENTS.md" ] || { echo "new-worktree: AGENTS.md is missing in $repo, copy it there first" >&2; exit 1; }
git -C "$repo" show-ref --verify --quiet "refs/remotes/$base" || base=HEAD
git -C "$repo" worktree add -b "$branch" -- "$target" "$base"
cp -- "$repo/AGENTS.md" "$target/AGENTS.md"
git -C "$target" config core.hooksPath .githooks
echo "new-worktree: $target ready"
