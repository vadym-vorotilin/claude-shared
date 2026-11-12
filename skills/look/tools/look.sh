#!/usr/bin/env bash
# look.sh — the one entry point for browser work: setup, one headless browser
# per named session, evidence kept in that session's own directory.
#
#   look.sh setup
#   look.sh open <session> <url> [--width N] [--height N] [--scheme light|dark]
#                [--disposable HOST] [--allow-post GLOB]... [--preset NAME]
#                [--allow-websocket]
#   look.sh cli <session> <command> [args...]   (allowlisted commands only)
#   look.sh checks <session>                    (JSON hits; writes checks.json)
#   look.sh shot <session> <name> [--full] [--hit N]
#   look.sh close <session>
#
# Env: LOOK_HOME (session dirs, default ${TMPDIR:-/tmp}/look), LOOK_BROWSER
# (browser binary), LOOK_CLI (an existing playwright-cli; skips the install).
# Exit: 0 ok, 2 usage, 3 a prerequisite is missing (the message says what).
# A session only ever closes itself; nothing here closes or kills others.
# Every session is read-only on the network: open installs guard.js before the
# first navigation (writes pass only per --allow-post/--preset, or on the one
# --disposable host). Presets are presets/<name>.json beside this script.
set -euo pipefail

LOOK_CLI_VERSION=0.1.24
LOOK_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# GET/HEAD/OPTIONS carrying one of these as a whole path segment or query value
# are blocked: a link that logs out or deletes is a write, whatever its method.
LOOK_DENY_GET_WORDS="logout delete remove destroy approve reject revoke unsubscribe"

# The playwright-cli commands `look.sh cli` passes on (checked against the
# 0.1.24 --help). An ALLOWLIST, not a denylist: the CLI is young and grows
# commands, and a denylist would let each new one through. Several known ones
# get around the guard: run-code is full Playwright (page.request never goes
# through the browser; it can detach the guard), a second open relaunches the
# browser unguarded, a CLI route would add a page-level route that lets
# leave-time beacons out, and tab-new --isolated-context makes a context the
# WebSocket route is not on. eval is allowed: it runs as page JavaScript, so
# its requests pass the guard like the page's own. `cli <s> close` is
# look.sh close. look.sh's own
# steps (the guard install, later checks and shots) call the CLI directly.
LOOK_CLI_ALLOWED=(
  goto go-back go-forward reload                                    # navigation
  click dblclick fill type press keydown keyup select check uncheck  # interaction
  hover drag drop upload mousemove mousedown mouseup mousewheel
  dialog-accept dialog-dismiss
  snapshot find eval console screenshot pdf                         # looking
  requests request request-headers request-body response-headers response-body
  tab-list tab-new tab-select tab-close resize                      # tabs, window
)
# Options that would pick another session, config, browser, profile or
# context. The CLI parses its arguments like minimist, so each is refused
# anywhere in a cli call with one dash or two, alone, as name=value or as
# --no-name (--s=other makes a second session value). Other words starting
# with "-" are left alone; the CLI rejects the ones it does not know.
LOOK_CLI_REFUSED_OPTIONS="s|session|config|browser|device|mobile|headed|persistent|profile|idle-timeout|isolated-context"

die()  { echo "look: $1" >&2; exit "${2:-1}"; }
need() { echo "look: $*" >&2; exit 3; }

find_browser() {
  if [ -n "${LOOK_BROWSER-}" ]; then
    command -v "$LOOK_BROWSER" 2>/dev/null && return 0
    need "LOOK_BROWSER=$LOOK_BROWSER is not an executable; install chromium or point LOOK_BROWSER at a browser"
  fi
  local b
  for b in chromium chromium-browser google-chrome google-chrome-stable; do
    command -v "$b" 2>/dev/null && return 0
  done
  need "no browser found; install chromium (or chromium-browser, google-chrome) or set LOOK_BROWSER. look never downloads one."
}

