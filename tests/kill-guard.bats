#!/usr/bin/env bats
#
# kill-guard-hook.sh (blocks a Bash command that would signal every process
# the user owns) and pidjail (runs a command where it cannot).

load 'helpers/setup'
bats_require_minimum_version 1.5.0

setup()    { common_setup; }
teardown() { common_teardown; }

# The command goes to jq on stdin: an argument over 128 KB fails to exec.
HOOK() {
  local j
  j="$(printf '%s' "$1" | jq -Rsc '{tool_name:"Bash", tool_input:{command:.}}')" || return 99
  printf '%s' "$j" | bash "$REPO/claude/kill-guard-hook.sh"
}

blocked() { run HOOK "$1"; [ "$status" -eq 2 ] || fail "not blocked: $1"; assert_contains "$output" "kill-guard: blocked"; }
allowed() { run HOOK "$1"; [ "$status" -eq 0 ] || fail "blocked: $1 ($output)"; }

# ----------------------------------------------------------------- hook ----

@test "hook blocks kill with a pid of -1" {
  blocked 'kill -9 -1'
  blocked 'kill -KILL -- -1'
  blocked 'kill -s TERM -1'
  blocked 'kill -1 -1'
  blocked 'kill -9 1234 -1'
  blocked 'kill -- -01'
  blocked 'kill -- "-1"'
  blocked '/bin/kill -9 -1'
  blocked '\kill -9 -1'
  blocked 'kill -9 -1>/dev/null'
}

@test "hook blocks a user's processes by user, with no process name" {
  blocked 'pkill -u me'
  blocked 'pkill -9 -u "$USER"'
  blocked 'pkill -fu me'
  blocked 'pkill -u1000'
  blocked 'pkill --euid me'
  blocked 'pkill --uid=1000'
  blocked 'killall -u me'
  blocked 'killall --user me'
  blocked 'pkill -u me 2>/dev/null'
  blocked 'pkill -u me > /dev/null'
  blocked 'pkill -u me 2> /dev/null'
  blocked 'killall -s KILL -u me'
  blocked 'killall -u me -s 9'
  blocked 'pkill --signal KILL -u me'
}

@test "hook blocks loginctl ending a user, session or seat" {
  blocked 'loginctl terminate-user me'
  blocked 'loginctl terminate-session 2'
  blocked 'loginctl --no-ask-password kill-user me'
  blocked 'loginctl kill-seat seat0'
}

@test "hook finds these behind wrappers and inside compound commands" {
  blocked 'sudo kill -9 -1'
  blocked 'timeout 5 kill -9 -1'
  blocked "bash -c 'kill -9 -1'"
  blocked 'echo $(kill -9 -1)'
  blocked 'echo 1 | xargs kill -9 -1'
  blocked 'cd /tmp && pkill -u me; echo done'
  blocked 'for i in 1; do kill -9 -1; done'
  blocked '{ loginctl terminate-user me; }'
}

@test "hook allows ordinary, targeted signals" {
  allowed 'kill 1234'
  allowed 'kill -9 1234'
  allowed 'kill -1 1234'
  allowed 'kill -TERM -- -4321'
  allowed 'kill 0'
  allowed 'kill -l'
  allowed 'kill -l 1'
  allowed 'kill -9 -12'
  allowed 'pkill -f "vite --port 5173"'
  allowed 'pkill -u "$USER" -n node'
  allowed 'pkill -USR1 -F run/app.pid'
  allowed 'killall -u me node'
  allowed 'loginctl list-sessions'
  allowed 'ls -l; echo hi'
}

@test "hook passes input without a command" {
  run bash "$REPO/claude/kill-guard-hook.sh" <<< '{"tool_name":"Read","tool_input":{}}'
  assert_equal "$status" 0
}

@test "hook reads a long line of kill words in time, and still finds a kill at its end" {
  local long; long="$(printf 'kill x %.0s' $(seq 1 20000))"
  SECONDS=0
  allowed "echo $long"
  blocked "echo $long; kill -9 -1"
  [ "$SECONDS" -lt 20 ] || fail "took ${SECONDS}s"
}

@test "hook reads a long line dense in quotes and separators in time" {
  local long; long="$(printf '"kill"; x | %.0s' $(seq 1 40000))"
  SECONDS=0
  blocked "echo $long; kill -9 -1"
  [ "$SECONDS" -lt 20 ] || fail "took ${SECONDS}s"
}

