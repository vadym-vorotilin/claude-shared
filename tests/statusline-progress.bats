#!/usr/bin/env bats
#
# The status line's progress line: the estimate (a /progress update in the
# transcript, or `statusline-progress.sh estimate`) and jobs (real
# percentages from `statusline-progress.sh run` / `watch` / `job`), at most
# one line in all.

load 'helpers/setup'
bats_require_minimum_version 1.5.0

T0=1767225600                                 # 2026-01-01T00:00:00Z
SID=sess-abc-1

setup() {
  common_setup
  export TZ=UTC
  export STATUSLINE_NOW=$(( T0 + 300 ))       # five minutes after T0
  export CLAUDE_CONFIG_DIR="$TEST_TMP/cfg"
  export CLAUDE_CODE_SESSION_ID="$SID"
  TR="$TEST_TMP/transcript.jsonl"
  : > "$TR"
}
teardown() { common_teardown; }

PROG() { bash "$REPO/claude/statusline-progress.sh" "$@"; }
EST_FILE() { echo "$CLAUDE_CONFIG_DIR/cache/statusline-progress/$SID.estimate"; }
JOBS_DIR() { echo "$CLAUDE_CONFIG_DIR/cache/statusline-progress/$SID.jobs"; }

# An assistant turn at epoch $1 whose text is $2 (JSON-escaped by jq).
assistant_turn() { # epoch text
  jq -cn --arg ts "$(date -u -d "@$1" +%Y-%m-%dT%H:%M:%S.000Z)" --arg t "$2" \
    '{type:"assistant", timestamp:$ts, message:{content:[{type:"text", text:$t}]}}' >> "$TR"
}

# The status line, colors kept.
render_raw() {
  jq -n --arg t "$TR" --arg s "$SID" \
    '{cwd:"/tmp", model:{display_name:"M"}, session_id:$s, transcript_path:$t}' \
    | bash "$REPO/claude/statusline-command.sh"
}
# The status line, colors stripped.
render() { render_raw | sed $'s/\033\\[[0-9;]*m//g'; }

# Everything between the model line and the trailing spacer: with no quota
# data sent, that is the progress line, or nothing.
progress_line() { render | sed -n '3,$p' | grep -v '^⠀$' || true; }

# ---------------------------------------------------------------- estimate --

@test "no progress anywhere: no progress line at all" {
  out="$(render)"
  assert_equal "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" 3
  assert_equal "$(progress_line)" ""
  mkdir -p "$(JOBS_DIR)"                    # an empty jobs dir: still nothing
  assert_equal "$(progress_line)" ""
}

@test "a /progress header renders the percentage and the ETA clock" {
  assistant_turn "$T0" $'**2026-01-01 00:00 UTC — Progress: 3/5 · ~55% · ETA ~20–30 min**\n- **Now:** x\n- **ETA:** ≈00:25 · medium — y'
  assert_equal "$(progress_line)" "55% ≈00:25 (5m ago)"
}

@test "an /unattended-run stamp counts as an estimate" {
  assistant_turn "$T0" $'**2026-01-01 00:00 - Progress: Goal 3/5 · 60%**\nmerged item 3'
  assert_equal "$(progress_line)" "60% (5m ago)"
}

@test "an /orchestrating-issue-runs stamp counts as an estimate" {
  assistant_turn "$T0" $'**2026-01-01 00:00 - Progress: Exit 2/4 · 50%**\nitem 2 merged'
  assert_equal "$(progress_line)" "50% (5m ago)"
}

@test "an idle update clears an earlier estimate, in the plain shape /progress gives it" {
  assistant_turn "$T0" '**2026-01-01 00:00 UTC - Progress: 1/4 · ~25% · ETA ~1 h**'
  assistant_turn $(( T0 + 60 )) $'2026-01-01 00:01 UTC - Progress: idle\n- **Next:** you — pick a task'
  assert_equal "$(progress_line)" ""
  : > "$TR"; rm -f "$(EST_FILE)"
  assistant_turn "$T0" '**x — Progress: 1/4 · ~25% · ETA ~1 h**'
  assistant_turn $(( T0 + 60 )) '**x — Progress: idle**'
  assert_equal "$(progress_line)" ""
}

@test "prose that ends in an idle update is not one" {
  assistant_turn "$T0" '**x - Progress: 1/4 · ~25% · ETA ~1 h**'
  assistant_turn $(( T0 + 60 )) 'Before anything starts, the line reads Progress: idle'
  assistant_turn $(( T0 + 60 )) 'It looks like `2026-01-01 00:01 UTC - Progress: idle`'
  assert_contains "$(progress_line)" "25%"
}

@test "the header in a user turn or a tool call is not an update" {
  jq -cn '{type:"user", timestamp:"2026-01-01T00:00:00.000Z", message:{content:"Progress: 3/5 · ~55% · ETA"}}' >> "$TR"
  jq -cn '{type:"assistant", timestamp:"2026-01-01T00:00:00.000Z", message:{content:[{type:"tool_use", input:{content:"Progress: 3/5 · ~55% · ETA"}}]}}' >> "$TR"
  assert_equal "$(progress_line)" ""
}

@test "prose that quotes a header is not an update" {
  assistant_turn "$T0" 'The /progress header looks like `Progress: 3/5 · ~55% · ETA ~20 min`, and the parser reads it.'
  assistant_turn "$T0" 'Inline, **x — Progress: 3/5 · ~55% · ETA ~20 min** is still prose.'
  assistant_turn "$T0" $'Example:\n  **x — Progress: 3/5 · ~55% · ETA ~20 min**'
  assert_equal "$(progress_line)" ""
}

@test "a header in a sidechain entry is not the session's update" {
  jq -cn '{type:"assistant", isSidechain:true, timestamp:"2026-01-01T00:00:00.000Z",
           message:{content:[{type:"text", text:"**x — Progress: 3/5 · ~55% · ETA ~20 min**"}]}}' >> "$TR"
  assert_equal "$(progress_line)" ""
}

@test "the estimate is cached: it survives the header leaving the transcript" {
  assistant_turn "$T0" '**x — Progress: 2/4 · ~50% · ETA ~1 h**'
  render >/dev/null
  : > "$TR"
  assistant_turn $(( T0 + 60 )) 'unrelated text'
  assert_contains "$(progress_line)" "50%"
}

@test "the newer of transcript and hand-written estimate wins" {
  assistant_turn "$T0" '**x — Progress: 2/4 · ~50% · ETA ~1 h**'
  STATUSLINE_NOW=$(( T0 + 120 )) PROG estimate 70 3/4
  assert_equal "$(progress_line)" "70%"
  assistant_turn $(( T0 + 200 )) '**x — Progress: 4/4 · 100% · ETA done**'
  assert_equal "$(progress_line)" "100% done"
}

