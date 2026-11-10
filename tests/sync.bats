#!/usr/bin/env bats
#
# sync.sh — deploys shared config into a sandbox $HOME/.claude.
# Covers its features plus the edge cases where it must not destroy user data.

load 'helpers/setup'

setup()    { common_setup; }
teardown() {
  # A sync started in the background by a test that failed before reaping it.
  # Only that pid is signalled; it is still our unreaped child, so it cannot
  # have been reused.
  if [ -n "${SYNC_PID:-}" ]; then kill -KILL "$SYNC_PID" 2>/dev/null || true; fi
  common_teardown
}

run_sync() { run bash "$REPO/sync.sh"; }

# ------------------------------------------------------------- FEATURES ----

@test "creates settings.json from the shared template when none exists" {
  run_sync
  assert_equal "$status" 0
  assert_file_exists "$HOME/.claude/settings.json"
  assert_equal "$(jq -r .model "$HOME/.claude/settings.json")" opus
}

@test "merge preserves local-only keys and overrides shared keys" {
  mkdir -p "$HOME/.claude"
  echo '{"model":"sonnet","permissions":{"allow":["Bash(ls)"]}}' > "$HOME/.claude/settings.json"
  run_sync
  assert_equal "$status" 0
  # shared key wins:
  assert_equal "$(jq -r .model "$HOME/.claude/settings.json")" opus
  # local-only key survives:
  assert_equal "$(jq -r '.permissions.allow[0]' "$HOME/.claude/settings.json")" "Bash(ls)"
}

@test "deploys both status line scripts, the helpers they source and the progress writer" {
  run_sync
  for f in statusline-command.sh subagent-statusline-command.sh statusline-lib.sh statusline-progress.sh statusline-progress-hook.sh; do
    assert_file_exists "$HOME/.claude/$f"
    assert_executable "$HOME/.claude/$f"
  done
}

@test "adds the progress hook once, keeping PostToolUse hooks already there" {
  mkdir -p "$HOME/.claude"
  echo '{"hooks":{"PostToolUse":[{"matcher":"Edit","hooks":[{"type":"command","command":"mine.sh"}]}]}}' \
    > "$HOME/.claude/settings.json"
  run_sync; run_sync
  assert_equal "$status" 0
  s="$HOME/.claude/settings.json"
  assert_equal "$(jq -r '.hooks.PostToolUse[0].hooks[0].command' "$s")" "mine.sh"
  assert_equal "$(jq '[.hooks.PostToolUse[].hooks[] | select(.command == "bash ~/.claude/statusline-progress-hook.sh")] | length' "$s")" 1
  assert_equal "$(jq -r '.hooks.PostToolUse[] | select(.hooks[0].command | test("progress-hook")) | .matcher' "$s")" Bash
}

# The scripts source the lib from their own directory, so a deployed copy must
# run from ~/.claude without the repo.
@test "the deployed status line runs from ~/.claude" {
  run_sync
  out="$(printf '%s' '{"cwd":"/tmp","model":{"display_name":"M"}}' | bash "$HOME/.claude/statusline-command.sh")"
  assert_contains "$out" "M"
  refute_contains "$out" "No such file"
}

