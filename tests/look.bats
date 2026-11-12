#!/usr/bin/env bats
#
# skills/look/tools/look.sh — setup, per-session lifecycle and the network
# guard. Browser tests skip when no browser or Playwright CLI is available (the
# Docker suite has neither). Point LOOK_CLI at an installed playwright-cli to
# skip the install.

load 'helpers/setup'

# One static server for the file, bound to 127.0.0.1 on a port the OS picks.
# python's http.server answers POST and DELETE with 501, so the guard tests
# tell "blocked" (the fetch rejects, ERR_BLOCKED_BY_CLIENT) from "sent" (any
# status), not 2xx from 4xx.
setup_file() {
  LOOK_PORT="" LOOK_SRV_PID=""
  if command -v python3 >/dev/null 2>&1; then
    local log="$BATS_FILE_TMPDIR/http.log" i
    python3 -u -m http.server 0 --bind 127.0.0.1 \
      --directory "$REPO_ROOT/tests/fixtures/look" >"$log" 2>&1 3>&- &
    LOOK_SRV_PID=$!
    for i in $(seq 50); do
      LOOK_PORT="$(sed -n 's/^Serving HTTP on 127\.0\.0\.1 port \([0-9][0-9]*\) .*/\1/p' "$log")"
      [ -z "$LOOK_PORT" ] || break
      sleep 0.1
    done
  fi
  export LOOK_PORT LOOK_SRV_PID
}
teardown_file() {
  [ -z "${LOOK_SRV_PID-}" ] || kill "$LOOK_SRV_PID" 2>/dev/null || true
}

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

# A fake CLI that logs its arguments and fails when FAKE_FAIL appears in them.
# Its run-code prints FAKE_RUNCODE_OUT, standing in for what the guard returned.
fake_cli() { # bin-dir
  cat > "$1/fakecli" <<'STUB'
#!/bin/sh
echo "$*" >> "$FAKE_LOG"
case "$*" in *"${FAKE_FAIL:-@@never@@}"*) exit 1 ;; esac
case "$*" in *run-code*) [ -z "${FAKE_RUNCODE_OUT-}" ] || printf '%s\n' "$FAKE_RUNCODE_OUT" ;; esac
exit 0
STUB
  chmod +x "$1/fakecli"
  export FAKE_LOG="$TEST_TMP/cli.log"
}

@test "open with no browser exits 3, names chromium, runs nothing and writes no config" {
  type -P node >/dev/null || skip "no node here"
  bin="$(sandbox_path bash env dirname mkdir rmdir sleep flock rm mv cat sed grep ls node)"
  fake_cli "$bin"
  PATH="$bin" LOOK_BROWSER= LOOK_CLI="$bin/fakecli" run "$LOOK" open "t$$-n" 'http://example.invalid/'
  [ "$status" -eq 3 ]
  assert_contains "$output" chromium
  [ ! -e "$FAKE_LOG" ]
  [ ! -e "$LOOK_HOME/t$$-n/.playwright/cli.config.json" ]
}

@test "open with a failing npm exits 3 with the npm message" {
  type -P node >/dev/null || skip "no node here"
  bin="$(sandbox_path bash env dirname mkdir rmdir sleep flock rm mv cat sed grep ls true node)"
  printf '#!/bin/sh\nexit 1\n' > "$bin/npm"; chmod +x "$bin/npm"
  PATH="$bin" LOOK_BROWSER="$bin/true" run env -u LOOK_CLI "$LOOK" open "t$$-n" 'http://example.invalid/'
  [ "$status" -eq 3 ]
  assert_contains "$output" "npm install"
  refute_contains "$output" "could not open"
}

