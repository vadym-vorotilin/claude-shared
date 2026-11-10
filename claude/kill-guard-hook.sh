#!/bin/bash
# PreToolUse hook for Bash: block a command that would signal every process
# you own, or end your login session, before it runs.
#
# Blocked, when they appear literally in the command (any path, e.g. /bin/kill):
#   - kill with -1 (or -01, ...) among its pids: `kill -9 -1`, `kill -KILL -- -1`,
#     `kill --signal TERM -1`, `kill -9 1234 -1` (`kill -1 <pid>`, signal 1 to
#     one pid, and `kill -l -1` are allowed); os.kill(-1, ...) and
#     os.killpg(1, ...) in inline Python
#   - pkill / killall with a broad selector and no process name or pattern:
#     a user (-u, -U, --euid, --uid, --user), for pkill also run states
#     (-r), a namespace (--ns), a group (-g, -G), a session (-s), a terminal
#     (-t) or a cgroup, for killall also an SELinux context (-Z), bundled
#     or not (`pkill -fu me`, `killall -qu me`); pkill, or killall -r, with
#     a match-anything pattern (`.`, `.*`, `^`, `''`); pkill --inverse;
#     killall5
#   - loginctl terminate-/kill- user, session or seat
#   - hyprctl dispatch exit, uwsm stop, systemctl --user exit
# wherever they appear: behind sudo, timeout, env, eval, watch, xargs, inside
# bash -c '...', $(...), a loop, an if, or { ...; }.
#
# Not blocked: `kill 0` / `kill -9 0` (the caller's own process group: the
# agent's shell, not the desktop).
#
# A tripwire, not a sandbox: it reads only the command line, so a script or a
# test teardown that computes `kill -- -$pg` with pg=1 gets past it. Run such
# code under ~/.claude/bin/pidjail, where -1 reaches only the jail.
#
# The command is split into simple commands at ; & | ( ) { } ` $( and
# newlines, quotes are dropped, and every word is looked at, without real
# shell parsing: text inside a heredoc, a commit message or an echo can be
# blocked too. Reword it, or put it in a file. Needs bash and jq; without jq
# it lets everything through and says so (exit 1, a non-blocking error the
# user sees).
#
# Settings (sync.sh merges this in):
#   "hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command",
#     "command": "bash ~/.claude/kill-guard-hook.sh"}]}]}

if ! command -v jq >/dev/null 2>&1; then
  echo "kill-guard: jq not found; broad kill commands are NOT being checked" >&2
  exit 1
fi
cmd="$(jq -r '.tool_input.command // empty' 2>/dev/null)"
[ -n "$cmd" ] || exit 0

block() {
  cat >&2 <<EOF
kill-guard: blocked. "$1" would signal every process this user owns, or end the login session: the desktop, the terminals and every other Claude session on the machine.
Signal specific pids, or one process group you started and checked (> 1); with pkill/killall, name the process. Code that must send broad signals (a test of a process supervisor, say) goes in a script run under ~/.claude/bin/pidjail. If the user really wants this, ask them to run it themselves.
If this is only text that mentions such a command (a grep pattern, a commit message, a heredoc of docs), it is a false positive: put the text in a file, or for a grep pattern write the word with a bracket (p[k]ill), and run it again.
EOF
  exit 2
}

# kill <args>: block when -1 is among the pids.
check_kill() {
  local first=1 a
  case "${1:-}" in -l|-L|--list|--table) return ;; esac
  # A leading -1 is a signal number (HUP), so `kill -1 1234` passes; a -1
  # after an option, after --, or after a pid is a pid.
  # -1, -01, -001 ... all mean pid -1 to kill.
  minus1() { [[ $1 =~ ^-0*1$ ]]; }
  while [ $# -gt 0 ]; do
    a=$1; shift
    if minus1 "$a"; then
      [ $first -eq 0 ] && block "kill $a (every process)"
      first=0; continue
    fi
    case $a in
      --) for a in "$@"; do minus1 "$a" && block "kill -- $a"; done; return ;;
      -s|-n|--signal|-q|--queue) shift; first=0 ;;
      -*) first=0 ;;
      *) for a in "$@"; do minus1 "$a" && block "kill ... $a"; done; return ;;
    esac
  done
}

# A signal given as an option: -9, -KILL, -SIGUSR1, -RTMIN+2.
is_signal() {
  [[ $1 =~ ^-[0-9]+$ || $1 =~ ^-(SIG)?(HUP|INT|QUIT|ILL|TRAP|ABRT|IOT|BUS|FPE|KILL|USR1|SEGV|USR2|PIPE|ALRM|TERM|STKFLT|CHLD|CLD|CONT|STOP|TSTP|TTIN|TTOU|URG|XCPU|XFSZ|VTALRM|PROF|WINCH|IO|POLL|PWR|SYS|RTMIN(\+[0-9]+)?|RTMAX(-[0-9]+)?)$ ]]
}