@test "a passed ETA is the same clock, in red, with no countdown" {
  assistant_turn "$T0" $'**x — Progress: 1/2 · ~50% · ETA ~2 min**\n- **ETA:** ≈00:02 · high'
  assert_equal "$(progress_line)" "50% ≈00:02 (5m ago)"
  assert_contains "$(render_raw)" $'\033[31m≈00:02'
  refute_contains "$(render)" "late"
  # One still ahead is not red.
  : > "$TR"; rm -f "$(EST_FILE)"
  PROG estimate 50 1/2 00:30
  refute_contains "$(render_raw)" $'\033[31m≈'
}

@test "an ETA past midnight is tomorrow, not 23 hours ago" {
  t=$(( T0 - 600 ))                           # 23:50 the day before
  assistant_turn "$t" $'**x — Progress: 1/2 · ~50% · ETA ~30 min**\n- **ETA:** ≈00:20 · high'
  assert_equal "$(progress_line)" "50% ≈00:20 (15m ago)"
}

@test "an estimate over 4 hours old is hidden; a finished one after 30 min" {
  assistant_turn "$T0" '**x — Progress: 1/2 · ~50% · ETA ~1 h**'
  assert_equal "$(STATUSLINE_NOW=$(( T0 + 14400 )) progress_line)" ""
  : > "$TR"; rm -f "$(EST_FILE)"
  assistant_turn "$T0" '**x — Progress: 2/2 · 100% · ETA done**'
  assert_equal "$(STATUSLINE_NOW=$(( T0 + 600 )) progress_line)" "100% done (10m ago)"
  assert_equal "$(STATUSLINE_NOW=$(( T0 + 1800 )) progress_line)" ""
}

@test "estimate: a hand-written ETA clock is shown" {
  PROG estimate 40 2/5 00:45
  assert_equal "$(progress_line)" "40% ≈00:45"
}

@test "estimate rejects a bad percentage" {
  run PROG estimate 140
  assert_equal "$status" 2
  [ ! -e "$(EST_FILE)" ] || fail "wrote an estimate for 140%"
}

@test "estimate rejects an n/m that isn't two numbers" {
  for nm in '1x/2 · ETA ≈never' '1/2/3' '/2' '1/' 'a/b'; do
    run PROG estimate 50 "$nm"
    assert_equal "$status" 2
  done
  [ ! -e "$(EST_FILE)" ] || fail "wrote an estimate with a bad n/m"
}

@test "a garbled estimate file is never evaluated, and shows only what checks out" {
  mkdir -p "$(dirname "$(EST_FILE)")"
  printf '%s\t50\t1/2\ta[$(touch "%s/PWNED")]\n' "$STATUSLINE_NOW" "$TEST_TMP" > "$(EST_FILE)"
  assert_equal "$(progress_line)" "50%"
  printf 'a[$(touch "%s/PWNED")]\ta[$(touch "%s/PWNED")]\tx/a[$(touch "%s/PWNED")]\t-\n' \
    "$TEST_TMP" "$TEST_TMP" "$TEST_TMP" > "$(EST_FILE)"
  assert_equal "$(progress_line)" ""
  [ ! -e "$TEST_TMP/PWNED" ] || fail "a field of the estimate file was run as code"
}

@test "an ETA clock across a DST change counts the change" {
  export TZ=Europe/Berlin
  ref=$(date -d '2026-03-29 01:50' +%s)          # CET; 03:20 is CEST, 30 min on
  STATUSLINE_NOW=$ref PROG estimate 50 1/2 03:20
  assert_equal "$(STATUSLINE_NOW=$ref progress_line)" "50% ≈03:20"
}

# -------------------------------------------------------------------- jobs --

@test "run: passes output through, keeps the exit code, ends done" {
  run PROG run "test suite" -- bash -c 'echo "t [ 40%]"; echo "t [100%]"'
  assert_equal "$status" 0
  assert_contains "$output" "t [ 40%]"
  assert_equal "$(progress_line)" "✓1"
}

@test "run: a failing command keeps its code and its last percentage" {
  run PROG run build -- bash -c 'printf "a 12%%\rb 33%%\r"; exit 3'
  assert_equal "$status" 3
  assert_equal "$(progress_line)" "✗1"
}

@test "run: output passes through byte for byte, \\r and CRLF included" {
  printf 'a 10%%\rb 20%%\r\nline\r\n\tno newline at end' > "$TEST_TMP/want"
  PROG run bytes -- cat "$TEST_TMP/want" > "$TEST_TMP/got"
  cmp "$TEST_TMP/want" "$TEST_TMP/got" || fail "output changed: $(od -c "$TEST_TMP/got")"
}

@test "run: output and the row stream live, a \\r-only redraw included" {
  PROG run live -- sh -c 'printf "first 10%%\r"; sleep 3; printf "second 20%%\n"' \
    > "$TEST_TMP/live" 3>&- &
  sleep 1.5
  assert_equal "$(cat "$TEST_TMP/live")" "$(printf 'first 10%%\r')"
  assert_equal "$(progress_line)" "live 10%"
  wait
  assert_equal "$(progress_line)" "✓1"
}

@test "run: a percentage split across two reads is read whole" {
  run PROG run split -- sh -c 'printf "a 12%%\rb 3"; sleep 1; printf "3%%\n"; exit 1'
  assert_equal "$(progress_line)" "✗1"
}

@test "run: the row is written at most once a second, and once at the end" {
  # Once the reader is up (it wrote 5%), 10% and 20% come 0.2 s apart, just
  # after a second starts: 20% waits for the next second. (The pause after
  # the second starts is for perl's time(), which can lag date by a tick.)
  PROG run rate -- sh -c 'printf "5%%\r"
    until [ "$(cut -f2 "$1" 2>/dev/null)" = 5 ]; do sleep 0.05; done
    s=$(date +%s); while [ "$(date +%s)" = "$s" ]; do :; done; sleep 0.05
    printf "10%%\r"; sleep 0.2; printf "20%%\r"; : > "$0"; sleep 3' \
    "$TEST_TMP/sent" "$(JOBS_DIR)/rate" > /dev/null 3>&- &
  while [ ! -e "$TEST_TMP/sent" ]; do sleep 0.05; done
  sleep 0.2                       # the row itself: a render takes too long
  assert_equal "$(cut -f2 "$(JOBS_DIR)/rate")" 10
  sleep 1.2
  assert_equal "$(cut -f2 "$(JOBS_DIR)/rate")" 20
  wait
}

