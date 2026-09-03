#!/usr/bin/env bats
#
# statusline-command.sh — reads a JSON blob on stdin, prints a colored line.

load 'helpers/setup'

setup() {
  common_setup
  # Hermetic by default: no CLI model table, so tests exercise the built-in
  # fallback unless they point STATUSLINE_MODEL_WINDOWS at a fixture.
  export STATUSLINE_MODEL_WINDOWS="$TEST_TMP/no-model-table"
  # Pin the clock 30 seconds past the turn the fixtures date, so the cache
  # reading is deterministic: a tenth of a subagent's 5-minute TTL.
  export STATUSLINE_NOW=1767225640            # 2026-01-01T00:00:40Z
}

# The fixtures' last turn, as an epoch, for tests that move the clock.
FIXTURE_TURN=1767225610                       # 2026-01-01T00:00:10Z
teardown() { common_teardown; }

statusline() { printf '%s' "$1" | bash "$REPO/claude/statusline-command.sh"; }

# Nth line of the output (1-based), for layout assertions.
line_n() { printf '%s\n' "$1" | sed -n "$2p"; }
# Lines in the output, counting a final unterminated line.
count_lines() { printf '%s\n' "$1" | wc -l | tr -d ' '; }

@test "renders model display name and cwd" {
  json="$(jq -n --arg c /tmp/proj --arg m 'Opus 4.8' '{cwd:$c, model:{display_name:$m}}')"
  out="$(statusline "$json")"
  assert_contains "$out" "Opus 4.8"
  assert_contains "$out" "/tmp/proj"
}

@test "shortens \$HOME to a literal ~" {
  json="$(jq -n --arg c "$HOME/foo" --arg m M '{cwd:$c, model:{display_name:$m}}')"
  out="$(statusline "$json")"
  # BUG: ${cwd/#$home/~} tilde-expands the replacement back to $HOME, so the
  # home prefix is rewritten to itself and the full path is shown, never "~".
  assert_contains "$out" "~/foo"
  refute_contains "$out" "$HOME/foo"
}

@test "renders context window percentage, rounded" {
  json="$(jq -n --arg c /tmp --arg m M '{cwd:$c, model:{display_name:$m}, context_window:{used_percentage:42.7}}')"
  out="$(statusline "$json")"
  assert_contains "$out" "ctx: 43%"
}

@test "renders 5-hour quota percentage" {
  json="$(jq -n --arg c /tmp --arg m M '{cwd:$c, model:{display_name:$m}, rate_limits:{five_hour:{used_percentage:10}}}')"
  out="$(statusline "$json")"
  assert_contains "$out" "5h: 10%"
}

# macOS /bin/bash is 3.2; its builtin printf has no %f support and errors on
# floats. Rounding must happen in jq so fractional percentages render cleanly
# under the actual interpreter the script runs with.
@test "rounds a fractional 5-hour percentage instead of erroring" {
  json="$(jq -n --arg c /tmp --arg m M '{cwd:$c, model:{display_name:$m}, rate_limits:{five_hour:{used_percentage:0.3}}}')"
  out="$(/bin/bash "$REPO/claude/statusline-command.sh" <<<"$json")"
  assert_contains "$out" "5h: 0%"
  refute_contains "$out" "invalid number"
}

@test "rounds a fractional 5-hour percentage up at the .5 boundary" {
  json="$(jq -n --arg c /tmp --arg m M '{cwd:$c, model:{display_name:$m}, rate_limits:{five_hour:{used_percentage:0.6}}}')"
  out="$(/bin/bash "$REPO/claude/statusline-command.sh" <<<"$json")"
  assert_contains "$out" "5h: 1%"
}

@test "rounds a fractional context percentage under /bin/bash 3.2" {
  json="$(jq -n --arg c /tmp --arg m M '{cwd:$c, model:{display_name:$m}, context_window:{used_percentage:42.7}}')"
  out="$(/bin/bash "$REPO/claude/statusline-command.sh" <<<"$json")"
  assert_contains "$out" "ctx: 43%"
  refute_contains "$out" "invalid number"
}

# The countdown to the 5-hour window reset uses resets_at (Unix epoch seconds)
# minus "now". STATUSLINE_NOW overrides now so the elapsed math is deterministic.
@test "shows hours and zero-padded minutes until the 5-hour window recycles" {
  now=1000000000; reset=$(( now + 2*3600 + 3*60 ))   # 2h03m out
  json="$(jq -n --arg c /tmp --arg m M --argjson r "$reset" \
    '{cwd:$c, model:{display_name:$m}, rate_limits:{five_hour:{used_percentage:10, resets_at:$r}}}')"
  out="$(STATUSLINE_NOW=$now statusline "$json")"
  assert_contains "$out" "5h: 10% (-2h 03m)"
}

@test "shows minutes-only countdown when under an hour remains" {
  now=1000000000; reset=$(( now + 13*60 ))           # 13m out
  json="$(jq -n --arg c /tmp --arg m M --argjson r "$reset" \
    '{cwd:$c, model:{display_name:$m}, rate_limits:{five_hour:{used_percentage:90, resets_at:$r}}}')"
  out="$(STATUSLINE_NOW=$now statusline "$json")"
  assert_contains "$out" "5h: 90% (-13m)"
}