find_cli() {
  if [ -n "${LOOK_CLI-}" ]; then
    [ -x "$LOOK_CLI" ] || need "LOOK_CLI=$LOOK_CLI is not executable"
    echo "$LOOK_CLI"; return 0
  fi
  local cache="${XDG_CACHE_HOME:-$HOME/.cache}/claude-look/cli-$LOOK_CLI_VERSION"
  local bin="$cache/node_modules/.bin/playwright-cli"
  if [ ! -x "$bin" ]; then
    command -v npm >/dev/null 2>&1 || need "npm not found; install Node.js 18 or newer"
    mkdir -p "$(dirname "$cache")" || need "cannot create $(dirname "$cache")"
    # One installer at a time; a late arrival finds the finished cache. flock when
    # present, else a mkdir lock; both wait at most 300 s. A stale mkdir lock from
    # a crashed install is named in the error so it can be removed by hand.
    local lockdir=""
    if command -v flock >/dev/null 2>&1; then
      exec 9>"$cache.lock"
      flock -w 300 9 || need "timed out waiting for another install (lock $cache.lock)"
    else
      lockdir="$cache.lock.d"
      local waited=0
      until mkdir "$lockdir" 2>/dev/null; do
        [ "$waited" -lt 300 ] || need "timed out waiting for another install; remove $lockdir if none is running"
        sleep 1; waited=$((waited + 1))
      done
    fi
    if [ ! -x "$bin" ]; then
      local tmp="$cache.tmp.$$"
      echo "look: installing @playwright/cli@$LOOK_CLI_VERSION into $cache (once; not global)" >&2
      rm -rf "$tmp"
      if ! npm install --silent --no-audit --no-fund --prefix "$tmp" "@playwright/cli@$LOOK_CLI_VERSION" >&2 \
         || [ ! -x "$tmp/node_modules/.bin/playwright-cli" ]; then
        rm -rf "$tmp"
        [ -z "$lockdir" ] || rmdir "$lockdir" 2>/dev/null || true
        need "npm install of @playwright/cli@$LOOK_CLI_VERSION failed"
      fi
      rm -rf "$cache" || need "cannot replace $cache"
      mv "$tmp" "$cache" || need "cannot move the install into $cache"
    fi
    [ -z "$lockdir" ] || rmdir "$lockdir" 2>/dev/null || true
  fi
  echo "$bin"
}

check_node() {
  command -v node >/dev/null 2>&1 || need "node not found; install Node.js 18 or newer"
  local major; major="$(node -p 'process.versions.node.split(".")[0]')"
  [ "$major" -ge 18 ] || need "Node.js $major is too old; install Node.js 18 or newer"
}

cmd_setup() {
  local browser cli
  # Explicit exits: errexit is off inside $(...) and the || lists below.
  browser="$(find_browser)" || exit $?
  check_node || exit $?
  cli="$(find_cli)" || exit $?
  echo "cli=$cli browser=$browser"
}

valid_session() { [[ "${1-}" =~ ^[a-z0-9][a-z0-9-]{0,39}$ ]] || die "bad session name '${1-}': use a-z, 0-9, '-', at most 40 characters, not starting with '-'" 2; }
session_dir()   { echo "${LOOK_HOME:-${TMPDIR:-/tmp}/look}/$1"; }