# Wait up to $2 seconds for process $1 to end; fail, and kill it, if it doesn't.
ends_within() { # pid seconds
  local i=0
  while kill -0 "$1" 2>/dev/null; do
    i=$(( i + 1 ))
    [ "$i" -le $(( $2 * 10 )) ] || { kill -KILL "$1"; fail "pid $1 still running after $2 s"; return 1; }
    sleep 0.1
  done
}

# Wait up to 5 s for the progress line to read "$1 $2".
row_reads() { # name text
  local i=0
  until [ "$(progress_line)" = "$1 $2" ]; do
    i=$(( i + 1 )); [ "$i" -le 50 ] || { fail "line never read [$1 $2]: $(progress_line)"; return 1; }
    sleep 0.1
  done
}

# Run the rest of the line in its own process group, with INT at its default
# (a background job of a script starts with INT ignored), as a terminal's
# foreground job has. It execs, so use it only as a background job: $! is
# then the command's own PID.
own_group() {
  exec python3 -c 'import os, signal, sys
signal.signal(signal.SIGINT, signal.SIG_DFL); os.setsid(); os.execvp(sys.argv[1], sys.argv[1:])' "$@"
}

# Wait up to 5 s for file $1 to contain $2.
file_has() { # file text
  local i=0
  until grep -qF -- "$2" "$1" 2>/dev/null; do
    i=$(( i + 1 )); [ "$i" -le 50 ] || { fail "$1 never had [$2]: $(cat "$1")"; return 1; }
    sleep 0.1
  done
}

@test "run: Ctrl-C to the whole group keeps the command's last output, and ends the row as killed" {
  # The command counts the INTs it gets, then exits 2 as a test runner does.
  own_group bash "$REPO/claude/statusline-progress.sh" run k -- \
    sh -c 'n=0; trap "n=\$((n+1)); echo INT\$n" INT; echo 40%
      i=0; while [ ! -e "$0" ] && [ $i -lt 300 ]; do sleep 0.1; i=$((i+1)); done; echo SUMMARY 3 passed; exit 2' "$TEST_TMP/stop" \
    > "$TEST_TMP/out" 3>&- &
  w=$!
  row_reads k "40%"
  kill -INT -- "-$w"
  file_has "$TEST_TMP/out" INT1
  sleep 1                              # time for a second INT, if one came
  : > "$TEST_TMP/stop"
  ends_within "$w" 5
  st=0; wait "$w" || st=$?
  assert_equal "$st" 130
  refute_contains "$(cat "$TEST_TMP/out")" "INT2"
  assert_contains "$(cat "$TEST_TMP/out")" "SUMMARY 3 passed"
  assert_equal "$(progress_line)" "✗1"
}

@test "run: INT to the wrapper alone is not passed on, and a command that then finishes 0 reads done" {
  # (Two INTs that arrive together reach a shell's trap as one, so the test
  # above cannot see a forwarded INT; this one sends the wrapper its only INT.)
  own_group bash "$REPO/claude/statusline-progress.sh" run k0 -- \
    sh -c 'trap "echo got INT" INT; echo 30%; sleep 4; echo finished' > "$TEST_TMP/out" 3>&- &
  w=$!
  row_reads k0 "30%"
  kill -INT "$w"
  ends_within "$w" 5
  st=0; wait "$w" || st=$?
  assert_equal "$st" 0
  refute_contains "$(cat "$TEST_TMP/out")" "got INT"
  assert_contains "$(cat "$TEST_TMP/out")" "finished"
  assert_equal "$(progress_line)" "✓1"
}

@test "run: a signal the wrapper starts with ignored (nohup) stays ignored, and the exit code is kept" {
  nohup bash "$REPO/claude/statusline-progress.sh" run nh -- \
    sh -c 'echo 30%; sleep 4; echo finished; exit 4' > "$TEST_TMP/out" 2>&1 3>&- &
  w=$!
  row_reads nh "30%"
  kill -HUP "$w"
  ends_within "$w" 5
  st=0; wait "$w" || st=$?
  assert_equal "$st" 4
  assert_contains "$(cat "$TEST_TMP/out")" "finished"
  assert_equal "$(progress_line)" "✗1"
}

@test "run: TERM to the wrapper alone stops the command, and the row says killed" {
  bash "$REPO/claude/statusline-progress.sh" run t -- \
    sh -c 'trap "echo stopped; exit 5" TERM; echo 30%; while :; do sleep 0.1; done; echo finished' \
    > "$TEST_TMP/out" 3>&- &
  w=$!
  row_reads t "30%"
  kill -TERM "$w"
  ends_within "$w" 5
  st=0; wait "$w" || st=$?
  assert_equal "$st" 143
  assert_contains "$(cat "$TEST_TMP/out")" "stopped"
  refute_contains "$(cat "$TEST_TMP/out")" "finished"
  assert_equal "$(progress_line)" "✗1"
}

@test "run: a command stopped by a passed-on TERM that exits 0 counts as ended, not done" {
  bash "$REPO/claude/statusline-progress.sh" run gs -- \
    sh -c 'trap "echo cleanup; exit 0" TERM; echo 30%; while :; do sleep 0.1; done' \
    > "$TEST_TMP/out" 3>&- &
  w=$!
  row_reads gs "30%"
  kill -TERM "$w"
  ends_within "$w" 5
  st=0; wait "$w" || st=$?
  assert_equal "$st" 0
  assert_contains "$(cat "$TEST_TMP/out")" "cleanup"
  assert_equal "$(progress_line)" "■1"
}

@test "run: a TERM sent before the command has started still stops it" {
  # The test hook holds the wrapper between blocking TERM and forking, the
  # gap where a signal used to reach neither the wrapper nor the command.
  SP_TEST_PREFORK_DELAY=1 bash "$REPO/claude/statusline-progress.sh" run pf -- \
    sh -c 'echo 30%; sleep 2; echo finished; exit 0' > "$TEST_TMP/out" 3>&- &
  w=$!
  sleep 0.4
  kill -TERM "$w"
  ends_within "$w" 5
  st=0; wait "$w" || st=$?
  assert_equal "$st" 143
  refute_contains "$(cat "$TEST_TMP/out")" "finished"
  assert_equal "$(progress_line)" "✗1"
}

