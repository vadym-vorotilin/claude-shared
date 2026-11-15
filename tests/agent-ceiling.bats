#!/usr/bin/env bats
#
# hooks/agent-ceiling.py — PreToolUse hook that measures a dispatched agent's
# context. It fails open; when it cannot measure an agent it leaves a
# "skipped" line on stderr. The main loop is exempt and must stay silent,
# because the hook runs on every one of its tool calls.

load 'helpers/setup'

setup() {
  common_setup
  HOOK="$REPO/skills/context-ceiling/hooks/agent-ceiling.py"
  PROJ="$TEST_TMP/projects/example"
  mkdir -p "$PROJ"
  MAIN="$PROJ/session-1.jsonl"
  printf '%s\n' '{"type":"user","message":{"content":"hi"}}' > "$MAIN"
}
teardown() { common_teardown; }

hook() { # payload-json
  printf '%s' "$1" | python3 "$HOOK" 2>"$TEST_TMP/stderr"
}

@test "main-loop call (no agent_id, main transcript) exits 0 and stays silent" {
  run hook "$(jq -cn --arg tp "$MAIN" '{transcript_path:$tp, tool_name:"Bash"}')"
  [ "$status" -eq 0 ]
  assert_equal "$(cat "$TEST_TMP/stderr")" ""
}

@test "agent_id whose transcript is missing exits 0 with a skipped breadcrumb" {
  run hook "$(jq -cn --arg tp "$MAIN" '{transcript_path:$tp, agent_id:"a1b2c3", tool_name:"Bash"}')"
  [ "$status" -eq 0 ]
  assert_contains "$(cat "$TEST_TMP/stderr")" "agent-ceiling: skipped"
}

@test "the pre-move hook and tool paths still resolve (installed links point there)" {
  # Projects installed before the context-ceiling skill existed link to the
  # orchestrator's copy; if that path dangles, the [ -r ] guard turns the hook
  # off silently.
  old="$REPO/skills/orchestrating-issue-runs"
  [ -r "$old/hooks/agent-ceiling.py" ] || fail "old hook path dangles"
  [ -r "$old/tools/context-size.py" ] || fail "old context-size path dangles"
  [ "$(readlink -f "$old/hooks/agent-ceiling.py")" = "$(readlink -f "$HOOK")" ] \
    || fail "old hook path does not resolve to the hook"
  [ "$(readlink -f "$old/tools/context-size.py")" = "$(readlink -f "$REPO/skills/context-ceiling/tools/context-size.py")" ] \
    || fail "old context-size path does not resolve to the tool"
}

# The thresholds themselves: a subagent transcript whose last assistant turn
# has the given context size, run through the hook as a dispatched agent.
agent_at() { # context-tokens
  local d="$PROJ/session-1/subagents"
  mkdir -p "$d"
  jq -cn --argjson c "$1" '
    {type:"assistant", requestId:"req-1",
     message:{usage:{input_tokens:10, cache_read_input_tokens:($c-10),
                     cache_creation_input_tokens:0, output_tokens:5}}}' \
    > "$d/agent-x.jsonl"
  hook "$(jq -cn --arg tp "$d/agent-x.jsonl" '{transcript_path:$tp, agent_id:"x", tool_name:"Bash"}')"
}

@test "an agent under the soft ceiling (240k) is not blocked" {
  run agent_at 240000
  [ "$status" -eq 0 ]
  assert_equal "$(cat "$TEST_TMP/stderr")" ""
}

@test "an agent past the default soft ceiling (260k) is blocked at ~250,000" {
  run agent_at 260000
  [ "$status" -eq 2 ]
  assert_contains "$(cat "$TEST_TMP/stderr")" "~250,000"
  [[ "$(cat "$TEST_TMP/stderr")" != *"HARD STOP"* ]]
}

@test "an agent past the default hard ceiling (310k) is blocked at ~300,000" {
  run agent_at 310000
  [ "$status" -eq 2 ]
  assert_contains "$(cat "$TEST_TMP/stderr")" "HARD STOP"
  assert_contains "$(cat "$TEST_TMP/stderr")" "~300,000"
}

@test "AGENT_CEILING_SOFT=150000 blocks an agent at 160k, which the default allows" {
  run agent_at 160000
  [ "$status" -eq 0 ]
  export AGENT_CEILING_SOFT=150000
  run agent_at 160000
  [ "$status" -eq 2 ]
  assert_contains "$(cat "$TEST_TMP/stderr")" "~150,000"
}
