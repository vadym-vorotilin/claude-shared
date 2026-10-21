#!/usr/bin/env bats
#
# statusline-command.sh — reads a JSON blob on stdin, prints a colored line.

load 'helpers/setup'

setup() {
  common_setup
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
  assert_contains "$out" "/t/proj"
}

@test "renders effort level and its bar between model and context" {
  json="$(jq -n --arg c /tmp --arg m M '{cwd:$c, model:{display_name:$m}, effort:{level:"high"}, context_window:{used_percentage:5}}')"
  out="$(statusline "$json" | sed $'s/\033\\[[0-9;]*m//g')"
  assert_contains "$out" "M | high ▅ | ctx: 5%"
}

# Each level: its exact escape (color, and bold at the top) and its bar.
effort_line() {
  statusline "$(jq -n --arg l "$1" '{cwd:"/tmp", model:{display_name:"M"}, effort:{level:$l}}')" | sed -n 2p
}

@test "effort low renders teal with the lowest bar" {
  assert_contains "$(effort_line low)" $'\033[38;5;30mlow ▁'
}

@test "effort medium renders green" {
  assert_contains "$(effort_line medium)" $'\033[38;5;71mmedium ▃'
}

@test "effort high renders dark yellow" {
  assert_contains "$(effort_line high)" $'\033[38;5;136mhigh ▅'
}

@test "effort xhigh renders orange" {
  assert_contains "$(effort_line xhigh)" $'\033[38;5;166mxhigh ▇'
}

@test "effort max renders bold red with a full bar" {
  assert_contains "$(effort_line max)" $'\033[1;38;5;160mmax █'
}

@test "effort ultra renders bold dark purple with a full bar" {
  assert_contains "$(effort_line ultra)" $'\033[1;38;5;91multra █'
}

@test "an unknown effort level prints plain, with no color or bar" {
  out="$(effort_line turbo)"
  assert_contains "$out" $'| turbo\033[0m'
  refute_contains "$out" "38;5;"
}