# pkill / killall <args>: block a broad selector (a user, run states, a
# namespace, a group, a session, a terminal, a cgroup, an SELinux context)
# with no process name, a match-all pattern, or pkill --inverse. The two
# tools' options differ (procps-ng 4 pkill, psmisc killall), so each has its
# own tables. Short options are read as getopt reads them: `-fu me` is -f
# then -u me, and `-u1000` is -u 1000.
check_pkill() {
  local name=$1 broad= npat=0 regex=0 a l rest sbroad sval; shift
  # Short options that are broad selectors, and others that take a value.
  if [ "$name" = pkill ]; then sbroad=uUrgGst sval=PFqO; else sbroad=uZ sval=snoy; fi
  # pkill patterns are regexes; killall's names are only with -r.
  match_all() {
    [ "$name" = pkill ] || [ $regex -eq 1 ] || return 0
    case $1 in .|'.*'|'^'|''|'^.*'|'$'|'.+') block "$name $1" ;; esac
  }
  while [ $# -gt 0 ]; do
    a=$1; shift
    is_signal "$a" && continue
    case $name:$a in
      *:--) for a in "$@"; do npat=$((npat + 1)); match_all "$a"; done; break ;;
      # Long broad selectors, with the value as the next word or attached.
      *:--user|pkill:--euid|pkill:--uid|pkill:--runstates|pkill:--pgroup|pkill:--group|pkill:--session|pkill:--terminal|*:--ns|pkill:--nslist|pkill:--cgroup|killall:--context)
        broad=$a; shift ;;
      *:--user=*|pkill:--euid=*|pkill:--uid=*|pkill:--runstates=*|pkill:--pgroup=*|pkill:--group=*|pkill:--session=*|pkill:--terminal=*|*:--ns=*|pkill:--nslist=*|pkill:--cgroup=*|killall:--context=*)
        broad=$a ;;
      # Every process except the ones named.
      pkill:--inverse) block "pkill --inverse (every process but the named ones)" ;;
      # Other long options that take a value.
      pkill:--parent|pkill:--pidfile|pkill:--queue|pkill:--older|*:--signal|killall:--older-than|killall:--younger-than)
        shift ;;
      killall:--regexp) regex=1 ;;
      *:--*) ;;
      *:-?*)
        rest=${a#-}
        while [ -n "$rest" ]; do
          l=${rest:0:1}; rest=${rest:1}
          if [[ $sbroad == *"$l"* ]]; then
            broad="-$l"; [ -n "$rest" ] || shift; break
          elif [[ $sval == *"$l"* ]]; then
            [ -n "$rest" ] || shift; break
          elif [ "$name$l" = killallr ]; then
            regex=1
          fi
        done ;;
      *) npat=$((npat + 1)); match_all "$a" ;;
    esac
  done
  [ -n "$broad" ] && [ $npat -eq 0 ] && block "$name $broad (no process name)"
}

# Every word of a simple command is looked at, not only the first, so the
# check still applies behind any wrapper: sudo -u x, timeout -s KILL 5,
# bash -c '...', eval, watch, xargs, `do`, `then`, `{`, `!`.
check_words() {
  local i w base
  local -a ws=("$@")
  for ((i = 0; i < ${#ws[@]}; i++)); do
    w=${ws[i]#\\}; base=${w##*/}
    case $base in
      kill) check_kill "${ws[@]:i+1}" ;;
      pkill|killall) check_pkill "$base" "${ws[@]:i+1}" ;;
      killall5) block killall5 ;;
      loginctl) case "${ws[i+1]:-}" in terminate-user|terminate-session|terminate-seat|kill-user|kill-session|kill-seat) block "loginctl ${ws[i+1]}" ;; esac ;;
      hyprctl) [ "${ws[i+1]:-}" = dispatch ] && [ "${ws[i+2]:-}" = exit ] && block "hyprctl dispatch exit" ;;
      uwsm) [ "${ws[i+1]:-}" = stop ] && block "uwsm stop" ;;
      systemctl)
        local rest=" ${ws[*]:i+1} "
        [[ $rest == *" --user "* && $rest == *" exit "* ]] && block "systemctl --user exit" ;;
    esac
  done
}

# Inline Python.
if [[ $cmd =~ os\.kill\([[:space:]]*-1[[:space:]]*, || $cmd =~ killpg\([[:space:]]*1[[:space:]]*, ]]; then
  block "os.kill(-1) / os.killpg(1)"
fi

# Split into simple commands with parameter expansion (no GNU sed needed).
nl=$'\n'
split=${cmd//\$(/$nl}
for ch in ';' '&' '|' '(' ')' '`' '{' '}'; do split=${split//"$ch"/$nl}; done
set -f
while IFS= read -r seg; do
  # Quotes are dropped so "-1" and '-1' read as -1; spacing is all that splits words.
  seg=${seg//\"/}; seg=${seg//\'/}
  read -ra words <<< "$seg"
  [ ${#words[@]} -gt 0 ] && check_words "${words[@]}"
done <<< "$split"
exit 0