@test "run: a TERM the caller blocked stays blocked for the command" {
  # The wrapper blocks TERM around the fork; it must put back the mask it
  # was given, not unblock TERM outright. TERM is bit 15, 0x4000 in SigBlk.
  # The command is cat itself: dash, as sh, clears the mask on its own.
  blk() { perl -ne 'print hex($1) & 0x4000 ? "blocked" : "open" if /^SigBlk:\s*(\S+)/' "$1"; }
  perl -MPOSIX -e 'POSIX::sigprocmask(POSIX::SIG_BLOCK(), POSIX::SigSet->new(POSIX::SIGTERM())); exec @ARGV' \
    bash "$REPO/claude/statusline-progress.sh" run mk -- cat /proc/self/status > "$TEST_TMP/blocked" 3>&-
  bash "$REPO/claude/statusline-progress.sh" run mk2 -- cat /proc/self/status > "$TEST_TMP/open" 3>&-
  assert_equal "$(blk "$TEST_TMP/blocked")" "blocked"
  assert_equal "$(blk "$TEST_TMP/open")" "open"
}

@test "run: a command that is not there exits 127 and counts as failed" {
  run -127 PROG run nx -- "$TEST_TMP/no-such-command"
  assert_equal "$status" 127
  assert_contains "$output" "no-such-command"
  assert_equal "$(progress_line)" "✗1"
}

@test "run: a job whose writer died without a word counts as failed (gone)" {
  bash "$REPO/claude/statusline-progress.sh" run g -- \
    sh -c 'echo $$ > "$0"; echo 40%; exec sleep 30' "$TEST_TMP/cmdpid" > /dev/null 3>&- &
  w=$!
  sleep 1
  assert_equal "$(progress_line)" "g 40%"
  kill -KILL "$w"; kill -KILL "$(cat "$TEST_TMP/cmdpid")"
  wait "$w" 2>/dev/null || true
  sleep 0.5
  assert_equal "$(progress_line)" "✗1"
}

@test "run and watch without perl: output passes through, and stderr says so" {
  mkdir "$TEST_TMP/bin"
  for f in /usr/bin/* /bin/*; do
    case "${f##*/}" in perl*) ;; *) ln -sf "$f" "$TEST_TMP/bin/" ;; esac
  done
  run env PATH="$TEST_TMP/bin" bash "$REPO/claude/statusline-progress.sh" run np -- sh -c 'echo ran; exit 5'
  assert_equal "$status" 5
  assert_contains "$output" "ran"
  assert_contains "$output" "perl not found"
  run env PATH="$TEST_TMP/bin" bash -c "printf 'x 5%%\n' | bash '$REPO/claude/statusline-progress.sh' watch np2"
  assert_equal "$status" 0
  assert_contains "$output" "x 5%"
  assert_contains "$output" "perl not found"
}

@test "watch: reads a pipe and counts as ended" {
  printf 'x 50%%\n' | PROG watch "tail log" >/dev/null
  assert_equal "$(progress_line)" "■1"
}

@test "watch: TERM stops it even when its input never ends, and it counts as failed" {
  # `while echo` ends on a failed write even if SIGPIPE is ignored.
  { while echo 10%; do sleep 0.2; done | PROG watch endless > /dev/null; } 3>&- &
  row_reads endless "10%"
  pid=$(cut -f5 "$(JOBS_DIR)/endless")    # the watcher's own PID, as it wrote it
  kill -TERM "$pid"
  ends_within "$pid" 5
  wait || true                            # the producer ends on its next write
  assert_equal "$(progress_line)" "✗1"
}

# follow: the output file of a Claude Code background command, grown here by
# hand, closing lines included.
FOLLOW() { bash "$REPO/claude/statusline-progress.sh" follow "$@" 3>&- & }

@test "follow: reads the percentage as the file grows, and ends done at exit code 0" {
  f="$TEST_TMP/b1.output"; : > "$f"
  FOLLOW "tests" bg-b1 "$f"; w=$!
  printf '10%%\nerr-line\n' >> "$f"
  row_reads tests "10%"
  printf '60%%\n' >> "$f"
  row_reads tests "60%"
  printf '100%%\n\n[exited with code 0]\n' >> "$f"
  ends_within "$w" 5
  assert_equal "$(progress_line)" "✓1"
}

@test "follow: another exit code fails with it, at the last percentage" {
  f="$TEST_TMP/b2.output"; printf '40%%\n' > "$f"
  FOLLOW "build" bg-b2 "$f"; w=$!
  row_reads build "40%"
  printf '\n[exited with code 3]\n' >> "$f"
  ends_within "$w" 5
  assert_equal "$(progress_line)" "✗1"
  assert_contains "$(cat "$(JOBS_DIR)/bg-b2")" $'\t40\tfail:3\t'
}

@test "follow: a stopped command ([killed]) counts as ended" {
  f="$TEST_TMP/b3.output"; printf '20%%\n' > "$f"
  FOLLOW "server" bg-b3 "$f"; w=$!
  row_reads server "20%"
  printf '\n[killed]\n' >> "$f"
  ends_within "$w" 5
  assert_equal "$(progress_line)" "■1"
}

@test "follow: a closing line inside the output is not the end" {
  f="$TEST_TMP/b4.output"; printf '[exited with code 0] in a log line\n30%%\n' > "$f"
  FOLLOW "logs" bg-b4 "$f"; w=$!
  row_reads logs "30%"
  kill -0 "$w" || fail "stopped at a closing line mid-output"
  printf '\n[exited with code 0]\n' >> "$f"
  ends_within "$w" 5
}

@test "follow: it ends when the session it follows for exits" {
  f="$TEST_TMP/b5.output"; printf '50%%\n' > "$f"
  sleep 30 & owner=$!
  FOLLOW "long" bg-b5 "$f" "$owner"; w=$!
  row_reads long "50%"
  kill "$owner"; wait "$owner" 2>/dev/null || true
  ends_within "$w" 5
  assert_equal "$(progress_line)" "■1"
}

@test "follow: it ends when the file is removed" {
  f="$TEST_TMP/b6.output"; printf '50%%\n' > "$f"
  FOLLOW "gone" bg-b6 "$f"; w=$!
  row_reads gone "50%"
  rm -f "$f"
  ends_within "$w" 5
  assert_equal "$(progress_line)" "■1"
}

@test "follow: a link at the file is never read, and leaves no row" {
  printf '70%%\n\n[exited with code 0]\n' > "$TEST_TMP/real"
  ln -s "$TEST_TMP/real" "$TEST_TMP/b7.output"
  FOLLOW "link" bg-b7 "$TEST_TMP/b7.output"; w=$!
  ends_within "$w" 20
  assert_equal "$(progress_line)" ""
}