@test "omits the countdown when the window has already reset" {
  now=1000000000; reset=$(( now - 60 ))              # already past
  json="$(jq -n --arg c /tmp --arg m M --argjson r "$reset" \
    '{cwd:$c, model:{display_name:$m}, rate_limits:{five_hour:{used_percentage:5, resets_at:$r}}}')"
  out="$(STATUSLINE_NOW=$now statusline "$json")"
  assert_contains "$out" "5h: 5%"
  refute_contains "$out" "("
}

@test "shows the 5h percentage with no countdown when resets_at is absent" {
  json="$(jq -n --arg c /tmp --arg m M \
    '{cwd:$c, model:{display_name:$m}, rate_limits:{five_hour:{used_percentage:10}}}')"
  out="$(statusline "$json")"
  assert_contains "$out" "5h: 10%"
  refute_contains "$out" "("
}

@test "omits ctx/5h segments when those fields are absent" {
  json="$(jq -n --arg c /tmp --arg m M '{cwd:$c, model:{display_name:$m}}')"
  out="$(statusline "$json")"
  refute_contains "$out" "ctx:"
  refute_contains "$out" "5h:"
}

# ---- multiline layout -----------------------------------------------------
# Line 1: dir + git | line 2: model + ctx | line 3: 5h + 1w quotas.

@test "renders three lines: location, session, quotas" {
  json="$(jq -n --arg c /tmp/proj --arg m 'Opus 4.8' \
    '{cwd:$c, model:{display_name:$m}, context_window:{used_percentage:42},
      rate_limits:{five_hour:{used_percentage:31}, seven_day:{used_percentage:58}}}')"
  out="$(statusline "$json")"
  assert_equal "$(count_lines "$out")" 4   # 3 content lines + spacer
  assert_contains "$(line_n "$out" 1)" "/tmp/proj"
  refute_contains "$(line_n "$out" 1)" "Opus 4.8"
  assert_contains "$(line_n "$out" 2)" "Opus 4.8"
  assert_contains "$(line_n "$out" 2)" "ctx: 42%"
  refute_contains "$(line_n "$out" 2)" "5h:"
  assert_contains "$(line_n "$out" 3)" "5h: 31%"
  assert_contains "$(line_n "$out" 3)" "1w: 58%"
}

# A trailing blank line keeps the status visually separated from the CLI
# chrome below it. Claude Code trims trailing whitespace-only lines, so the
# spacer must be a non-whitespace blank: U+2800 BRAILLE PATTERN BLANK.
@test "ends with a braille-blank spacer line" {
  json="$(jq -n --arg c /tmp --arg m M \
    '{cwd:$c, model:{display_name:$m}, rate_limits:{five_hour:{used_percentage:10}}}')"
  raw="$(statusline "$json"; printf x)"; raw="${raw%x}"
  case "$raw" in
    *$'\n'"⠀") : ;;
    *) fail "expected output to end with a newline + U+2800 spacer" ;;
  esac
}

@test "git branch renders on the first line, next to the dir" {
  make_git_repo "$TEST_TMP/r"
  json="$(jq -n --arg c "$TEST_TMP/r" --arg m M '{cwd:$c, model:{display_name:$m}}')"
  out="$(statusline "$json")"
  assert_contains "$(line_n "$out" 1)" "main"
}

@test "omits the quota line entirely when rate_limits is absent" {
  json="$(jq -n --arg c /tmp --arg m M \
    '{cwd:$c, model:{display_name:$m}, context_window:{used_percentage:42}}')"
  out="$(statusline "$json")"
  assert_equal "$(count_lines "$out")" 3   # 2 content lines + spacer
  refute_contains "$out" "5h:"
  refute_contains "$out" "1w:"
}

@test "renders the quota line with only the weekly segment when 5h is absent" {
  json="$(jq -n --arg c /tmp --arg m M \
    '{cwd:$c, model:{display_name:$m}, rate_limits:{seven_day:{used_percentage:58}}}')"
  out="$(statusline "$json")"
  assert_contains "$(line_n "$out" 3)" "1w: 58%"
  refute_contains "$out" "5h:"
}

# 5h is the quota you actively burn through; 1w moves slowly, so it renders
# in dark gray (ANSI 90) to recede next to the white 5h segment.
@test "colors the weekly quota darker than the 5h quota" {
  json="$(jq -n --arg c /tmp --arg m M \
    '{cwd:$c, model:{display_name:$m}, rate_limits:{five_hour:{used_percentage:31}, seven_day:{used_percentage:58}}}')"
  out="$(statusline "$json")"
  assert_contains "$out" $'\033[37m'"5h: 31%"
  assert_contains "$out" $'\033[90m'"1w: 58%"
}

@test "rounds a fractional weekly percentage under /bin/bash 3.2" {
  json="$(jq -n --arg c /tmp --arg m M \
    '{cwd:$c, model:{display_name:$m}, rate_limits:{seven_day:{used_percentage:0.6}}}')"
  out="$(/bin/bash "$REPO/claude/statusline-command.sh" <<<"$json")"
  assert_contains "$out" "1w: 1%"
  refute_contains "$out" "invalid number"
}

