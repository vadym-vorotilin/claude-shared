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
#     for pkill a user (-u/--euid, -U/--uid), run states (-r), a group (-g,
#     -G), a session (-s), a terminal (-t), a namespace (--ns), a cgroup or
#     an environment variable (--env); for killall a user (-u/--user) or an
#     SELinux context (-Z/--context); pkill, or killall -r, with a
#     match-anything pattern (`.`, `.*`, `^`, `''`); pkill --inverse or -v;
#     killall5
#   - pkill / killall with an option the hook does not know (fail closed):
#     options are read as the tools read them (bundles like -fu, attached
#     values, unique prefixes of long options like --eu, killall's
#     one-dash long options like -user, signal names in any case like
#     -stop), and anything else is blocked until it is spelled out
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
# newlines, then into words at blanks outside quotes, and every word is
# looked at; each quoted part is also checked as a command of its own. This
# is not real shell parsing: text inside a heredoc, a commit message or an
# echo can be blocked too. Reword it, or put it in a file. Needs bash and jq; without jq
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

# A signal given as an option, in any case: -9, -KILL, -term, -SIGUSR1,
# -RTMIN+2. pkill and killall both read signal names case-insensitively.
is_signal() {
  local s=${1^^}
  [[ $s =~ ^-[0-9]+$ || $s =~ ^-(SIG)?(HUP|INT|QUIT|ILL|TRAP|ABRT|IOT|BUS|FPE|KILL|USR1|SEGV|USR2|PIPE|ALRM|TERM|STKFLT|CHLD|CLD|CONT|STOP|TSTP|TTIN|TTOU|URG|XCPU|XFSZ|VTALRM|PROF|WINCH|IO|POLL|PWR|SYS|RTMIN(\+[0-9]+)?|RTMAX(-[0-9]+)?)$ ]]
}

# The options of each tool, from `pkill --help` (procps-ng 4.0.7, plus its
# hidden --inverse) and `killall --help` (psmisc 23.7). Kinds: f a flag,
# v takes a value, b a broad selector (takes a value), r killall's regex
# switch, x blocked outright.
PKILL_LONG="require-handler:f queue:v echo:f mrelease:f count:f full:f
  pgroup:b group:b ignore-case:f newest:f oldest:f older:v pid:v parent:v
  session:b signal:v terminal:b euid:b uid:b exact:f pidfile:v logpidfile:f
  runstates:b ignore-ancestors:f shell-quote:f cgroup:b ns:b nslist:v env:b
  inverse:x help:f version:f"
PKILL_SHORT="H:f q:v e:f m:f c:f f:f g:b G:b i:f n:f o:f O:v p:v P:v s:b
  t:b u:b U:b x:f F:v L:f r:b A:f Q:f h:f V:f v:x"
KILLALL_LONG="exact:f ignore-case:f process-group:f younger-than:v
  older-than:v interactive:f list:f quiet:f regexp:r signal:v user:b
  verbose:f version:f wait:f ns:v context:b"
KILLALL_SHORT="e:f I:f g:f y:v o:v i:f l:f q:f r:r s:v u:b v:f V:f w:f n:v
  Z:b"