@test "follow: with no percentage it shows name and run time; stopped, it leaves no row; failed, it counts" {
  f="$TEST_TMP/b8.output"; printf 'listening on :8080\n' > "$f"
  FOLLOW "server" bg-b8 "$f"; w=$!
  row_reads server "0s"
  printf 'still no number\n\n[killed]\n' >> "$f"
  ends_within "$w" 5
  assert_equal "$(progress_line)" ""
  [ ! -e "$(JOBS_DIR)/bg-b8" ] || fail "a stopped job kept its row"
  f="$TEST_TMP/b9.output"; printf 'ok\n\n[exited with code 1]\n' > "$f"
  FOLLOW "quiet fail" bg-b9 "$f"; w=$!
  ends_within "$w" 5
  assert_equal "$(progress_line)" "✗1"
  f="$TEST_TMP/b13.output"; printf 'ok\n\n[exited with code 0]\n' > "$f"
  FOLLOW "quiet ok" bg-b13 "$f"; w=$!
  ends_within "$w" 5
  assert_equal "$(progress_line)" "✓1 ✗1"
}

@test "follow: a month-old empty jobs dir is pruned before use, not after" {
  mkdir -p "$(JOBS_DIR)"; touch -d '@1000000' "$(JOBS_DIR)"
  f="$TEST_TMP/b11.output"; : > "$f"
  FOLLOW "resumed" bg-b11 "$f"; w=$!
  sleep 1; printf '25%%\n' >> "$f"
  row_reads resumed "25%"
  printf '\n[killed]\n' >> "$f"
  ends_within "$w" 5
}

@test "follow: a TERM before any percentage exits 143 and leaves no row" {
  f="$TEST_TMP/b12.output"; printf 'waiting\n' > "$f"
  FOLLOW "early" bg-b12 "$f"; w=$!
  sleep 1
  kill -TERM "$w"
  ends_within "$w" 5
  st=0; wait "$w" || st=$?
  assert_equal "$st" 143
  [ ! -e "$(JOBS_DIR)/bg-b12" ] || fail "a row was written"
}

@test "usage prints the whole header, to its last line" {
  run bash "$REPO/claude/statusline-progress.sh"
  assert_equal "$status" 2
  assert_contains "$output" "estimate and job exit 1, run still runs."
}

@test "follow: the percentage replaces the run time once one is printed" {
  f="$TEST_TMP/b10.output"; printf 'starting\n' > "$f"
  FOLLOW "late" bg-b10 "$f"; w=$!
  row_reads late "0s"
  printf '15%%\n' >> "$f"
  row_reads late "15%"
  printf '\n[exited with code 0]\n' >> "$f"
  ends_within "$w" 5
  assert_equal "$(progress_line)" "✓1"
}

@test "follow: two commands with one name keep a row each" {
  printf '10%%\n' > "$TEST_TMP/x.output"; printf '20%%\n' > "$TEST_TMP/y.output"
  FOLLOW "tests" bg-x "$TEST_TMP/x.output"; w1=$!
  FOLLOW "tests" bg-y "$TEST_TMP/y.output"; w2=$!
  i=0; until [ -n "$(progress_line | grep -F '+1')" ]; do
    i=$(( i + 1 )); [ "$i" -le 50 ] || fail "no second row: $(progress_line)"; sleep 0.1; done
  printf '\n[exited with code 0]\n' >> "$TEST_TMP/x.output"
  printf '\n[exited with code 0]\n' >> "$TEST_TMP/y.output"
  ends_within "$w1" 5; ends_within "$w2" 5
  assert_equal "$(progress_line)" "✓2"
}

@test "follow: a percentage inside a longer number or a version is not one" {
  f="$TEST_TMP/c8.output"; printf 'Extracting...20%%\n1234.5%%\nv1.2.50%%\n\n[killed]\n' > "$f"
  FOLLOW "versions" bg-c8 "$f"; w=$!
  ends_within "$w" 5
  assert_contains "$(cat "$(JOBS_DIR)/bg-c8")" $'\t20\tend\t'
}

@test "follow: a closing line split across two reads is joined" {
  f="$TEST_TMP/c1.output"; printf '30%%\n\n[exited wi' > "$f"
  FOLLOW "split" bg-c1 "$f"; w=$!
  row_reads split "30%"
  sleep 1.5
  printf 'th code 0]\n' >> "$f"
  ends_within "$w" 5
  assert_equal "$(progress_line)" "✓1"
}

@test "follow: text like a closing line, not on a line of its own, is not one" {
  f="$TEST_TMP/c2.output"; printf '30%%\nfoo[killed]\n' > "$f"
  FOLLOW "lookalike" bg-c2 "$f"; w=$!
  row_reads lookalike "30%"
  sleep 2.5
  kill -0 "$w" || fail "ended at a lookalike"
  printf '\n[killed]\n' >> "$f"
  ends_within "$w" 5
}

@test "follow: a closing line that more output follows is not the end" {
  f="$TEST_TMP/c3.output"; : > "$f"
  FOLLOW "cat" bg-c3 "$f"; w=$!
  printf '\n[exited with code 0]\n' >> "$f"; sleep 0.3; printf '40%%\n' >> "$f"
  row_reads cat "40%"
  kill -0 "$w" || fail "ended at a printed closing line"
  printf '\n[exited with code 0]\n' >> "$f"
  ends_within "$w" 5
}

@test "follow: a file cut short or replaced ends the row" {
  f="$TEST_TMP/c4.output"; printf '30%%\n' > "$f"
  FOLLOW "cut" bg-c4 "$f"; w=$!
  row_reads cut "30%"
  : > "$f"
  ends_within "$w" 5
  printf '30%%\n' > "$TEST_TMP/c5.output"
  FOLLOW "moved" bg-c5 "$TEST_TMP/c5.output"; w=$!
  i=0; until [ "$(progress_line)" = "moved 30% · ■1" ]; do
    i=$(( i + 1 )); [ "$i" -le 50 ] || fail "never read: $(progress_line)"; sleep 0.1; done
  printf 'new\n' > "$TEST_TMP/c5.new"; mv "$TEST_TMP/c5.new" "$TEST_TMP/c5.output"
  ends_within "$w" 5
  assert_equal "$(progress_line)" "■2"
}

@test "follow: a long line, or a long run of digits, is read in one pass" {
  f="$TEST_TMP/c6.output"; : > "$f"
  FOLLOW "minified" bg-c6 "$f"; w=$!
  { head -c 2000000 /dev/zero | tr '\0' 'x'; printf '\n'
    head -c 2000000 /dev/zero | tr '\0' '7'; printf '\n55%%\n\n[exited with code 4]\n'; } >> "$f"
  ends_within "$w" 10
  assert_contains "$(cat "$(JOBS_DIR)/bg-c6")" $'\t55\tfail:4\t'
}