@test "symlinks every shared skill into ~/.claude/skills" {
  run_sync
  for d in "$REPO"/skills/*/; do
    name="$(basename "$d")"
    assert_symlink "$HOME/.claude/skills/$name"
  done
}

@test "records the repo location marker" {
  run_sync
  assert_file_exists "$HOME/.claude/claude-shared-repo"
  assert_equal "$(cat "$HOME/.claude/claude-shared-repo")" "$REPO"
}

@test "appends the managed block to a CLAUDE.md, preserving prior content" {
  mkdir -p "$HOME/.claude"
  printf 'MY PERSONAL NOTES\n' > "$HOME/.claude/CLAUDE.md"
  run_sync
  body="$(cat "$HOME/.claude/CLAUDE.md")"
  assert_contains "$body" "MY PERSONAL NOTES"
  assert_contains "$body" "Shared Claude setup"
  assert_equal "$(count_occurrences "$HOME/.claude/CLAUDE.md" '>>> claude-shared')" 1
}

@test "re-running is idempotent: managed block replaced, not duplicated" {
  run_sync
  run_sync
  assert_equal "$(count_occurrences "$HOME/.claude/CLAUDE.md" '>>> claude-shared')" 1
}

@test "replace preserves content above and below the managed block" {
  run_sync                                   # writes the first managed block
  printf 'TOP LINE\n' | cat - "$HOME/.claude/CLAUDE.md" > "$HOME/.claude/CLAUDE.md.x"
  printf 'BOTTOM LINE\n' >> "$HOME/.claude/CLAUDE.md.x"
  mv "$HOME/.claude/CLAUDE.md.x" "$HOME/.claude/CLAUDE.md"
  run_sync                                   # replace path (both markers present)
  body="$(cat "$HOME/.claude/CLAUDE.md")"
  assert_contains "$body" "TOP LINE"
  assert_contains "$body" "BOTTOM LINE"
  assert_equal "$(count_occurrences "$HOME/.claude/CLAUDE.md" '>>> claude-shared')" 1
}

# ----------------------------------------------------------- EDGE CASES ----

MD_START='<!-- >>> claude-shared (managed by claude-shared/sync.sh — edit the snippet, not here) >>> -->'
MD_END='<!-- <<< claude-shared <<< -->'

# Write a CLAUDE.md from the given lines, run sync.sh twice, and require that
# it fails with the marker error and leaves the file byte-for-byte unchanged.
assert_malformed_untouched() {
  mkdir -p "$HOME/.claude"
  printf '%s\n' "$@" > "$HOME/.claude/CLAUDE.md"
  cp "$HOME/.claude/CLAUDE.md" "$TEST_TMP/before"
  for _ in 1 2; do
    run_sync
    assert_equal "$status" 1
    assert_contains "$output" "malformed claude-shared markers"
    assert_contains "$output" "$HOME/.claude/CLAUDE.md"
    assert_contains "$output" "by hand"
    cmp "$HOME/.claude/CLAUDE.md" "$TEST_TMP/before" || fail "CLAUDE.md was modified"
  done
}

@test "markers: START only is an error and leaves CLAUDE.md unchanged" {
  assert_malformed_untouched 'TOP' "$MD_START" 'stale' 'PRESERVE THIS LINE'
}

@test "markers: END only is an error and leaves CLAUDE.md unchanged" {
  assert_malformed_untouched 'TOP' 'middle' "$MD_END" 'PRESERVE THIS LINE'
}

@test "markers: END before START is an error and leaves CLAUDE.md unchanged" {
  assert_malformed_untouched 'TOP' "$MD_END" 'middle' "$MD_START" 'PRESERVE THIS LINE'
}

@test "markers: duplicate START is an error and leaves CLAUDE.md unchanged" {
  assert_malformed_untouched "$MD_START" 'a' "$MD_START" 'b' "$MD_END" 'PRESERVE THIS LINE'
}

@test "markers: duplicate END is an error and leaves CLAUDE.md unchanged" {
  assert_malformed_untouched "$MD_START" 'a' "$MD_END" 'b' "$MD_END" 'PRESERVE THIS LINE'
}

@test "markers: two pairs is an error and leaves CLAUDE.md unchanged" {
  assert_malformed_untouched "$MD_START" 'a' "$MD_END" 'between' "$MD_START" 'b' "$MD_END" 'PRESERVE THIS LINE'
}

@test "markers: CRLF line endings on the markers still replace the block" {
  mkdir -p "$HOME/.claude"
  {
    printf 'TOP LINE\r\n'
    printf '%s\r\n' "$MD_START"
    printf 'stale managed content\r\n'
    printf '%s\r\n' "$MD_END"
    printf 'BOTTOM LINE\r\n'
  } > "$HOME/.claude/CLAUDE.md"
  run_sync
  assert_equal "$status" 0
  body="$(cat "$HOME/.claude/CLAUDE.md")"
  assert_contains "$body" "TOP LINE"
  assert_contains "$body" "BOTTOM LINE"
  refute_contains "$body" "stale managed content"
  assert_equal "$(count_occurrences "$HOME/.claude/CLAUDE.md" '>>> claude-shared')" 1
  run_sync
  assert_equal "$status" 0
  assert_equal "$(count_occurrences "$HOME/.claude/CLAUDE.md" '>>> claude-shared')" 1
}

@test "markers: malformed CLAUDE.md stops sync before anything is deployed" {
  mkdir -p "$HOME/.claude"
  printf '%s\n' 'TOP' "$MD_START" 'stale' > "$HOME/.claude/CLAUDE.md"
  (cd "$HOME" && find . | LC_ALL=C sort) > "$TEST_TMP/before.list"
  cp "$HOME/.claude/CLAUDE.md" "$TEST_TMP/before"
  run_sync
  assert_equal "$status" 1
  (cd "$HOME" && find . | LC_ALL=C sort) > "$TEST_TMP/after.list"
  cmp "$TEST_TMP/before.list" "$TEST_TMP/after.list" || fail "sync created or removed files before failing"
  [ ! -e "$HOME/.claude/settings.json" ] || fail "settings.json was written"
  [ ! -e "$HOME/.claude/claude-shared-repo" ] || fail "claude-shared-repo was written"
  [ ! -e "$HOME/.claude/statusline-command.sh" ] || fail "status line was deployed"
  cmp "$HOME/.claude/CLAUDE.md" "$TEST_TMP/before" || fail "CLAUDE.md was modified"
}

# Require that no CLAUDE.md temp file (CLAUDE.md.*) is left in a directory,
# apart from the names given, which the user already had there.
assert_no_md_temp() { # dir [expected-name...]
  local dir="$1" f found="" want=""
  shift
  for f in "$dir"/CLAUDE.md.*; do
    [ -e "$f" ] || [ -L "$f" ] || continue
    found="$found ${f##*/}"
  done
  for f in "$@"; do want="$want $f"; done
  assert_equal "$found" "$want"
}

