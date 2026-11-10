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

@test "hook blocks kill with -1 among its pids" {
  blocked 'kill -9 -1'
  blocked 'kill -KILL -- -1'
  blocked 'kill -s TERM -1'
  blocked 'kill --signal KILL -1'
  blocked 'kill -1 -1'
  blocked 'kill -9 1234 -1'
  blocked 'kill -9 -01'
  blocked 'kill -- -001'
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
  blocked "bash -c 'cd /tmp; kill -9 -1'"
  blocked 'sh -c "pkill -u \"$USER\""'
  blocked "bash -c \"sh -c 'kill -9 -1'\""
  blocked "echo don't; kill -9 -1"
}

@test "hook blocks killing everything of a user, and ending the session" {
  blocked 'pkill -u me'
  blocked 'pkill -9 -U 1000'
  blocked 'pkill -u1000'
  blocked 'pkill --euid me'
  blocked 'pkill --uid=1000'
  blocked 'pkill -n -u me'
  blocked 'pkill -u me -q 5'
  blocked 'pkill -r S'
  blocked 'pkill --ns 1'
  blocked 'pkill -G 1000'
  blocked 'killall --user me'
  blocked 'killall -u me -s KILL'
  blocked 'pkill -f .'
  blocked 'pkill ".*"'
  blocked 'killall -r .'
  blocked 'pkill -u me -O 60'
  blocked 'pkill -O60 -u me'
  blocked 'pkill --older 60 -u me'
  blocked 'pkill --inverse node'
  blocked 'pkill -fu me'
  blocked 'pkill -eu 1000'
  blocked 'pkill -fu1000'
  blocked 'pkill -USR1 -u me'
  blocked 'killall -qu me'
  blocked 'killall -Z .'
  blocked 'killall -Z unconfined_t'
  blocked 'killall --context=unconfined_t'
  blocked 'killall5 -9'
  # The verb after options.
  blocked 'loginctl --no-ask-password terminate-user me'
  blocked 'loginctl kill-session 3'
  blocked 'hyprctl -i 0 dispatch exit'
  blocked 'hyprctl --batch "dispatch exit"'
  blocked 'hyprctl --batch "keyword general:gaps_in 0; dispatch exit"'
  blocked "systemctl --user kill --signal=KILL '*'"
  blocked "systemctl --user stop '*.service'"
  blocked 'systemctl --user start exit.target'
  blocked 'systemctl --user stop graphical-session.target'
  blocked 'systemctl --user --no-block stop default.target'
}

@test "hook blocks kill(-1) in inline code" {
  blocked "kill -9 ' -1'"
  blocked "kill ' -1'"
  blocked 'python3 -c "from os import kill; kill(-1, 9)"'
  blocked "node -e 'process.kill(-1)'"
  blocked "python3 -c 'import subprocess; subprocess.run([\"kill\", \"-9\", \"-1\"])'"
  blocked "python3 -c \"import subprocess; subprocess.run(['kill','-KILL','--','-1'])\""
  blocked "python3 -c \"import subprocess; subprocess.check_call(('kill','-s','KILL','-1'))\""
  blocked "python3 -c 'import subprocess; subprocess.run([\"/bin/kill\", \"-9\", \"-1\"])'"
  blocked "ruby -e 'Process.kill(\"KILL\", -1)'"
  blocked "perl -e 'kill(9, -1)'"
  blocked "perl -e 'kill \"KILL\", -1;'"
  blocked "ruby -e 'Process.kill 9, -1'"
  blocked "perl -e 'kill 9, -1'"
}

