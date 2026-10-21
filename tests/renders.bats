#!/usr/bin/env bats
#
# docs/statusline/*.svg — the README's status line renders. They are drawn by
# the real scripts, so a change to either script must re-render them.

load 'helpers/setup'

setup()    { common_setup; }
teardown() { common_teardown; }

@test "the committed renders match what the scripts draw now" {
  run bash "$REPO/docs/statusline/render.sh" "$TEST_TMP/out"
  [ "$status" -eq 0 ] || fail "render.sh failed: $output"
  n=0
  for f in "$REPO"/docs/statusline/*.svg; do
    n=$((n + 1))
    diff -q "$f" "$TEST_TMP/out/${f##*/}" >/dev/null \
      || fail "${f##*/} is stale; run docs/statusline/render.sh and commit the result"
  done
  [ "$n" -ge 6 ] || fail "found only $n committed renders"
  for f in "$TEST_TMP"/out/*.svg; do
    [ -e "$REPO/docs/statusline/${f##*/}" ] || fail "${f##*/} is rendered but not committed"
  done
}
