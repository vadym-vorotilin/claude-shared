#!/usr/bin/env bats
#
# skills/look/tools/look.sh — setup, per-session lifecycle and the network
# guard. Browser tests skip when no browser or Playwright CLI is available (the
# Docker suite has neither). Point LOOK_CLI at an installed playwright-cli to
# skip the install.

load 'helpers/setup'

# Two static servers for the files, bound to 127.0.0.1 on ports the OS picks:
# the second is another server on the same host, for the disposable-port
# tests. python's http.server answers POST and DELETE with 501, so the guard
# tests tell "blocked" (the fetch rejects, ERR_BLOCKED_BY_CLIENT) from "sent"
# (any status), not 2xx from 4xx.
start_server() { # log -> sets SRV_PID, SRV_PORT
  local log="$1" i
  SRV_PORT=""
  python3 -u -m http.server 0 --bind 127.0.0.1 \
    --directory "$REPO_ROOT/tests/fixtures/look" >"$log" 2>&1 3>&- &
  SRV_PID=$!
  for i in $(seq 50); do
    SRV_PORT="$(sed -n 's/^Serving HTTP on 127\.0\.0\.1 port \([0-9][0-9]*\) .*/\1/p' "$log")"
    [ -z "$SRV_PORT" ] || break
    sleep 0.1
  done
}
setup_file() {
  LOOK_PORT="" LOOK_SRV_PID="" LOOK_SRV_LOG="$BATS_FILE_TMPDIR/http.log"
  LOOK_PORT2="" LOOK_SRV2_PID="" LOOK_SRV2_LOG="$BATS_FILE_TMPDIR/http2.log"
  if command -v python3 >/dev/null 2>&1; then
    start_server "$LOOK_SRV_LOG"; LOOK_SRV_PID="$SRV_PID" LOOK_PORT="$SRV_PORT"
    start_server "$LOOK_SRV2_LOG"; LOOK_SRV2_PID="$SRV_PID" LOOK_PORT2="$SRV_PORT"
  fi
  export LOOK_PORT LOOK_SRV_PID LOOK_SRV_LOG LOOK_PORT2 LOOK_SRV2_PID LOOK_SRV2_LOG
}
teardown_file() {
  [ -z "${LOOK_SRV_PID-}" ] || kill "$LOOK_SRV_PID" 2>/dev/null || true
  [ -z "${LOOK_SRV2_PID-}" ] || kill "$LOOK_SRV2_PID" 2>/dev/null || true
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
  local why
  why="$("$LOOK" setup 2>&1)" || skip "no browser or Playwright CLI here: $(printf '%s' "$why" | tail -n 3 | tr '\n' ' ')"
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

# guard_rules <config-json>: loads guard.js with that config against a fake
# page, browser CDP session and WebSocket route, then feeds it the
# "want METHOD URL" lines on stdin (want: pass | block; METHOD WS is a
# WebSocket connection) and prints each one it decided differently.
# GUARD_NO_BROWSER=1 gives it a context with no browser. Needs node only.
guard_rules() {
  node -e '
    const fs = require("fs");
    const [file, cfgJson] = process.argv.slice(1);
    const words = ["logout","delete","remove","destroy","approve","reject","revoke","unsubscribe"];
    const cfg = Object.assign({allowPost: [], denyGetWords: words, disposableHost: null, allowWebsocket: false},
                              JSON.parse(cfgJson));
    const parts = fs.readFileSync(file, "utf8").split("/*GUARD_CONFIG*/");
    if (parts.length !== 2) { console.log("placeholders: " + (parts.length - 1)); process.exit(1); }
    const guard = eval("(" + parts.join(JSON.stringify(cfg)) + "\n)");
    let paused = null, ws = null, enabled = null, replies = [];
    const cdp = {
      on: (event, h) => { if (event === "Fetch.requestPaused") paused = h; },
      send: async (method, params) => {
        if (method === "Fetch.enable") enabled = params; else replies.push({method, params});
      },
    };
    const browser = process.env.GUARD_NO_BROWSER ? null : {newBrowserCDPSession: async () => cdp};
    const page = {context: () => ({browser: () => browser, routeWebSocket: async (p, h) => { ws = h; }})};
    (async () => {
      const said = await guard(page);
      if (said !== "look-guard-on" || !paused || !ws) { console.log("guard said " + said); process.exit(1); }
      if (!enabled || enabled.patterns.length !== 1 || enabled.patterns[0].urlPattern !== "*") {
        console.log("Fetch.enable: " + JSON.stringify(enabled)); process.exit(1);
      }
      let bad = 0, n = 0;
      for (const line of fs.readFileSync(0, "utf8").split("\n")) {
        const t = line.trim();
        if (!t || t.startsWith("#")) continue;
        const [want, method, url] = t.split(/\s+/);
        let got = "nothing";
        if (method === "WS") {
          ws({url: () => url, connectToServer: () => { got = "pass"; },
              close: o => { got = o && o.code === 4000 ? "block" : "close " + JSON.stringify(o); }});
        } else {
          replies = [];
          paused({requestId: "r" + n, request: {method, url}});
          await new Promise(r => setImmediate(r));
          const r = replies[0] || {};
          if (replies.length === 1 && r.params.requestId === "r" + n) {
            if (r.method === "Fetch.continueRequest") got = "pass";
            else if (r.method === "Fetch.failRequest" && r.params.errorReason === "BlockedByClient") got = "block";
            else got = r.method + " " + JSON.stringify(r.params);
          } else got = replies.length + " replies";
        }
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
block GET      http://h.test/account?logout=1
block GET      http://h.test/items?Delete
pass  GET      http://h.test/items?deleted=1
block GET      not-a-url
EOF
  [ "$status" -eq 0 ] || fail "$output"
  assert_contains "$output" "checked 24"
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
block POST   http://grafana.test/api/ds/query%2F..%2Fdashboards
block POST   http://grafana.test/api/ds/query%5c..%5Cdashboards
pass  POST   http://h.test/items/7
block POST   http://h.test/items/7/delete
block POST   http://h.test/items/7?op=destroy
block GET    http://h.test/items/7/approve
EOF
  [ "$status" -eq 0 ] || fail "$output"
  assert_contains "$output" "checked 14"
}

@test "guard rules: the disposable host takes writes, matched exactly by host name" {
  type -P node >/dev/null || skip "no node here"
  run guard_rules '{"disposableHost":"127.0.0.1:5173"}' <<'EOF'
pass  POST   http://127.0.0.1:5173/api/save
pass  DELETE http://127.0.0.1:5173/items/7
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
  run guard_rules '{"disposableHost":"dev.example.test:8443"}' <<'EOF'
pass  POST   http://DEV.example.test:8443/x
block POST   http://example.test:8443/x
EOF
  [ "$status" -eq 0 ] || fail "$output"
  run guard_rules '{"disposableHost":"127.0.0.1:80"}' <<'EOF'
pass  POST   http://127.1/x
EOF
  [ "$status" -eq 0 ] || fail "$output"
}

@test "guard rules: a disposable HOST:PORT lifts writes on that port only" {
  type -P node >/dev/null || skip "no node here"
  run guard_rules '{"disposableHost":"127.0.0.1:5173"}' <<'EOF'
pass  POST   http://127.0.0.1:5173/api/save
pass  POST   https://127.0.0.1:5173/api/save
block POST   http://127.0.0.1:8080/api/orders
block DELETE http://127.0.0.1:8080/api/orders
block POST   http://127.0.0.1/api/save
block POST   https://127.0.0.1/api/save
block POST   http://127.0.0.1:51730/api/save
pass  WS     ws://127.0.0.1:5173/live
block WS     ws://127.0.0.1:8080/live
EOF
  [ "$status" -eq 0 ] || fail "$output"
  assert_contains "$output" "checked 9"
  run guard_rules '{"disposableHost":"127.0.0.1:80"}' <<'EOF'
pass  POST   http://127.0.0.1/x
pass  POST   http://127.0.0.1:80/x
block POST   https://127.0.0.1/x
block POST   http://127.0.0.1:5173/x
block POST   http://127.0.0.1:443/x
pass  WS     ws://127.0.0.1/live
block WS     wss://127.0.0.1/live
EOF
  [ "$status" -eq 0 ] || fail "$output"
  assert_contains "$output" "checked 7"
  run guard_rules '{"disposableHost":"dev.example.test:443"}' <<'EOF'
pass  POST   https://dev.example.test/x
pass  WS     wss://dev.example.test/live
block POST   http://dev.example.test/x
EOF
  [ "$status" -eq 0 ] || fail "$output"
  run guard_rules '{"disposableHost":"[::1]:8080"}' <<'EOF'
pass  POST   http://[::1]:8080/x
block POST   http://[::1]:8081/x
block POST   http://[::1]/x
EOF
  [ "$status" -eq 0 ] || fail "$output"
}

# A bare HOST would be two servers, ports 80 and 443: the guard refuses it,
# so open fails before the first navigation.
@test "guard rules: a disposable host with no port stops the guard" {
  type -P node >/dev/null || skip "no node here"
  for h in 127.0.0.1 dev.example.test '[::1]'; do
    run guard_rules "{\"disposableHost\":\"$h\"}" </dev/null
    [ "$status" -ne 0 ] || fail "disposableHost $h: the guard started: $output"
    assert_contains "$output" "error: look guard: bad disposable"
  done
}

# The guard reads only the canonical form look.sh writes: a lower-case name
# or IPv4 address, or a bracketed IPv6 one, and a port 1-65535. Anything else
# stops it rather than lift writes on whatever new URL makes of it
# (x@evil.test is evil.test, a/b:80 is a:80), and so does a value that is
# not its own canonical form (127.1:80, h:080, -a:80), which look.sh never writes.
@test "guard rules: a disposable value not in look.sh's canonical form stops the guard" {
  type -P node >/dev/null || skip "no node here"
  for h in ::1 h h:0 h:65536 x@evil.test:80 a/b:80 Dev.Example.test:80 '[::1]x:80' 'h :80' \
           127.1:80 0x7f.1:80 h:080 h:00080 '[::ffff:127.0.0.1]:80' h.:80 -a:80 .a:80; do
    run guard_rules "{\"disposableHost\":\"$h\"}" </dev/null
    [ "$status" -ne 0 ] || fail "disposableHost $h: the guard started: $output"
    assert_contains "$output" "error: look guard: bad disposable"
  done
}

@test "guard rules: a WebSocket opens only to the disposable host, or anywhere when allowed" {
  type -P node >/dev/null || skip "no node here"
  run guard_rules '{"disposableHost":"127.0.0.1:8080"}' <<'EOF'
pass  WS ws://127.0.0.1:8080/live
block WS ws://127.0.0.1:8081/live
block WS ws://localhost:8080/live
block WS wss://chat.example.test/socket
EOF
  [ "$status" -eq 0 ] || fail "$output"
  run guard_rules '{}' <<'EOF'
block WS ws://127.0.0.1:8080/live
EOF
  [ "$status" -eq 0 ] || fail "$output"
  run guard_rules '{"allowWebsocket":true}' <<'EOF'
pass  WS wss://chat.example.test/socket
block POST http://chat.example.test/send
EOF
  [ "$status" -eq 0 ] || fail "$output"
}

@test "the guard refuses to start without a browser to attach to" {
  type -P node >/dev/null || skip "no node here"
  GUARD_NO_BROWSER=1 run guard_rules '{}' </dev/null
  [ "$status" -ne 0 ]
  assert_contains "$output" "no browser to attach to"
}

GUARD_ON='### Result
"look-guard-on"'

@test "open writes the merged rules into the guard, installs it before goto, blocks service workers" {
  type -P node >/dev/null || skip "no node here"
  bin="$(sandbox_path bash env dirname mkdir rmdir sleep flock rm mv cat sed grep ls true node)"
  fake_cli "$bin"
  FAKE_RUNCODE_OUT="$GUARD_ON" PATH="$bin" LOOK_BROWSER="$bin/true" LOOK_CLI="$bin/fakecli" \
    run "$LOOK" open "t$$-n" 'http://example.invalid/' \
      --preset grafana --allow-post '**/q*' --disposable Dev.Example.test:8443
  [ "$status" -eq 0 ] || fail "$output"
  dir="$LOOK_HOME/t$$-n"
  grep -qF '"serviceWorkers": "block"' "$dir/.playwright/cli.config.json"
  gen="$dir/guard.gen.js"
  [ -f "$gen" ]
  ! grep -qF '/*GUARD_CONFIG*/' "$gen"
  grep -qF '"allowPost":["**/api/ds/query*","**/q*"]' "$gen"
  grep -qF '"denyGetWords":["logout","delete","remove","destroy","approve","reject","revoke","unsubscribe"]' "$gen"
  grep -qF '"disposableHost":"dev.example.test:8443"' "$gen"
  grep -qF '"allowWebsocket":false' "$gen"
  # The order that matters: blank page, guard, then the first real navigation.
  run grep -nE '^-s=t[0-9]+-n (open about:blank|run-code --filename=guard.gen.js|goto)' "$FAKE_LOG"
  assert_equal "$(printf '%s\n' "$output" | sed 's/^[0-9]*:-s=t[0-9]*-n //; s/ .*//')" \
    "$(printf 'open\nrun-code\ngoto')"
}

@test "the guard's confirmation is found ahead of a long echo of its source" {
  type -P node >/dev/null || skip "no node here"
  bin="$(sandbox_path bash env dirname mkdir rmdir sleep flock rm mv cat sed grep ls true node)"
  fake_cli "$bin"
  long="$(printf '// echoed guard source line, long enough to fill a pipe buffer\n%.0s' $(seq 1500))"
  FAKE_RUNCODE_OUT="$GUARD_ON
$long" PATH="$bin" LOOK_BROWSER="$bin/true" LOOK_CLI="$bin/fakecli" \
    run "$LOOK" open "t$$-n" 'http://127.0.0.1:5173/'
  [ "$status" -eq 0 ] || fail "$(printf '%s\n' "$output" | head -3)"
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
  grep -qF '"allowWebsocket":false' "$LOOK_HOME/t$$-n/guard.gen.js"
}

@test "open --allow-websocket and a non-canonical --disposable reach the guard's config" {
  type -P node >/dev/null || skip "no node here"
  bin="$(sandbox_path bash env dirname mkdir rmdir sleep flock rm mv cat sed grep ls true node)"
  fake_cli "$bin"
  # given=canonical: the host as URL.hostname gives it, the port in decimal.
  for pair in 127.1:5173=127.0.0.1:5173 0x7f.1:05173=127.0.0.1:5173 \
              127.0.0.1:5173=127.0.0.1:5173 127.1:80=127.0.0.1:80 \
              DEV.Example.Test:8443=dev.example.test:8443 '[0:0::1]:8080=[::1]:8080'; do
    h="${pair%%=*}" want="${pair#*=}"
    FAKE_RUNCODE_OUT="$GUARD_ON" PATH="$bin" LOOK_BROWSER="$bin/true" LOOK_CLI="$bin/fakecli" \
      run "$LOOK" open "t$$-n" 'http://127.0.0.1:5173/' --disposable "$h" --allow-websocket
    [ "$status" -eq 0 ] || fail "--disposable $h: $output"
    grep -qF "\"disposableHost\":\"$want\"" "$LOOK_HOME/t$$-n/guard.gen.js" \
      || fail "--disposable $h: want $want, got $(grep -o '"disposableHost":[^,]*' "$LOOK_HOME/t$$-n/guard.gen.js")"
    grep -qF '"allowWebsocket":true' "$LOOK_HOME/t$$-n/guard.gen.js"
    # What look.sh accepts, the guard must start with.
    run guard_rules "{\"disposableHost\":\"$want\"}" </dev/null
    [ "$status" -eq 0 ] || fail "--disposable $h: the guard refused $want: $output"
  done
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

@test "a disposable server must be HOST:PORT and nothing else" {
  type -P node >/dev/null || skip "no node here"
  bin="$(sandbox_path bash env dirname mkdir rmdir sleep flock rm mv cat sed grep ls true node)"
  fake_cli "$bin"
  for h in http://127.0.0.1 http://127.0.0.1:3000 127.0.0.1:0 127.0.0.1:65536 127.0.0.1: \
           ::1:8080 '[::1]:x' 'h.test/x' 'h.test:80/x' '*.test' 'h test'; do
    FAKE_RUNCODE_OUT="$GUARD_ON" PATH="$bin" LOOK_BROWSER="$bin/true" LOOK_CLI="$bin/fakecli" \
      run "$LOOK" open "t$$-n" 'http://example.invalid/' --disposable "$h"
    [ "$status" -eq 2 ] || fail "--disposable $h: status $status: $output"
    assert_contains "$output" "--disposable"
  done
  [ ! -e "$FAKE_LOG" ]
}

@test "a bare --disposable HOST is refused, asking for the server's port" {
  type -P node >/dev/null || skip "no node here"
  bin="$(sandbox_path bash env dirname mkdir rmdir sleep flock rm mv cat sed grep ls true node)"
  fake_cli "$bin"
  for h in 127.0.0.1 localhost Dev.Example.test '[::1]'; do
    FAKE_RUNCODE_OUT="$GUARD_ON" PATH="$bin" LOOK_BROWSER="$bin/true" LOOK_CLI="$bin/fakecli" \
      run "$LOOK" open "t$$-n" 'http://example.invalid/' --disposable "$h"
    [ "$status" -eq 2 ] || fail "--disposable $h: status $status: $output"
    assert_contains "$output" "HOST:PORT"
    assert_contains "$output" "port"
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
# The test server's own log is the ground truth: "not sent" means no line for
# the request reached it since srv_mark, not only that the CLI did not list it.
srv_mark()  { SRV_MARK="$(wc -l < "$LOOK_SRV_LOG")"; }
srv_since() { tail -n "+$((SRV_MARK + 1))" "$LOOK_SRV_LOG"; }
refute_sent()   { refute_contains "$(srv_since)" "\"$1 $2 HTTP/"; } # method path
assert_reached() { assert_contains "$(srv_since)" "\"$1 $2 HTTP/"; } # method path
url_path() { local p="${1#*://}"; echo "/${p#*/}"; }

# Blocked by the guard, not by anything else: the fetch rejected, the server
# never saw it, and the session's request log says ERR_BLOCKED_BY_CLIENT.
assert_blocked() { # session method url [mode]
  srv_mark
  run fetch_from "$@"
  [ "$status" -eq 0 ] || fail "eval failed: $output"
  assert_contains "$output" '"rejected"'
  refute_sent "$2" "$(url_path "$3")"
  run "$LOOK" cli "$1" requests --all
  assert_contains "$output" "[$2] $3 => [FAILED] net::ERR_BLOCKED_BY_CLIENT"
}
assert_sent() { # session method url [mode]
  srv_mark
  run fetch_from "$@"
  [ "$status" -eq 0 ] || fail "eval failed: $output"
  assert_contains "$output" '"status '
  assert_reached "$2" "$(url_path "$3")"
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
  srv_mark
  run "$LOOK" open "$S" "$BASE/onload-post.html"
  [ "$status" -eq 0 ] || fail "$output"
  for i in $(seq 20); do
    run "$LOOK" cli "$S" requests --all
    case "$output" in *"/save => "*) break ;; esac
    sleep 0.25
  done
  assert_contains "$output" "[POST] $BASE/save => [FAILED] net::ERR_BLOCKED_BY_CLIENT"
  assert_reached GET /onload-post.html
  refute_sent POST /save
  refute_sent POST /beacon
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
  assert_blocked "$S" GET "$BASE/catalog?logout=1"
}

@test "a disposable host takes writes; another host still does not" {
  need_browser; need_server
  S="t$$-a"
  run "$LOOK" open "$S" "$BASE/index.html" --disposable "127.0.0.1:$LOOK_PORT"
  [ "$status" -eq 0 ] || fail "$output"
  assert_sent "$S" POST "$BASE/catalog"
  assert_sent "$S" DELETE "$BASE/catalog"
  assert_blocked "$S" POST "http://localhost:$LOOK_PORT/catalog" no-cors
  assert_blocked "$S" POST "http://127.0.0.10:$LOOK_PORT/catalog" no-cors
  assert_blocked "$S" GET "$BASE/logout"
}

@test "a disposable port takes writes; another server on the same host does not" {
  need_browser; need_server
  [ -n "${LOOK_PORT2-}" ] || skip "no second http.server here"
  A="t$$-a"; B="t$$-b"
  BASE2="http://127.0.0.1:$LOOK_PORT2"
  run "$LOOK" open "$A" "$BASE/index.html" --disposable "127.0.0.1:$LOOK_PORT"
  [ "$status" -eq 0 ] || fail "$output"
  assert_sent "$A" POST "$BASE/api/orders"
  LOOK_SRV_LOG="$LOOK_SRV2_LOG" assert_blocked "$A" POST "$BASE2/api/orders" no-cors
  # The control: the second server's own port does take them.
  run "$LOOK" open "$B" "$BASE/index.html" --disposable "127.0.0.1:$LOOK_PORT2"
  [ "$status" -eq 0 ] || fail "$output"
  LOOK_SRV_LOG="$LOOK_SRV2_LOG" assert_sent "$B" POST "$BASE2/api/orders" no-cors
  assert_blocked "$B" POST "$BASE/api/orders"
}

# ---- what look.sh cli passes on ------------------------------------------

@test "cli refuses commands outside its allowlist and runs none of them" {
  bin="$(sandbox_path bash env dirname mkdir cat sed grep ls true)"
  fake_cli "$bin"
  mkdir -p "$LOOK_HOME/t$$-n"
  for c in run-code open attach detach close-all kill-all install install-browser \
           route unroute route-list state-load state-save cookie-set cookie-clear \
           localstorage-set sessionstorage-clear delete-data network-state-set \
           webmcp-call list show config no-such-command; do
    PATH="$bin" LOOK_CLI="$bin/fakecli" run "$LOOK" cli "t$$-n" "$c" x
    [ "$status" -eq 2 ] || fail "$c: status $status: $output"
    assert_contains "$output" "'$c'"
  done
  [ ! -e "$FAKE_LOG" ]
}

@test "cli refuses session, config, browser and context flags anywhere in its arguments" {
  bin="$(sandbox_path bash env dirname mkdir cat sed grep ls true)"
  fake_cli "$bin"
  mkdir -p "$LOOK_HOME/t$$-n"
  while IFS='|' read -r a b c; do
    PATH="$bin" LOOK_CLI="$bin/fakecli" run "$LOOK" cli "t$$-n" "$a" "$b" "$c"
    [ "$status" -eq 2 ] || fail "$a $b $c: status $status: $output"
  done <<'EOF'
eval|-s=other|() => 1
eval|() => 1|--s=other
eval|() => 1|--no-session
eval|-session=x|() => 1
eval|() => 1|-s
eval|--session=other|() => 1
goto|--config=x.json|http://h.test/
goto|http://h.test/|--browser=firefox
goto|http://h.test/|--headed
goto|http://h.test/|--profile=/x
goto|http://h.test/|--persistent
tab-new|--isolated-context=x|http://h.test/
--raw|eval|() => 1
EOF
  [ ! -e "$FAKE_LOG" ]
}

@test "cli passes an allowed command on with this session, and close closes only it" {
  bin="$(sandbox_path bash env dirname mkdir cat sed grep ls true)"
  fake_cli "$bin"
  mkdir -p "$LOOK_HOME/t$$-n"
  PATH="$bin" LOOK_CLI="$bin/fakecli" run "$LOOK" cli "t$$-n" eval '() => 1' --raw
  [ "$status" -eq 0 ] || fail "$output"
  PATH="$bin" LOOK_CLI="$bin/fakecli" run "$LOOK" cli "t$$-n" requests --all
  [ "$status" -eq 0 ] || fail "$output"
  PATH="$bin" LOOK_CLI="$bin/fakecli" run "$LOOK" cli "t$$-n" fill e5 -sale
  [ "$status" -eq 0 ] || fail "$output"
  PATH="$bin" LOOK_CLI="$bin/fakecli" run "$LOOK" cli "t$$-n" close
  [ "$status" -eq 0 ] || fail "$output"
  assert_equal "$(cat "$FAKE_LOG")" "$(printf -- '-s=t%s-n eval () => 1 --raw\n-s=t%s-n requests --all\n-s=t%s-n fill e5 -sale\n-s=t%s-n close' $$ $$ $$ $$)"
  PATH="$bin" LOOK_CLI="$bin/fakecli" run "$LOOK" cli "t$$-n" close extra
  [ "$status" -eq 2 ]
}

@test "the two verified bypasses are refused and the guard stays in force" {
  need_browser; need_server
  S="t$$-a"
  run "$LOOK" open "$S" "$BASE/index.html"
  [ "$status" -eq 0 ] || fail "$output"
  run "$LOOK" cli "$S" run-code "async page => (await page.request.post('$BASE/catalog')).status()"
  [ "$status" -eq 2 ] || fail "run-code: $output"
  refute_contains "$output" 501
  run "$LOOK" cli "$S" open "$BASE/index.html"
  [ "$status" -eq 2 ] || fail "open: $output"
  run "$LOOK" cli "$S" tab-new --isolated-context=x "$BASE/index.html"
  [ "$status" -eq 2 ] || fail "tab-new: $output"
  run "$LOOK" cli "$S" eval "() => document.title"
  [ "$status" -eq 0 ] || fail "eval: $output"
  assert_contains "$output" '"Fixture"'
  assert_blocked "$S" POST "$BASE/catalog"
}

# ---- what escapes a page-level route -------------------------------------

# leave <session>: go away from leave.html four ways: goto, reload, a link
# click (with <a ping>) and go-back then goto. Each fires its pagehide writes.
leave_four_ways() {
  "$LOOK" cli "$1" goto "$BASE/index.html" >/dev/null
  "$LOOK" cli "$1" goto "$BASE/leave.html" >/dev/null
  "$LOOK" cli "$1" reload >/dev/null
  "$LOOK" cli "$1" click '#away' >/dev/null
  "$LOOK" cli "$1" go-back >/dev/null
  "$LOOK" cli "$1" goto "$BASE/index.html" >/dev/null
  sleep 1
}

@test "writes sent as a page goes away do not reach the server; on the disposable host they do" {
  need_browser; need_server
  A="t$$-a"; B="t$$-b"
  run "$LOOK" open "$A" "$BASE/leave.html"
  [ "$status" -eq 0 ] || fail "$output"
  srv_mark
  leave_four_ways "$A"
  assert_reached GET /index.html
  refute_sent POST /beacon-on-leave
  refute_sent POST /keepalive-on-leave
  refute_sent POST /ping-on-click
  # The control: with writes lifted, the same steps do reach the server.
  run "$LOOK" open "$B" "$BASE/leave.html" --disposable "127.0.0.1:$LOOK_PORT"
  [ "$status" -eq 0 ] || fail "$output"
  srv_mark
  leave_four_ways "$B"
  assert_reached POST /beacon-on-leave
  assert_reached POST /keepalive-on-leave
}

@test "a shared worker's and a dedicated worker's writes do not reach the server" {
  need_browser; need_server
  S="t$$-a"
  run "$LOOK" open "$S" "$BASE/index.html"
  [ "$status" -eq 0 ] || fail "$output"
  srv_mark
  run "$LOOK" cli "$S" eval "async () => new Promise(r => { const w = new SharedWorker('/shared-worker.js'); w.port.onmessage = e => r(e.data); w.port.start(); setTimeout(() => r('no answer'), 5000); })"
  assert_contains "$output" '"rejected"'
  run "$LOOK" cli "$S" eval "async () => new Promise(r => { const w = new Worker('/worker.js'); w.onmessage = e => r(e.data); setTimeout(() => r('no answer'), 5000); })"
  assert_contains "$output" '"rejected"'
  assert_reached GET /shared-worker.js
  refute_sent POST /from-shared-worker
  refute_sent POST /from-worker
}

@test "a submitted POST form does not reach the server" {
  need_browser; need_server
  S="t$$-a"
  run "$LOOK" open "$S" "$BASE/index.html"
  [ "$status" -eq 0 ] || fail "$output"
  srv_mark
  "$LOOK" cli "$S" eval "() => { const f = document.createElement('form'); f.method = 'post'; f.action = '/form-post'; document.body.append(f); setTimeout(() => f.submit(), 0); return 'submitting'; }" >/dev/null
  sleep 1
  run "$LOOK" cli "$S" requests --all
  assert_contains "$output" "[POST] $BASE/form-post => [FAILED] net::ERR_BLOCKED_BY_CLIENT"
  refute_sent POST /form-post
}

@test "a WebSocket is closed by the guard unless allowed or to the disposable host" {
  need_browser; need_server
  A="t$$-a"; B="t$$-b"
  srv_mark
  run "$LOOK" open "$A" "$BASE/websocket.html"
  [ "$status" -eq 0 ] || fail "$output"
  run "$LOOK" cli "$A" eval "async () => window.wsResult"
  assert_contains "$output" '"closed 4000 blocked by the look guard"'
  refute_sent GET /ws
  "$LOOK" close "$A"
  run "$LOOK" open "$B" "$BASE/websocket.html" --allow-websocket
  [ "$status" -eq 0 ] || fail "$output"
  run "$LOOK" cli "$B" eval "async () => window.wsResult"
  refute_contains "$output" 'blocked by the look guard'
  assert_reached GET /ws
  "$LOOK" close "$B"
  srv_mark
  run "$LOOK" open "$A" "$BASE/websocket.html" --disposable "127.0.0.1:$LOOK_PORT"
  [ "$status" -eq 0 ] || fail "$output"
  run "$LOOK" cli "$A" eval "async () => window.wsResult"
  refute_contains "$output" 'blocked by the look guard'
  assert_reached GET /ws
}

# --- checks and shots ---------------------------------------------------

# Height of a PNG, read from its IHDR with the standard library only.
png_height() { python3 -c 'import struct,sys; print(struct.unpack(">II", open(sys.argv[1],"rb").read(24)[16:24])[1])' "$1"; }

# The pixels of the outline colour (#e5484d) in a PNG: "count x0 y0 x1 y1"
# (count 0 and no box when there are none). Plain 8-bit RGB/RGBA, as Chromium
# writes; the stdlib decodes it.
png_marks() {
  python3 - "$1" <<'PY'
import sys, zlib, struct
d = open(sys.argv[1], "rb").read()
pos, idat, w, h, bpp = 8, b"", 0, 0, 0
while pos < len(d):
    n, t = struct.unpack(">I4s", d[pos:pos + 8])
    body = d[pos + 8:pos + 8 + n]
    if t == b"IHDR":
        w, h, depth, ctype = struct.unpack(">IIBB", body[:10])
        assert depth == 8 and ctype in (2, 6), "unexpected PNG format"
        bpp = 3 if ctype == 2 else 4
    elif t == b"IDAT":
        idat += body
    pos += 12 + n
raw, stride, prev = zlib.decompress(idat), w * bpp, bytearray(w * bpp)
count, x0, y0, x1, y1, o = 0, 10**9, 10**9, -1, -1, 0
for y in range(h):
    f = raw[o]; row = bytearray(raw[o + 1:o + 1 + stride]); o += 1 + stride
    for i in range(stride):
        a = row[i - bpp] if i >= bpp else 0
        b = prev[i]
        c = prev[i - bpp] if i >= bpp else 0
        if f == 1: row[i] = (row[i] + a) & 255
        elif f == 2: row[i] = (row[i] + b) & 255
        elif f == 3: row[i] = (row[i] + (a + b) // 2) & 255
        elif f == 4:
            p = a + b - c; pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
            row[i] = (row[i] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
    for x in range(w):
        if tuple(row[x * bpp:x * bpp + 3]) == (0xe5, 0x48, 0x4d):
            count += 1; x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y)
    prev = row
print(count, x0, y0, x1, y1) if count else print(0)
PY
}

# The JSON an eval returned, from the CLI's output.
eval_json() { sed -n '/^### Result/,/^### Ran/p' <<<"$1" | sed '1d;$d'; }

# Shoot hit N and assert the outline is in the PNG, around the element's box in
# the viewport as the page is after the shot: its pixels sit within 4 px of it.
assert_marked() { # session shot-name hit selector
  run "$LOOK" shot "$1" "$2" --hit "$3"
  [ "$status" -eq 0 ] || fail "$output"
  marks="$(png_marks "$LOOK_HOME/$1/shots/$2.png")"
  [ "$marks" != 0 ] || fail "no outline pixels in $2.png"
  run "$LOOK" cli "$1" eval "() => { const r = document.querySelector('$4').getBoundingClientRect(); return [r.left, r.top, r.right, r.bottom]; }"
  node -e '
    const m = process.argv[1].split(" ").map(Number).slice(1), r = JSON.parse(process.argv[2]);
    const ok = m[0] >= r[0] - 4 && m[1] >= r[1] - 4 && m[2] <= r[2] + 4 && m[3] <= r[3] + 4 && m[2] - m[0] > 10;
    if (!ok) { console.error("outline " + m + " is not around the element " + r); process.exit(1); }
  ' "$marks" "$(eval_json "$output" | tr -d '[:space:]')" || fail "outline is not around $4"
}

# Run checks on defects.html in the open session and require every data-defect
# element to have a hit of its kind and no box hit to be unexpected.
assert_seeded() { # session
  local S="$1"
  run "$LOOK" checks "$S"
  [ "$status" -eq 0 ] || fail "$output"
  hits="$output"
  [ -f "$LOOK_HOME/$S/checks.json" ]
  # Every element carrying data-defect, with its box in document coordinates.
  run "$LOOK" cli "$S" eval "() => [...document.querySelectorAll('[data-defect]')].map(e => { const r = e.getBoundingClientRect(); return {d: e.dataset.defect, x: r.left + scrollX, y: r.top + scrollY, w: r.width, h: r.height}; })"
  seeded="$(eval_json "$output")"
  run node -e '
    const hits = JSON.parse(process.argv[1]), seeded = JSON.parse(process.argv[2]);
    const inside = (b, s) => b.x >= s.x - 1 && b.y >= s.y - 1 && b.x + b.w <= s.x + s.w + 1 && b.y + b.h <= s.y + s.h + 1;
    const bad = [];
    if (seeded.length < 8) bad.push("only " + seeded.length + " seeded elements found");
    for (const s of seeded)
      if (!hits.some(k => k.check === s.d && k.box && inside(k.box, s))) bad.push("no " + s.d + " hit inside " + JSON.stringify(s));
    for (const k of hits)
      if (k.box && !seeded.some(s => s.d === k.check && inside(k.box, s))) bad.push("unexpected hit " + JSON.stringify(k));
    if (bad.length) { console.error(bad.join("\n")); process.exit(1); }
  ' "$hits" "$seeded"
  [ "$status" -eq 0 ] || fail "$output"
}

@test "checks find every seeded defect, and nothing the page did not seed" {
  need_browser; need_server
  S="t$$-a"
  run "$LOOK" open "$S" "$BASE/defects.html"
  [ "$status" -eq 0 ] || fail "$output"
  assert_seeded "$S"
}

@test "the seeded defects, icon-link rows included, are found at 800 px wide too" {
  need_browser; need_server
  S="t$$-a"
  run "$LOOK" open "$S" "$BASE/defects.html" --width 800
  [ "$status" -eq 0 ] || fail "$output"
  assert_seeded "$S"
}

@test "a field cropped by its padded card is one overflow hit, not one for the card too" {
  need_browser; need_server
  S="t$$-a"
  run "$LOOK" open "$S" "$BASE/defects.html"
  [ "$status" -eq 0 ] || fail "$output"
  run "$LOOK" checks "$S"
  [ "$status" -eq 0 ] || fail "$output"
  hits="$output"
  run "$LOOK" cli "$S" eval "() => { const r = document.querySelector('#pad-card').getBoundingClientRect(); return {x: r.left + scrollX, y: r.top + scrollY, w: r.width, h: r.height}; }"
  card="$(eval_json "$output")"
  run node -e '
    const hits = JSON.parse(process.argv[1]), c = JSON.parse(process.argv[2]);
    const meets = b => b.x < c.x + c.w && b.x + b.w > c.x && b.y < c.y + c.h && b.y + b.h > c.y;
    const n = hits.filter(k => k.check === "overflow" && k.box && meets(k.box));
    if (n.length !== 1) { console.error(n.length + " overflow hits on the card: " + JSON.stringify(n)); process.exit(1); }
  ' "$hits" "$card"
  [ "$status" -eq 0 ] || fail "$output"
}

@test "checks keep a guard-blocked write apart from a failed request and a console error" {
  need_browser; need_server
  S="t$$-a"
  run "$LOOK" open "$S" "$BASE/onload-post.html"
  [ "$status" -eq 0 ] || fail "$output"
  run "$LOOK" checks "$S"
  [ "$status" -eq 0 ] || fail "$output"
  assert_contains "$output" '"request-blocked"'
  assert_contains "$output" "POST $BASE/save"
  refute_contains "$output" '"request-failed"'
  refute_contains "$output" 'ERR_BLOCKED_BY_CLIENT.Inspector'
  # The blocked writes' own console errors are not console-error hits.
  node -e 'const h = JSON.parse(process.argv[1]); process.exit(h.some(k => k.check === "console-error" && /BLOCKED/.test(k.detail)) ? 1 : 0)' "$output"
}

@test "a clean page has no hits" {
  need_browser; need_server
  S="t$$-a"
  run "$LOOK" open "$S" "$BASE/clean.html"
  [ "$status" -eq 0 ] || fail "$output"
  run "$LOOK" checks "$S"
  [ "$status" -eq 0 ] || fail "$output"
  [ "$output" = "[]" ] || fail "$output"
}

@test "clean dark-scheme pages with default colours have no hits" {
  need_browser; need_server
  S="t$$-a"
  for page in clean-dark dark-root; do
    run "$LOOK" open "$S" "$BASE/$page.html" --scheme dark
    [ "$status" -eq 0 ] || fail "$output"
    run "$LOOK" checks "$S"
    [ "$status" -eq 0 ] || fail "$output"
    [ "$output" = "[]" ] || fail "$page: $output"
    "$LOOK" close "$S"
  done
}

@test "a page with 1,600 hits is checked in full, and the overlap cap is said aloud" {
  need_browser; need_server
  S="t$$-a"
  run "$LOOK" open "$S" "$BASE/many.html"
  [ "$status" -eq 0 ] || fail "$output"
  "$LOOK" checks "$S" >"$TEST_TMP/hits.json" 2>"$TEST_TMP/err.txt" || fail "$(cat "$TEST_TMP/err.txt")"
  assert_contains "$(cat "$TEST_TMP/err.txt")" "overlap compared only the first 1500"
  run node -e '
    const h = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    const n = h.filter(k => k.check === "small-target").length, lim = h.filter(k => k.check === "limit").length;
    if (n < 1600 || lim !== 1) { console.error("small-target " + n + ", limit notes " + lim); process.exit(1); }
  ' "$TEST_TMP/hits.json"
  [ "$status" -eq 0 ] || fail "$output"
}

@test "a hit below the fold gets a screenshot that shows it" {
  need_browser; need_server
  S="t$$-a"
  run "$LOOK" open "$S" "$BASE/below-fold.html" --width 800 --height 600
  [ "$status" -eq 0 ] || fail "$output"
  run "$LOOK" checks "$S"
  [ "$status" -eq 0 ] || fail "$output"
  assert_contains "$output" '"contrast"'
  run "$LOOK" shot "$S" low --hit 0
  [ "$status" -eq 0 ] || fail "$output"
  png="$LOOK_HOME/$S/shots/low.png"
  [ -f "$png" ]
  assert_contains "$output" "$png"
  [ "$(png_height "$png")" -eq 600 ]
  run "$LOOK" cli "$S" eval "() => document.querySelector('#low').getBoundingClientRect().top"
  top="$(eval_json "$output")"
  awk -v t="$top" 'BEGIN { exit !(t >= 0 && t < 600) }' || fail "top=$top"
  # The outline is gone again: nothing was left on the page.
  run "$LOOK" cli "$S" eval "() => document.documentElement.outerHTML.includes('e5484d') ? 'marked' : 'clean:' + document.body.children.length"
  assert_contains "$output" '"clean:2"'
  assert_marked "$S" low2 0 '#low'
}

@test "a smooth-scrolling page is shot where it landed, with the outline in the picture" {
  need_browser; need_server
  S="t$$-a"
  run "$LOOK" open "$S" "$BASE/smooth.html" --width 800 --height 600
  [ "$status" -eq 0 ] || fail "$output"
  "$LOOK" checks "$S" >/dev/null || fail "checks"
  assert_marked "$S" smooth 0 '#low'
}

@test "a hit inside an inner scroller is outlined where it is on screen" {
  need_browser; need_server
  S="t$$-a"
  run "$LOOK" open "$S" "$BASE/inner.html" --width 800 --height 600
  [ "$status" -eq 0 ] || fail "$output"
  run "$LOOK" checks "$S"
  [ "$status" -eq 0 ] || fail "$output"
  assert_contains "$output" '"contrast"'
  assert_marked "$S" inner 0 '#low'
}

@test "a hit under a sticky header is outlined where it is on screen" {
  need_browser; need_server
  S="t$$-a"
  run "$LOOK" open "$S" "$BASE/sticky.html" --width 800 --height 600
  [ "$status" -eq 0 ] || fail "$output"
  run "$LOOK" checks "$S"
  [ "$status" -eq 0 ] || fail "$output"
  assert_contains "$output" '"contrast"'
  assert_marked "$S" sticky 0 '#low'
}

@test "a full-page shot is taller than the viewport" {
  need_browser; need_server
  S="t$$-a"
  run "$LOOK" open "$S" "$BASE/below-fold.html" --width 800 --height 600
  [ "$status" -eq 0 ] || fail "$output"
  run "$LOOK" shot "$S" full --full
  [ "$status" -eq 0 ] || fail "$output"
  [ "$(png_height "$LOOK_HOME/$S/shots/full.png")" -gt 600 ]
}

@test "shot --hit says why when there is nothing to mark" {
  need_browser; need_server
  S="t$$-a"
  run "$LOOK" open "$S" "$BASE/below-fold.html"
  [ "$status" -eq 0 ] || fail "$output"
  run "$LOOK" shot "$S" x --hit 0
  [ "$status" -ne 0 ]
  assert_contains "$output" "checks"
  "$LOOK" checks "$S" >/dev/null
  run "$LOOK" shot "$S" x --hit 99
  [ "$status" -ne 0 ]
  assert_contains "$output" "out of range"
  run "$LOOK" shot "$S" "../x"
  [ "$status" -eq 2 ]
  # A hit with a box but no selector, and one with neither, each say what they are.
  cat > "$LOOK_HOME/$S/checks.json" <<'JSON'
[{"check":"overlap","selector":"","text":"","box":{"x":1,"y":1,"w":5,"h":5},"detail":""},
 {"check":"console-error","selector":"","text":"","box":null,"detail":"boom"}]
JSON
  run "$LOOK" shot "$S" x --hit 0
  [ "$status" -ne 0 ]
  assert_contains "$output" "no selector"
  refute_contains "$output" "console"
  run "$LOOK" shot "$S" x --hit 1
  [ "$status" -ne 0 ]
  assert_contains "$output" "no box"
}

@test "a file:// URL and a bare path both open, check and shoot a local file" {
  need_browser
  F="$REPO/tests/fixtures/look/clean.html"
  for target in "file://$F" "$F"; do
    S="t$$-a"
    run "$LOOK" open "$S" "$target"
    [ "$status" -eq 0 ] || fail "open $target: $output"
    grep -qF '"allowUnrestrictedFileAccess": true' "$LOOK_HOME/$S/.playwright/cli.config.json" \
      || fail "a file session lacks allowUnrestrictedFileAccess"
    run "$LOOK" checks "$S"
    [ "$status" -eq 0 ] || fail "$output"
    [ "$output" = "[]" ] || fail "$output"
    run "$LOOK" shot "$S" local
    [ "$status" -eq 0 ] || fail "$output"
    [ -s "$LOOK_HOME/$S/shots/local.png" ]
    "$LOOK" close "$S"
  done
}

@test "an http session's config does not carry the file-access key" {
  need_browser; need_server
  S="t$$-a"
  run "$LOOK" open "$S" "$BASE/clean.html"
  [ "$status" -eq 0 ] || fail "$output"
  ! grep -q allowUnrestrictedFileAccess "$LOOK_HOME/$S/.playwright/cli.config.json" \
    || fail "an http session may read local files"
}

@test "a missing /favicon.ico is not a console-error or request-failed hit" {
  need_browser; need_server
  S="t$$-a"
  run "$LOOK" open "$S" "$BASE/favicon.html"
  [ "$status" -eq 0 ] || fail "$output"
  run "$LOOK" checks "$S"
  [ "$status" -eq 0 ] || fail "$output"
  [ "$output" = "[]" ] || fail "$output"
}

@test "checks count an uncaught exception, an unhandled rejection and a logged error" {
  need_browser; need_server
  S="t$$-a"
  run "$LOOK" open "$S" "$BASE/errors.html"
  [ "$status" -eq 0 ] || fail "$output"
  sleep 0.5
  run "$LOOK" checks "$S"
  [ "$status" -eq 0 ] || fail "$output"
  run node -e '
    const h = JSON.parse(process.argv[1]).filter(k => k.check === "console-error");
    const want = ["boom-logged", "boom-rejected", "boom-uncaught"];
    const bad = want.filter(w => !h.some(k => k.detail.includes(w)));
    if (h.length !== 3 || bad.length) { console.error(h.length + " hits; missing " + bad); process.exit(1); }
  ' "$output"
  [ "$status" -eq 0 ] || fail "$output"
}

@test "checks say so when the CLI's error count is higher than the lines they recognise" {
  type -P node >/dev/null || skip "no node here"
  bin="$(sandbox_path bash env dirname mkdir rmdir sleep flock rm mv cat cp sed grep ls true node)"
  cat > "$bin/fakecli" <<'STUB'
#!/bin/sh
case "$*" in
  *run-code*url.gen.js*) printf '### Result\n"http://example.invalid/"\n' ;;
  *run-code*) printf '### Result\n[]\n' ;;
  *console\ error*) printf '### Result\nTotal messages: 2 (Errors: 2, Warnings: 0)\n\n  ERR some future format\n  ERR another\n' ;;
  *requests*) printf '### Result\n' ;;
esac
exit 0
STUB
  chmod +x "$bin/fakecli"
  mkdir -p "$LOOK_HOME/t$$-n"
  PATH="$bin" LOOK_BROWSER="$bin/true" LOOK_CLI="$bin/fakecli" run "$LOOK" checks "t$$-n"
  [ "$status" -eq 0 ] || fail "$output"
  assert_contains "$output" '"console-error"'
  assert_contains "$output" "2 console errors, 0 recognised"
  assert_contains "$output" "checks.console.txt"
}

@test "checks list only the requests since the current page's load" {
  need_browser; need_server
  S="t$$-a"
  run "$LOOK" open "$S" "$BASE/onload-post.html"
  [ "$status" -eq 0 ] || fail "$output"
  run "$LOOK" checks "$S"
  assert_contains "$output" '"request-blocked"'
  run "$LOOK" cli "$S" goto "$BASE/clean.html"
  [ "$status" -eq 0 ] || fail "$output"
  run "$LOOK" checks "$S"
  [ "$status" -eq 0 ] || fail "$output"
  [ "$output" = "[]" ] || fail "$output"
}

@test "every hit carries its page URL, and shot --hit refuses on another page" {
  need_browser; need_server
  S="t$$-a"
  run "$LOOK" open "$S" "$BASE/below-fold.html" --width 800 --height 600
  [ "$status" -eq 0 ] || fail "$output"
  run "$LOOK" checks "$S"
  [ "$status" -eq 0 ] || fail "$output"
  node -e 'const h = JSON.parse(process.argv[1]); process.exit(h.length && h.every(k => k.url === process.argv[2]) ? 0 : 1)' "$output" "$BASE/below-fold.html" \
    || fail "hits lack the page URL: $output"
  run "$LOOK" cli "$S" goto "$BASE/clean.html"
  [ "$status" -eq 0 ] || fail "$output"
  run "$LOOK" shot "$S" wrong --hit 0
  [ "$status" -ne 0 ]
  assert_contains "$output" "found on $BASE/below-fold.html"
  [ ! -e "$LOOK_HOME/$S/shots/wrong.png" ]
}

@test "a clean page's multi-line logs and warnings are not console-error hits" {
  need_browser; need_server
  S="t$$-a"
  run "$LOOK" open "$S" "$BASE/multiline-log.html"
  [ "$status" -eq 0 ] || fail "$output"
  sleep 0.3
  run "$LOOK" checks "$S"
  [ "$status" -eq 0 ] || fail "$output"
  [ "$output" = "[]" ] || fail "$output"
}