@test "follow: waiting on an idle file costs next to no CPU" {
  [ -r /proc/self/stat ] || skip "needs /proc"
  f="$TEST_TMP/c7.output"; printf '10%%\n' > "$f"
  FOLLOW "idle" bg-c7 "$f"; w=$!
  row_reads idle "10%"
  sleep 3
  # utime + stime, in clock ticks (100 a second): under 0.3 s over 3 s idle.
  ticks=$(awk '{print $14 + $15}' "/proc/$w/stat")
  [ "$ticks" -lt 30 ] || fail "busy at EOF: $ticks ticks"
  printf '\n[killed]\n' >> "$f"
  ends_within "$w" 5
}

# The hook: a PostToolUse event in, a follower on the task's output file out.
hook_event() { # background? task-id [description]
  jq -cn --argjson bg "$1" --arg id "$2" --arg d "${3:-}" --arg s "$SID" \
    --arg t "$TEST_TMP/projects/-demo-proj/$SID.jsonl" \
    '{hook_event_name:"PostToolUse", session_id:$s, transcript_path:$t,
      tool_name:"Bash", tool_input:{command:"make", description:$d, run_in_background:$bg},
      tool_response:{stdout:"", stderr:"", backgroundTaskId:$id}}'
}
task_file() { echo "/tmp/claude-$(id -u)/-demo-proj/$SID/tasks/$1.output"; }

@test "hook: a background command gets a follower on its output file, and prints nothing" {
  mkdir -p "$(dirname "$(task_file t1)")"; printf '35%%\n' > "$(task_file t1)"
  # Not under $(...): the follower stops with the hook's parent, the session
  # in real use, and a command substitution's shell would end at once.
  hook_event true t1 "Run the suite" | bash "$REPO/claude/statusline-progress-hook.sh" > "$TEST_TMP/hook.out"
  assert_equal "$(cat "$TEST_TMP/hook.out")" ""
  row_reads "Run the suite" "35%"
  printf '\n[exited with code 0]\n' >> "$(task_file t1)"
  i=0; until [ "$(progress_line)" = "✓1" ]; do
    i=$(( i + 1 )); [ "$i" -le 50 ] || fail "never done: $(progress_line)"; sleep 0.1; done
  rm -rf "/tmp/claude-$(id -u)/-demo-proj"
}

@test "hook: a backslash in the description reaches the row as it is" {
  mkdir -p "$(dirname "$(task_file t3)")"; printf '5%%\n' > "$(task_file t3)"
  hook_event true t3 'a\b' | bash "$REPO/claude/statusline-progress-hook.sh" > /dev/null
  row_reads 'a\b' "5%"
  printf '\n[killed]\n' >> "$(task_file t3)"
  sleep 2.5; rm -rf "/tmp/claude-$(id -u)/-demo-proj"
}

@test "hook: a bare sleep (a heartbeat, a timer) starts nothing; a wait loop does" {
  mkdir -p "$(dirname "$(task_file t4)")"
  hb=$(hook_event true t4 "Re-arm" | jq -c '.tool_input.command = "sleep 3000; echo \"HEARTBEAT $(date +%H:%M)\""')
  printf '%s' "$hb" | bash "$REPO/claude/statusline-progress-hook.sh"
  sleep 0.5
  [ ! -e "$(JOBS_DIR)/bg-t4" ] || fail "a heartbeat got a row"
  dl=$(hook_event true t6 "delayed build" | jq -c '.tool_input.command = "sleep 5 && make"')
  printf 'x\n' > "$(task_file t6)"
  printf '%s' "$dl" | bash "$REPO/claude/statusline-progress-hook.sh" > /dev/null
  row_reads "delayed build" "0s"
  printf '\n[killed]\n' >> "$(task_file t6)"
  sleep 2.5
  printf 'x\n' > "$(task_file t5)"
  wl=$(hook_event true t5 "wait for deploy" | jq -c '.tool_input.command = "until test -e done; do sleep 60; done"')
  printf '%s' "$wl" | bash "$REPO/claude/statusline-progress-hook.sh" > /dev/null
  row_reads "wait for deploy" "0s"
  printf '\n[exited with code 0]\n' >> "$(task_file t5)"
  sleep 2.5; rm -rf "/tmp/claude-$(id -u)/-demo-proj"
}

@test "hook: a foreground command, or a bad id, starts nothing" {
  hook_event false t2 "fg" | bash "$REPO/claude/statusline-progress-hook.sh"
  hook_event true '../x' "bad" | bash "$REPO/claude/statusline-progress-hook.sh"
  echo 'not json' | bash "$REPO/claude/statusline-progress-hook.sh"
  sleep 0.5
  [ ! -d "$(JOBS_DIR)" ] || assert_equal "$(ls "$(JOBS_DIR)")" ""
}

@test "job: set by hand, shown as name and percentage, the percentage in cyan" {
  PROG job render 42
  assert_equal "$(progress_line)" "render 42%"
  assert_contains "$(render_raw)" $'render \033[36m42%'
}

@test "a job name is never run as code" {
  run PROG run '$(touch "$TEST_TMP/pwned")' -- bash -c 'echo 10%'
  assert_equal "$status" 0
  run PROG watch '`touch "$TEST_TMP/pwned"`' < /dev/null
  run PROG job '$(touch "$TEST_TMP/pwned")' 10
  render > /dev/null
  [ ! -e "$TEST_TMP/pwned" ] || fail "job name was executed"
}

@test "a job name's control characters never reach the terminal" {
  PROG job $'ev\033]0;TITLE\007il\r' 30
  out=$(render | cat -v)
  refute_contains "$out" "^["; refute_contains "$out" "^G"; refute_contains "$out" "^M"
  assert_contains "$out" "ev]0;TITLEil "
  refute_contains "$(cat -v "$(JOBS_DIR)"/ev*)" "^["              # nor the row
  # Nor does one planted in a row by something else.
  printf '%s\t5\trun\tx\033]52;c;AAAA\007y\n' "$STATUSLINE_NOW" > "$(JOBS_DIR)/planted"
  refute_contains "$(render | cat -v)" "^["
}

@test "a long name is cut to 20 characters, by character, not mid-character" {
  PROG job "a$(printf 'é%.0s' $(seq 30))" 5
  assert_equal "$(progress_line)" "a$(printf 'é%.0s' $(seq 19)) 5%"
}

