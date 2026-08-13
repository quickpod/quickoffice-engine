#!/usr/bin/env bash
# Fetch the exact LibreOffice source this engine is built from.
#
#   fetch-core.sh [destination]        default: ../../office/core
#
# The engine repo does NOT vendor a copy of LibreOffice. It pins one: `pin.txt`
# records the upstream branch and commit, and this script clones it. That keeps
# this repo small enough to be a normal QuickOpen repo, and it makes the
# provenance of every build checkable in one line — which is exactly what
# MPL-2.0 section 3.2 asks of us when we hand somebody a binary.
#
# If we ever have to patch a core file (see README — we try very hard not to),
# the patch lands in patches/ and is applied here, so the tree this produces is
# still the complete corresponding source for the shipped binary.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="${1:-$HERE/../../office/core}"
UPSTREAM="https://github.com/LibreOffice/core.git"

BRANCH="$(awk -F= '/^branch=/{print $2}' "$HERE/pin.txt")"
COMMIT="$(awk -F= '/^commit=/{print $2}' "$HERE/pin.txt")"
[ -n "$BRANCH" ] && [ -n "$COMMIT" ] || { echo "pin.txt is incomplete"; exit 1; }

if [ -d "$DEST/.git" ]; then
  echo "== updating existing tree at $DEST"
  git -C "$DEST" fetch --depth 1 origin "$BRANCH"
else
  echo "== cloning $BRANCH into $DEST (about 2 GB)"
  git clone --depth 1 --branch "$BRANCH" "$UPSTREAM" "$DEST"
  git -C "$DEST" fetch --depth 1 origin "$BRANCH"
fi

git -C "$DEST" checkout -q -B quickoffice "$COMMIT" 2>/dev/null || {
  echo "!! pinned commit $COMMIT is not in the shallow fetch."
  echo "   Deepen with: git -C $DEST fetch --unshallow origin $BRANCH"
  exit 1
}
echo "== core at $(git -C "$DEST" log --oneline -1)"

shopt -s nullglob
patches=("$HERE"/patches/*.patch)
if [ ${#patches[@]} -gt 0 ]; then
  echo "== applying ${#patches[@]} patch(es)"
  for p in "${patches[@]}"; do
    git -C "$DEST" apply --check "$p" && git -C "$DEST" apply "$p"
    echo "   $(basename "$p")"
  done
else
  echo "== no patches — every customisation is in this overlay, none in core"
fi