@test "shows a day-scale countdown until the weekly window recycles" {
  now=1000000000; reset=$(( now + 3*86400 + 14*3600 ))   # 3d 14h out
  json="$(jq -n --arg c /tmp --arg m M --argjson r "$reset" \
    '{cwd:$c, model:{display_name:$m}, rate_limits:{seven_day:{used_percentage:58, resets_at:$r}}}')"
  out="$(STATUSLINE_NOW=$now statusline "$json")"
  assert_contains "$out" "1w: 58% (-3d 14h)"
}

@test "weekly countdown falls back to hours and minutes under a day" {
  now=1000000000; reset=$(( now + 2*3600 + 3*60 ))       # 2h03m out
  json="$(jq -n --arg c /tmp --arg m M --argjson r "$reset" \
    '{cwd:$c, model:{display_name:$m}, rate_limits:{seven_day:{used_percentage:90, resets_at:$r}}}')"
  out="$(STATUSLINE_NOW=$now statusline "$json")"
  assert_contains "$out" "1w: 90% (-2h 03m)"
}

@test "shows the git branch for a repo cwd" {
  make_git_repo "$TEST_TMP/r"
  json="$(jq -n --arg c "$TEST_TMP/r" --arg m M '{cwd:$c, model:{display_name:$m}}')"
  out="$(statusline "$json")"
  assert_contains "$out" "main"
}

@test "shows staged / unstaged / untracked indicators" {
  make_git_repo "$TEST_TMP/r"
  echo new > "$TEST_TMP/r/staged.txt";   git -C "$TEST_TMP/r" add staged.txt   # staged  +1
  echo more >> "$TEST_TMP/r/seed.txt"                                          # unstaged !1
  echo loose > "$TEST_TMP/r/untracked.txt"                                     # untracked ?1
  json="$(jq -n --arg c "$TEST_TMP/r" --arg m M '{cwd:$c, model:{display_name:$m}}')"
  out="$(statusline "$json")"
  assert_contains "$out" "+1"
  assert_contains "$out" "!1"
  assert_contains "$out" "?1"
}

@test "shows ahead count against an upstream" {
  make_git_repo_with_upstream "$TEST_TMP/r"
  echo a >> "$TEST_TMP/r/seed.txt"
  git -C "$TEST_TMP/r" commit -qam local   # one commit ahead of origin/main
  json="$(jq -n --arg c "$TEST_TMP/r" --arg m M '{cwd:$c, model:{display_name:$m}}')"
  out="$(statusline "$json")"
  assert_contains "$out" "⇡1"
}

@test "a non-git cwd shows no branch segment" {
  json="$(jq -n --arg c "$HOME" --arg m M '{cwd:$c, model:{display_name:$m}}')"
  out="$(statusline "$json")"
  assert_contains "$out" "M"
  refute_contains "$out" "main"
}

# ---- subagents ------------------------------------------------------------
# The harness never sends subagent state, so the script reads the sidechain
# transcripts Claude Code writes under <session-id>/subagents/ and renders the
# ones still being appended to as one compact line: "S/34%/40% · O/11%/2%".

# Session JSON pointing at a transcript path inside the test tmpdir.
session_json() { # transcript-path
  jq -n --arg c /tmp/proj --arg m 'Opus 5' --arg tp "$1" \
    '{cwd:$c, model:{display_name:$m}, transcript_path:$tp}'
}

# The agent line composes colored fragments, so assert on it without ANSI.
plain() { printf '%s' "$1" | sed -E "s/$(printf '\033')\[[0-9;]*m//g"; }
agent_line() { plain "$(line_n "$1" 3)"; }

@test "renders a live subagent as a model initial and context percentage" {
  tp="$TEST_TMP/sess.jsonl"
  make_subagent "$tp" a1 general-purpose claude-haiku-4-5-20251001 40000
  out="$(statusline "$(session_json "$tp")")"
  assert_equal "$(agent_line "$out")" "H/20%/10%"
}

@test "the initial is the agent's own model, not the session's" {
  tp="$TEST_TMP/sess.jsonl"
  make_subagent "$tp" a1 Explore claude-haiku-4-5-20251001 20000
  out="$(statusline "$(session_json "$tp")")"
  assert_contains "$(line_n "$out" 2)" "Opus 5"   # session line unchanged
  assert_equal "$(agent_line "$out")" "H/10%/10%"
}

@test "renders several subagents on one line, separated by a middot" {
  tp="$TEST_TMP/sess.jsonl"
  make_subagent "$tp" a1 Explore claude-haiku-4-5-20251001 40000
  make_subagent "$tp" a2 Explore claude-sonnet-5 250000
  out="$(statusline "$(session_json "$tp")")"
  assert_equal "$(count_lines "$out")" 4           # dir, session, agents, spacer
  assert_equal "$(agent_line "$out")" "H/20%/10% · S/25%/10%"
}

# Spawn order, matching the agent list the CLI shows below the prompt. meta.json
# is written once at spawn; the transcript is appended to constantly, so
# ordering on that reshuffled the line every second.
@test "orders subagents oldest-spawned first" {
  tp="$TEST_TMP/sess.jsonl"
  make_subagent "$tp" zzz Explore claude-haiku-4-5-20251001 40000
  make_subagent "$tp" aaa Explore claude-sonnet-5 250000
  touch -d "@$(( $(date +%s) - 30 ))" "$TEST_TMP/sess/subagents/agent-zzz.meta.json"
  out="$(statusline "$(session_json "$tp")")"
  assert_equal "$(agent_line "$out")" "H/20%/10% · S/25%/10%"
}

