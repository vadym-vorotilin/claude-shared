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
#     an environment variable (--env) or the children of PID 1 (-P 1); for
#     killall a user (-u/--user) or an SELinux context (-Z/--context);
#     pkill, or killall -r, with a match-anything pattern (`.`, `.*`, `^`,
#     `''`); pkill --inverse or -v; killall5
#   - pkill / killall with an option the hook does not know (fail closed):
#     options are read as the tools read them (bundles like -fu, attached
#     values, unique prefixes of long options like --eu, killall's
#     one-dash long options like -user; pkill's first signal word wherever
#     it stands and in any case, killall's only when upper-case), and
#     anything else is blocked until it is spelled out
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
# The command is split into simple commands at ; & | ( ) { } ` $( outside
# quotes and at newlines, then into words at blanks outside quotes, with
# redirections (2>/dev/null, >&2) left out and a # ending the command, and
# every word is looked at; each quoted part is also checked as a command of
# its own. This is not real shell parsing: text inside a heredoc, a commit
# message, a comment or an echo can be blocked too. Reword it, or put it in
# a file. Needs bash and jq; without jq it lets everything through and says
# so (exit 1, a non-blocking error the user sees).
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

# is_signal <tool> <word>: the word is a signal given as an option: -9,
# -KILL, -SIGUSR1, -RTMIN+2. pkill reads names in any case (-term);
# killall only when they start upper-case (`killall -usr1` is -u sr1).
is_signal() {
  local s=${2^^}
  [ "$1" = killall ] && [[ ${2:1:1} != [A-Z0-9] ]] && return 1
  [[ $s =~ ^-[0-9]+$ || $s =~ ^-(SIG)?(HUP|INT|QUIT|ILL|TRAP|ABRT|IOT|BUS|FPE|KILL|USR1|SEGV|USR2|PIPE|ALRM|TERM|STKFLT|CHLD|CLD|CONT|STOP|TSTP|TTIN|TTOU|URG|XCPU|XFSZ|VTALRM|PROF|WINCH|IO|POLL|PWR|SYS|RTMIN(\+[0-9]+)?|RTMAX(-[0-9]+)?)$ ]]
}

# The options of each tool, from `pkill --help` (procps-ng 4.0.7, plus its
# hidden --inverse) and `killall --help` (psmisc 23.7). Kinds: f a flag,
# v takes a value, b a broad selector (takes a value), p pkill's parent
# list (broad when it holds 1: every child of PID 1, systemd --user
# included), r killall's regex switch, x blocked outright.
PKILL_LONG="require-handler:f queue:v echo:f mrelease:f count:f full:f
  pgroup:b group:b ignore-case:f newest:f oldest:f older:v pid:v parent:p
  session:b signal:v terminal:b euid:b uid:b exact:f pidfile:v logpidfile:f
  runstates:b ignore-ancestors:f shell-quote:f cgroup:b ns:b nslist:v env:b
  inverse:x help:f version:f"
PKILL_SHORT="H:f q:v e:f m:f c:f f:f g:b G:b i:f n:f o:f O:v p:v P:p s:b
  t:b u:b U:b x:f F:v L:f r:b A:f Q:f h:f V:f v:x"
KILLALL_LONG="exact:f ignore-case:f process-group:f younger-than:v
  older-than:v interactive:f list:f quiet:f regexp:r signal:v user:b
  verbose:f version:f wait:f ns:v context:b"
KILLALL_SHORT="e:f I:f g:f y:v o:v i:f l:f q:f r:r s:v u:b v:f V:f w:f n:v
  Z:b"

