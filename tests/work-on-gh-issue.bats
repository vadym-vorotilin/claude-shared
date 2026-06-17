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
    "## 2a. Existing PRs on this issue" \
    "## Ground truth" \
    "{{DOMAIN_KNOWLEDGE}}" \
    "## 4. Implement via strict TDD" \
    "CANNOT REPRODUCE" \
    "{{TEST_CMD}}" \
    "## Pre-PR self-review" \
    "## Pre-review notes" \
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

# ------------------------------------------------------- PLACEHOLDER SCAN ----

scan_cmd() { extract_code_block "$(ADDER)" "FAIL if any placeholder survived" bash; }

@test "placeholder scan flags a leftover {{TOKEN}}" {
  d="$TEST_TMP/out"; mkdir -p "$d"
  printf 'ok line\n{{LEFTOVER}}\n' > "$d/SKILL.md"
  run bash -c "DEST='$d'; $(scan_cmd)"
  assert_equal "$status" 1
  assert_contains "$output" "leftover placeholder"
}

@test "placeholder scan leaves legitimate <runtime> placeholders alone" {
  d="$TEST_TMP/out"; mkdir -p "$d"
  # The installed worker keeps lowercase <n>, <short-slug>, <pr-repo> etc.
  printf 'gh issue edit <n> --add-label foo; branch fix/<short-slug>\n' > "$d/SKILL.md"
  run bash -c "DEST='$d'; $(scan_cmd)"
  assert_equal "$status" 0
}

@test "placeholder scan passes a fully-filled file" {
  d="$TEST_TMP/out"; mkdir -p "$d"
  printf 'fully filled, no tokens here\n' > "$d/SKILL.md"
  run bash -c "DEST='$d'; $(scan_cmd)"
  assert_equal "$status" 0
}

# ----------------------------------------------------------------- LINT ----

template_tokens() { grep -oE '\{\{[A-Z_]+\}\}' "$(TEMPLATE)" | sort -u; }

@test "every {{TOKEN}} in the template has a fill rule in the installer" {
  for tok in $(template_tokens); do
    grep -qF "$tok" "$(ADDER)" || fail "template token $tok has no rule in installer"
  done
}

@test "placeholder scan targets {{ }} install tokens, not <runtime> placeholders" {
  pat="$(grep -nE "grep -RnE" "$(ADDER)" | head -1)"
  # The scan matches {{UPPER_SNAKE}} tokens (braces are backslash-escaped for grep -E,
  # so check for the uppercase-token character class, which is unambiguous).
  assert_contains "$pat" '[A-Z_]'
  # It must NOT scan for lowercase <...>, which legitimately survive in the worker.
  refute_contains "$pat" '<[a-z]'
}

@test "worker forbids merging and main-pushing" {
  body="$(cat "$(TEMPLATE)")"
  assert_contains "$body" "## Forbidden"
  assert_contains "$body" "gh pr merge"
}