@test "the order ignores which subagent wrote most recently" {
  tp="$TEST_TMP/sess.jsonl"
  make_subagent "$tp" older Explore claude-haiku-4-5-20251001 40000
  make_subagent "$tp" newer Explore claude-sonnet-5 250000
  d="$TEST_TMP/sess/subagents"
  touch -d "@$(( $(date +%s) - 30 ))" "$d/agent-older.meta.json"
  touch "$d/agent-older.jsonl"                    # oldest agent, newest write
  out="$(statusline "$(session_json "$tp")")"
  assert_equal "$(agent_line "$out")" "H/20%/10% · S/25%/10%"
}

# A single tool result can run past the tail the script scans — a big file
# read lands as one 400 KB line — and then the tail holds no assistant turn at
# all. The agent must not lose its readings to that; scan further back.
@test "still reads an agent whose last transcript line outruns the scanned tail" {
  tp="$TEST_TMP/sess.jsonl"
  make_subagent "$tp" a1 Explore claude-haiku-4-5-20251001 20000
  { printf '{"type":"user","isSidechain":true,"timestamp":"2026-01-01T00:00:11.000Z","message":{"role":"user","content":"'
    head -c 300000 /dev/zero | tr '\0' x
    printf '"}}\n'; } >> "$TEST_TMP/sess/subagents/agent-a1.jsonl"
  out="$(statusline "$(session_json "$tp")")"
  assert_equal "$(agent_line "$out")" "H/10%/10%"
}

@test "shows no subagent line when the session has none" {
  tp="$TEST_TMP/sess.jsonl"
  out="$(statusline "$(session_json "$tp")")"
  assert_equal "$(count_lines "$out")" 3   # dir, session, spacer
}

@test "shows no subagent line when transcript_path is absent" {
  json="$(jq -n --arg c /tmp --arg m M '{cwd:$c, model:{display_name:$m}}')"
  out="$(statusline "$json")"
  assert_equal "$(count_lines "$out")" 3
}

# An agent that finished is retired by the session's record of its result (see
# below); the window is only a backstop for one whose result never lands.
@test "drops a subagent long past the liveness window" {
  tp="$TEST_TMP/sess.jsonl"
  make_subagent "$tp" a1 general-purpose claude-opus-5 10000
  out="$(STATUSLINE_NOW=$(( $(date +%s) + 7200 )) statusline "$(session_json "$tp")")"
  assert_equal "$(count_lines "$out")" 3
}

# A running agent goes quiet for minutes waiting on a long tool call — 1% of
# the gaps between a running agent's own entries run past 170s — so silence is
# not evidence that it finished.
@test "keeps a subagent that has gone quiet mid-run" {
  tp="$TEST_TMP/sess.jsonl"
  make_subagent "$tp" a1 general-purpose claude-haiku-4-5 20000
  touch -d "@$(( $(date +%s) - 300 ))" "$TEST_TMP/sess/subagents/agent-a1.jsonl"
  out="$(statusline "$(session_json "$tp")")"
  assert_equal "$(agent_line "$out")" "H/10%/10%"
}

# What does retire an agent: the session collecting its result, which it
# records after that agent's own last entry.
@test "drops a subagent once the session has recorded its result" {
  tp="$TEST_TMP/sess.jsonl"
  make_subagent "$tp" a1 general-purpose claude-haiku-4-5 20000
  make_session_ref "$tp" a1 "2026-01-01T00:00:12.000Z"   # after its last entry
  out="$(statusline "$(session_json "$tp")")"
  assert_equal "$(count_lines "$out")" 3
}

# The session also names an agent when it spawns it. That mention predates the
# agent's own entries and must not be read as a result.
@test "keeps a subagent whose only mention predates its last entry" {
  tp="$TEST_TMP/sess.jsonl"
  make_subagent "$tp" a1 general-purpose claude-haiku-4-5 20000
  make_session_ref "$tp" a1 "2026-01-01T00:00:05.000Z"   # before its last entry
  out="$(statusline "$(session_json "$tp")")"
  assert_equal "$(agent_line "$out")" "H/10%/10%"
}

# A background agent's tool result lands at spawn, long before it finishes, so
# a result alone can never retire one. What does is the notification the
# session gets when the agent reports its task complete.
@test "drops a background subagent once its completion notification lands" {
  tp="$TEST_TMP/sess.jsonl"
  make_subagent "$tp" a1 general-purpose claude-haiku-4-5 20000
  make_session_ref    "$tp" a1 "2026-01-01T00:00:02.000Z"   # the spawn result
  make_session_notify "$tp" a1 "2026-01-01T00:00:12.000Z"   # after its last entry
  out="$(statusline "$(session_json "$tp")")"
  assert_equal "$(count_lines "$out")" 3
}