@test "omits effort segment when the harness sends none" {
  json="$(jq -n --arg c /tmp --arg m M '{cwd:$c, model:{display_name:$m}}')"
  out="$(statusline "$json" | sed $'s/\033\\[[0-9;]*m//g')"
  # No dangling separator: the model line is the model name alone.
  assert_equal "$(line_n "$out" 2)" "M"
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
  assert_contains "$(line_n "$out" 1)" "/t/proj"
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

# ---- location -------------------------------------------------------------
# Line 1 names the repo, not its path, so a long checkout path never pushes the
# branch past the edge of the terminal. Outside git the path is abbreviated.

location_line() { # cwd -> line 1, ANSI stripped
  plain "$(line_n "$(statusline "$(jq -n --arg c "$1" '{cwd:$c, model:{display_name:"M"}}')")" 1)"
}

@test "a repo cwd shows the repo name, not its path" {
  make_git_repo "$TEST_TMP/projects/orchard"
  assert_equal "$(location_line "$TEST_TMP/projects/orchard")" "orchard | main"
}

@test "a subfolder of a repo follows the repo name, its parents abbreviated" {
  make_git_repo "$TEST_TMP/orchard"
  mkdir -p "$TEST_TMP/orchard/src/api/routes"
  assert_equal "$(location_line "$TEST_TMP/orchard/src/api/routes")" "orchard/s/a/routes | main"
}

@test "a linked worktree shows the main repo's name and the worktree's" {
  make_git_repo "$TEST_TMP/orchard"
  git -C "$TEST_TMP/orchard" worktree add -q -b docs/14-login-flow "$TEST_TMP/orchard/_trees/feat-14-login"
  assert_equal "$(location_line "$TEST_TMP/orchard/_trees/feat-14-login")" \
    "orchard:feat-14-login | docs/14-login-flow"
}

@test "a subfolder of a linked worktree keeps both names" {
  make_git_repo "$TEST_TMP/orchard"
  git -C "$TEST_TMP/orchard" worktree add -q -b feat "$TEST_TMP/wt/spike"
  mkdir -p "$TEST_TMP/wt/spike/docs"
  assert_equal "$(location_line "$TEST_TMP/wt/spike/docs")" "orchard:spike/docs | feat"
}

@test "a worktree of a bare repo names the repo without .git" {
  make_git_repo "$TEST_TMP/src"
  git clone -q --bare "$TEST_TMP/src" "$TEST_TMP/orchard.git"
  git -C "$TEST_TMP/orchard.git" worktree add -q -b feat "$TEST_TMP/feature"
  assert_equal "$(location_line "$TEST_TMP/feature")" "orchard:feature | feat"
}

@test "outside git, every folder but the last is cut to its first letter" {
  mkdir -p "$HOME/projects/scratch/notes"
  assert_equal "$(location_line "$HOME/projects/scratch/notes")" "~/p/s/notes"
}

@test "outside git, a leading dot or underscore keeps the letter after it" {
  mkdir -p "$HOME/.config/_cache/notes"
  assert_equal "$(location_line "$HOME/.config/_cache/notes")" "~/.c/_c/notes"
}

@test "outside git, the filesystem root and a top-level folder print whole" {
  assert_equal "$(location_line /)" "/"
  assert_equal "$(location_line /tmp)" "/tmp"
}

# Session JSON pointing at a transcript path inside the test tmpdir.
session_json() { # transcript-path
  jq -n --arg c /tmp/proj --arg m 'Opus 5' --arg tp "$1" \
    '{cwd:$c, model:{display_name:$m}, transcript_path:$tp}'
}

# Strip ANSI so layout can be asserted on the text alone.
plain() { printf '%s' "$1" | sed -E "s/$(printf '\033')\[[0-9;]*m//g"; }

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

# Live subagents are drawn in the agent panel by their own script; the session
# line no longer carries a line for them, however many are running.
@test "draws no subagent line, even with agents running" {
  tp="$TEST_TMP/sess.jsonl"
  make_session_turn "$tp" "2026-01-01T00:00:10.000Z"
  make_subagent "$tp" a1 Explore claude-opus-5 110000
  json="$(jq -n --arg c /tmp/proj --arg m 'Opus 5' --arg tp "$tp" \
    '{cwd:$c, model:{display_name:$m}, transcript_path:$tp,
      context_window:{used_percentage:22}, rate_limits:{five_hour:{used_percentage:10}}}')"
  out="$(plain "$(STATUSLINE_NOW=$(( FIXTURE_TURN + 120 )) statusline "$json")")"
  assert_equal "$(line_n "$out" 2)" "Opus 5 | ctx: 22% | TTL: 3% (-58m)"
  assert_equal "$(line_n "$out" 3)" "5h: 10%"
  refute_contains "$out" "O/"
}

# Agents without an effort of their own run at the session's, which only this
# line is told, so it records it per session for the agent panel.
@test "records the session's effort for the agent panel" {
  statusline "$(jq -n '{cwd:"/tmp", session_id:"s1", model:{display_name:"M"}, effort:{level:"xhigh"}}')" >/dev/null
  assert_equal "$(cat "$HOME/.claude/cache/statusline-session-effort/s1")" "xhigh"
}

@test "drops the record once the session's model has no effort" {
  statusline "$(jq -n '{cwd:"/tmp", session_id:"s1", model:{display_name:"M"}, effort:{level:"high"}}')" >/dev/null
  statusline "$(jq -n '{cwd:"/tmp", session_id:"s1", model:{display_name:"M"}}')" >/dev/null
  [ ! -e "$HOME/.claude/cache/statusline-session-effort/s1" ] || fail "stale effort record kept"
}

@test "writes no record for a session id that is not a plain name" {
  statusline "$(jq -n '{cwd:"/tmp", session_id:"../x", model:{display_name:"M"}, effort:{level:"high"}}')" >/dev/null
  [ ! -e "$HOME/.claude/cache/x" ] || fail "wrote outside the cache dir"
  [ ! -e "$HOME/.claude/cache/statusline-session-effort/../x" ] || fail "wrote a traversal path"
}

@test "says what is wrong when its helpers are missing" {
  mkdir -p "$TEST_TMP/bin"
  cp "$REPO/claude/statusline-command.sh" "$TEST_TMP/bin/"
  out="$(printf '%s' '{"cwd":"/tmp"}' | bash "$TEST_TMP/bin/statusline-command.sh" 2>&1)"
  assert_equal "$out" "statusline-lib.sh is missing beside this script; re-run sync.sh"
}