@test "replace keeps a symlinked CLAUDE.md a symlink and updates its target" {
  mkdir -p "$HOME/.claude" "$TEST_TMP/dotfiles"
  printf '%s\n' 'TOP LINE' "$MD_START" 'STALE BLOCK TEXT' "$MD_END" 'BOTTOM LINE' > "$TEST_TMP/dotfiles/CLAUDE.md"
  ln -s "$TEST_TMP/dotfiles/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
  run_sync
  assert_equal "$status" 0
  assert_symlink "$HOME/.claude/CLAUDE.md"
  body="$(cat "$TEST_TMP/dotfiles/CLAUDE.md")"
  assert_contains "$body" "TOP LINE"
  assert_contains "$body" "BOTTOM LINE"
  refute_contains "$body" "STALE BLOCK TEXT"
  assert_equal "$(count_occurrences "$TEST_TMP/dotfiles/CLAUDE.md" '>>> claude-shared')" 1
  assert_no_md_temp "$HOME/.claude"
}

file_mode() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }

@test "replace keeps the mode of CLAUDE.md" {
  mkdir -p "$HOME/.claude"
  printf '%s\n' 'TOP LINE' "$MD_START" 'stale' "$MD_END" > "$HOME/.claude/CLAUDE.md"
  chmod 600 "$HOME/.claude/CLAUDE.md"
  run_sync
  assert_equal "$status" 0
  refute_contains "$(cat "$HOME/.claude/CLAUDE.md")" "stale"
  assert_equal "$(file_mode "$HOME/.claude/CLAUDE.md")" 600
}