@test "hook reads pkill and killall options as the tools do, and fails closed" {
  # Signal names in any case are signals, not option bundles.
  blocked 'pkill -iO -u me'
  blocked 'pkill -SToP -u me'
  blocked 'pkill -term -u me'
  # killall reads a one-dash word as a long option.
  blocked 'killall -user me'
  blocked 'killall -signal KILL -u me'
  blocked 'killall -older-than 60 -u me'
  blocked 'killall -younger-than 1h -u me'
  blocked 'killall -context X'
  blocked 'killall -c X'
  # Unique prefixes of long options.
  blocked 'pkill --eu me'
  blocked 'pkill --ui 1000'
  blocked 'pkill --pg 1'
  blocked 'pkill --run S'
  blocked 'pkill --term pts/1'
  blocked 'pkill --sess 1'
  blocked 'pkill --inv node'
  blocked 'pkill --sig KILL -u me'
  blocked 'killall --us me'
  blocked 'killall --sig KILL -u me'
  blocked 'killall --old 60 -u me'
  blocked 'killall --reg .'
  # Selectors that need no name.
  blocked 'pkill --env HOME=/home/me'
  blocked 'pkill --env=HOME=/home/me'
  blocked 'pkill -v node'
  # A redirection or a comment is not a process name.
  blocked 'pkill -u me 2>/dev/null'
  blocked 'pkill -u me >/dev/null'
  blocked 'pkill -u me > /dev/null 2>&1'
  blocked 'pkill -u me >&2'
  blocked 'pkill -u me </dev/null'
  blocked 'pkill -u me &>log'
  blocked 'pkill -U 1000 2>/dev/null || true'
  blocked 'killall -u "$USER" -9 2>/dev/null'
  blocked 'pkill -u "$USER" # stop everything'
  blocked 'pkill 2>&- -u me'
  blocked 'pkill -u me >-log'
  blocked 'pkill -u "$USER" 2>-err'
  # A # ends the command, not the line: the line may be inside a string.
  blocked $'git commit -m "fix\n\nCloses #12" && pkill -u "$USER"'
  blocked 'echo $(date)#x; pkill -u me'
  blocked 'echo `date`#x; pkill -u me'
  blocked $'k\\\nill -9 -1'
  # killall reads a lower-case signal as options: -usr1 is -u sr1.
  blocked 'killall -usr1'
  blocked 'killall -quit'
  # pkill takes out only the first signal word, wherever it stands.
  blocked 'pkill -u me -- -9'
  blocked 'pkill -u me -O -9 60'
  blocked 'pkill -u me --signal -9 KILL'
  blocked 'pkill -9 -usr1'
  # Every child of PID 1 (systemd --user among them).
  blocked 'pkill -P 1'
  blocked 'pkill --parent=1'
  blocked 'pkill -P 4321,1'
  # A line continued with a backslash.
  blocked $'pkill \\\n  -u me'
  blocked $'kill -9 \\\n -1'
  # Quotes and backslashes inside the command name.
  blocked "'k'ill -9 -1"
  blocked 'ki""ll -9 -1'
  blocked "pk''ill -u me"
  blocked 'k\ill -9 -1'
  blocked "login''ctl terminate-user me"
  # Anything unknown, until it is spelled out.
  blocked 'pkill --no-such-option -u me node'
  blocked 'pkill -w node'
  blocked 'pkill --e node'
  blocked 'killall -k node'
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
  allowed 'pkill -r S -f "my-test-server"'
  allowed 'pkill -P 4321'
  allowed 'pkill -F run/app.pid'
  allowed 'pkill -USR1 -F run/app.pid'
  allowed 'pkill -USR2 -P 4321'
  allowed 'pkill -SIGHUP nginx'
  allowed 'pkill -RTMIN+2 -x worker'
  allowed 'pkill -fx "sleep 30"'
  allowed 'pkill -u me -O 60 node'
  allowed 'killall -Z unconfined_t node'
  allowed 'killall -qr "^node"'
  allowed 'pkill -hup -F run/app.pid'
  allowed 'pkill -usr1 -F run/app.pid'
  allowed 'pkill -term -P 4321'
  allowed 'pkill -p 4321'
  allowed 'pkill --pid=4321'
  allowed 'pkill --full --exact "sleep 30"'
  allowed 'pkill --signal KILL --parent 4321'
  allowed 'pkill --sig=TERM -f my-dev-server'
  allowed 'pkill --euid me node'
  allowed 'killall -signal TERM node'
  allowed 'killall --signal=TERM -w node'
  allowed 'killall -u me -Z unconfined_t node'
  # A quoted pattern is one word, whatever it holds.
  allowed 'pkill -f "vite --port 5173"'
  allowed "pkill -f 'node server.js --inspect -u x'"
  allowed 'pkill -f "my\"server --x"'
  allowed "pkill -f '(vite|esbuild)'"
  allowed 'pkill -f "$(cat pat)"'
  allowed 'pkill -f ${PAT}'
  allowed 'pkill -f "${PAT:-vite}" 2>/dev/null || true'
  allowed 'pkill -x node # the dev server'
  allowed 'killall -USR1 node'
  allowed 'pkill -P 4321 2>/dev/null'
  allowed 'pkill -P 10 -x node'
  allowed 'kill -9 -10'
  allowed 'killall -u me node'
  allowed 'killall -r "^node"'
  allowed 'killall node'
  allowed 'systemctl --user restart foo.service'
  allowed 'loginctl list-sessions'
  allowed 'echo skill -1; ls -1 /tmp'
  allowed 'git log --oneline -1'
  allowed 'grep -c kill notes.txt'
  allowed 'echo "${HOME}/x" 2>&1 | tee log'
  allowed 'hyprctl -j clients'
  allowed 'hyprctl dispatch exec foot'
  allowed 'loginctl show-session 3 -p Name'
  allowed "systemctl --user kill --signal=HUP 'waybar.service'"
  allowed "systemctl --user stop 'app-*.scope'"
  allowed 'python3 -c "import os; os.kill(1234, 9)"'
  allowed "python3 -c 'import subprocess; subprocess.run([\"kill\", \"-1\", \"1234\"])'"
  allowed "ruby -e 'Process.kill(\"TERM\", 1234)'"
  allowed "perl -e 'kill 9, 1234;'"
  allowed 'systemctl --user stop app-foo.service'
  allowed 'systemctl --user start graphical-session.target'
  allowed "perl -e 'kill 9, -12345'"
  allowed 'echo kill a, b, -10'
}

