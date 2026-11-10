#!/usr/bin/env bats
#
# sync.sh — deploys shared config into a sandbox $HOME/.claude.
# Covers its features plus the edge cases where it must not destroy user data.

load 'helpers/setup'

setup()    { common_setup; }
teardown() { common_teardown; }

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
    [ "$status" -ne 0 ] || fail "sync.sh succeeded on malformed markers"
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

@test "leaves a real (non-symlink) skill directory in ~/.claude/skills untouched" {
  mkdir -p "$HOME/.claude/skills/sync-claude-env"   # collides with a shipped skill name
  echo "user's own work" > "$HOME/.claude/skills/sync-claude-env/USER_FILE.md"
  run_sync
  # BUG: `rm -rf "$link"` blows away the user's real directory before symlinking.
  assert_file_exists "$HOME/.claude/skills/sync-claude-env/USER_FILE.md"
}
