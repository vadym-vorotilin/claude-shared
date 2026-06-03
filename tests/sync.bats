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

@test "deploys an executable statusline script" {
  run_sync
  assert_file_exists "$HOME/.claude/statusline-command.sh"
  assert_executable "$HOME/.claude/statusline-command.sh"
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

@test "managed-block edit keeps user content when the END marker is missing" {
  mkdir -p "$HOME/.claude"
  start='<!-- >>> claude-shared (managed by claude-shared/sync.sh — edit the snippet, not here) >>> -->'
  {
    printf '%s\n' "$start"
    printf 'stale managed content\n'
    printf 'PRESERVE THIS LINE\n'   # below where the END marker should be
  } > "$HOME/.claude/CLAUDE.md"
  run_sync
  body="$(cat "$HOME/.claude/CLAUDE.md")"
  # BUG: awk enters skip mode at START and, finding no END, drops everything after it.
  assert_contains "$body" "PRESERVE THIS LINE"
}

@test "leaves a real (non-symlink) skill directory in ~/.claude/skills untouched" {
  mkdir -p "$HOME/.claude/skills/sync-claude-env"   # collides with a shipped skill name
  echo "user's own work" > "$HOME/.claude/skills/sync-claude-env/USER_FILE.md"
  run_sync
  # BUG: `rm -rf "$link"` blows away the user's real directory before symlinking.
  assert_file_exists "$HOME/.claude/skills/sync-claude-env/USER_FILE.md"
}
