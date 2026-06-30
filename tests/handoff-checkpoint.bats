#!/usr/bin/env bats
#
# handoff-checkpoint.sh is the Stop hook installed by add-handoff. It snapshots
# git state + last messages into a gitignored autosave next to the handoff doc.
# These tests run the real script against throwaway git repos.

load 'helpers/setup'

setup()    { common_setup; }
teardown() { common_teardown; }

HOOK() { echo "$REPO/templates/handoff/handoff-checkpoint.sh"; }

# Build a fake Claude Code transcript JSONL with one user + one assistant line.
make_transcript() { # path user_text assistant_text
  printf '%s\n' \
    "$(jq -nc --arg t "$2" '{type:"user",message:{role:"user",content:$t}}')" \
    "$(jq -nc --arg t "$3" '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:$t}]}}')" \
    > "$1"
}

# Run the hook with a stdin payload pointing at $cwd and $transcript.
run_hook() { # cwd transcript
  printf '%s' "$(jq -nc --arg c "$1" --arg t "$2" '{cwd:$c,transcript_path:$t}')" \
    | bash "$(HOOK)"
}

@test "writes the autosave with git facts and last messages" {
  repo="$TEST_TMP/proj"; make_git_repo "$repo"
  tr="$TEST_TMP/t.jsonl"; make_transcript "$tr" "do the thing" "I did the thing"
  run_hook "$repo" "$tr"
  auto="$repo/docs/HANDOFF.autosave.md"
  assert_file_exists "$auto"
  body="$(cat "$auto")"
  assert_contains "$body" "Branch:"
  assert_contains "$body" "main"
  assert_contains "$body" "do the thing"
  assert_contains "$body" "I did the thing"
  assert_contains "$body" "$tr"
}

@test "honors a custom HANDOFF_DOC path" {
  repo="$TEST_TMP/proj"; make_git_repo "$repo"
  tr="$TEST_TMP/t.jsonl"; make_transcript "$tr" "u" "a"
  HANDOFF_DOC="docs/SESSION.md" run_hook "$repo" "$tr"
  assert_file_exists "$repo/docs/SESSION.autosave.md"
}

@test "registers the autosave in .git/info/exclude (idempotently)" {
  repo="$TEST_TMP/proj"; make_git_repo "$repo"
  tr="$TEST_TMP/t.jsonl"; make_transcript "$tr" "u" "a"
  run_hook "$repo" "$tr"
  run_hook "$repo" "$tr"
  excl="$repo/.git/info/exclude"
  assert_equal "$(count_occurrences "$excl" "docs/HANDOFF.autosave.md")" 1
}

@test "no-ops cleanly outside a git repo" {
  plain="$TEST_TMP/plain"; mkdir -p "$plain"
  tr="$TEST_TMP/t.jsonl"; make_transcript "$tr" "u" "a"
  run run_hook "$plain" "$tr"
  assert_equal "$status" 0
  [ ! -e "$plain/docs/HANDOFF.autosave.md" ] || fail "should not write outside a repo"
}