@test "a failing replace is an error, leaves CLAUDE.md unchanged and no .tmp behind" {
  run_sync
  cp "$HOME/.claude/CLAUDE.md" "$TEST_TMP/before"
  mkdir -p "$TEST_TMP/bin"
  real_awk="$(command -v awk)"
  # An awk that fails only for the replace pass (the one given -v snip=...).
  {
    echo '#!/bin/sh'
    echo 'for a in "$@"; do case "$a" in snip=*) exit 2 ;; esac; done'
    echo "exec \"$real_awk\" \"\$@\""
  } > "$TEST_TMP/bin/awk"
  chmod +x "$TEST_TMP/bin/awk"
  PATH="$TEST_TMP/bin:$PATH" run bash "$REPO/sync.sh"
  assert_equal "$status" 1
  refute_contains "$output" "Synced"
  cmp "$HOME/.claude/CLAUDE.md" "$TEST_TMP/before" || fail "CLAUDE.md was modified"
  assert_no_md_temp "$HOME/.claude"
}

# An mv shim that fails only when moving a CLAUDE.md temp file (CLAUDE.md.XXXXXX).
make_failing_mv() {
  mkdir -p "$TEST_TMP/bin"
  real_mv="$(command -v mv)"
  {
    echo '#!/bin/sh'
    echo 'for a in "$@"; do case "$a" in *CLAUDE.md.?*) exit 1 ;; esac; done'
    echo "exec \"$real_mv\" \"\$@\""
  } > "$TEST_TMP/bin/mv"
  chmod +x "$TEST_TMP/bin/mv"
}

@test "a failing write-back is an error, CLAUDE.md is byte-identical and no .tmp is left" {
  run_sync
  printf '%s\n' 'TOP' "$MD_START" 'stale' "$MD_END" 'BOTTOM' > "$HOME/.claude/CLAUDE.md"
  cp "$HOME/.claude/CLAUDE.md" "$TEST_TMP/before"
  make_failing_mv
  PATH="$TEST_TMP/bin:$PATH" run bash "$REPO/sync.sh"
  assert_equal "$status" 1
  refute_contains "$output" "Synced"
  assert_contains "$output" "CLAUDE.md"
  cmp "$HOME/.claude/CLAUDE.md" "$TEST_TMP/before" || fail "CLAUDE.md was modified"
  assert_no_md_temp "$HOME/.claude"
}

@test "a failing write-back through a symlink leaves the target and no .tmp" {
  mkdir -p "$HOME/.claude" "$TEST_TMP/dotfiles"
  printf '%s\n' 'TOP' "$MD_START" 'stale' "$MD_END" > "$TEST_TMP/dotfiles/CLAUDE.md"
  ln -s "$TEST_TMP/dotfiles/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
  cp "$TEST_TMP/dotfiles/CLAUDE.md" "$TEST_TMP/before"
  make_failing_mv
  PATH="$TEST_TMP/bin:$PATH" run bash "$REPO/sync.sh"
  assert_equal "$status" 1
  refute_contains "$output" "Synced"
  assert_symlink "$HOME/.claude/CLAUDE.md"
  cmp "$TEST_TMP/dotfiles/CLAUDE.md" "$TEST_TMP/before" || fail "target was modified"
  assert_no_md_temp "$TEST_TMP/dotfiles"
}

@test "a failing write-back on the first append is an error, CLAUDE.md is byte-identical and no temp is left" {
  mkdir -p "$HOME/.claude"
  printf 'MY PERSONAL NOTES\n' > "$HOME/.claude/CLAUDE.md"   # no markers: the append path
  cp "$HOME/.claude/CLAUDE.md" "$TEST_TMP/before"
  make_failing_mv
  PATH="$TEST_TMP/bin:$PATH" run bash "$REPO/sync.sh"
  assert_equal "$status" 1
  refute_contains "$output" "Synced"
  assert_contains "$output" "CLAUDE.md"
  cmp "$HOME/.claude/CLAUDE.md" "$TEST_TMP/before" || fail "CLAUDE.md was modified"
  assert_no_md_temp "$HOME/.claude"
}

