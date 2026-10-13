#!/usr/bin/env bats
#
# context-size.py — measures a session's context size from its transcript.
# The harness writes one assistant turn as several JSONL lines (one per content
# block), each repeating the same usage; the tool must count that turn once.

load 'helpers/setup'

setup() {
  common_setup
  TOOL="$REPO/skills/context-ceiling/tools/context-size.py"
  T="$TEST_TMP/session.jsonl"
  # Fictional transcript, four real turns:
  #   req-a  split over 3 lines, context 100k
  #   msg-b  split over 2 lines (message id only, no requestId), context 250k
  #   (none) one line with neither id, context 50k
  #   req-c  split over 2 lines, context 300k
  turn() { # requestId messageId ctx
    jq -cn --arg r "$1" --arg m "$2" --argjson c "$3" '
      {type:"assistant", timestamp:"2026-01-01T00:00:00Z",
       message:{usage:{input_tokens:10, cache_read_input_tokens:($c-10),
                       cache_creation_input_tokens:0, output_tokens:5}}}
      | if $r != "" then .requestId = $r else . end
      | if $m != "" then .message.id = $m else . end'
  }
  {
    printf '%s\n' '{"type":"user","message":{"content":"hi"}}'
    turn req-a "" 100000; turn req-a "" 100000; turn req-a "" 100000
    turn "" msg-b 250000; turn "" msg-b 250000
    turn "" ""    50000
    turn req-c "" 300000; turn req-c "" 300000
  } > "$T"
}
teardown() { common_teardown; }

@test "counts a turn split across lines once" {
  run python3 "$TOOL" --transcript "$T" --json --soft 400 --hard 500
  [ "$status" -eq 0 ]
  assert_equal "$(jq -r .turns   <<<"$output")" 4
  assert_equal "$(jq -r .current <<<"$output")" 300000
  assert_equal "$(jq -r .peak    <<<"$output")" 300000
  assert_equal "$(jq -r .avg     <<<"$output")" 175000
}

@test "exit status tracks the soft and hard ceilings" {
  run python3 "$TOOL" --transcript "$T" --json --soft 400 --hard 500
  [ "$status" -eq 0 ]
  assert_equal "$(jq -r .state <<<"$output")" under-soft
  run python3 "$TOOL" --transcript "$T" --json --soft 200 --hard 500
  [ "$status" -eq 1 ]
  assert_equal "$(jq -r .state <<<"$output")" past-soft
  run python3 "$TOOL" --transcript "$T" --json --soft 100 --hard 250
  [ "$status" -eq 2 ]
  assert_equal "$(jq -r .state <<<"$output")" past-hard
}