# kind_of <table> <option>: the kind of an option given in full, or as a
# unique prefix of a long one (getopt accepts both). Empty when unknown or
# ambiguous.
kind_of() {
  local e k= hits=0
  for e in $1; do
    [ "${e%:*}" = "$2" ] && { echo "${e#*:}"; return; }
    [[ ${e%:*} == "$2"* ]] && { hits=$((hits + 1)); k=${e#*:}; }
  done
  [ $hits -eq 1 ] && echo "$k"
}

# pkill / killall <args>: block a broad selector with no process name, a
# match-all pattern, pkill --inverse, or any option this does not know.
# Options are read as each tool reads them: pkill uses getopt_long (`-fu me`
# is -f then -u me; `-u1000` is -u 1000; `--eu` is --euid) after taking out
# any word that is a signal; killall uses getopt_long_only, so `-user` is
# --user, and a word that is not a long option is a bundle of short ones.
check_pkill() {
  local name=$1 broad= npat=0 regex=0 a o k l rest take long short; shift
  if [ "$name" = pkill ]; then long=$PKILL_LONG short=$PKILL_SHORT
  else long=$KILLALL_LONG short=$KILLALL_SHORT; fi
  # pkill patterns are regexes; killall's names are only with -r.
  match_all() {
    [ "$name" = pkill ] || [ $regex -eq 1 ] || return 0
    case $1 in .|'.*'|'^'|''|'^.*'|'$'|'.+') block "$name $1" ;; esac
  }
  # apply <kind> <shown as> <value attached?>: sets take=1 when the value is
  # the next word.
  apply() {
    case $1 in
      f) ;;
      r) regex=1 ;;
      v) [ "$3" = 1 ] || take=1 ;;
      b) broad=$2; [ "$3" = 1 ] || take=1 ;;
      x) block "$name $2 (every process but the named ones)" ;;
      *) block "$name $2 (an option kill-guard does not know; spell it out in full)" ;;
    esac
  }
  while [ $# -gt 0 ]; do
    a=$1; shift; take=0
    case $a in
      --) for a in "$@"; do npat=$((npat + 1)); match_all "$a"; done; break ;;
      --*)
        o=${a#--}; k=$(kind_of "$long" "${o%%=*}")
        [[ $o == *=* ]] && apply "$k" "--${o%%=*}" 1 || apply "$k" "--$o" 0 ;;
      -?*)
        o=${a#-}
        # killall: a one-dash word is a long option if it names one and is
        # not a single short option (`-c` is --context). Read as a bundle of
        # short options too, and take the broader of the two: `-qu me` is
        # --quiet me, or -q -u me.
        if [ "$name" = killall ] && { [ ${#o} -gt 1 ] || [ -z "$(kind_of "$short" "$o")" ]; } &&
           k=$(kind_of "$long" "${o%%=*}") && [ -n "$k" ]; then
          [[ $o == *=* ]] && apply "$k" "-${o%%=*}" 1 || apply "$k" "-$o" 0
          rest=$o
          while [ -n "$rest" ]; do
            l=${rest:0:1}; rest=${rest:1}
            case $(kind_of "$short" "$l") in
              f|r) ;;
              b) broad=$a; [ -n "$rest" ] || take=1; break ;;
              *) break ;;
            esac
          done
        elif is_signal "$a"; then
          :
        else
          rest=$o
          while [ -n "$rest" ]; do
            l=${rest:0:1}; rest=${rest:1}
            k=$(kind_of "$short" "$l")
            case $k in
              v|b) [ -n "$rest" ] && apply "$k" "-$l" 1 || apply "$k" "-$l" 0; break ;;
              *) apply "$k" "-$l" ;;
            esac
          done
        fi ;;
      *) npat=$((npat + 1)); match_all "$a" ;;
    esac
    [ $take -eq 1 ] && shift
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

# check_line <text>: split into simple commands with parameter expansion (no
# GNU sed needed), and check each.
check_line() {
  local split seg ch
  split=${1//\$(/$nl}
  for ch in ';' '&' '|' '(' ')' '`' '{' '}'; do split=${split//"$ch"/$nl}; done
  while IFS= read -r seg; do check_seg "$seg"; done <<< "$split"
}

# check_seg <text>: split a simple command into words at blanks outside
# quotes, dropping the quotes ("-1" and '-1' read as -1, and
# "vite --port 5173" stays one word); a backslash escapes the next
# character. Then check the words, and check each quoted part as a command
# line of its own, for bash -c '...' and sh -c "...". An unclosed quote ends
# at the end of the segment.
check_seg() {
  local s=$1 i c q= w= have=0 part= inq=0
  local -a ws=() parts=()
  for ((i = 0; i < ${#s}; i++)); do
    c=${s:i:1}
    if [ -n "$q" ]; then
      if [ "$c" = "$q" ]; then
        q=; parts+=("$part"); part=
      elif [ "$q" = '"' ] && [ "$c" = '\' ] && [[ ${s:i+1:1} == [\"\\\$\`] ]]; then
        i=$((i + 1)); w+=${s:i:1}; part+=${s:i:1}
      else
        w+=$c; part+=$c
      fi
      continue
    fi
    case $c in
      \'|\") q=$c; have=1 ;;
      \\) i=$((i + 1)); w+=${s:i:1}; have=1 ;;
      [[:space:]]) [ $have -eq 1 ] && ws+=("$w"); w=; have=0 ;;
      *) w+=$c; have=1 ;;
    esac
  done
  [ -n "$q" ] && parts+=("$part")
  [ $have -eq 1 ] && ws+=("$w")
  [ ${#ws[@]} -gt 0 ] && check_words "${ws[@]}"
  for part in "${parts[@]}"; do check_line "$part"; done
}

# Nothing to look at unless the command names one of the tools at all.
[[ $cmd == *kill* || $cmd == *loginctl* || $cmd == *hyprctl* || $cmd == *uwsm* || $cmd == *systemctl* ]] || exit 0

# Byte-wise, so ${s:i:1} is cheap on a long command.
export LC_ALL=C
nl=$'\n'
set -f
check_line "$cmd"
exit 0