@test "a failed open about:blank stops open before any goto" {
  type -P node >/dev/null || skip "no node here"
  bin="$(sandbox_path bash env dirname mkdir rmdir sleep flock rm mv cat sed grep ls true node)"
  fake_cli "$bin"
  FAKE_FAIL="open about:blank" PATH="$bin" LOOK_BROWSER="$bin/true" LOOK_CLI="$bin/fakecli" \
    run "$LOOK" open "t$$-n" 'http://example.invalid/'
  [ "$status" -ne 0 ]
  assert_contains "$output" "look: could not open"
  ! grep -q 'goto' "$FAKE_LOG"
}

@test "a guard that fails stops open before navigation and closes the session" {
  type -P node >/dev/null || skip "no node here"
  bin="$(sandbox_path bash env dirname mkdir rmdir sleep flock rm mv cat sed grep ls true node)"
  fake_cli "$bin"
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

# ---- the network guard ---------------------------------------------------

# guard_rules <config-json>: loads guard.js with that config into a fake page,
# then feeds it the "want METHOD URL" lines on stdin (want: pass | block) and
# prints each one it decided differently. Needs node, not a browser.
guard_rules() {
  node -e '
    const fs = require("fs");
    const [file, cfgJson] = process.argv.slice(1);
    const words = ["logout","delete","remove","destroy","approve","reject","revoke","unsubscribe"];
    const cfg = Object.assign({allowPost: [], denyGetWords: words, disposableHost: null}, JSON.parse(cfgJson));
    const parts = fs.readFileSync(file, "utf8").split("/*GUARD_CONFIG*/");
    if (parts.length !== 2) { console.log("placeholders: " + (parts.length - 1)); process.exit(1); }
    const guard = eval("(" + parts.join(JSON.stringify(cfg)) + "\n)");
    let handler = null;
    const page = {context: () => ({route: async (pattern, h) => { if (pattern === "**/*") handler = h; }})};
    (async () => {
      const said = await guard(page);
      if (said !== "look-guard-on" || !handler) { console.log("guard said " + said); process.exit(1); }
      let bad = 0, n = 0;
      for (const line of fs.readFileSync(0, "utf8").split("\n")) {
        const t = line.trim();
        if (!t || t.startsWith("#")) continue;
        const [want, method, url] = t.split(/\s+/);
        let got = "nothing";
        await handler({
          request: () => ({method: () => method, url: () => url}),
          continue: async () => { got = "pass"; },
          fallback: async () => { got = "fallback"; },
          abort: async code => { got = code === "blockedbyclient" ? "block" : "abort " + code; },
        });
        n++;
        if (got !== want) { bad++; console.log("WRONG " + method + " " + url + ": want " + want + ", got " + got); }
      }
      console.log("checked " + n);
      process.exit(bad ? 1 : 0);
    })().catch(e => { console.log("error: " + e.message); process.exit(1); });
  ' "$REPO/skills/look/tools/guard.js" "$1"
}

@test "guard rules: reads pass, every write is blocked, deny words block reads" {
  type -P node >/dev/null || skip "no node here"
  run guard_rules '{}' <<'EOF'
pass  GET      http://h.test/catalog
pass  HEAD     http://h.test/catalog
pass  OPTIONS  http://h.test/api/items
block POST     http://h.test/catalog
block PUT      http://h.test/catalog
block PATCH    http://h.test/catalog
block DELETE   http://h.test/catalog
block PROPFIND http://h.test/catalog
block GET      http://h.test/logout
block GET      http://h.test/account/LogOut/
block GET      http://h.test/logout.php
block GET      http://h.test/logout;jsessionid=AB12
block GET      http://h.test/log%6Fut
block GET      http://h.test/users/7/delete?confirm=1
block HEAD     http://h.test/logout
block GET      http://h.test/items?action=remove
block GET      http://h.test/mail?id=3&do=Unsubscribe
pass  GET      http://h.test/delete-guide
pass  GET      http://h.test/removed/items
pass  GET      http://h.test/catalog?q=deleted
block GET      not-a-url
EOF
  [ "$status" -eq 0 ] || fail "$output"
  assert_contains "$output" "checked 21"
}

@test "guard rules: an allowlist glob lets a POST through unless a deny word is in it" {
  type -P node >/dev/null || skip "no node here"
  run guard_rules '{"allowPost":["**/q*","**/api/ds/query*","**/items/**"]}' <<'EOF'
pass  POST   http://h.test/q
pass  POST   http://h.test:8080/a/b/quiet
block POST   http://h.test/q/x
block PUT    http://h.test/q
block DELETE http://h.test/q
pass  POST   http://grafana.test:3000/api/ds/query?ds_type=prometheus&requestId=Q1
block POST   http://grafana.test/api/dashboards/db
block POST   http://grafana.test/api/dashboards/db?next=/api/ds/query
pass  POST   http://h.test/items/7
block POST   http://h.test/items/7/delete
block POST   http://h.test/items/7?op=destroy
block GET    http://h.test/items/7/approve
EOF
  [ "$status" -eq 0 ] || fail "$output"
  assert_contains "$output" "checked 12"
}

@test "guard rules: the disposable host takes writes, matched exactly by host name" {
  type -P node >/dev/null || skip "no node here"
  run guard_rules '{"disposableHost":"127.0.0.1"}' <<'EOF'
pass  POST   http://127.0.0.1:5173/api/save
pass  DELETE http://127.0.0.1/items/7
pass  POST   http://127.0.0.1:5173/items/7/delete
block GET    http://127.0.0.1:5173/logout
block POST   http://127.0.0.10:5173/api/save
block POST   http://localhost:5173/api/save
block POST   http://127.0.0.1.example.test/api/save
block POST   http://evil.test/?host=127.0.0.1
block POST   http://127.0.0.1@evil.test/x
EOF
  [ "$status" -eq 0 ] || fail "$output"
  assert_contains "$output" "checked 9"
  run guard_rules '{"disposableHost":"Dev.Example.test"}' <<'EOF'
pass  POST   http://DEV.example.test:8443/x
block POST   http://example.test/x
EOF
  [ "$status" -eq 0 ] || fail "$output"
}

GUARD_ON='### Result
"look-guard-on"'

@test "open writes the merged rules into the guard, installs it before goto, blocks service workers" {
  type -P node >/dev/null || skip "no node here"
  bin="$(sandbox_path bash env dirname mkdir rmdir sleep flock rm mv cat sed grep ls true node)"
  fake_cli "$bin"
  FAKE_RUNCODE_OUT="$GUARD_ON" PATH="$bin" LOOK_BROWSER="$bin/true" LOOK_CLI="$bin/fakecli" \
    run "$LOOK" open "t$$-n" 'http://example.invalid/' \
      --preset grafana --allow-post '**/q*' --disposable Dev.Example.test
  [ "$status" -eq 0 ] || fail "$output"
  dir="$LOOK_HOME/t$$-n"
  grep -qF '"serviceWorkers": "block"' "$dir/.playwright/cli.config.json"
  gen="$dir/guard.gen.js"
  [ -f "$gen" ]
  ! grep -qF '/*GUARD_CONFIG*/' "$gen"
  grep -qF '"allowPost":["**/api/ds/query*","**/q*"]' "$gen"
  grep -qF '"denyGetWords":["logout","delete","remove","destroy","approve","reject","revoke","unsubscribe"]' "$gen"
  grep -qF '"disposableHost":"dev.example.test"' "$gen"
  # The order that matters: blank page, guard, then the first real navigation.
  run grep -nE '^-s=t[0-9]+-n (open about:blank|run-code --filename=guard.gen.js|goto)' "$FAKE_LOG"
  assert_equal "$(printf '%s\n' "$output" | sed 's/^[0-9]*:-s=t[0-9]*-n //; s/ .*//')" \
    "$(printf 'open\nrun-code\ngoto')"
}

@test "with no options the guard has no allowlist and no disposable host" {
  type -P node >/dev/null || skip "no node here"
  bin="$(sandbox_path bash env dirname mkdir rmdir sleep flock rm mv cat sed grep ls true node)"
  fake_cli "$bin"
  FAKE_RUNCODE_OUT="$GUARD_ON" PATH="$bin" LOOK_BROWSER="$bin/true" LOOK_CLI="$bin/fakecli" \
    run "$LOOK" open "t$$-n" 'http://127.0.0.1:5173/'
  [ "$status" -eq 0 ] || fail "$output"
  grep -qF '"allowPost":[]' "$LOOK_HOME/t$$-n/guard.gen.js"
  grep -qF '"disposableHost":null' "$LOOK_HOME/t$$-n/guard.gen.js"
}

@test "a guard that does not confirm it is on stops open before navigation" {
  type -P node >/dev/null || skip "no node here"
  bin="$(sandbox_path bash env dirname mkdir rmdir sleep flock rm mv cat sed grep ls true node)"
  fake_cli "$bin"
  FAKE_RUNCODE_OUT='### Result
"something else"' PATH="$bin" LOOK_BROWSER="$bin/true" LOOK_CLI="$bin/fakecli" \
    run "$LOOK" open "t$$-n" 'http://example.invalid/'
  [ "$status" -ne 0 ]
  assert_contains "$output" "guard"
  assert_contains "$output" "look: could not open"
  grep -q 'run-code' "$FAKE_LOG"
  grep -q 'close' "$FAKE_LOG"
  ! grep -q 'goto' "$FAKE_LOG"
}

@test "an unknown preset fails open, names the preset and starts no browser" {
  type -P node >/dev/null || skip "no node here"
  bin="$(sandbox_path bash env dirname mkdir rmdir sleep flock rm mv cat sed grep ls true node)"
  fake_cli "$bin"
  for p in nosuch ../tools/presets/grafana GRAFANA; do
    FAKE_RUNCODE_OUT="$GUARD_ON" PATH="$bin" LOOK_BROWSER="$bin/true" LOOK_CLI="$bin/fakecli" \
      run "$LOOK" open "t$$-n" 'http://example.invalid/' --preset "$p"
    [ "$status" -eq 2 ] || fail "--preset $p: status $status: $output"
    assert_contains "$output" "preset '$p'"
  done
  [ ! -e "$FAKE_LOG" ]
}

@test "a disposable host must be a bare host name" {
  type -P node >/dev/null || skip "no node here"
  bin="$(sandbox_path bash env dirname mkdir rmdir sleep flock rm mv cat sed grep ls true node)"
  fake_cli "$bin"
  for h in http://127.0.0.1 127.0.0.1:3000 'h.test/x' '*.test' 'h test'; do
    FAKE_RUNCODE_OUT="$GUARD_ON" PATH="$bin" LOOK_BROWSER="$bin/true" LOOK_CLI="$bin/fakecli" \
      run "$LOOK" open "t$$-n" 'http://example.invalid/' --disposable "$h"
    [ "$status" -eq 2 ] || fail "--disposable $h: status $status: $output"
    assert_contains "$output" "--disposable"
  done
  [ ! -e "$FAKE_LOG" ]
}

need_server() {
  [ -n "${LOOK_PORT-}" ] || skip "no python3 http.server here"
  BASE="http://127.0.0.1:$LOOK_PORT"
}

# What a fetch from the page got: "status N" when it was sent, "rejected" when not.
fetch_from() { # session method url [mode]
  "$LOOK" cli "$1" eval "async () => { try { const r = await fetch('$3', {method: '$2', mode: '${4:-cors}'}); return 'status ' + r.status; } catch (e) { return 'rejected'; } }"
}
# Blocked by the guard, not by anything else: the fetch rejected and the
# session's request log says ERR_BLOCKED_BY_CLIENT for exactly that request.
assert_blocked() { # session method url [mode]
  run fetch_from "$@"
  [ "$status" -eq 0 ] || fail "eval failed: $output"
  assert_contains "$output" '"rejected"'
  run "$LOOK" cli "$1" requests --all
  assert_contains "$output" "[$2] $3 => [FAILED] net::ERR_BLOCKED_BY_CLIENT"
}
assert_sent() { # session method url [mode]
  run fetch_from "$@"
  [ "$status" -eq 0 ] || fail "eval failed: $output"
  assert_contains "$output" '"status '
}

@test "the guard blocks POST and DELETE and lets GET through" {
  need_browser; need_server
  S="t$$-a"
  run "$LOOK" open "$S" "$BASE/index.html"
  [ "$status" -eq 0 ] || fail "$output"
  run fetch_from "$S" GET "$BASE/catalog"
  assert_contains "$output" '"status 200"'
  assert_blocked "$S" POST "$BASE/catalog"
  assert_blocked "$S" DELETE "$BASE/catalog"
  assert_blocked "$S" PUT "$BASE/catalog"
}

@test "a service worker cannot register in a guarded session" {
  need_browser; need_server
  S="t$$-a"
  run "$LOOK" open "$S" "$BASE/index.html"
  [ "$status" -eq 0 ] || fail "$output"
  run "$LOOK" cli "$S" eval "async () => { await navigator.serviceWorker.register('/sw.js').catch(() => {}); return 'registrations ' + (await navigator.serviceWorker.getRegistrations()).length; }"
  assert_contains "$output" '"registrations 0"'
}

@test "a POST fired on page load is blocked" {
  need_browser; need_server
  S="t$$-a"
  run "$LOOK" open "$S" "$BASE/onload-post.html"
  [ "$status" -eq 0 ] || fail "$output"
  for i in $(seq 20); do
    run "$LOOK" cli "$S" requests --all
    case "$output" in *"/save => "*"/beacon => "*|*"/beacon => "*"/save => "*) break ;; esac
    sleep 0.25
  done
  assert_contains "$output" "[POST] $BASE/save => [FAILED] net::ERR_BLOCKED_BY_CLIENT"
  assert_contains "$output" "[POST] $BASE/beacon => [FAILED] net::ERR_BLOCKED_BY_CLIENT"
}