# The notification does not always land as a turn. When the session is
# mid-turn it is enqueued and then removed from the queue, absorbed into the
# turn in flight, and the transcript holds only those queue entries for it.
# They carry the notification text, so they retire the agent just the same.
@test "drops a background subagent whose notification was queued but never delivered" {
  tp="$TEST_TMP/sess.jsonl"
  make_subagent "$tp" a1 general-purpose claude-haiku-4-5 20000
  make_session_ref           "$tp" a1 "2026-01-01T00:00:02.000Z"   # the spawn result
  make_session_notify_queued "$tp" a1 "2026-01-01T00:00:12.000Z"   # after its last entry
  out="$(statusline "$(session_json "$tp")")"
  assert_equal "$(count_lines "$out")" 3
}

# Given more work, it writes past that notification and comes back.
@test "keeps a background subagent that has written since its notification" {
  tp="$TEST_TMP/sess.jsonl"
  make_subagent "$tp" a1 general-purpose claude-haiku-4-5 20000
  make_session_notify "$tp" a1 "2026-01-01T00:00:05.000Z"   # before its last entry
  out="$(statusline "$(session_json "$tp")")"
  assert_equal "$(agent_line "$out")" "H/10%/10%"
}

# A session names an agent for reasons other than collecting its result.
# Queueing it a message writes entries naming it, and an agent idling on that
# queued message has by definition not written since — so the mention lands
# after its last entry and looks exactly like a result. Reading it as one
# retired agents in mid-run, which is the shape this rule must never get wrong.
@test "keeps a subagent that only had a message queued for it" {
  tp="$TEST_TMP/sess.jsonl"
  make_subagent "$tp" a1 general-purpose claude-haiku-4-5 20000
  make_session_queue "$tp" a1 "2026-01-01T00:00:12.000Z"   # after its last entry
  out="$(statusline "$(session_json "$tp")")"
  assert_equal "$(agent_line "$out")" "H/10%/10%"
}

# Sending a running agent a message is also a tool call with a result naming
# it, and an agent blocked on a long poll has not written since — so that
# result lands after its last entry too. It is not the agent's output.
@test "keeps a subagent that was sent a message while blocked on a poll" {
  tp="$TEST_TMP/sess.jsonl"
  make_subagent "$tp" a1 general-purpose claude-haiku-4-5 20000
  make_session_message "$tp" a1 "2026-01-01T00:00:12.000Z"   # after its last entry
  out="$(statusline "$(session_json "$tp")")"
  assert_equal "$(agent_line "$out")" "H/10%/10%"
}

@test "retires it once a result does land, queued message or not" {
  tp="$TEST_TMP/sess.jsonl"
  make_subagent "$tp" a1 general-purpose claude-haiku-4-5 20000
  make_session_queue "$tp" a1 "2026-01-01T00:00:12.000Z"
  make_session_ref   "$tp" a1 "2026-01-01T00:00:13.000Z"
  out="$(statusline "$(session_json "$tp")")"
  assert_equal "$(count_lines "$out")" 3
}

@test "retires only the finished agent, not its siblings" {
  tp="$TEST_TMP/sess.jsonl"
  make_subagent "$tp" a1 general-purpose claude-haiku-4-5 20000
  make_subagent "$tp" a2 general-purpose claude-haiku-4-5 40000
  make_session_ref "$tp" a1 "2026-01-01T00:00:12.000Z"
  out="$(statusline "$(session_json "$tp")")"
  assert_equal "$(agent_line "$out")" "H/20%/10%"
}

@test "collapses subagents past the cap into a +N entry" {
  tp="$TEST_TMP/sess.jsonl"
  for id in a1 a2 a3 a4; do make_subagent "$tp" "$id" Explore claude-haiku-4-5 20000; done
  out="$(STATUSLINE_AGENT_MAX=2 statusline "$(session_json "$tp")")"
  assert_equal "$(agent_line "$out")" "H/10%/10% · H/10%/10% · +2"
}

# meta.json records the spec ("haiku") even before the agent's first turn, but
# there's no usage yet to derive a percentage from.
@test "shows the initial alone before the agent's first turn" {
  tp="$TEST_TMP/sess.jsonl"
  make_subagent "$tp" a1 Plan ""
  out="$(statusline "$(session_json "$tp")")"
  assert_equal "$(agent_line "$out")" "H"
}

@test "falls back to ? when the model can't be determined" {
  tp="$TEST_TMP/sess.jsonl"
  make_subagent "$tp" a1 Plan ""
  rm "$TEST_TMP/sess/subagents/agent-a1.meta.json"
  out="$(statusline "$(session_json "$tp")")"
  assert_equal "$(agent_line "$out")" "?"
}

# Only the tail of a transcript is scanned, so a long-running agent stays
# cheap to read — but the last turn must still be found in it.
@test "reads the last turn from a transcript past the tail budget" {
  tp="$TEST_TMP/sess.jsonl"
  make_subagent "$tp" a1 Explore claude-haiku-4-5 10000
  f="$TEST_TMP/sess/subagents/agent-a1.jsonl"
  # A single oversized turn, written without passing it through argv.
  { printf '{"type":"user","message":{"role":"user","content":"'
    head -c 300000 /dev/zero | tr '\0' x
    printf '"}}\n'; } >> "$f"
  jq -cn '{type:"assistant", timestamp:"2026-01-01T00:00:10.000Z",
    message:{model:"claude-haiku-4-5", usage:{
      input_tokens:1, cache_creation_input_tokens:0, cache_read_input_tokens:59999}}}' >> "$f"
  out="$(statusline "$(session_json "$tp")")"
  assert_equal "$(agent_line "$out")" "H/30%/10%"
}

