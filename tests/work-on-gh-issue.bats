#!/usr/bin/env bats
#
# work-on-gh-issue: exercises the executable fenced blocks in the template +
# installer (ranking jq, placeholder scan) and lints the token contract.
# The test image has bash/bats/jq/git/gawk only — NO gh, NO node. Tests must
# never invoke gh.

load 'helpers/setup'
load 'helpers/extract'

setup()    { common_setup; }
teardown() { common_teardown; }

TEMPLATE() { echo "$REPO/templates/work-on-gh-issue/SKILL.md"; }
ADDER()    { echo "$REPO/skills/add-work-on-gh-issue/SKILL.md"; }

# ------------------------------------------------------------- SCAFFOLD ----

@test "template and installer exist with a name frontmatter field" {
  assert_file_exists "$(TEMPLATE)"
  assert_file_exists "$(ADDER)"
  assert_contains "$(head -5 "$(TEMPLATE)")" "name: work-on-gh-issue"
  assert_contains "$(head -5 "$(ADDER)")" "name: add-work-on-gh-issue"
}

# --------------------------------------------------------- WORKER SHAPE ----

@test "worker template has the required sections and tokens" {
  body="$(cat "$(TEMPLATE)")"
  for needle in \
    "## 1. Select the issue" \
    "{{STATE_ADAPTER}}" \
    "## 4. Implement via strict TDD" \
    "CANNOT REPRODUCE" \
    "{{TEST_CMD}}" \
    "## 6. Hard stops" \
    "## Forbidden" \
    "{{PR_LABELS_BLOCK}}" \
    "{{COPILOT_LOOP}}" \
    "{{ATTRIBUTION}}"; do
    assert_contains "$body" "$needle"
  done
}

# -------------------------------------------------------------- RANKING ----

# Extract the canonical ranking jq from the installer's labels adapter and fill its
# two tokens to concrete values, the way the installer would (sed-on-extract, like
# add-handoff.bats does with <target>). extract_code_block keys on a substring that
# must appear BEFORE the ```bash fence, so we key on the prose phrase that introduces
# it. The block reads the issue JSON on stdin.
rank_cmd() { # priority_json
  extract_code_block "$(ADDER)" "into this ranking jq" bash \
    | sed -e "s/{{PRIORITY_ORDER}}/$1/g" -e "s/{{BLOCKED_STATE}}/blocked/g"
}

@test "ranking drops blocked and orders by priority then issue number" {
  fixture='[{"number":5,"title":"A","labels":[{"name":"go"},{"name":"p1"}]},
            {"number":3,"title":"B","labels":[{"name":"go"},{"name":"p0"}]},
            {"number":9,"title":"C","labels":[{"name":"go"}]},
            {"number":2,"title":"D","labels":[{"name":"go"},{"name":"blocked"}]},
            {"number":7,"title":"E","labels":[{"name":"go"},{"name":"p0"}]}]'
  out="$(printf '%s' "$fixture" | bash -c "$(rank_cmd '["p0","p1","p2"]')")"
  # #2 blocked -> dropped. p0: 3,7 (by number); p1: 5; unranked: 9.
  assert_equal "$(printf '%s' "$out" | cut -f1 | tr '\n' ' ')" "3 7 5 9 "
}

@test "ranking with empty priority list is pure oldest-first" {
  fixture='[{"number":5,"title":"A","labels":[{"name":"go"}]},
            {"number":3,"title":"B","labels":[{"name":"go"}]}]'
  out="$(printf '%s' "$fixture" | bash -c "$(rank_cmd '[]')")"
  assert_equal "$(printf '%s' "$out" | cut -f1 | tr '\n' ' ')" "3 5 "
}