# The network guard (guard.js; its header has the rules), installed before the
# first navigation. Run from the session directory. guard.gen.js is guard.js
# with its placeholder replaced by this session's config.
# CONTRACT: return non-zero on ANY failure (check every step; do not rely on set -e,
# which is off in a function called from a tested context). A failure aborts the
# open before navigation and closes the session.
install_guard() { # session cli disposable preset allow-websocket [allow-post...]
  [ -z "${LOOK_TEST_GUARD_FAIL-}" ] || return 1  # test hook
  local session="$1" cli="$2" disposable="$3" preset="$4" allow_websocket="$5" preset_file="" out
  shift 5
  if [ -n "$preset" ]; then
    preset_file="$(preset_path "$preset")" || return 1
  fi
  node -e '
    const fs = require("fs");
    const [tmpl, out, disposable, allowWebsocket, presetFile, words, ...allow] = process.argv.slice(1);
    let allowPost = allow;
    if (presetFile) {
      const p = JSON.parse(fs.readFileSync(presetFile, "utf8"));
      const keys = Object.keys(p);
      if (keys.length !== 1 || keys[0] !== "allowPost" || !Array.isArray(p.allowPost) ||
          !p.allowPost.every(g => typeof g === "string" && g !== ""))
        throw new Error(presetFile + ": a preset is {\"allowPost\": [glob, ...]} and nothing else");
      allowPost = p.allowPost.concat(allow);
    }
    const config = {allowPost, denyGetWords: words.split(" "), disposableHost: disposable || null,
                    allowWebsocket: allowWebsocket === "true"};
    const parts = fs.readFileSync(tmpl, "utf8").split("/*GUARD_CONFIG*/");
    if (parts.length !== 2) throw new Error(tmpl + ": expected exactly one config placeholder");
    fs.writeFileSync(out, parts.join(JSON.stringify(config)));
  ' "$LOOK_DIR/guard.js" guard.gen.js "$disposable" "$allow_websocket" "$preset_file" "$LOOK_DENY_GET_WORDS" "$@" || return 1
  out="$("$cli" -s="$session" run-code --filename=guard.gen.js 2>&1)" || { printf '%s\n' "$out" >&2; return 1; }
  # The guard returns this only after its interception is on. A here-string,
  # not a pipe: grep -q stops at the match, and under pipefail the writer's
  # SIGPIPE on the long echoed source would read as "not confirmed".
  grep -qxF '"look-guard-on"' <<<"$out" \
    || { printf 'look: the network guard did not confirm it is on; the CLI said:\n%s\n' "$out" >&2; return 1; }
}

# presets/<name>.json beside this script; an unknown name is an error, never "no preset".
preset_path() { # name
  local f="$LOOK_DIR/presets/$1.json"
  if [[ ! "$1" =~ ^[a-z0-9][a-z0-9-]*$ ]] || [ ! -f "$f" ]; then
    local have="" p
    for p in "$LOOK_DIR"/presets/*.json; do
      [ -e "$p" ] || continue
      p="${p##*/}"; have+="${have:+, }${p%.json}"
    done
    echo "look: unknown preset '$1' (have: ${have:-none})" >&2
    return 1
  fi
  echo "$f"
}

# The steps after the session dir exists. Every step is checked explicitly.
open_steps() { # dir session cli url disposable preset allow-websocket [allow-post...]
  local dir="$1" session="$2" cli="$3" url="$4" disposable="$5" preset="$6" allow_websocket="$7"
  shift 7
  cd "$dir" || return 1
  "$cli" -s="$session" open about:blank >/dev/null || return 1
  install_guard "$session" "$cli" "$disposable" "$preset" "$allow_websocket" "$@" || return 1
  "$cli" -s="$session" goto "$url" >/dev/null || return 1
}