@test "hook reads a long command in time, and still finds a kill at its end" {
  local line
  line="$(printf 'echo "a (b) | c; d" %.0s' $(seq 1 4000))"
  SECONDS=0
  blocked "$line; kill -9 -1"
  [ "$SECONDS" -lt 5 ] || fail "took ${SECONDS}s for ${#line} bytes"
  # One long word on a line that names a tool, and long quote-dense text
  # that names none.
  line="echo skill $(head -c 200000 /dev/zero | tr '\0' a)"
  SECONDS=0
  allowed "$line"
  [ "$SECONDS" -lt 5 ] || fail "took ${SECONDS}s for a ${#line}-byte word"
  line="$(printf '"a" %.0s' $(seq 1 250000))"
  SECONDS=0
  allowed "$line"
  [ "$SECONDS" -lt 5 ] || fail "took ${SECONDS}s for ${#line} bytes naming no tool"
  # A long word that ends in a tool's name.
  line="echo $(head -c 400000 /dev/zero | tr '\0' a)kill; pkill -u me"
  SECONDS=0
  blocked "$line"
  [ "$SECONDS" -lt 5 ] || fail "took ${SECONDS}s for a long word ending in a tool name"
  # Many tool words on one line: each is not checked against all the rest.
  line="echo $(printf 'kill %.0s' $(seq 1 20000))"
  SECONDS=0
  allowed "$line"
  [ "$SECONDS" -lt 5 ] || fail "took ${SECONDS}s for ${#line} bytes of kill words"
  line="systemctl --user stop $(printf 'start stop systemctl hyprctl loginctl %.0s' $(seq 1 3000))"
  SECONDS=0
  allowed "$line"
  [ "$SECONDS" -lt 5 ] || fail "took ${SECONDS}s for ${#line} bytes of systemctl verbs"
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
