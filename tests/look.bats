#!/usr/bin/env bats
#
# skills/look/tools/look.sh — setup and per-session lifecycle. Browser tests
# skip when no browser or Playwright CLI is available (the Docker suite has
# neither). Point LOOK_CLI at an installed playwright-cli to skip the install.

load 'helpers/setup'

setup() {
  common_setup
  LOOK="$REPO/skills/look/tools/look.sh"
  export LOOK_HOME="$TEST_TMP/look"
}
teardown() {
  for s in a b; do "$LOOK" close "$s" >/dev/null 2>&1 || true; done
  common_teardown
}

need_browser() {
  [ -x "$LOOK" ] || fail "look.sh missing"
  "$LOOK" setup >/dev/null 2>&1 || skip "no browser or Playwright CLI here"
}

@test "setup with no browser names what to install and exits 3" {
  bin="$TEST_TMP/bin"; mkdir -p "$bin"
  for t in bash env node npm dirname basename mkdir cat sed grep; do
    p="$(command -v "$t" 2>/dev/null)" && ln -s "$p" "$bin/$t"
  done
  PATH="$bin" LOOK_BROWSER= run "$LOOK" setup
  [ "$status" -eq 3 ]
  assert_contains "$output" chromium
}

@test "a session name with a space or a slash is refused" {
  run "$LOOK" open "bad name" about:blank
  [ "$status" -eq 2 ]
  run "$LOOK" open ../x about:blank
  [ "$status" -eq 2 ]
  [ ! -e "$TEST_TMP/x" ]
  [ ! -e "$LOOK_HOME/../x" ]
}

@test "two sessions keep separate pages and evidence directories" {
  need_browser
  run "$LOOK" open a 'data:text/html,<title>A</title>'
  [ "$status" -eq 0 ]
  dir_a="$output"
  run "$LOOK" open b 'data:text/html,<title>B</title>'
  [ "$status" -eq 0 ]
  dir_b="$output"
  [ "$dir_a" != "$dir_b" ]
  [ -d "$LOOK_HOME/a" ] && [ -d "$LOOK_HOME/b" ]
  run "$LOOK" cli a eval "() => document.title"
  assert_contains "$output" A
  refute_contains "$output" '"B"'
  run "$LOOK" cli b eval "() => document.title"
  assert_contains "$output" B
  run "$LOOK" close a
  [ "$status" -eq 0 ]
  run "$LOOK" close b
  [ "$status" -eq 0 ]
}
