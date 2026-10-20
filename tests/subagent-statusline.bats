#!/usr/bin/env bats
#
# subagent-statusline-command.sh — reads the agent panel's rows as JSON on
# stdin, prints one {"id","content"} line per row.

load 'helpers/setup'

setup() {
  common_setup
  # Pin the clock 30 seconds past the turn the fixtures date: a tenth of a
  # subagent's 5-minute TTL.
  export STATUSLINE_NOW=1767225640            # 2026-01-01T00:00:40Z
  TP="$TEST_TMP/sess.jsonl"
  : > "$TP"
}
teardown() { common_teardown; }

# The fixtures' last turn, as an epoch, for tests that move the clock.
FIXTURE_TURN=1767225610                       # 2026-01-01T00:00:10Z

# Panel input: the session's transcript, a width, and the rows given as JSON
# objects, merged over a running Opus agent's defaults.
panel_json() { # columns task-json...
  local cols="$1"; shift
  printf '%s\n' "$@" | jq -s --arg tp "$TP" --argjson c "$cols" '
    {transcript_path: $tp, columns: $c,
     tasks: [to_entries[] | {id: "a\(.key + 1)", type: "local_agent",
       agentType: "Explore", status: "running", model: "claude-opus-5-5",
       effort: "high", contextWindowSize: 1000000, tokenCount: 0,
       label: "Working", startTime: (.key + 1)} + .value]}'
}

panel() { panel_json "$@" | bash "$REPO/claude/subagent-statusline-command.sh"; }

plain() { printf '%s' "$1" | sed -E "s/$(printf '\033')\[[0-9;]*m//g"; }
# Content of the Nth row, with and without color.
row()       { printf '%s\n' "$1" | sed -n "$2p" | jq -r '.content'; }
plain_row() { plain "$(row "$1" "$2")"; }

@test "prints one id/content line per row, in the harness's schema" {
  make_subagent "$TP" a1 Explore claude-opus-5-5 220000
  out="$(panel 120 '{}' '{}')"
  assert_equal "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" 2
  assert_equal "$(printf '%s\n' "$out" | sed -n 1p | jq -r 'keys | join(",")')" "content,id"
  assert_equal "$(printf '%s\n' "$out" | sed -n 2p | jq -r '.id')" "a2"
}

@test "lays a row out like the session line: agent, model, effort, context, TTL, details" {
  make_subagent "$TP" a1 Explore claude-opus-5-5 220000
  out="$(panel 120 '{"label":"Finding where the TTL is computed"}')"
  assert_equal "$(plain_row "$out" 1)" "Explore | O 5.5 | h ▅ | 22% | 10% | Finding where the TTL is computed"
}

@test "prints nothing when the panel has no rows" {
  out="$(printf '%s' '{"columns":120,"tasks":[]}' | bash "$REPO/claude/subagent-statusline-command.sh")"
  assert_equal "$out" ""
}

@test "never prints empty content, which would hide the row" {
  out="$(panel 20 '{"label":""}')"
  [ -n "$(row "$out" 1)" ] || fail "empty content"
}

# ---- columns ---------------------------------------------------------------

@test "labels the model by family initial and version" {
  out="$(panel 120 '{"model":"claude-opus-5-5"}' '{"model":"claude-haiku-4-5-20251001"}' \
                   '{"model":"claude-sonnet-5[1m]"}' '{"model":"claude-fable-5-1"}')"
  assert_contains "$(plain_row "$out" 1)" "| O 5.5 |"
  assert_contains "$(plain_row "$out" 2)" "| H 4.5 |"
  assert_contains "$(plain_row "$out" 3)" "| S 5   |"
  assert_contains "$(plain_row "$out" 4)" "| F 5.1 |"
}

@test "falls back to the model the agent's last turn ran on" {
  make_subagent "$TP" a1 Explore claude-sonnet-5 100000
  out="$(panel 120 '{"model":null}')"
  assert_contains "$(plain_row "$out" 1)" "| S 5 |"
}