@test "the subagent line sits between the session line and the quota line" {
  tp="$TEST_TMP/sess.jsonl"
  make_subagent "$tp" a1 Explore claude-haiku-4-5 20000
  json="$(jq -n --arg c /tmp/proj --arg m 'Opus 5' --arg tp "$tp" \
    '{cwd:$c, model:{display_name:$m}, transcript_path:$tp,
      context_window:{used_percentage:12},
      rate_limits:{five_hour:{used_percentage:31}}}')"
  out="$(statusline "$json")"
  assert_equal "$(count_lines "$out")" 5   # dir, session, agents, quotas, spacer
  assert_contains "$(line_n "$out" 2)" "ctx: 12%"
  assert_equal "$(agent_line "$out")" "H/10%/10%"
  assert_contains "$(line_n "$out" 4)" "5h: 31%"
}

# The model initial takes the session model's color, the percentage the green
# of a healthy reading, and the slash the gray of the receding weekly quota.
@test "colors the initial, the percentage and the slash apart" {
  tp="$TEST_TMP/sess.jsonl"
  make_subagent "$tp" a1 Explore claude-haiku-4-5 20000
  out="$(statusline "$(session_json "$tp")")"
  assert_contains "$out" $'\033[35m'"H"
  assert_contains "$out" $'\033[90m'"/"
  assert_contains "$out" $'\033[32m'"10%"
}

# ---- subagent context windows ---------------------------------------------
# Windows are per-model — 1M for Fable and the [1m] variants, 200k for most
# others — and a transcript doesn't record which one an agent was given. The
# harness does send the size for the session's own model.

@test "measures an agent on the session's model against the harness's window size" {
  tp="$TEST_TMP/sess.jsonl"
  make_subagent "$tp" a1 general-purpose claude-fable-5-1 227678
  json="$(jq -n --arg c /tmp --arg tp "$tp" \
    '{cwd:$c, transcript_path:$tp, model:{id:"claude-fable-5-1", display_name:"Fable 5.1"},
      context_window:{used_percentage:14, context_window_size:1000000}}')"
  out="$(statusline "$json")"
  assert_equal "$(agent_line "$out")" "F/23%/10%"
}

# A smaller model under a 1M session keeps its own window, not the session's.
@test "an agent on a different model is measured by the model table" {
  tp="$TEST_TMP/sess.jsonl"
  make_subagent "$tp" a1 general-purpose claude-haiku-4-5-20251001 20000
  json="$(jq -n --arg c /tmp --arg tp "$tp" \
    '{cwd:$c, transcript_path:$tp, model:{id:"claude-fable-5-1", display_name:"Fable 5.1"},
      context_window:{context_window_size:1000000}}')"
  out="$(statusline "$json")"
  assert_equal "$(agent_line "$out")" "H/10%/10%"
}

@test "measures a 1M-context model against the million-token window" {
  tp="$TEST_TMP/sess.jsonl"
  make_subagent "$tp" a1 Explore 'claude-sonnet-5[1m]' 500000
  out="$(statusline "$(session_json "$tp")")"
  assert_equal "$(agent_line "$out")" "S/50%/10%"
}

# The model table will go stale. A turn can't exceed its own window, so a
# reading past 200k is proof a model it doesn't know was given a bigger one.
@test "infers a large window for an unknown model past the 200k default" {
  tp="$TEST_TMP/sess.jsonl"
  make_subagent "$tp" a1 general-purpose claude-sonnet-9 227678
  out="$(statusline "$(session_json "$tp")")"
  assert_equal "$(agent_line "$out")" "S/23%/10%"
}

# Sonnet and Opus crossed to 1M at 5 and 4.7; reading them against 200k put a
# perfectly healthy agent at 64%.
@test "measures the 1M generation of Sonnet and Opus against a million tokens" {
  tp="$TEST_TMP/sess.jsonl"
  make_subagent "$tp" a1 Explore claude-sonnet-5 250000
  make_subagent "$tp" a2 Explore claude-opus-5 100000
  out="$(statusline "$(session_json "$tp")")"
  assert_equal "$(agent_line "$out")" "S/25%/10% · O/10%/10%"
}

@test "measures the 200k generation of Sonnet and Opus against 200k" {
  tp="$TEST_TMP/sess.jsonl"
  make_subagent "$tp" a1 Explore claude-sonnet-4-5 40000
  make_subagent "$tp" a2 Explore claude-opus-4-5 40000
  out="$(statusline "$(session_json "$tp")")"
  assert_equal "$(agent_line "$out")" "S/20%/10% · O/20%/10%"
}

@test "never renders a context percentage past 100" {
  tp="$TEST_TMP/sess.jsonl"
  make_subagent "$tp" a1 general-purpose claude-opus-5 260000
  json="$(jq -n --arg c /tmp --arg tp "$tp" \
    '{cwd:$c, transcript_path:$tp, model:{id:"claude-opus-5", display_name:"Opus 5"},
      context_window:{context_window_size:200000}}')"
  out="$(statusline "$json")"
  assert_equal "$(agent_line "$out")" "O/100%/10%"
}

