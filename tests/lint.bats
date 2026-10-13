#!/usr/bin/env bats
#
# Static lint over the instruction skills / templates. These don't execute
# code; they guard the prose contracts the skills depend on.

load 'helpers/setup'

setup()    { common_setup; }
teardown() { common_teardown; }

TEMPLATE() { echo "$REPO/templates/handoff/SKILL.md"; }
ADDH()     { echo "$REPO/skills/add-handoff/SKILL.md"; }

template_tokens() { grep -oE '\{\{[A-Z0-9_]+\}\}' "$(TEMPLATE)" | sort -u; }

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

@test "every ../<skill>/<file> a skill points at exists" {
  # A skill that leans on a sibling (orchestrating-issue-runs -> cache-warmth)
  # names it by relative path; a rename or move must not leave it dangling.
  n=0
  for f in "$REPO"/skills/*/*.md; do
    dir="$(dirname "$f")"
    for ref in $(grep -oE '\.\./[a-z0-9-]+/[A-Za-z0-9_./-]+\.(md|py|sh)' "$f" | sort -u); do
      n=$((n + 1))
      [ -e "$dir/$ref" ] || fail "$f points at $ref, which does not exist"
    done
  done
  [ "$n" -gt 0 ] || fail "found no sibling references at all; the pattern no longer matches"
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

@test "the leftover-placeholder scan covers {{...}} tokens and unfilled <fill-in> markers" {
  scan="$(grep -i 'leftover' "$(ADDH)")"
  assert_contains "$scan" '{{'
  # The fill tables use <task-doc>/<test-cmd> as fill-in markers that must not survive.
  assert_contains "$scan" '<task-doc>'
}

@test "the only <...> literal intentionally left in the handoff template is <repo>" {
  # The scan in add-handoff must be satisfiable: it allows exactly these literals.
  lits="$(grep -oE '<[^>]+>' "$(TEMPLATE)" | sort -u)"
  assert_equal "$lits" "<repo>"
  grep -qF '<repo>' "$(ADDH)" || fail "add-handoff does not list <repo> as an allowed literal"
}
