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
