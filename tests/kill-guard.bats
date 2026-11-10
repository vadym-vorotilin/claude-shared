#!/usr/bin/env bats
#
# kill-guard-hook.sh (blocks a Bash command that would signal every process
# the user owns) and pidjail (runs a command where it cannot).

load 'helpers/setup'

setup()    { common_setup; }
teardown() { common_teardown; }

HOOK() { printf '%s' "$(jq -cn --arg c "$1" '{tool_name:"Bash", tool_input:{command:$c}}')" | bash "$REPO/claude/kill-guard-hook.sh"; }

blocked() { run HOOK "$1"; [ "$status" -eq 2 ] || fail "not blocked: $1"; assert_contains "$output" "kill-guard: blocked"; }
allowed() { run HOOK "$1"; [ "$status" -eq 0 ] || fail "blocked: $1 ($output)"; }

# ----------------------------------------------------------------- hook ----

@test "hook blocks kill with -1 as its target" {
  blocked 'kill -9 -1'
  blocked 'kill -KILL -- -1'
  blocked 'kill -s TERM -1'
  blocked 'cd /tmp && kill -TERM -1; echo done'
  blocked 'kill -- "-1"'
  blocked 'python3 -c "import os; os.kill(-1, 9)"'
  blocked 'python3 -c "import os; os.killpg(1, 9)"'
}

@test "hook names the matched command without the character around it" {
  run HOOK 'echo "x kill -9 -1"'
  assert_contains "$output" 'blocked. "kill -9 -1" would'
}

@test "hook blocks killing by user and ending the session" {
  blocked 'pkill -u me'
  blocked 'pkill -9 -U 1000'
  blocked 'killall --user me'
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
  allowed 'kill -TERM -- -4321'
  allowed 'kill -9 -12'
  allowed 'kill -0 "$pid" 2>/dev/null && echo alive'
  allowed 'pkill -f "dotnet test MyApp.Tests"'
  allowed 'killall node'
  allowed 'systemctl --user restart foo.service'
  allowed 'loginctl list-sessions'
  allowed 'echo skill -1; ls -1 /tmp'
  allowed 'git log --oneline -1'
}

@test "hook passes input without a command" {
  run bash "$REPO/claude/kill-guard-hook.sh" <<< '{"tool_name":"Bash","tool_input":{}}'
  assert_equal "$status" 0
}

# -------------------------------------------------------------- pidjail ----

jail_available() { unshare --user --map-current-user --pid --fork --mount-proc true 2>/dev/null; }

@test "pidjail refuses, and runs nothing, where namespaces are unavailable" {
  jail_available && skip "namespaces available here; covered by the tests below"
  run "$REPO/claude/pidjail" touch "$TEST_TMP/ran"
  assert_equal "$status" 125
  assert_contains "$output" "not running the command unjailed"
  [ ! -e "$TEST_TMP/ran" ] || fail "the command ran unjailed"
}

@test "pidjail passes stdin and the exit status through" {
  jail_available || skip "no unprivileged user+PID namespaces here (the refusal test covers this)"
  run "$REPO/claude/pidjail" sh -c 'exit 7'
  assert_equal "$status" 7
  assert_equal "$(echo hi | "$REPO/claude/pidjail" cat)" hi
}

@test "pidjail: kill -KILL -1 inside reaches only the jail" {
  jail_available || skip "no unprivileged user+PID namespaces here (the refusal test covers this)"
  sleep 300 & outside=$!
  # Two checks before the kill, so a broken jail skips it rather than killing
  # the machine: PID 1 is not the host's init, and only a few processes show.
  run "$REPO/claude/pidjail" bash -c '
    [ "$(cat /proc/1/comm)" = bash ] && [ "$(ps -e --no-headers | wc -l)" -lt 10 ] || exit 99
    sleep 300 & inner=$!
    kill -KILL -- -1; sleep 0.3
    kill -0 "$inner" 2>/dev/null && exit 1; exit 0'
  kill -0 "$outside" && alive=1 || alive=0
  kill "$outside" 2>/dev/null || true
  assert_equal "$status" 0
  assert_equal "$alive" 1
}

@test "pidjail kills what the command leaves running" {
  jail_available || skip "no unprivileged user+PID namespaces here (the refusal test covers this)"
  "$REPO/claude/pidjail" bash -c "sleep 299.5 & disown"
  sleep 0.3
  ! pgrep -fx "sleep 299.5" >/dev/null || { pkill -fx "sleep 299.5"; fail "a leftover survived the jail"; }
}