@test "a file the user keeps at CLAUDE.md.tmp is left untouched" {
  mkdir -p "$HOME/.claude"
  printf '%s\n' 'TOP' "$MD_START" 'stale' "$MD_END" > "$HOME/.claude/CLAUDE.md"
  printf 'MY SCRATCH FILE\n' > "$HOME/.claude/CLAUDE.md.tmp"
  cp "$HOME/.claude/CLAUDE.md.tmp" "$TEST_TMP/scratch-before"
  run_sync
  assert_equal "$status" 0
  refute_contains "$(cat "$HOME/.claude/CLAUDE.md")" "stale"
  cmp "$HOME/.claude/CLAUDE.md.tmp" "$TEST_TMP/scratch-before" || fail "CLAUDE.md.tmp was modified"
  assert_no_md_temp "$HOME/.claude" CLAUDE.md.tmp
}

@test "replace rewrites a read-only CLAUDE.md and keeps it read-only" {
  mkdir -p "$HOME/.claude"
  printf '%s\n' 'TOP' "$MD_START" 'stale' "$MD_END" 'BOTTOM' > "$HOME/.claude/CLAUDE.md"
  chmod 444 "$HOME/.claude/CLAUDE.md"
  if [ "$(id -u)" = 0 ]; then
    # Root ignores write permission, so run as an unprivileged user to
    # exercise the read-only case for real.
    command -v setpriv >/dev/null || skip "running as root without setpriv"
    chown -R 65534:65534 "$TEST_TMP"
    run setpriv --reuid=65534 --regid=65534 --clear-groups bash "$REPO/sync.sh"
  else
    run_sync
  fi
  assert_equal "$status" 0
  body="$(cat "$HOME/.claude/CLAUDE.md")"
  refute_contains "$body" "stale"
  assert_contains "$body" "TOP"
  assert_contains "$body" "BOTTOM"
  assert_contains "$body" "Shared Claude setup"
  assert_equal "$(file_mode "$HOME/.claude/CLAUDE.md")" 444
  assert_no_md_temp "$HOME/.claude"
}

file_owner() { stat -c %u "$1" 2>/dev/null || stat -f %u "$1"; }

# Root may write any file, so [ -w ] says nothing about a read-only CLAUDE.md
# there; the mode has to come from the file's own owner-write bit.
@test "as root, a read-only CLAUDE.md keeps its mode on the append path" {
  [ "$(id -u)" = 0 ] || skip "needs root"
  mkdir -p "$HOME/.claude"
  for mode in 444 400; do
    printf 'MY NOTES\n' > "$HOME/.claude/CLAUDE.md"   # no markers: the append path
    chmod "$mode" "$HOME/.claude/CLAUDE.md"
    run_sync
    assert_equal "$status" 0
    body="$(cat "$HOME/.claude/CLAUDE.md")"
    assert_contains "$body" "MY NOTES"
    assert_contains "$body" "Shared Claude setup"
    assert_equal "$(file_mode "$HOME/.claude/CLAUDE.md")" "$mode"
    assert_no_md_temp "$HOME/.claude"
  done
}

@test "as root, a read-only CLAUDE.md keeps its mode on the replace path" {
  [ "$(id -u)" = 0 ] || skip "needs root"
  mkdir -p "$HOME/.claude"
  for mode in 444 400; do
    printf '%s\n' 'TOP' "$MD_START" 'stale' "$MD_END" 'BOTTOM' > "$HOME/.claude/CLAUDE.md"
    chmod "$mode" "$HOME/.claude/CLAUDE.md"
    run_sync
    assert_equal "$status" 0
    body="$(cat "$HOME/.claude/CLAUDE.md")"
    refute_contains "$body" "stale"
    assert_contains "$body" "BOTTOM"
    assert_equal "$(file_mode "$HOME/.claude/CLAUDE.md")" "$mode"
    assert_no_md_temp "$HOME/.claude"
  done
}