@test "writes effort as its initial with the session line's bar and color" {
  out="$(panel 120 '{"effort":"low"}' '{"effort":"medium"}' '{"effort":"high"}' \
                   '{"effort":"xhigh"}' '{"effort":"max"}')"
  assert_contains "$(row "$out" 1)" $'\033[38;5;30ml ▁'
  assert_contains "$(row "$out" 2)" $'\033[38;5;71mm ▃'
  assert_contains "$(row "$out" 3)" $'\033[38;5;136mh ▅'
  assert_contains "$(row "$out" 4)" $'\033[38;5;166mx ▇'
  assert_contains "$(row "$out" 5)" $'\033[1;38;5;160mM █'
}

@test "drops the effort column when no agent has an effort" {
  out="$(panel 120 '{"effort":null,"model":"claude-haiku-4-5"}')"
  assert_contains "$(plain_row "$out" 1)" "Explore | H 4.5 | — | — | Working"
}

@test "leaves the effort cell blank for an agent without one beside one with" {
  out="$(panel 120 '{"effort":null}' '{"effort":"high"}')"
  assert_contains "$(plain_row "$out" 1)" "| O 5.5 |     |"
}

# An agent whose definition sets no effort runs at the session's, which the
# main status line records per session.
@test "shows the session's effort for an agent without one of its own" {
  mkdir -p "$HOME/.claude/cache/statusline-session-effort"
  echo xhigh > "$HOME/.claude/cache/statusline-session-effort/s1"
  out="$(panel_json 120 '{"effort":null}' '{"effort":"low"}' | jq '.session_id = "s1"' \
    | bash "$REPO/claude/subagent-statusline-command.sh")"
  assert_contains "$(plain_row "$out" 1)" "| x ▇ |"
  assert_contains "$(plain_row "$out" 2)" "| l ▁ |"
}

# The task's tokenCount adds every output token the agent ever wrote, so the
# transcript's last turn is the reading; the window is the harness's.
@test "measures context off the last turn against the harness's window" {
  make_subagent "$TP" a1 Explore claude-opus-5-5 220000
  out="$(panel 120 '{"tokenCount":300000,"contextWindowSize":1000000}')"
  assert_contains "$(plain_row "$out" 1)" "| 22% |"
}

@test "falls back to the task's token count before a transcript exists" {
  out="$(panel 120 '{"tokenCount":50000,"contextWindowSize":200000}')"
  assert_contains "$(plain_row "$out" 1)" "| 25% |"
}

@test "guesses the window from the reading when the harness sends none" {
  make_subagent "$TP" a1 Explore claude-opus-5-5 300000
  out="$(panel 120 '{"contextWindowSize":null}')"
  assert_contains "$(plain_row "$out" 1)" "| 30% |"
}

@test "never renders a context percentage past 100" {
  make_subagent "$TP" a1 Explore claude-opus-5-5 260000
  out="$(panel 120 '{"contextWindowSize":200000}')"
  assert_contains "$(plain_row "$out" 1)" "| 100% |"
}

@test "shows a dash, not 0%, before an agent's first turn" {
  make_subagent "$TP" a1 Explore ""
  out="$(panel 120 '{}')"
  assert_contains "$(plain_row "$out" 1)" "| h ▅ | — | — |"
}

@test "colors context yellow and the TTL white, turning red near expiry" {
  make_subagent "$TP" a1 Explore claude-opus-5-5 220000
  fresh="$(row "$(panel 120 '{}')" 1)"
  stale="$(row "$(STATUSLINE_NOW=$(( FIXTURE_TURN + 240 )) panel 120 '{}')" 1)"
  assert_contains "$fresh" $'\033[33m22%'
  assert_contains "$fresh" $'\033[37m10%'
  assert_contains "$stale" $'\033[31m80%'
}

@test "falls back to five minutes for a turn that wrote no cache" {
  make_subagent "$TP" a1 Explore ""
  jq -cn '{type:"assistant", timestamp:"2026-01-01T00:00:10.000Z",
    message:{model:"claude-haiku-4-5", usage:{input_tokens:1,
      cache_creation_input_tokens:0, cache_read_input_tokens:19999}}}' \
    >> "$TEST_TMP/sess/subagents/agent-a1.jsonl"
  out="$(panel 120 '{}')"
  assert_contains "$(plain_row "$out" 1)" "| 10% |"
}