@test "names starting with a dot get a row, and nothing lands outside the jobs dir" {
  PROG job .. 30
  assert_equal "$(progress_line)" ".. 30%"
  PROG job .. done
  PROG job .hidden 20
  assert_equal "$(progress_line)" ".hidden 20% · ✓1"
  assert_equal "$(ls -A "$CLAUDE_CONFIG_DIR/cache/statusline-progress")" "$SID.jobs"
}

@test "a garbled job row is never evaluated, and is skipped" {
  mkdir -p "$(JOBS_DIR)"
  x='a[$(touch "'"$TEST_TMP"'/PWNED")]'
  printf '%s\t5\trun\tw\n'           "$x"             > "$(JOBS_DIR)/w"
  printf '%s\t%s\trun\tp\n'          "$STATUSLINE_NOW" "$x" > "$(JOBS_DIR)/p"
  printf '%s\t5\tfail:%s\ts\n'       "$STATUSLINE_NOW" "$x" > "$(JOBS_DIR)/s"
  printf '%s\t5\trun\tpid\t%s\t-\n'  "$STATUSLINE_NOW" "$x" > "$(JOBS_DIR)/pid"
  assert_equal "$(progress_line)" "pid 5%"
  [ ! -e "$TEST_TMP/PWNED" ] || fail "a field of a job row was run as code"
}

@test "the newest running job is shown, +N for the rest; finished ones go after 30 min" {
  # ls -t orders by mtime, so set it, seconds apart, in the recent past: a
  # month-old file would be pruned by the next write.
  for n in a b c d; do PROG job "$n" 10; done
  r=$(( $(date +%s) - 60 ))
  touch -d "@$(( r + 1 ))" "$(JOBS_DIR)/a"; touch -d "@$(( r + 2 ))" "$(JOBS_DIR)/b"
  touch -d "@$(( r + 3 ))" "$(JOBS_DIR)/c"; touch -d "@$(( r + 4 ))" "$(JOBS_DIR)/d"
  assert_equal "$(progress_line)" "d 10% +3"
  PROG job done-one done
  assert_equal "$(progress_line)" "d 10% +3 · ✓1"
  refute_contains "$(STATUSLINE_NOW=$(( T0 + 300 + 1800 )) progress_line)" "✓"
}

@test "finished jobs collapse into counters, a zero counter omitted" {
  PROG job one done; PROG job two done; PROG watch three < /dev/null > /dev/null
  assert_equal "$(progress_line)" "✓2 ■1"
  run PROG run bad -- false
  assert_equal "$(progress_line)" "✓2 ✗1 ■1"
  assert_contains "$(render_raw)" $'\033[32m✓2 \033[31m✗1 \033[90m■1'
}

@test "estimate, running job and counters share one line" {
  PROG estimate 60 3/5 00:30
  PROG job "test suite" 38
  PROG job lint done
  run PROG run deploy -- false
  touch -d "@$(( $(date +%s) - 60 ))" "$(JOBS_DIR)/lint" "$(JOBS_DIR)/deploy"
  assert_equal "$(progress_line)" "60% ≈00:30 · test suite 38% · ✓1 ✗1"
  refute_contains "$(render)" "█"
  refute_contains "$(render)" "3/5"
}

@test "an estimate alone, and jobs alone, each make the line by themselves" {
  PROG estimate 60 3/5 00:30
  assert_equal "$(progress_line)" "60% ≈00:30"
  rm -f "$(EST_FILE)"
  PROG job build 38
  assert_equal "$(progress_line)" "build 38%"
}

@test "an age is shown only past 5 minutes; a running job's only past 15" {
  STATUSLINE_NOW=$(( T0 + 1 )) PROG estimate 40
  assert_equal "$(progress_line)" "40%"
  STATUSLINE_NOW=$(( T0 - 1 )) PROG estimate 40
  assert_equal "$(progress_line)" "40% (5m ago)"
  rm -f "$(EST_FILE)"
  PROG job slow 10
  assert_equal "$(STATUSLINE_NOW=$(( T0 + 300 + 899 )) progress_line)" "slow 10%"
  assert_equal "$(STATUSLINE_NOW=$(( T0 + 300 + 900 )) progress_line)" "slow 10% (15m ago)"
  assert_contains "$(STATUSLINE_NOW=$(( T0 + 300 + 900 )) render_raw)" $'\033[90mslow 10% (15m ago)'
}

@test "one progress line in all, however many jobs there are" {
  PROG estimate 30 1/9 01:00
  for n in 1 2 3 4 5 6 7 8; do PROG job "run$n" "$n"; done
  for n in 1 2 3; do PROG job "ok$n" done; PROG watch "end$n" < /dev/null > /dev/null; done
  out="$(render)"
  assert_equal "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" 4
  assert_contains "$(progress_line)" "+7 · ✓3 ■3"
}

@test "a silent running job is hidden after 6 hours" {
  PROG job old 30
  assert_equal "$(STATUSLINE_NOW=$(( T0 + 300 + 21600 )) progress_line)" ""
}

@test "the writer prunes month-old files, so a jobs-only session is pruned too" {
  mkdir -p "$CLAUDE_CONFIG_DIR/cache/statusline-progress/old.jobs"
  touch -d '@1000000' "$CLAUDE_CONFIG_DIR/cache/statusline-progress/old.jobs"
  PROG job fresh 10
  [ ! -e "$CLAUDE_CONFIG_DIR/cache/statusline-progress/old.jobs" ] || fail "not pruned"
}

# Rows written straight into the cache, at a set age, for the boundaries the
# writer cannot reach quickly. The clock is the real one: ls -t orders rows by
# mtime, and the pid of a running row must be alive or dead here.
plant_setup() {
  NOW=$(date +%s); export STATUSLINE_NOW=$NOW
  PD="$CLAUDE_CONFIG_DIR/cache/statusline-progress"; mkdir -p "$PD/$SID.jobs"
  NS=$(readlink /proc/self/ns/pid 2>/dev/null || echo -)
}
plant_job() { # name age pct state [pid] [ns]
  local w=$(( NOW - $2 ))
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$w" "$3" "$4" "$1" "${5:-$$}" "${6:-$NS}" > "$PD/$SID.jobs/$1"
  touch -d "@$w" "$PD/$SID.jobs/$1"
}
plant_estimate() { # age pct [eta_epoch]
  printf '%s\t%s\t-\t%s\n' "$(( NOW - $1 ))" "$2" "${3:--}" > "$PD/$SID.estimate"
}

