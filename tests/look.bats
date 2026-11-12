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
  for s in "t$$-a" "t$$-b"; do "$LOOK" close "$s" >/dev/null 2>&1 || true; done
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

# A PATH holding only the named tools, so nothing else (browser, node, npm) resolves.
sandbox_path() { # tool...
  bin="$TEST_TMP/bin"; mkdir -p "$bin"
  local t p
  for t in "$@"; do p="$(type -P "$t" 2>/dev/null)" && ln -sf "$p" "$bin/$t"; done
  echo "$bin"
}

@test "setup without node exits 3 and names node" {
  bin="$(sandbox_path bash env dirname mkdir rmdir sleep flock rm mv cat sed grep ls true)"
  PATH="$bin" LOOK_BROWSER="$bin/true" run "$LOOK" setup
  [ "$status" -eq 3 ]
  assert_contains "$output" node
}

@test "a failed npm install exits 3, names npm, and leaves no cache a later setup accepts" {
  type -P node >/dev/null || skip "no node here"
  bin="$(sandbox_path bash env dirname mkdir rmdir sleep flock rm mv cat sed grep ls true node)"
  # The stub makes the hazard: a runnable-looking CLI under --prefix, then failure.
  cat > "$bin/npm" <<'STUB'
#!/bin/sh
while [ $# -gt 0 ]; do
  if [ "$1" = --prefix ]; then p="$2"; fi
  shift
done
mkdir -p "$p/node_modules/.bin"
printf '#!/bin/sh\nexit 0\n' > "$p/node_modules/.bin/playwright-cli"
chmod +x "$p/node_modules/.bin/playwright-cli"
exit 1
STUB
  chmod +x "$bin/npm"
  for i in 1 2; do
    PATH="$bin" LOOK_BROWSER="$bin/true" run env -u LOOK_CLI "$LOOK" setup
    [ "$status" -eq 3 ]
    assert_contains "$output" npm
  done
  [ ! -e "$XDG_CACHE_HOME/claude-look/cli-0.1.24" ]
  [ -z "$(ls -A "$XDG_CACHE_HOME/claude-look" | grep -v '\.lock$')" ]
}

@test "a guard that fails stops open before navigation and closes the session" {
  type -P node >/dev/null || skip "no node here"
  bin="$(sandbox_path bash env dirname mkdir rmdir sleep flock rm mv cat sed grep ls true node)"
  cat > "$bin/fakecli" <<'STUB'
#!/bin/sh
echo "$*" >> "$FAKE_LOG"
STUB
  chmod +x "$bin/fakecli"
  export FAKE_LOG="$TEST_TMP/cli.log"
  PATH="$bin" LOOK_BROWSER="$bin/true" LOOK_CLI="$bin/fakecli" LOOK_TEST_GUARD_FAIL=1 \
    run "$LOOK" open "t$$-g" 'http://example.invalid/'
  [ "$status" -ne 0 ]
  assert_contains "$output" "look: could not open http://example.invalid/ in session 't$$-g'"
  grep -q 'open about:blank' "$FAKE_LOG"
  grep -q 'close' "$FAKE_LOG"
  ! grep -q 'goto' "$FAKE_LOG"
}

@test "two sessions keep separate pages and evidence directories" {
  need_browser
  A="t$$-a"; B="t$$-b"
  run "$LOOK" open "$A" 'data:text/html,<title>Alpha</title>'
  [ "$status" -eq 0 ]
  dir_a="$output"
  run "$LOOK" open "$B" 'data:text/html,<title>Bravo</title>'
  [ "$status" -eq 0 ]
  dir_b="$output"
  [ "$dir_a" != "$dir_b" ]
  [ -d "$LOOK_HOME/$A" ] && [ -d "$LOOK_HOME/$B" ]
  run "$LOOK" cli "$A" eval "() => document.title"
  [ "$status" -eq 0 ]
  assert_contains "$output" '"Alpha"'
  refute_contains "$output" Bravo
  run "$LOOK" cli "$B" eval "() => document.title"
  [ "$status" -eq 0 ]
  assert_contains "$output" '"Bravo"'
  refute_contains "$output" Alpha
  run "$LOOK" close "$A"
  [ "$status" -eq 0 ]
  run "$LOOK" close "$B"
  [ "$status" -eq 0 ]
}

@test "a failed navigation closes its own session and exits non-zero" {
  need_browser
  S="t$$-a"
  run "$LOOK" open "$S" 'http://127.0.0.1:9/'
  [ "$status" -ne 0 ]
  assert_contains "$output" "look: could not open http://127.0.0.1:9/ in session '$S'"
  run "$LOOK" cli "$S" eval "() => 1"
  [ "$status" -ne 0 ]
}