@test "finds the transcripts by session id when no transcript path is sent" {
  mkdir -p "$HOME/.claude/projects/-proj"
  TP="$HOME/.claude/projects/-proj/s1.jsonl"
  make_subagent "$TP" a1 Explore claude-opus-5-5 220000
  out="$(panel_json 120 '{}' | jq '.session_id = "s1" | del(.transcript_path)' \
    | bash "$REPO/claude/subagent-statusline-command.sh")"
  assert_contains "$(plain_row "$out" 1)" "| 22% | 10% |"
}

# ---- names -----------------------------------------------------------------

@test "a named agent keeps its name" {
  out="$(panel 120 '{"name":"reviewer"}')"
  assert_contains "$(plain_row "$out" 1)" "reviewer |"
}

@test "numbers a repeated type in spawn order, and only a repeated one" {
  out="$(panel 120 '{"startTime":30}' '{"startTime":10}' '{"agentType":"general-purpose","startTime":20}')"
  assert_equal "$(printf '%s\n' "$out" | jq -r '.id' | tr '\n' ' ')" "a2 a3 a1 "
  assert_contains "$(plain_row "$out" 1)" "Explore#1 |"
  assert_contains "$(plain_row "$out" 2)" "general   |"
  assert_contains "$(plain_row "$out" 3)" "Explore#2 |"
}

@test "shows the built-in general-purpose type as general" {
  out="$(panel 120 '{"agentType":"general-purpose"}')"
  assert_contains "$(plain_row "$out" 1)" "general | O 5.5"
}

# The narrow case the panel actually meets: a 60-column terminal, with every
# column in use, still keeps some details.
@test "keeps details on a 60-column panel" {
  make_subagent "$TP" a1 Explore claude-opus-5-5 220000
  out="$(panel 60 '{"agentType":"general-purpose","label":"Ping localhost"}' '{"agentType":"general-purpose"}')"
  assert_contains "$(plain_row "$out" 1)" "general#1 | O 5.5 | h ▅ | 22% | 10% | Ping loc"
}

@test "drops a plugin prefix from the agent type" {
  out="$(panel 120 '{"agentType":"toolkit:builder"}')"
  assert_contains "$(plain_row "$out" 1)" "builder |"
  refute_contains "$(plain_row "$out" 1)" "toolkit"
}

@test "pads every row to the same columns" {
  out="$(panel 120 '{"name":"a"}' '{"name":"much-longer-name","model":"claude-sonnet-5"}')"
  assert_contains "$(plain_row "$out" 1)" "a                | O 5.5 |"
  assert_contains "$(plain_row "$out" 2)" "much-longer-name | S 5   |"
}

# ---- state -----------------------------------------------------------------

@test "grays a finished row and marks how it ended" {
  out="$(panel 120 '{"status":"completed","label":"Listed callers"}' '{"status":"failed","label":"Ported tests"}')"
  assert_contains "$(plain_row "$out" 1)" "| ✓ Listed callers"
  assert_contains "$(plain_row "$out" 2)" "| ✗ Ported tests"
  refute_contains "$(row "$out" 1)" $'\033[35m'
  assert_contains "$(row "$out" 1)" $'\033[90mO 5.5'
}

@test "shows the description when there is no progress label" {
  out="$(panel 120 '{"label":null,"description":"Review the diff"}')"
  assert_contains "$(plain_row "$out" 1)" "| Review the diff"
}

@test "flattens tabs and newlines in a label onto one line" {
  out="$(panel 120 '{"label":"one\ttwo\nthree"}')"
  assert_contains "$(plain_row "$out" 1)" "| one two three"
}

# ---- width -----------------------------------------------------------------

@test "cuts long details to the width, by character" {
  out="$(panel 60 '{"label":"ünïcödé détails that run well past the edge"}')"
  r="$(plain_row "$out" 1)"
  assert_contains "$r" "| ünïcö"
  assert_contains "$r" "…"
  [ "$(printf '%s' "$r" | jq -Rr 'length')" -le 54 ] || fail "row wider than 54: $r"
}

@test "drops the details first, then the effort letter, then cuts the name" {
  assert_equal "$(plain_row "$(panel 44 '{}')" 1)" "Explore | O 5.5 | h ▅ | — | —"
  assert_equal "$(plain_row "$(panel 34 '{}')" 1)" "Explore | O 5.5 | ▅ | — | —"
  assert_equal "$(plain_row "$(panel 32 '{}')" 1)" "Explo… | O 5.5 | ▅ | — | —"
}