# The user cannot write a file someone else owns, but can rename over it in
# their own folder. The new file keeps the mode and is owned by the user.
@test "a 0644 CLAUDE.md owned by someone else in the user's folder stays 644" {
  [ "$(id -u)" = 0 ] || skip "needs root to give the file another owner"
  command -v setpriv >/dev/null || skip "running as root without setpriv"
  mkdir -p "$HOME/.claude"
  printf '%s\n' 'TOP' "$MD_START" 'stale' "$MD_END" 'BOTTOM' > "$HOME/.claude/CLAUDE.md"
  chown -R 65534:65534 "$TEST_TMP"
  chown 0:0 "$HOME/.claude/CLAUDE.md"
  chmod 644 "$HOME/.claude/CLAUDE.md"
  run setpriv --reuid=65534 --regid=65534 --clear-groups bash "$REPO/sync.sh"
  assert_equal "$status" 0
  body="$(cat "$HOME/.claude/CLAUDE.md")"
  refute_contains "$body" "stale"
  assert_contains "$body" "BOTTOM"
  assert_equal "$(file_mode "$HOME/.claude/CLAUDE.md")" 644
  assert_equal "$(file_owner "$HOME/.claude/CLAUDE.md")" 65534
  assert_no_md_temp "$HOME/.claude"
}

# Retry a command every 0.05 s, up to N times.
wait_until() { # tries command...
  local n="$1"
  shift
  until "$@"; do
    n=$((n - 1))
    [ "$n" -gt 0 ] || return 1
    sleep 0.05
  done
}

@test "TERM during the write exits 143, leaves CLAUDE.md byte-identical and no temp" {
  mkdir -p "$HOME/.claude" "$TEST_TMP/bin"
  printf 'MY PERSONAL NOTES\n' > "$HOME/.claude/CLAUDE.md"   # no markers: the append path
  cp "$HOME/.claude/CLAUDE.md" "$TEST_TMP/before"
  real_cat="$(command -v cat)"
  # A cat that, when given the snippet, says it started and then waits until
  # released. It gives up after 10 s or once the test dir is gone, so it never
  # outlives a failed test.
  {
    echo '#!/bin/sh'
    echo 'for a in "$@"; do'
    echo '  case "$a" in */CLAUDE.snippet.md)'
    echo "    : > '$TEST_TMP/cat-started'"
    echo '    i=0'
    echo "    while [ -d '$TEST_TMP' ] && [ ! -e '$TEST_TMP/cat-release' ] && [ \$i -lt 200 ]; do"
    echo '      sleep 0.05; i=$((i + 1))'
    echo '    done ;;'
    echo '  esac'
    echo 'done'
    echo "exec '$real_cat' \"\$@\""
  } > "$TEST_TMP/bin/cat"
  chmod +x "$TEST_TMP/bin/cat"

  PATH="$TEST_TMP/bin:$PATH" bash "$REPO/sync.sh" > "$TEST_TMP/out" 2>&1 3>&- &
  SYNC_PID=$!
  wait_until 200 test -e "$TEST_TMP/cat-started" || fail "sync never reached the append"
  kill -TERM "$SYNC_PID"
  # bash runs the trap once the foreground cat returns, so let it return.
  : > "$TEST_TMP/cat-release"
  rc=0
  wait "$SYNC_PID" || rc=$?
  SYNC_PID=""
  out="$(cat "$TEST_TMP/out")"
  assert_equal "$rc" 143
  refute_contains "$out" "Synced"
  cmp "$HOME/.claude/CLAUDE.md" "$TEST_TMP/before" || fail "CLAUDE.md was modified"
  assert_no_md_temp "$HOME/.claude"
}

@test "a new CLAUDE.md gets the mode the umask gives a new file" {
  umask 027
  run_sync
  assert_equal "$status" 0
  assert_equal "$(file_mode "$HOME/.claude/CLAUDE.md")" 640
  assert_no_md_temp "$HOME/.claude"
}

@test "an unreadable snippet during the replace is an error, not an emptied block" {
  run_sync
  printf '%s\n' 'TOP' "$MD_START" 'stale' "$MD_END" 'BOTTOM' > "$HOME/.claude/CLAUDE.md"
  cp "$HOME/.claude/CLAUDE.md" "$TEST_TMP/before"
  mkdir -p "$TEST_TMP/bin"
  real_awk="$(command -v awk)"
  # Point the replace pass's snippet at a missing file, as if it vanished after the preflight.
  {
    echo '#!/bin/sh'
    echo 'for a in "$@"; do'
    echo '  case "$a" in snip=*) a="snip=/nonexistent/snippet" ;; esac'
    echo '  set -- "$@" "$a"; shift'
    echo 'done'
    echo "exec \"$real_awk\" \"\$@\""
  } > "$TEST_TMP/bin/awk"
  chmod +x "$TEST_TMP/bin/awk"
  PATH="$TEST_TMP/bin:$PATH" run bash "$REPO/sync.sh"
  assert_equal "$status" 1
  refute_contains "$output" "Synced"
  cmp "$HOME/.claude/CLAUDE.md" "$TEST_TMP/before" || fail "CLAUDE.md was modified"
  assert_no_md_temp "$HOME/.claude"
}

