#!/usr/bin/env bats
#
# add-handoff SKILL.md — section 4b documents a jq merge that installs a
# SessionStart hook into a target repo's .claude/settings.json. These tests
# run the *actual* extracted command block so they stay honest to the doc.

load 'helpers/setup'
load 'helpers/extract'

setup()    { common_setup; }
teardown() { common_teardown; }

# Extract the section-4b bash block, point it at $1, and run it.
# Honors $HANDOFF_DOC from the environment (after the fix parameterizes it).
install_hook() { # target_dir
  local target="$1" script="$TEST_TMP/install_hook.sh"
  extract_code_block "$REPO/skills/add-handoff/SKILL.md" "## 4b" bash \
    | sed "s#<target>#$target#g" > "$script"
  bash "$script"
}

# Count installed handoff hooks (path-independent marker).
handoff_hook_count() { # settings_file
  jq '[.hooks.SessionStart[]?.hooks[]? | select((.command // "") | contains("handoff skill in RESUME"))] | length' "$1"
}

# Concatenate every SessionStart command string.
all_session_commands() { # settings_file
  jq -r '.hooks.SessionStart[]?.hooks[]?.command // empty' "$1"
}

# ------------------------------------------------------------- FEATURES ----

@test "installs the hook when no settings.json exists" {
  target="$TEST_TMP/proj"; mkdir -p "$target"
  install_hook "$target"
  assert_file_exists "$target/.claude/settings.json"
  assert_equal "$(handoff_hook_count "$target/.claude/settings.json")" 1
}

@test "preserves other top-level keys and other hook events" {
  target="$TEST_TMP/proj"; mkdir -p "$target/.claude"
  echo '{"model":"sonnet","hooks":{"PreToolUse":[{"hooks":[{"type":"command","command":"echo hi"}]}]}}' \
    > "$target/.claude/settings.json"
  install_hook "$target"
  assert_equal "$(jq -r .model "$target/.claude/settings.json")" sonnet
  assert_equal "$(jq '.hooks.PreToolUse | length' "$target/.claude/settings.json")" 1
  assert_equal "$(handoff_hook_count "$target/.claude/settings.json")" 1
}

@test "appends alongside an unrelated existing SessionStart hook" {
  target="$TEST_TMP/proj"; mkdir -p "$target/.claude"
  echo '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"echo other"}]}]}}' \
    > "$target/.claude/settings.json"
  install_hook "$target"
  assert_contains "$(all_session_commands "$target/.claude/settings.json")" "echo other"
  assert_equal "$(handoff_hook_count "$target/.claude/settings.json")" 1
}

@test "is idempotent: re-installing the same path adds no duplicate" {
  target="$TEST_TMP/proj"; mkdir -p "$target"
  install_hook "$target"
  install_hook "$target"
  assert_equal "$(handoff_hook_count "$target/.claude/settings.json")" 1
}

# ----------------------------------------------------------- EDGE CASES ----

@test "the hook references the chosen handoff doc path, not a hardcoded one" {
  target="$TEST_TMP/proj"; mkdir -p "$target"
  export HANDOFF_DOC="docs/SESSION.md"
  install_hook "$target"
  cmd="$(all_session_commands "$target/.claude/settings.json")"
  # BUG: the documented command hardcodes docs/HANDOFF.md and ignores the chosen path.
  assert_contains "$cmd" "docs/SESSION.md"
}

@test "re-installing with a changed doc path updates the hook" {
  target="$TEST_TMP/proj"; mkdir -p "$target"
  export HANDOFF_DOC="docs/HANDOFF.md"; install_hook "$target"
  export HANDOFF_DOC="docs/SESSION.md"; install_hook "$target"
  cmd="$(all_session_commands "$target/.claude/settings.json")"
  # BUG: the path-independent dedup marker makes the second install a no-op,
  # leaving the stale docs/HANDOFF.md hook and never wiring the new path.
  assert_contains "$cmd" "docs/SESSION.md"
}
