#!/usr/bin/env bats
#
# Static lint over the instruction skills / templates. These don't execute
# code; they guard the prose contracts the skills depend on.

load 'helpers/setup'

setup()    { common_setup; }
teardown() { common_teardown; }

TEMPLATE() { echo "$REPO/templates/handoff/SKILL.md"; }
ADDH()     { echo "$REPO/skills/add-handoff/SKILL.md"; }

template_tokens() { grep -oE '\{\{[A-Z_]+\}\}' "$(TEMPLATE)" | sort -u; }

# ------------------------------------------------------------- FEATURES ----

@test "every {{TOKEN}} in the template has a substitution rule in add-handoff" {
  for tok in $(template_tokens); do
    grep -qF "$tok" "$(ADDH)" || fail "template token $tok has no rule in add-handoff"
  done
}

@test "settings.shared.json statusLine command matches the deployed script" {
  cmd="$(jq -r '.statusLine.command' "$REPO/claude/settings.shared.json")"
  assert_contains "$cmd" "statusline-command.sh"
  grep -q 'statusline-command.sh' "$REPO/sync.sh" || fail "sync.sh does not deploy statusline-command.sh"
}

@test "CLAUDE.snippet.md carries both managed-block markers" {
  snip="$REPO/claude/CLAUDE.snippet.md"
  grep -qF '>>> claude-shared' "$snip" || fail "snippet missing START marker"
  grep -qF '<<< claude-shared <<<' "$snip" || fail "snippet missing END marker"
}

# ----------------------------------------------------------- EDGE CASES ----

@test "tokens sharing a line with content aren't told to delete the line" {
  for tok in $(template_tokens); do
    line="$(grep -F "$tok" "$(TEMPLATE)" | head -1)"
    rest="$(printf '%s' "${line//$tok/}" | tr -d '[:space:]')"
    [ -n "$rest" ] || continue   # token alone on its line -> deleting the line is safe
    bad="$(grep -F "$tok" "$(ADDH)" | grep -i 'delete the' || true)"
    [ -z "$bad" ] || fail "token $tok shares a line with real content but add-handoff says: $bad"
  done
}

@test "the leftover-placeholder scan also covers <...> placeholders" {
  scan="$(grep -i 'leftover' "$(ADDH)")"
  assert_contains "$scan" '{{'
  # BUG: the scan only looks for {{ }}, so literal <task-doc>/<test-cmd> fills can survive.
  assert_contains "$scan" '<'
}