# ---- the CLI's model table ------------------------------------------------
# Windows move with the model lineup, so rather than carrying a table that goes
# stale they're read out of the installed CLI's own bundle and cached against
# its mtime and size.

# A file shaped like the bundle's model list, with invented models so a real
# lineup change can't make the test pass or fail for the wrong reason.
fake_bundle() { # path window-for-zeta
  printf '%s' 'var x=[' > "$1"
  for m in alpha-1 beta-2 gamma-3 delta-4; do
    printf '{id:"claude-%s",family:"%s",display_name:"X",context:{window:200000}},' \
      "$m" "${m%%-*}" >> "$1"
  done
  printf '{id:"claude-zeta-5",family:"zeta",display_name:"Z",context:{window:%s,native_1m:!0}}];' \
    "$2" >> "$1"
}

@test "reads context windows out of the installed CLI" {
  tp="$TEST_TMP/sess.jsonl"
  make_subagent "$tp" a1 Explore claude-zeta-5 100000
  fake_bundle "$TEST_TMP/claude" 400000
  unset STATUSLINE_MODEL_WINDOWS
  out="$(STATUSLINE_CLAUDE_BIN="$TEST_TMP/claude" statusline "$(session_json "$tp")")"
  assert_equal "$(agent_line "$out")" "Z/25%/10%"
  assert_file_exists "$HOME/.claude/cache/statusline-model-windows"
}

@test "re-reads the table when the CLI changes" {
  tp="$TEST_TMP/sess.jsonl"
  make_subagent "$tp" a1 Explore claude-zeta-5 100000
  unset STATUSLINE_MODEL_WINDOWS
  fake_bundle "$TEST_TMP/claude" 400000
  STATUSLINE_CLAUDE_BIN="$TEST_TMP/claude" statusline "$(session_json "$tp")" >/dev/null
  fake_bundle "$TEST_TMP/claude" 1000000      # a different size, so a new signature
  out="$(STATUSLINE_CLAUDE_BIN="$TEST_TMP/claude" statusline "$(session_json "$tp")")"
  assert_equal "$(agent_line "$out")" "Z/10%/10%"
}

# Transcripts name a dated build ("claude-haiku-4-5-20251001") where the table
# carries the family entry.
@test "matches a dated model id against the table by prefix" {
  tp="$TEST_TMP/sess.jsonl"
  make_subagent "$tp" a1 Explore claude-alpha-1-20260101 50000
  fake_bundle "$TEST_TMP/claude" 400000
  unset STATUSLINE_MODEL_WINDOWS
  out="$(STATUSLINE_CLAUDE_BIN="$TEST_TMP/claude" statusline "$(session_json "$tp")")"
  assert_equal "$(agent_line "$out")" "A/25%/10%"
}

@test "ignores a CLI that yields no model table" {
  tp="$TEST_TMP/sess.jsonl"
  make_subagent "$tp" a1 Explore claude-sonnet-5 250000
  echo "not a bundle" > "$TEST_TMP/claude"
  unset STATUSLINE_MODEL_WINDOWS
  out="$(STATUSLINE_CLAUDE_BIN="$TEST_TMP/claude" statusline "$(session_json "$tp")")"
  assert_equal "$(agent_line "$out")" "S/25%/10%"   # built-in fallback still knows Sonnet 5
}

# ---- the cache clock ------------------------------------------------------
# A context is only cheap to come back to while its prompt cache is alive, and
# that cache outlives the request that wrote it by five minutes for a subagent
# and an hour for a main session. So both lines carry how much of that window
# the silence since the last turn has spent. STATUSLINE_NOW is pinned 30s past
# the turn the fixtures date; tests wanting another reading move it.

@test "shows the share of the cache TTL spent and what is left of it" {
  tp="$TEST_TMP/sess.jsonl"
  make_session_turn "$tp" "2026-01-01T00:00:10.000Z"
  out="$(plain "$(statusline "$(session_json "$tp")")")"
  assert_contains "$(line_n "$out" 2)" "TTL: 0% (-59m)"
}

@test "reads a third of the hour spent after twenty minutes quiet" {
  tp="$TEST_TMP/sess.jsonl"
  make_session_turn "$tp" "2026-01-01T00:00:10.000Z"
  out="$(plain "$(STATUSLINE_NOW=$(( FIXTURE_TURN + 1200 )) statusline "$(session_json "$tp")")")"
  assert_contains "$(line_n "$out" 2)" "TTL: 33% (-40m)"
}

# Which bucket a turn wrote is the TTL, and the API reports it, so a session
# that wrote the 5-minute one is measured against five minutes.
@test "measures a session against the cache bucket its turn actually wrote" {
  tp="$TEST_TMP/sess.jsonl"
  make_session_turn "$tp" "2026-01-01T00:00:10.000Z" 5m
  out="$(plain "$(STATUSLINE_NOW=$(( FIXTURE_TURN + 150 )) statusline "$(session_json "$tp")")")"
  assert_contains "$(line_n "$out" 2)" "TTL: 50% (-2m)"
}

