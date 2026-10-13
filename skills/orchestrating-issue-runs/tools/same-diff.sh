#!/usr/bin/env bash
# same-diff.sh <old-base> <old-head> <new-base> <new-head> [repo]
# Exit 0 only when a rebase is content-identical: both sides produce a patch and
# the patches match. A bad or garbage-collected SHA makes git diff print nothing,
# and two empty outputs must never read as "identical" — a gate that licenses
# skipping a review must not pass by producing nothing.
set -u
[ $# -ge 4 ] || { echo "usage: same-diff.sh <old-base> <old-head> <new-base> <new-head> [repo]" >&2; exit 2; }
repo="${5:-.}"
before=$(git -C "$repo" diff "$1".."$2") || { echo "old side failed — NOT verified"; exit 1; }
after=$(git -C "$repo" diff "$3".."$4")  || { echo "new side failed — NOT verified"; exit 1; }
[ -n "$before" ] && [ -n "$after" ] || { echo "one side produced no patch — NOT verified"; exit 1; }
[ "$before" = "$after" ] || { echo "content differs — re-review"; exit 1; }
echo "content identical"