# A checkout with a local bare origin, one commit behind it.
make_pull_fixture() {
  mkdir -p "$TEST_TMP/seed"
  cp -R "$REPO/claude" "$REPO/skills" "$REPO/sync.sh" "$TEST_TMP/seed/"
  git -C "$TEST_TMP/seed" init -q
  git -C "$TEST_TMP/seed" add -A
  git -C "$TEST_TMP/seed" commit -q -m seed
  git clone -q --bare "$TEST_TMP/seed" "$TEST_TMP/origin.git"
  git clone -q "$TEST_TMP/origin.git" "$TEST_TMP/clone"
}

@test "--pull pulls first, then deploys the pulled snippet" {
  make_pull_fixture
  echo 'PULLED SNIPPET LINE' >> "$TEST_TMP/seed/claude/CLAUDE.snippet.md"
  git -C "$TEST_TMP/seed" commit -q -am up
  git -C "$TEST_TMP/seed" push -q "$TEST_TMP/origin.git" HEAD:main
  run bash "$TEST_TMP/clone/sync.sh" --pull
  assert_equal "$status" 0
  assert_contains "$(cat "$HOME/.claude/CLAUDE.md")" "PULLED SNIPPET LINE"
  assert_contains "$output" "Synced"
}

@test "--pull checks the pulled snippet, so a snippet removed upstream changes nothing" {
  make_pull_fixture
  git -C "$TEST_TMP/seed" rm -q claude/CLAUDE.snippet.md
  git -C "$TEST_TMP/seed" commit -q -m drop
  git -C "$TEST_TMP/seed" push -q "$TEST_TMP/origin.git" HEAD:main
  run bash "$TEST_TMP/clone/sync.sh" --pull
  assert_equal "$status" 1
  assert_contains "$output" "snippet"
  [ ! -e "$HOME/.claude/settings.json" ] || fail "settings.json was written"
  [ ! -e "$HOME/.claude/statusline-command.sh" ] || fail "status line was deployed"
}

@test "a missing snippet refuses before changing anything and keeps the block" {
  run_sync
  cp "$HOME/.claude/CLAUDE.md" "$TEST_TMP/before"
  # sync.sh resolves its own directory, so run a copy with the snippet removed.
  mkdir -p "$TEST_TMP/repo"
  cp -R "$REPO/claude" "$REPO/skills" "$REPO/sync.sh" "$TEST_TMP/repo/"
  rm "$TEST_TMP/repo/claude/CLAUDE.snippet.md"
  rm -f "$HOME/.claude/claude-shared-repo"
  run bash "$TEST_TMP/repo/sync.sh"
  assert_equal "$status" 1
  assert_contains "$output" "snippet"
  cmp "$HOME/.claude/CLAUDE.md" "$TEST_TMP/before" || fail "the managed block was deleted"
  [ ! -e "$HOME/.claude/claude-shared-repo" ] || fail "claude-shared-repo was written"
}

@test "leaves a real (non-symlink) skill directory in ~/.claude/skills untouched" {
  mkdir -p "$HOME/.claude/skills/sync-claude-env"   # collides with a shipped skill name
  echo "user's own work" > "$HOME/.claude/skills/sync-claude-env/USER_FILE.md"
  run_sync
  # BUG: `rm -rf "$link"` blows away the user's real directory before symlinking.
  assert_file_exists "$HOME/.claude/skills/sync-claude-env/USER_FILE.md"
}