@test "clamps the TTL at 100% and drops the countdown once the cache is gone" {
  tp="$TEST_TMP/sess.jsonl"
  make_session_turn "$tp" "2026-01-01T00:00:10.000Z" 5m
  out="$(plain "$(STATUSLINE_NOW=$(( FIXTURE_TURN + 400 )) statusline "$(session_json "$tp")")")"
  assert_contains "$(line_n "$out" 2)" "TTL: 100%"
  refute_contains "$out" "(-"
}

@test "spells a whole hour left as -1h, without the zero minutes" {
  tp="$TEST_TMP/sess.jsonl"
  make_session_turn "$tp" "2026-01-01T00:00:10.000Z"
  out="$(plain "$(STATUSLINE_NOW=$FIXTURE_TURN statusline "$(session_json "$tp")")")"
  assert_contains "$(line_n "$out" 2)" "TTL: 0% (-1h)"
}

# Each field needs its own hue or it reads as part of the one before it. The
# session's context is yellow, so the TTL takes white.
@test "colors the TTL apart from the context reading" {
  tp="$TEST_TMP/sess.jsonl"
  make_session_turn "$tp" "2026-01-01T00:00:10.000Z"
  out="$(STATUSLINE_NOW=$(( FIXTURE_TURN + 600 )) statusline "$(session_json "$tp")")"
  assert_contains "$out" $'\033[37m'"TTL: 16%"
}

@test "turns the TTL red once the cache is nearly gone" {
  tp="$TEST_TMP/sess.jsonl"
  make_session_turn "$tp" "2026-01-01T00:00:10.000Z"
  out="$(STATUSLINE_NOW=$(( FIXTURE_TURN + 3000 )) statusline "$(session_json "$tp")")"
  assert_contains "$out" $'\033[31m'"TTL: 83%"
}

@test "omits the cache TTL when the session has taken no turn yet" {
  tp="$TEST_TMP/sess.jsonl"
  make_session_ref "$tp" a1 "2026-01-01T00:00:05.000Z"   # a user line, no turn
  out="$(statusline "$(session_json "$tp")")"
  refute_contains "$out" "TTL:"
}

@test "omits the cache TTL when there is no transcript to read" {
  json="$(jq -n --arg c /tmp --arg m M '{cwd:$c, model:{display_name:$m}}')"
  out="$(statusline "$json")"
  refute_contains "$out" "TTL:"
}

# Five minutes run out fast: four minutes quiet is 80% of a subagent's cache
# gone, where the same wait costs a session 7% of its hour.
@test "measures a subagent's silence against its five-minute cache" {
  tp="$TEST_TMP/sess.jsonl"
  make_subagent "$tp" a1 Explore claude-haiku-4-5-20251001 40000
  out="$(STATUSLINE_NOW=$(( FIXTURE_TURN + 240 )) statusline "$(session_json "$tp")")"
  assert_equal "$(agent_line "$out")" "H/20%/80%"
}

# A turn can write no cache at all, which says nothing about the TTL; the
# five-minute default stands in.
@test "falls back to five minutes for a subagent turn that wrote no cache" {
  tp="$TEST_TMP/sess.jsonl"
  make_subagent "$tp" a1 Explore ""
  jq -cn '{type:"assistant", isSidechain:true, timestamp:"2026-01-01T00:00:10.000Z",
    message:{model:"claude-haiku-4-5", usage:{input_tokens:1,
      cache_creation_input_tokens:0, cache_read_input_tokens:19999}}}' \
    >> "$TEST_TMP/sess/subagents/agent-a1.jsonl"
  out="$(statusline "$(session_json "$tp")")"
  assert_equal "$(agent_line "$out")" "H/10%/10%"
}

@test "gives a subagent's context reading and its TTL different colors" {
  tp="$TEST_TMP/sess.jsonl"
  make_subagent "$tp" a1 Explore claude-haiku-4-5-20251001 40000
  fresh="$(STATUSLINE_NOW=$(( FIXTURE_TURN + 60 ))  statusline "$(session_json "$tp")")"
  stale="$(STATUSLINE_NOW=$(( FIXTURE_TURN + 240 )) statusline "$(session_json "$tp")")"
  assert_contains "$fresh" $'\033[32m'"20%"   # context, green
  assert_contains "$fresh" $'\033[37m'"20%"   # TTL, white
  assert_contains "$stale" $'\033[31m'"80%"   # red at four of its five minutes
}

# Both clocks at once: the session's hour on line 2, each agent's five minutes
# on line 3.
@test "renders the session's clock and each agent's on their own lines" {
  tp="$TEST_TMP/sess.jsonl"
  make_session_turn "$tp" "2026-01-01T00:00:10.000Z"
  make_subagent "$tp" a1 Explore claude-opus-5 110000
  make_subagent "$tp" a2 Explore claude-sonnet-5 250000
  json="$(jq -n --arg c /tmp/proj --arg m 'Opus 5' --arg tp "$tp" \
    '{cwd:$c, model:{display_name:$m}, transcript_path:$tp,
      context_window:{used_percentage:22}}')"
  out="$(plain "$(STATUSLINE_NOW=$(( FIXTURE_TURN + 120 )) statusline "$json")")"
  assert_equal "$(line_n "$out" 2)" "Opus 5 | ctx: 22% | TTL: 3% (-58m)"
  assert_equal "$(line_n "$out" 3)" "O/11%/40% · S/25%/40%"
}