cmd_open() {
  local session="${1-}" url="${2-}"
  [ $# -ge 2 ] || die "usage: look.sh open <session> <url> [options]" 2
  shift 2
  valid_session "$session"
  local width=1280 height=800 scheme=light disposable="" preset="" allow_post=() allow_websocket=false
  while [ $# -gt 0 ]; do
    # The one option without a value: WebSocket messages may write, and
    # nothing inspects them, so connections are off unless asked for.
    if [ "$1" = --allow-websocket ]; then allow_websocket=true; shift; continue; fi
    case "$1" in
      --width|--height|--scheme|--disposable|--allow-post|--preset)
        [ $# -ge 2 ] || die "$1 needs a value" 2 ;;
    esac
    case "$1" in
      --width) width="$2" ;;
      --height) height="$2" ;;
      --scheme) scheme="$2" ;;
      --disposable) disposable="$2" ;;
      --allow-post) allow_post+=("$2") ;;
      --preset) preset="$2" ;;
      *) die "unknown option $1" 2 ;;
    esac
    shift 2
  done
  [[ "$width" =~ ^[0-9]+$ && "$height" =~ ^[0-9]+$ ]] || die "--width and --height must be numbers" 2
  case "$scheme" in light|dark) ;; *) die "--scheme must be light or dark" 2 ;; esac
  # A bare host name or IP, compared with URL.hostname on any port: no scheme,
  # port, path or wildcard, so what is lifted is exactly one host.
  if [ -n "$disposable" ]; then
    [[ "$disposable" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ || "$disposable" =~ ^\[[0-9A-Fa-f:.]+\]$ ]] \
      || die "--disposable takes a bare host name such as 127.0.0.1 or dev.example.test, not '$disposable'" 2
    disposable="${disposable,,}"
  fi
  if [ -n "$preset" ]; then preset_path "$preset" >/dev/null || exit 2; fi

  local cli browser dir
  browser="$(find_browser)" || exit $?
  check_node || exit $?
  if [ -n "$disposable" ]; then
    # The form URL.hostname gives, the one the guard compares (127.1 is 127.0.0.1).
    local canonical
    canonical="$(node -e 'console.log(new URL("http://" + process.argv[1]).hostname)' "$disposable" 2>/dev/null)" \
      || die "--disposable '$disposable' is not a host name" 2
    [ "$canonical" = "$disposable" ] || echo "look: --disposable $disposable is $canonical" >&2
    disposable="$canonical"
  fi
  cli="$(find_cli)" || exit $?
  dir="$(session_dir "$session")"
  mkdir -p "$dir/.playwright"
  node -e '
    const [exe, w, h, scheme] = process.argv.slice(1);
    console.log(JSON.stringify({browser: {
      launchOptions: {executablePath: exe},
      // A service worker could answer for the network, so none may register.
      contextOptions: {viewport: {width: +w, height: +h}, colorScheme: scheme,
                       serviceWorkers: "block"}}}, null, 2));
  ' "$browser" "$width" "$height" "$scheme" > "$dir/.playwright/cli.config.json"

  # After the browser is up, any failure closes this session (only this one).
  if ! ( open_steps "$dir" "$session" "$cli" "$url" "$disposable" "$preset" "$allow_websocket" "${allow_post[@]+"${allow_post[@]}"}" ); then
    ( cd "$dir" && "$cli" -s="$session" close >/dev/null 2>&1 ) || true
    die "could not open $url in session '$session'"
  fi
  echo "$dir"
}

