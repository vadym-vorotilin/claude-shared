#!/usr/bin/env bats
#
# add-context-ceiling SKILL.md — section 2 documents the install block: link the
# hook, merge a PreToolUse entry into .claude/settings.local.json, exclude both
# from commits. These tests run the *actual* extracted block.

load 'helpers/setup'
load 'helpers/extract'

setup() {
  common_setup
  # The hook where sync.sh would put it, inside the sandbox $HOME.
  mkdir -p "$HOME/.claude/skills"
  ln -s "$REPO/skills/context-ceiling" "$HOME/.claude/skills/context-ceiling"
  TARGET="$TEST_TMP/proj"
  make_git_repo "$TARGET"
}
teardown() { common_teardown; }

install() {
  local script="$TEST_TMP/install.sh"
  extract_code_block "$REPO/skills/add-context-ceiling/SKILL.md" "## 2. Install" bash \
    | sed "s#<target>#$TARGET#g" > "$script"
  bash "$script"
}

ceiling_entries() { # settings_file
  jq '[.hooks.PreToolUse[]?.hooks[]? | select((.command // "") | contains("agent-ceiling.py"))] | length' "$1"
}

# ------------------------------------------------------------- FEATURES ----

@test "links the hook and adds one PreToolUse entry inside the hooks object" {
  install
  assert_symlink "$TARGET/.claude/hooks/agent-ceiling.py"
  [ -r "$TARGET/.claude/hooks/agent-ceiling.py" ] || fail "link target unreadable"
  assert_equal "$(ceiling_entries "$TARGET/.claude/settings.local.json")" 1
  assert_equal "$(jq -r '.hooks.PreToolUse[0].matcher' "$TARGET/.claude/settings.local.json")" "*"
}

@test "a re-install stays at one entry" {
  install; install
  assert_equal "$(ceiling_entries "$TARGET/.claude/settings.local.json")" 1
}

@test "keeps unrelated settings and hooks" {
  mkdir -p "$TARGET/.claude"
  jq -n '{model:"x", hooks:{PreToolUse:[{matcher:"Bash",hooks:[{type:"command",command:"other.sh"}]}], Stop:[{hooks:[{type:"command",command:"s.sh"}]}]}}' \
    > "$TARGET/.claude/settings.local.json"
  install
  f="$TARGET/.claude/settings.local.json"
  assert_equal "$(jq -r .model "$f")" "x"
  assert_equal "$(jq '.hooks.PreToolUse | length' "$f")" 2
  assert_equal "$(jq -r '.hooks.Stop[0].hooks[0].command' "$f")" "s.sh"
}

@test "excludes the link and the local settings from commits, once each" {
  install; install
  excl="$TARGET/.git/info/exclude"
  assert_equal "$(grep -cxF .claude/hooks/agent-ceiling.py "$excl")" 1
  assert_equal "$(grep -cxF .claude/settings.local.json "$excl")" 1
  assert_equal "$(git -C "$TARGET" status --porcelain)" ""
}

# ----------------------------------------------------------- EDGE CASES ----

@test "the installed command exits 0 when the hook file is gone (never blocks)" {
  install
  rm "$TARGET/.claude/hooks/agent-ceiling.py"
  cmd="$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$TARGET/.claude/settings.local.json")"
  run env CLAUDE_PROJECT_DIR="$TARGET" sh -c "$cmd" </dev/null
  [ "$status" -eq 0 ] || fail "missing hook must not block; got exit $status"
}

@test "refuses to install when the hook is not where it says" {
  rm "$HOME/.claude/skills/context-ceiling"
  run install
  [ "$status" -ne 0 ] || fail "should fail without the hook"
  [ ! -e "$TARGET/.claude/settings.local.json" ] || fail "wrote settings without a hook"
}

@test "stops, and changes nothing, when an older install committed the hook link" {
  mkdir -p "$TARGET/.claude/hooks"
  ln -s /nonexistent/agent-ceiling.py "$TARGET/.claude/hooks/agent-ceiling.py"
  git -C "$TARGET" add .claude/hooks/agent-ceiling.py
  git -C "$TARGET" -c user.name=t -c user.email=t@example.com commit -qm "old install"
  run install
  [ "$status" -ne 0 ] || fail "should refuse a tracked link"
  assert_contains "$output" "tracked by git"
  assert_equal "$(git -C "$TARGET" status --porcelain)" ""
}

@test "a target that does not exist writes nothing into the caller's directory" {
  TARGET="$TEST_TMP/no-such-dir"
  mkdir -p "$TEST_TMP/caller"; cd "$TEST_TMP/caller"
  run install
  [ "$status" -ne 0 ] || fail "should fail on a missing target"
  [ ! -e "$TEST_TMP/caller/.claude" ] || fail "wrote .claude into the caller's directory"
}
