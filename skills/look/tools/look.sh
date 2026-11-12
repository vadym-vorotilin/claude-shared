#!/usr/bin/env bash
# look.sh — the one entry point for browser work: setup, one headless browser
# per named session, evidence kept in that session's own directory.
#
#   look.sh setup
#   look.sh open <session> <url> [--width N] [--height N] [--scheme light|dark]
#                [--disposable HOST] [--allow-post GLOB]... [--preset NAME]
#   look.sh cli <session> <playwright-cli args...>
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
install_guard() { # session cli disposable preset [allow-post...]
  [ -z "${LOOK_TEST_GUARD_FAIL-}" ] || return 1  # test hook
  local session="$1" cli="$2" disposable="$3" preset="$4" preset_file="" out
  shift 4
  if [ -n "$preset" ]; then
    preset_file="$(preset_path "$preset")" || return 1
  fi
  node -e '
    const fs = require("fs");
    const [tmpl, out, disposable, presetFile, words, ...allow] = process.argv.slice(1);
    let allowPost = allow;
    if (presetFile) {
      const p = JSON.parse(fs.readFileSync(presetFile, "utf8"));
      const keys = Object.keys(p);
      if (keys.length !== 1 || keys[0] !== "allowPost" || !Array.isArray(p.allowPost) ||
          !p.allowPost.every(g => typeof g === "string" && g !== ""))
        throw new Error(presetFile + ": a preset is {\"allowPost\": [glob, ...]} and nothing else");
      allowPost = p.allowPost.concat(allow);
    }
    const config = {allowPost, denyGetWords: words.split(" "), disposableHost: disposable || null};
    const parts = fs.readFileSync(tmpl, "utf8").split("/*GUARD_CONFIG*/");
    if (parts.length !== 2) throw new Error(tmpl + ": expected exactly one config placeholder");
    fs.writeFileSync(out, parts.join(JSON.stringify(config)));
  ' "$LOOK_DIR/guard.js" guard.gen.js "$disposable" "$preset_file" "$LOOK_DENY_GET_WORDS" "$@" || return 1
  out="$("$cli" -s="$session" run-code --filename=guard.gen.js 2>&1)" || { printf '%s\n' "$out" >&2; return 1; }
  # The guard returns this only after its route is installed.
  printf '%s\n' "$out" | grep -qxF '"look-guard-on"' \
    || { echo "look: the network guard did not confirm it is on" >&2; return 1; }
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
open_steps() { # dir session cli url disposable preset [allow-post...]
  local dir="$1" session="$2" cli="$3" url="$4" disposable="$5" preset="$6"
  shift 6
  cd "$dir" || return 1
  "$cli" -s="$session" open about:blank >/dev/null || return 1
  install_guard "$session" "$cli" "$disposable" "$preset" "$@" || return 1
  "$cli" -s="$session" goto "$url" >/dev/null || return 1
}

cmd_open() {
  local session="${1-}" url="${2-}"
  [ $# -ge 2 ] || die "usage: look.sh open <session> <url> [options]" 2
  shift 2
  valid_session "$session"
  local width=1280 height=800 scheme=light disposable="" preset="" allow_post=()
  while [ $# -gt 0 ]; do
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
  cli="$(find_cli)" || exit $?
  dir="$(session_dir "$session")"
  mkdir -p "$dir/.playwright"
  node -e '
    const [exe, w, h, scheme] = process.argv.slice(1);
    console.log(JSON.stringify({browser: {
      launchOptions: {executablePath: exe},
      // Routes do not see requests a service worker makes, so none may register.
      contextOptions: {viewport: {width: +w, height: +h}, colorScheme: scheme,
                       serviceWorkers: "block"}}}, null, 2));
  ' "$browser" "$width" "$height" "$scheme" > "$dir/.playwright/cli.config.json"

  # After the browser is up, any failure closes this session (only this one).
  if ! ( open_steps "$dir" "$session" "$cli" "$url" "$disposable" "$preset" "${allow_post[@]+"${allow_post[@]}"}" ); then
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
  local dir; dir="$(session_dir "$session")"
  [ -d "$dir" ] || die "no session '$session'; run look.sh open first" 2
  local cli; cli="$(find_cli)"
  cd "$dir"
  exec "$cli" -s="$session" "$@"
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
  close) shift; cmd_close "$@" ;;
  *) die "usage: look.sh setup | open | cli | close" 2 ;;
esac