@test "two running jobs: the newer one is shown, +1 for the other" {
  plant_setup
  plant_job older 20 10 run; plant_job newer 10 40 run
  assert_equal "$(progress_line)" "newer 40% +1"
}

@test "a running job with no percentage yet shows its run time; elsewhere \"-\" is no percentage" {
  plant_setup
  plant_job wait 1380 - run
  assert_equal "$(progress_line)" "wait 23m"
  plant_job wait 1380 - done
  assert_equal "$(progress_line)" ""
}

@test "an estimate turns gray at 30 minutes old, not before" {
  plant_setup
  plant_estimate 1799 50; assert_contains "$(render_raw)" $'\033[37m50%'
  plant_estimate 1800 50; assert_contains "$(render_raw)" $'\033[90m50%'
}

@test "an ETA of exactly now is not red yet" {
  plant_setup
  plant_estimate 0 50 "$NOW"; refute_contains "$(render_raw)" $'\033[31m'
  plant_estimate 0 50 $(( NOW - 60 )); assert_contains "$(render_raw)" $'\033[31m≈'
}

@test "a running row from another pid namespace is not judged by this one's pids" {
  plant_setup
  sh -c 'exit 0' & dead=$!; wait "$dead"
  plant_job here 10 5 run "$dead"
  assert_equal "$(progress_line)" "✗1"
  plant_job here 10 5 run "$dead" "pid:[1]"
  assert_equal "$(progress_line)" "here 5%"
}

# ------------------------------------------------- planted files in the cache --

@test "a link planted at a row or its temp file is never written through" {
  echo precious > "$TEST_TMP/victim"
  mkdir -p "$(JOBS_DIR)" "$TEST_TMP/shim"
  # The status line's estimate, over a link at the target.
  ln -s "$TEST_TMP/victim" "$(EST_FILE)"
  assistant_turn "$T0" '**x - Progress: 1/4 · ~25% · ETA ~1 h**'
  render > /dev/null
  # A row set by hand, over a link at the target.
  ln -s "$TEST_TMP/victim" "$(JOBS_DIR)/hand"
  run PROG job hand 10
  assert_equal "$status" 1
  # Both, over a link at the temp file's name: mktemp is made to name it.
  printf '#!/bin/sh\necho "%s"\n' "$TEST_TMP/planted" > "$TEST_TMP/shim/mktemp"
  chmod +x "$TEST_TMP/shim/mktemp"
  ln -s "$TEST_TMP/victim" "$TEST_TMP/planted"
  rm -f "$(EST_FILE)"
  run env PATH="$TEST_TMP/shim:$PATH" bash "$REPO/claude/statusline-progress.sh" job viatmp 10
  assert_equal "$status" 1
  : > "$TR"; assistant_turn $(( T0 + 60 )) '**x - Progress: 2/4 · ~50% · ETA ~1 h**'
  jq -n --arg t "$TR" --arg s "$SID" '{session_id:$s, transcript_path:$t}' \
    | PATH="$TEST_TMP/shim:$PATH" bash "$REPO/claude/statusline-command.sh" > /dev/null
  # run's own writer, over links at its row and at its temp file. The
  # command plants them: the writer is its parent.
  run PROG run viarun -- sh -c 'ln -sf "$0" "$1.tmp.$PPID"; echo 20%; sleep 1.2; echo 30%' \
    "$TEST_TMP/victim" "$(JOBS_DIR)/viarun"
  assert_equal "$status" 0
  assert_contains "$(progress_line)" "✓1"
  run PROG run viarow -- sh -c 'ln -sf "$0" "$1"; echo 20%; sleep 1.2; echo 30%' \
    "$TEST_TMP/victim" "$(JOBS_DIR)/viarow"
  assert_contains "$output" "cannot write"
  assert_equal "$(cat "$TEST_TMP/victim")" precious
}

@test "a FIFO or a device in the cache never hangs the status line" {
  mkdir -p "$(JOBS_DIR)"
  mkfifo "$(JOBS_DIR)/fifo" "$(EST_FILE)"
  ln -s /dev/zero "$(JOBS_DIR)/zero"
  PROG job real 40
  jq -n --arg t "$TR" --arg s "$SID" '{session_id:$s, transcript_path:$t}' > "$TEST_TMP/in"
  st=0; timeout 5 bash "$REPO/claude/statusline-command.sh" < "$TEST_TMP/in" > "$TEST_TMP/out" || st=$?
  assert_equal "$st" 0
  assert_equal "$(sed $'s/\033\\[[0-9;]*m//g' "$TEST_TMP/out" | sed -n 3p)" "real 40%"
}

@test "rows past 6 hours are skipped, a running one with a live writer too" {
  mkdir -p "$(JOBS_DIR)"
  ns=$(readlink /proc/self/ns/pid 2>/dev/null || echo -)
  printf '%s\t50\trun\tstale\t%s\t%s\n' "$(( STATUSLINE_NOW - 30000 ))" "$$" "$ns" > "$(JOBS_DIR)/stale"
  assert_equal "$(progress_line)" ""
  PROG job new 20
  assert_equal "$(progress_line)" "new 20%"
}

# --------------------------------------------------------- cache unwritable --

@test "an unwritable cache: estimate and job say so and fail; run still runs" {
  mkdir -p "$CLAUDE_CONFIG_DIR"; : > "$CLAUDE_CONFIG_DIR/cache"   # a file, not a dir
  run PROG estimate 50
  assert_equal "$status" 1
  assert_contains "$output" "cannot write"
  run PROG job x 5
  assert_equal "$status" 1
  assert_contains "$output" "cannot write"
  run PROG run x -- bash -c 'echo ran; exit 4'
  assert_equal "$status" 4
  assert_contains "$output" "ran"
  assert_contains "$output" "cannot write"
}

# ----------------------------------------------------------- no session id --

@test "no session id: estimate and job say so and exit 2" {
  unset CLAUDE_CODE_SESSION_ID
  run PROG estimate 50
  assert_equal "$status" 2
  assert_contains "$output" "CLAUDE_CODE_SESSION_ID"
  run PROG job x 5
  assert_equal "$status" 2
}

@test "no session id: run still runs the command and keeps its code" {
  unset CLAUDE_CODE_SESSION_ID
  run PROG run x -- bash -c 'echo ran; exit 4'
  assert_equal "$status" 4
  assert_contains "$output" "ran"
}

@test "a session id with a path in it is refused" {
  CLAUDE_CODE_SESSION_ID='../../evil' run PROG estimate 50
  assert_equal "$status" 2
  [ ! -e "$CLAUDE_CONFIG_DIR/evil.estimate" ] || fail "wrote outside the progress dir"
}
