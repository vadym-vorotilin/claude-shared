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

@test "deploys both status line scripts and the helpers they source" {
  run_sync
  for f in statusline-command.sh subagent-statusline-command.sh statusline-lib.sh; do
    assert_file_exists "$HOME/.claude/$f"
    assert_executable "$HOME/.claude/$f"
  done
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

# ------------------------------------------------------------ CHECKPOINT ----

@test "deploys an executable checkpoint.sh" {
  run_sync
  assert_executable "$HOME/.claude/checkpoint.sh"
  cmp -s "$REPO/claude/checkpoint.sh" "$HOME/.claude/checkpoint.sh" || fail "deployed copy differs"
}

@test "merging adds the checkpoint hooks and keeps the user's own hooks for the same events" {
  mkdir -p "$HOME/.claude"
  echo '{"hooks":{
     "PostToolUse":[{"hooks":[{"type":"command","command":"echo local-post"}]}],
     "SessionStart":[{"matcher":"startup","hooks":[{"type":"command","command":"echo local-start"}]}],
     "PreCompact":[{"hooks":[{"type":"command","command":"echo local-pre"}]}]}}' \
    > "$HOME/.claude/settings.json"
  run_sync
  s="$HOME/.claude/settings.json"
  # BUG: jq '*' replaces arrays, so the user's SessionStart/PreCompact hooks vanish.
  assert_equal "$(jq -r '.hooks.PostToolUse[0].hooks[0].command' "$s")" "echo local-post"
  assert_equal "$(jq -r '[.hooks.SessionStart[].hooks[].command] | join(",")' "$s")" \
    "echo local-start,bash ~/.claude/checkpoint.sh restore"
  assert_equal "$(jq -r '[.hooks.PreCompact[].hooks[].command] | join(",")' "$s")" \
    "echo local-pre,bash ~/.claude/checkpoint.sh precompact || true"
  assert_equal "$(jq -r '.hooks.SessionStart[1].matcher' "$s")" "compact"
}

@test "re-running sync registers each checkpoint hook once, with the shared timeout" {
  mkdir -p "$HOME/.claude"
  # An older deploy: the same command with a different timeout.
  echo '{"hooks":{"PreCompact":[{"hooks":[{"type":"command","command":"bash ~/.claude/checkpoint.sh precompact || true","timeout":30}]}]}}' \
    > "$HOME/.claude/settings.json"
  run_sync
  run_sync
  s="$HOME/.claude/settings.json"
  assert_equal "$(jq '[.hooks.PreCompact[].hooks[]] | length' "$s")" 1
  assert_equal "$(jq '[.hooks.SessionStart[].hooks[]] | length' "$s")" 1
  assert_equal "$(jq '.hooks.PreCompact[0].hooks[0].timeout' "$s")" 300
}