cmd_cli() {
  local session="${1-}"
  [ $# -ge 2 ] || die "usage: look.sh cli <session> <playwright-cli args...>" 2
  shift
  valid_session "$session"
  # The command must come first: a flag before it could take the next word as
  # its value and leave the CLI running a different command than checked here.
  local command="$1" a
  if [ "$command" = close ]; then
    [ $# -eq 1 ] || die "usage: look.sh cli <session> close (no arguments)" 2
    cmd_close "$session"; return
  fi
  local allowed=" ${LOOK_CLI_ALLOWED[*]} "
  [[ "$command" != *" "* && "$allowed" == *" $command "* ]] \
    || die "cli does not pass on '$command': it is not on look.sh's allowlist (LOOK_CLI_ALLOWED), which keeps the network guard in force" 2
  for a in "$@"; do
    [[ ! "$a" =~ ^--?(no-)?($LOOK_CLI_REFUSED_OPTIONS)(=|$) ]] \
      || die "cli refuses '$a': it would change the session, browser or context the guard is on" 2
  done
  local dir; dir="$(session_dir "$session")"
  [ -d "$dir" ] || die "no session '$session'; run look.sh open first" 2
  local cli; cli="$(find_cli)"
  cd "$dir"
  exec "$cli" -s="$session" "$@"
}

# The text between "### Result" and the next "### " heading of a run-code
# call's output: what the page function returned, as JSON. Fails on none.
run_result() { # output
  node -e '
    const t = process.argv[1], a = t.indexOf("### Result\n");
    if (a < 0) process.exit(1);
    let b = t.indexOf("\n### ", a + 11);
    if (b < 0) b = t.length;
    process.stdout.write(t.slice(a + 11, b).trim());
  ' "$1"
}

# Runs a generated script with run-code from the session directory, prints the
# JSON it returned. Any failure of the CLI or of the script is non-zero.
run_script() { # session cli script-file
  local out
  out="$("$2" -s="$1" run-code --filename="$3" 2>&1)" || { printf '%s\n' "$out" >&2; return 1; }
  if grep -qF '### Error' <<<"$out"; then printf '%s\n' "$out" >&2; return 1; fi
  run_result "$out" || { printf 'look: the CLI returned no result; it said:\n%s\n' "$out" >&2; return 1; }
}

# The session's dir and CLI, for the commands that look at a page.
session_env() { # session -> sets dir, cli
  valid_session "$1"
  dir="$(session_dir "$1")"
  [ -d "$dir" ] || die "no session '$1'; run look.sh open first" 2
  cli="$(find_cli)" || exit $?
}

cmd_checks() {
  [ $# -eq 1 ] || die "usage: look.sh checks <session>" 2
  local dir cli session="$1" page console requests
  session_env "$session"
  cd "$dir"
  cp "$LOOK_DIR/checks.js" checks.gen.js || die "cannot write in $dir"
  page="$(run_script "$session" "$cli" checks.gen.js)" || die "the page checks did not run"
  console="$("$cli" -s="$session" console 2>&1)" || die "cannot read the console: $console"
  requests="$("$cli" -s="$session" requests --all --static 2>&1)" || die "cannot read the requests: $requests"
  # console-error: console lines the guard did not cause. A request the guard
  # blocked is a request-blocked hit (and its console error is dropped), so a
  # caller can tell a broken page from a write the guard stopped. A request
  # that failed otherwise is request-failed.
  node -e '
    const fs = require("fs");
    const [pageJson, consoleOut, requestsOut] = process.argv.slice(1);
    const hits = JSON.parse(pageJson);
    const extra = (check, detail) => ({check, selector: "", text: "", box: null, detail});
    const BLOCKED = /ERR_BLOCKED_BY_CLIENT/;
    for (const line of consoleOut.split("\n")) {
      const m = /^\[ERROR\] (.*)$/.exec(line);
      if (m && !BLOCKED.test(m[1])) hits.push(extra("console-error", m[1]));
    }
    for (const line of requestsOut.split("\n")) {
      const m = /^\d+\. \[([A-Z]+)\] (\S+) => \[FAILED\] (.*)$/.exec(line);
      if (!m) continue;
      hits.push(BLOCKED.test(m[3])
        ? extra("request-blocked", m[1] + " " + m[2] + " (blocked by the look guard)")
        : extra("request-failed", m[1] + " " + m[2] + " " + m[3]));
    }
    fs.writeFileSync("checks.json", JSON.stringify(hits, null, 2) + "\n");
    process.stdout.write(JSON.stringify(hits) + "\n");
  ' "$page" "$console" "$requests"
}

cmd_shot() {
  [ $# -ge 2 ] || die "usage: look.sh shot <session> <name> [--full] [--hit N]" 2
  local session="$1" name="$2" full=false hit="" dir cli
  shift 2
  while [ $# -gt 0 ]; do
    case "$1" in
      --full) full=true; shift ;;
      --hit) [ $# -ge 2 ] || die "--hit needs a number" 2; hit="$2"; shift 2 ;;
      *) die "unknown option $1" 2 ;;
    esac
  done
  [[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,60}$ ]] || die "bad shot name '$name': letters, digits, '.', '_', '-'" 2
  [[ -z "$hit" || "$hit" =~ ^[0-9]+$ ]] || die "--hit takes a hit number from checks" 2
  [ -z "$hit" ] || ! $full || die "--full and --hit do not combine: a marked shot is of the viewport" 2
  session_env "$session"
  local target="" box=""
  if [ -n "$hit" ]; then
    [ -f "$dir/checks.json" ] || die "no $dir/checks.json; run look.sh checks $session first" 2
    local picked
    picked="$(node -e '
      const hits = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")), n = +process.argv[2];
      if (n >= hits.length) { console.error("hit " + n + " is out of range: the last checks run found " + hits.length); process.exit(2); }
      const h = hits[n];
      if (!h.box || !h.selector) { console.error("hit " + n + " (" + h.check + ") has no box to mark: it came from the console or the network log"); process.exit(2); }
      console.log(JSON.stringify({selector: h.selector, box: h.box}));
    ' "$dir/checks.json" "$hit" 2>&1)" || die "$picked" 2
    target="$picked"
  fi
  mkdir -p "$dir/shots"
  cd "$dir"
  # The shot script runs in the page's browser: with a hit it checks the
  # selector resolves to one element, scrolls it into view, draws the outline
  # as a fixed overlay (not clipped by an ancestor), takes the viewport shot and
  # removes the overlay again, whatever happens.
  node -e '
    const [file, out, full, target] = process.argv.slice(1);
    const t = target ? JSON.parse(target) : null;
    const src = `async page => {
      const out = ${JSON.stringify(out)}, full = ${full}, t = ${JSON.stringify(t)};
      if (!t) { await page.screenshot({path: out, fullPage: full}); return "look-shot-ok"; }
      const found = await page.evaluate(sel => {
        const els = document.querySelectorAll(sel);
        if (els.length !== 1) return els.length;
        els[0].scrollIntoView({block: "center", inline: "center"});
        return 1;
      }, t.selector);
      if (found !== 1) return "look-shot-error: " + t.selector + " matches " + found + " elements now; run checks again";
      const mark = await page.evaluate(box => {
        const d = document.createElement("div");
        d.setAttribute("data-look-mark", "");
        // The hit box is in document coordinates; the page is scrolled now.
        d.style.cssText = "position:fixed;z-index:2147483647;pointer-events:none;box-sizing:border-box;" +
          "border:2px solid #e5484d;left:" + (box.x - scrollX - 2) + "px;top:" + (box.y - scrollY - 2) + "px;" +
          "width:" + (box.w + 4) + "px;height:" + (box.h + 4) + "px";
        document.documentElement.appendChild(d);
        return true;
      }, t.box);
      try { await page.screenshot({path: out}); }
      finally { await page.evaluate(() => document.querySelectorAll("[data-look-mark]").forEach(n => n.remove())); }
      return "look-shot-ok";
    }`;
    require("fs").writeFileSync(file, src);
  ' shot.gen.js "$dir/shots/$name.png" "$full" "$target" || die "cannot write the shot script"
  local res
  res="$(run_script "$session" "$cli" shot.gen.js)" || die "the screenshot failed"
  [ "$res" = '"look-shot-ok"' ] || die "${res//\"/}"
  [ -s "$dir/shots/$name.png" ] || die "no screenshot was written"
  echo "$dir/shots/$name.png"
}

cmd_close() {
  local session="${1-}"
  [ $# -eq 1 ] || die "usage: look.sh close <session>" 2
  valid_session "$session"
  local dir; dir="$(session_dir "$session")"
  [ -d "$dir" ] || die "no session '$session'" 2
  local cli; cli="$(find_cli)"
  cd "$dir"
  "$cli" -s="$session" close >/dev/null
}

case "${1-}" in
  setup) shift; cmd_setup "$@" ;;
  open)  shift; cmd_open "$@" ;;
  cli)   shift; cmd_cli "$@" ;;
  checks) shift; cmd_checks "$@" ;;
  shot)  shift; cmd_shot "$@" ;;
  close) shift; cmd_close "$@" ;;
  *) die "usage: look.sh setup | open | cli | checks | shot | close" 2 ;;
esac