@test "an allowlisted POST passes and a preset allows Grafana's query path" {
  need_browser; need_server
  A="t$$-a"; B="t$$-b"
  run "$LOOK" open "$A" "$BASE/index.html" --allow-post '**/q*'
  [ "$status" -eq 0 ] || fail "$output"
  assert_sent "$A" POST "$BASE/q"
  assert_blocked "$A" POST "$BASE/catalog"
  assert_blocked "$A" PUT "$BASE/q"
  run "$LOOK" open "$B" "$BASE/index.html" --preset grafana --allow-post '**/items/**'
  [ "$status" -eq 0 ] || fail "$output"
  assert_sent "$B" POST "$BASE/api/ds/query?x=1"
  assert_blocked "$B" POST "$BASE/q"
  assert_sent "$B" POST "$BASE/items/7"
  assert_blocked "$B" POST "$BASE/items/7/delete"
}

@test "a GET to a logout link is blocked" {
  need_browser; need_server
  S="t$$-a"
  run "$LOOK" open "$S" "$BASE/index.html"
  [ "$status" -eq 0 ] || fail "$output"
  assert_blocked "$S" GET "$BASE/logout"
  run fetch_from "$S" GET "$BASE/catalog"
  assert_contains "$output" '"status 200"'
  assert_blocked "$S" GET "$BASE/catalog?action=delete"
}

@test "a disposable host takes writes; another host still does not" {
  need_browser; need_server
  S="t$$-a"
  run "$LOOK" open "$S" "$BASE/index.html" --disposable 127.0.0.1
  [ "$status" -eq 0 ] || fail "$output"
  assert_sent "$S" POST "$BASE/catalog"
  assert_sent "$S" DELETE "$BASE/catalog"
  assert_blocked "$S" POST "http://localhost:$LOOK_PORT/catalog" no-cors
  assert_blocked "$S" POST "http://127.0.0.10:$LOOK_PORT/catalog" no-cors
  assert_blocked "$S" GET "$BASE/logout"
}
