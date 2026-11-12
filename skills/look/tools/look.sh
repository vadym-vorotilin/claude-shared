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
set -euo pipefail

LOOK_CLI_VERSION=0.1.24

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
    mkdir -p "$(dirname "$cache")"
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
      rm -rf "$cache"
      mv "$tmp" "$cache"
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
  browser="$(find_browser)"
  check_node
  cli="$(find_cli)"
  echo "cli=$cli browser=$browser"
}

valid_session() { [[ "${1-}" =~ ^[a-z0-9][a-z0-9-]{0,39}$ ]] || die "bad session name '${1-}': use a-z, 0-9, '-', at most 40 characters, not starting with '-'" 2; }
session_dir()   { echo "${LOOK_HOME:-${TMPDIR:-/tmp}/look}/$1"; }

# Task 2 fills this in: the network guard, installed before the first navigation.
# CONTRACT: return non-zero on ANY failure (check every step; do not rely on set -e,
# which is off in a function called from a tested context). A failure aborts the
# open before navigation and closes the session.
install_guard() {
  [ -z "${LOOK_TEST_GUARD_FAIL-}" ] || return 1  # test hook
  return 0
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

  local info cli browser dir
  info="$(cmd_setup)" || exit $?
  cli="${info#cli=}"; cli="${cli%% browser=*}"
  browser="${info##* browser=}"
  dir="$(session_dir "$session")"
  mkdir -p "$dir/.playwright"
  node -e '
    const [exe, w, h, scheme] = process.argv.slice(1);
    console.log(JSON.stringify({browser: {
      launchOptions: {executablePath: exe},
      contextOptions: {viewport: {width: +w, height: +h}, colorScheme: scheme}}}, null, 2));
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