# kind_of <table> <option>: set K to the kind of an option given in full,
# or as a unique prefix of a long one (getopt accepts both). Empty when
# unknown or ambiguous. (A variable, not output: no subshell per option.)
kind_of() {
  local e k= hits=0
  K=
  for e in $1; do
    [ "${e%:*}" = "$2" ] && { K=${e#*:}; return; }
    [[ ${e%:*} == "$2"* ]] && { hits=$((hits + 1)); k=${e#*:}; }
  done
  [ $hits -eq 1 ] && K=$k
  return 0
}

# pkill / killall <args>: block a broad selector with no process name, a
# match-all pattern, pkill --inverse, or any option this does not know.
# Options are read as each tool reads them. pkill first takes out the first
# word that is a signal, wherever it stands (after --, or where a value
# goes), then uses getopt_long: `-fu me` is -f then -u me, `-u1000` is
# -u 1000, `--eu` is --euid. killall uses getopt_long_only, so `-user` is
# --user; a word that is not a long option is a signal, or a bundle of
# short ones.
check_pkill() {
  local name=$1 broad= npat=0 regex=0 a o k l rest take pchk long short i; shift
  if [ "$name" = pkill ]; then
    long=$PKILL_LONG short=$PKILL_SHORT
    local -a args=("$@")
    for ((i = 0; i < ${#args[@]}; i++)); do
      if is_signal pkill "${args[i]}"; then
        set -- "${args[@]:0:i}" "${args[@]:i+1}"; break
      fi
    done
  else
    long=$KILLALL_LONG short=$KILLALL_SHORT
  fi
  # A parent list that holds PID 1.
  parent1() { [[ ,$1, =~ ,0*1, ]] && broad="--parent 1"; }
  # pkill patterns are regexes; killall's names are only with -r.
  match_all() {
    [ "$name" = pkill ] || [ $regex -eq 1 ] || return 0
    case $1 in .|'.*'|'^'|''|'^.*'|'$'|'.+') block "$name $1" ;; esac
  }
  # apply <kind> <shown as> <value attached?> [<the attached value>]: sets
  # take=1 when the value is the next word, and pchk=1 when that word is a
  # parent list to check.
  apply() {
    case $1 in
      f) ;;
      r) regex=1 ;;
      v) [ "$3" = 1 ] || take=1 ;;
      p) if [ "$3" = 1 ]; then parent1 "$4"; else take=1 pchk=1; fi ;;
      b) broad=$2; [ "$3" = 1 ] || take=1 ;;
      x) block "$name $2 (every process but the named ones)" ;;
      *) block "$name $2 (an option kill-guard does not know; spell it out in full)" ;;
    esac
  }
  while [ $# -gt 0 ]; do
    a=$1; shift; take=0 pchk=0
    case $a in
      --) for a in "$@"; do npat=$((npat + 1)); match_all "$a"; done; break ;;
      --*)
        o=${a#--}; kind_of "$long" "${o%%=*}"; k=$K
        [[ $o == *=* ]] && apply "$k" "--${o%%=*}" 1 "${o#*=}" || apply "$k" "--$o" 0 ;;
      -?*)
        o=${a#-}
        # killall: a one-dash word is a long option if it names one and is
        # not a single short option (`-c` is --context). Read as a bundle of
        # short options too, and take the broader of the two: `-qu me` is
        # --quiet me, or -q -u me.
        k=
        if [ "$name" = killall ]; then
          kind_of "$short" "$o"
          if [ ${#o} -gt 1 ] || [ -z "$K" ]; then kind_of "$long" "${o%%=*}"; k=$K; fi
        fi
        if [ -n "$k" ]; then
          [[ $o == *=* ]] && apply "$k" "-${o%%=*}" 1 || apply "$k" "-$o" 0
          rest=$o
          while [ -n "$rest" ]; do
            l=${rest:0:1}; rest=${rest:1}
            kind_of "$short" "$l"
            case $K in
              f|r) ;;
              b) broad=$a; [ -n "$rest" ] || take=1; break ;;
              *) break ;;
            esac
          done
        elif [ "$name" = killall ] && is_signal killall "$a"; then
          :
        else
          rest=$o
          while [ -n "$rest" ]; do
            l=${rest:0:1}; rest=${rest:1}
            kind_of "$short" "$l"; k=$K
            case $k in
              v|b|p) [ -n "$rest" ] && apply "$k" "-$l" 1 "$rest" || apply "$k" "-$l" 0; break ;;
              *) apply "$k" "-$l" ;;
            esac
          done
        fi ;;
      *) npat=$((npat + 1)); match_all "$a" ;;
    esac
    [ $pchk -eq 1 ] && parent1 "${1:-}"
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
    # Only a word that ends in a tool's name, and only its last 12 bytes
    # (the longest name is 9): ${w##*/} costs the square of a long word's
    # length.
    case ${ws[i]} in *kill|*killall|*killall5|*loginctl|*hyprctl|*uwsm|*systemctl) ;; *) continue ;; esac
    w=${ws[i]}; [ ${#w} -gt 12 ] && w=${w: -12}
    w=${w#\\}; base=${w##*/}
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

# names_tool <text>: the text names one of the guarded tools, once quotes and
# backslashes are taken out ('k'ill, k\ill).
names_tool() {
  local p=$1
  has_name() { [[ $p == *kill* || $p == *loginctl* || $p == *hyprctl* || $p == *uwsm* || $p == *systemctl* ]]; }
  has_name && return 0
  [[ $p == *[\'\"\\]* ]] || return 1
  # ${p//...} costs the square of the length on long text; tr does not.
  if [ ${#p} -gt 4096 ]; then
    p=$(printf '%s' "$p" | tr -d "\\\\'\"")
  else
    p=${p//[\'\"\\]/}
  fi
  has_name
}

# check_line <text>: check each line that names a guarded tool. A quote left
# open at the end of a line ends there; what it held is still checked (see
# check_seg).
check_line() {
  local line
  while IFS= read -r line; do
    names_tool "$line" && check_seg "$line"
  done <<< "$1"
}

# check_seg <line>: read a line the way the shell splits it, roughly, and
# check each simple command in it.
# - Simple commands end at ; & | ( ) { } ` and $( outside quotes.
# - Words split at blanks outside quotes. Quotes are dropped, so "-1" and
#   '-1' read as -1, and "vite --port 5173" stays one word. A backslash
#   escapes the next character, and ${...} stays inside its word.
# - A redirection is not a word: `2>/dev/null`, `>&2`, `2>&1`, `</dev/null`,
#   `&>log` and a heredoc's delimiter are dropped, the fd number with them.
# - A # that starts a word ends the command. The words after it are still
#   read, as a command of their own: a line that looks like a comment may
#   be inside a multi-line string (`git commit -m "...` then `Closes #12"`).
# Each quoted part is also checked as a line of its own, for bash -c '...'
# and sh -c "...". The line is walked in chunks of CH bytes, because a
# substring costs the length of the string it is taken from.
check_seg() {
  local s=$1 n=${#1} base j c nx chunk q= w= have=0 part= skip=0 tgt=0 redir=0 br=0 re r rl=
  local -a ws=() parts=()
  word() {
    if [ $have -eq 1 ]; then
      if [ $tgt -eq 1 ]; then tgt=0; else ws+=("$w"); fi
    fi
    w= have=0
  }
  cmdend() {
    word; tgt=0 redir=0
    [ ${#ws[@]} -gt 0 ] && check_words "${ws[@]}"
    ws=()
  }
  for ((base = 0; base < n; base += $CH)); do
    chunk=${s:base:$CH + 1}
    for ((j = 0; j < $CH && base + j < n; j++)); do
      if [ $skip -eq 1 ]; then skip=0; continue; fi
      c=${chunk:j:1}; nx=${chunk:j+1:1}
      if [ -n "$q" ]; then
        # A run of characters that end nothing is taken in one match.
        if [ "$q" = "'" ]; then re=$re_sq; else re=$re_dq; fi
        if [[ ${chunk:j:$CH-j} =~ $re ]]; then
          r=${BASH_REMATCH[0]}; w+=$r; part+=$r; j=$((j + ${#r} - 1)); continue
        fi
        if [ "$c" = "$q" ]; then
          q=; parts+=("$part"); part=
        elif [ "$q" = '"' ] && [ "$c" = '\' ] && [[ $nx == [\"\\\$\`] ]]; then
          skip=1; w+=$nx; part+=$nx
        else
          w+=$c; part+=$c
        fi
        continue
      fi
      if [ $br -eq 1 ]; then
        w+=$c; [ "$c" = '}' ] && br=0; continue
      fi
      if [ $redir -eq 1 ]; then
        # `2>&-` closes the fd: it has no target word. (`>-log` writes to
        # the file "-log".)
        [ "$c" = - ] && [ $have -eq 0 ] && [ "$rl" = '&' ] && { tgt=0 redir=0; continue; }
        case $c in '<'|'>'|'&'|'|') [ $have -eq 0 ] && { rl=$c; continue; } ;; esac
        redir=0
      fi
      if [[ ${chunk:j:$CH-j} =~ $re_pl ]]; then
        r=${BASH_REMATCH[0]}; w+=$r; have=1; j=$((j + ${#r} - 1)); continue
      fi
      case $c in
        \'|\") q=$c; have=1 ;;
        \\) skip=1; w+=$nx; have=1 ;;
        [[:space:]]) word ;;
        '<'|'>')
          [ $have -eq 1 ] && [[ $w =~ ^[0-9]+$ ]] && w= have=0
          word; tgt=1 redir=1 rl=$c ;;
        '&')
          if [ "$nx" = '>' ]; then word; tgt=1 redir=1 rl=$c; else cmdend; fi ;;
        ';'|'|'|'('|')'|'{'|'}'|'`') cmdend ;;
        '$')
          case $nx in
            '(') cmdend; skip=1 ;;
            '{') w+='${'; have=1 br=1 skip=1 ;;
            *) w+=$c; have=1 ;;
          esac ;;
        '#') if [ $have -eq 0 ]; then cmdend; else w+=$c; fi ;;
        *) w+=$c; have=1 ;;
      esac
    done
  done
  [ -n "$q" ] && parts+=("$part")
  cmdend
  # A part holds no newline (lines are split first), so it goes straight to
  # check_seg, and only when it names a tool.
  for part in "${parts[@]}"; do names_tool "$part" && check_seg "$part"; done
  return 0
}

# Byte-wise from here: string expansions are many times slower in UTF-8.
export LC_ALL=C
# A backslash-newline continues the line (k\<newline>ill is kill).
cmd=${cmd//$'\\\n'/}
# Nothing to look at unless the command names one of the tools at all.
names_tool "$cmd" || exit 0

CH=256
# Runs of characters that end nothing: inside '...', inside "...", and
# outside quotes. (Inside brackets a backslash is a literal character.)
re_sq="^[^']+"
re_dq='^[^"\]+'
re_pl='^[^[:space:]'\''"\<>&;|(){}`$#]+'
set -f
check_line "$cmd"
exit 0
