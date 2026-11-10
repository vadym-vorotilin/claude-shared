#!/usr/bin/env bats
#
# kill-guard-hook.sh (blocks a Bash command that would signal every process
# the user owns) and pidjail (runs a command where it cannot).

load 'helpers/setup'
bats_require_minimum_version 1.5.0

setup()    { common_setup; }
teardown() { common_teardown; }

HOOK() { printf '%s' "$(jq -cn --arg c "$1" '{tool_name:"Bash", tool_input:{command:$c}}')" | bash "$REPO/claude/kill-guard-hook.sh"; }

blocked() { run HOOK "$1"; [ "$status" -eq 2 ] || fail "not blocked: $1"; assert_contains "$output" "kill-guard: blocked"; }
allowed() { run HOOK "$1"; [ "$status" -eq 0 ] || fail "blocked: $1 ($output)"; }

# ----------------------------------------------------------------- hook ----

@test "hook blocks kill with -1 among its pids" {
  blocked 'kill -9 -1'
  blocked 'kill -KILL -- -1'
  blocked 'kill -s TERM -1'
  blocked 'kill --signal KILL -1'
  blocked 'kill -1 -1'
  blocked 'kill -9 1234 -1'
  blocked '/bin/kill -9 -1'
  blocked 'cd /tmp && kill -TERM -1; echo done'
  blocked 'echo $(kill -9 -1)'
  blocked 'kill -- "-1"'
  blocked 'python3 -c "import os; os.kill(-1, 9)"'
  blocked 'python3 -c "import os; os.killpg(1, 9)"'
}

@test "hook blocks kill -1 behind wrappers and inside compound commands" {
  blocked 'sudo kill -9 -1'
  blocked 'sudo -u root kill -9 -1'
  blocked 'timeout -s KILL 5 kill -9 -1'
  blocked 'env FOO=1 kill -9 -1'
  blocked "bash -c 'kill -9 -1'"
  blocked 'sh -c "kill -9 -1"'
  blocked 'eval kill -9 -1'
  blocked 'watch -n1 kill -9 -1'
  blocked 'echo 1 | xargs kill -9 -1'
  blocked 'for i in 1; do kill -9 -1; done'
  blocked 'if true; then kill -9 -1; fi'
  blocked '{ kill -9 -1; }'
  blocked '! kill -9 -1'
  blocked '\kill -9 -1'
}

@test "hook blocks killing everything of a user, and ending the session" {
  blocked 'pkill -u me'
  blocked 'pkill -9 -U 1000'
  blocked 'pkill -u1000'
  blocked 'pkill --euid me'
  blocked 'pkill --uid=1000'
  blocked 'pkill -n -u me'
  blocked 'killall --user me'
  blocked 'killall -u me -s KILL'
  blocked 'pkill -f .'
  blocked 'pkill ".*"'
  blocked 'killall -r .'
  blocked 'killall5 -9'
  blocked 'loginctl terminate-user me'
  blocked 'loginctl kill-session 3'
  blocked 'hyprctl dispatch exit'
  blocked 'uwsm stop'
  blocked 'systemctl --user exit'
}

@test "hook allows ordinary, targeted signals" {
  allowed 'kill 1234'
  allowed 'kill -9 1234 5678'
  allowed 'kill -1 1234'
  allowed 'kill -l -1'
  allowed 'kill -TERM -- -4321'
  allowed 'kill -9 -12'
  allowed 'kill -9 0'
  allowed 'kill -0 "$pid" 2>/dev/null && echo alive'
  allowed 'pkill -f "dotnet test MyApp.Tests"'
  allowed 'pkill -u "$USER" -f vite'
  allowed 'pkill -u "$USER" -n node'
  allowed 'killall -u me node'
  allowed 'killall -r "^node"'
  allowed 'killall node'
  allowed 'systemctl --user restart foo.service'
  allowed 'loginctl list-sessions'
  allowed 'echo skill -1; ls -1 /tmp'
  allowed 'git log --oneline -1'
  allowed 'grep -c kill notes.txt'
  allowed 'echo "${HOME}/x" 2>&1 | tee log'
}

@test "hook names the matched command" {
  run HOOK 'echo "x"; kill -9 -1'
  assert_contains "$output" 'blocked. "kill -1 (every process)" would'
}

@test "hook passes input without a command" {
  run bash "$REPO/claude/kill-guard-hook.sh" <<< '{"tool_name":"Bash","tool_input":{}}'
  assert_equal "$status" 0
}

@test "hook says so, as a non-blocking error, when jq is missing" {
  mkdir -p "$TEST_TMP/bin"; ln -s "$(command -v bash)" "$TEST_TMP/bin/bash"
  run env PATH="$TEST_TMP/bin" bash "$REPO/claude/kill-guard-hook.sh" <<< '{}'
  assert_equal "$status" 1
  assert_contains "$output" "NOT being checked"
}

# -------------------------------------------------------------- pidjail ----

jail_available() { unshare --user --map-current-user --pid --fork --mount-proc true 2>/dev/null; }
need_jail() {
  jail_available || skip "no unprivileged user+PID namespaces here (the refusal tests cover pidjail here)"
  command -v ps >/dev/null && command -v pgrep >/dev/null || skip "needs ps and pgrep (procps)"
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

@test "pidjail passes TERM on to the command, even straight after it starts" {
  need_jail
  "$REPO/claude/pidjail" bash -c "trap 'echo got-term > \"$TEST_TMP/t\"; exit 143' TERM; sleep 297.5 & wait" &
  p=$!
  # The sleep exists once the command's trap is set.
  until pgrep -fx "sleep 297.5" >/dev/null; do sleep 0.05; done
  kill -TERM "$p"
  wait "$p" && rc=0 || rc=$?
  assert_equal "$rc" 143
  assert_equal "$(cat "$TEST_TMP/t")" got-term
  # A TERM before the jail is up is held, not lost.
  "$REPO/claude/pidjail" sleep 297.25 & p=$!
  kill -TERM "$p"
  wait "$p" && rc=0 || rc=$?
  assert_equal "$rc" 143
}

@test "pidjail takes the jail down when it is killed itself" {
  need_jail
  "$REPO/claude/pidjail" sleep 298.5 & p=$!
  until pgrep -fx "sleep 298.5" >/dev/null; do sleep 0.05; done
  kill -KILL "$p"; wait "$p" 2>/dev/null || true
  sleep 0.5
  ! pgrep -fx "sleep 298.5" >/dev/null || { pkill -fx "sleep 298.5"; fail "the jail outlived pidjail"; }
}

@test "pidjail: the command starts with INT and QUIT not ignored" {
  need_jail
  run "$REPO/claude/pidjail" awk '/^SigIgn:/ {print $2}' /proc/self/status
  # INT is bit 1 (0x2), QUIT bit 2 (0x4); other bits come from the caller.
  assert_equal "$(( (16#$output >> 1) & 3 ))" 0
}

@test "pidjail reaps orphans, and kills what the command leaves running" {
  need_jail
  run "$REPO/claude/pidjail" bash -c '(sleep 0.2 &); sleep 0.6; ps -e -o stat= | grep -c Z'
  assert_equal "$output" 0
  "$REPO/claude/pidjail" bash -c "sleep 299.5 & disown"
  sleep 0.3
  ! pgrep -fx "sleep 299.5" >/dev/null || { pkill -fx "sleep 299.5"; fail "a leftover survived the jail"; }
}