@test "hook says so, as a non-blocking error, when jq is missing" {
  mkdir -p "$TEST_TMP/bin"; ln -s "$(command -v bash)" "$TEST_TMP/bin/bash"
  run env PATH="$TEST_TMP/bin" bash "$REPO/claude/kill-guard-hook.sh" <<< '{}'
  assert_equal "$status" 1
  assert_contains "$output" "NOT being checked"
}

# -------------------------------------------------------------- pidjail ----

# The whole chain pidjail runs the command under.
jail_available() {
  env --ignore-signal=HUP -- setpriv --pdeathsig KILL -- unshare --user --map-current-user --pid --fork --mount-proc --kill-child \
    -- setsid -w env --default-signal=INT,QUIT,HUP -- true 2>/dev/null
}
need_jail() {
  jail_available || skip "cannot set up a jail here (the refusal tests cover pidjail here)"
  command -v ps >/dev/null && command -v pgrep >/dev/null || skip "needs ps and pgrep (procps)"
}
# A sleep length unique to this run, so suites running at once (two
# worktrees, two sessions) never match each other's processes.
uniq_secs() { echo "29$1.$$$RANDOM"; }
# Retry a check for up to 10 s.
wait_for() { local n=200; until "$@"; do n=$((n - 1)); [ $n -gt 0 ] || fail "timed out waiting for: $*"; sleep 0.05; done; }
running() { pgrep -fx "sleep $1" >/dev/null; }
# True once process $1 has a TERM handler (SigCgt bit 14).
has_term_trap() {
  local c; c="$(awk '/^SigCgt:/ {print $2}' "/proc/$1/status" 2>/dev/null)"
  [ -n "$c" ] && (( (16#$c >> 14) & 1 ))
}

@test "pidjail refuses, and runs nothing, when unshare fails (stubbed)" {
  mkdir -p "$TEST_TMP/bin"
  printf '#!/bin/sh\necho "unshare: stub failure" >&2\nexit 1\n' > "$TEST_TMP/bin/unshare"
  chmod +x "$TEST_TMP/bin/unshare"
  PATH="$TEST_TMP/bin:$PATH" run "$REPO/claude/pidjail" touch "$TEST_TMP/ran"
  assert_equal "$status" 125
  assert_contains "$output" "pidjail: refused:"
  assert_contains "$output" "stub failure"
  [ ! -e "$TEST_TMP/ran" ] || fail "the command ran unjailed"
}

@test "pidjail refuses, and runs nothing, when another tool in its chain fails (stubbed)" {
  mkdir -p "$TEST_TMP/bin"
  printf '#!/bin/sh\necho "setpriv: stub failure" >&2\nexit 127\n' > "$TEST_TMP/bin/setpriv"
  chmod +x "$TEST_TMP/bin/setpriv"
  PATH="$TEST_TMP/bin:$PATH" run "$REPO/claude/pidjail" touch "$TEST_TMP/ran"
  assert_equal "$status" 125
  assert_contains "$output" "pidjail: refused:"
  [ ! -e "$TEST_TMP/ran" ] || fail "the command ran unjailed"
}

@test "pidjail refuses, and runs nothing, where namespaces are unavailable" {
  jail_available && skip "namespaces available here; the stubbed refusal test covers this"
  run "$REPO/claude/pidjail" touch "$TEST_TMP/ran"
  assert_equal "$status" 125
  [ ! -e "$TEST_TMP/ran" ] || fail "the command ran unjailed"
}

@test "pidjail passes stdin and the exit status through" {
  need_jail
  run "$REPO/claude/pidjail" sh -c 'exit 7'
  assert_equal "$status" 7
  assert_equal "$(echo hi | "$REPO/claude/pidjail" cat)" hi
  run -127 "$REPO/claude/pidjail" no-such-command-here
  assert_equal "$status" 127
}

# Each broad signal below runs only after checks that it is inside a jail
# (PID 1 is not the host's init, the command is PID 2, few processes show),
# so a broken jail exits 99 rather than killing the machine.
@test "pidjail: kill -KILL -1 inside reaches only the jail" {
  need_jail
  sleep 300 & outside=$!
  run "$REPO/claude/pidjail" bash -c '
    [ "$(cat /proc/1/comm)" = bash ] && [ $$ -eq 2 ] && [ "$(ps -e --no-headers | wc -l)" -lt 10 ] || exit 99
    sleep 300 & inner=$!
    kill -KILL -- -1; sleep 0.3
    kill -0 "$inner" 2>/dev/null && exit 1; exit 0'
  kill -0 "$outside" && alive=1 || alive=0
  kill "$outside" 2>/dev/null || true
  assert_equal "$status" 0
  assert_equal "$alive" 1
}

# Run in a fresh session, so even an escaped `kill 0` stays there.
@test "pidjail: kill 0 inside does not reach the caller's process group" {
  need_jail
  run setsid -w bash -c '
    sleep 300 & s=$!
    "$1" bash -c "[ \"\$(cat /proc/1/comm)\" = bash ] && [ \$\$ -eq 2 ] || exit 99; kill -TERM 0; sleep 5"
    rc=$?
    kill -0 $s 2>/dev/null && r=survived || r=killed
    kill $s 2>/dev/null; echo "$r $rc"' _ "$REPO/claude/pidjail"
  assert_equal "$output" "survived 143"
}

@test "pidjail passes TERM on to the command" {
  need_jail
  d=$(uniq_secs 7)
  "$REPO/claude/pidjail" bash -c "trap 'echo got-term > \"$TEST_TMP/t\"; exit 143' TERM; sleep $d & wait" &
  p=$!
  # The sleep exists once the command's trap is set.
  wait_for running "$d"
  kill -TERM "$p"
  wait "$p" && rc=0 || rc=$?
  assert_equal "$rc" 143
  assert_equal "$(cat "$TEST_TMP/t")" got-term
}

# A closed terminal or a dropped ssh session sends HUP to the whole
# foreground process group, pidjail's helpers included.
@test "pidjail passes a HUP to its process group on to the command as TERM" {
  need_jail
  d=$(uniq_secs 5)
  run setsid -w bash -c '
    "$1" bash -c "trap '\''echo got-term > \"$2/h\"; exit 143'\'' TERM; sleep $3 & wait" & p=$!
    for _ in $(seq 200); do pgrep -fx "sleep $3" >/dev/null && break; sleep 0.05; done
    trap "" HUP; kill -HUP 0
    wait "$p"; echo "rc=$?"' _ "$REPO/claude/pidjail" "$TEST_TMP" "$d"
  ! running "$d" || { pkill -fx "sleep $d"; fail "the command outlived a HUP"; }
  assert_equal "$output" "rc=143"
  assert_equal "$(cat "$TEST_TMP/h")" got-term
}

@test "pidjail holds a TERM that arrives before the jail is up" {
  need_jail
  d=$(uniq_secs 6)
  "$REPO/claude/pidjail" sleep "$d" & p=$!
  # Once pidjail's own trap is set (its first statement after the checks),
  # the jail is not up yet: the TERM has to be held and delivered later.
  wait_for has_term_trap "$p"
  kill -TERM "$p"
  wait "$p" && rc=0 || rc=$?
  assert_equal "$rc" 143
  ! running "$d" || { pkill -fx "sleep $d"; fail "the command outlived a TERM"; }
}

@test "pidjail takes the jail down when it is killed itself" {
  need_jail
  d=$(uniq_secs 8)
  "$REPO/claude/pidjail" sleep "$d" & p=$!
  wait_for running "$d"
  kill -KILL "$p"; wait "$p" 2>/dev/null || true
  sleep 0.5
  ! running "$d" || { pkill -fx "sleep $d"; fail "the jail outlived pidjail"; }
}

@test "pidjail: the command starts with HUP, INT and QUIT not ignored" {
  need_jail
  run nohup "$REPO/claude/pidjail" awk '/^SigIgn:/ {print $2}' /proc/self/status
  # HUP is bit 0 (0x1), INT bit 1 (0x2), QUIT bit 2 (0x4); other bits come
  # from the caller (nohup ignores HUP).
  assert_equal "$(( 16#$output & 7 ))" 0
}

@test "pidjail reaps orphans, and kills what the command leaves running" {
  need_jail
  run "$REPO/claude/pidjail" bash -c '(sleep 0.2 &); sleep 0.6; ps -e -o stat= | grep -c Z'
  assert_equal "$output" 0
  d=$(uniq_secs 9)
  "$REPO/claude/pidjail" bash -c "sleep $d & disown"
  sleep 0.3
  ! running "$d" || { pkill -fx "sleep $d"; fail "a leftover survived the jail"; }
}
