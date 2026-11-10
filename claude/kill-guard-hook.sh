#!/bin/bash
# PreToolUse hook for Bash: block a command that would signal every process
# you own, or end your login session, before it runs.
#
# Blocked, when they appear literally in the command (any path, e.g. /bin/kill):
#   - kill with -1 among its pids: `kill -9 -1`, `kill -KILL -- -1`,
#     `kill --signal TERM -1`, `kill -9 1234 -1` (`kill -1 <pid>`, signal 1 to
#     one pid, and `kill -l -1` are allowed); os.kill(-1, ...) and
#     os.killpg(1, ...) in inline Python
#   - pkill / killall filtered by user (-u, -U, --euid, --uid, --user) with no
#     process name or pattern, so every process of that user;
#     pkill with a match-anything pattern (`.`, `.*`, `^`, `''`); killall5
#   - loginctl terminate-/kill- user, session or seat
#   - hyprctl dispatch exit, uwsm stop, systemctl --user exit
#
# A tripwire, not a sandbox: it reads only the command line, so a script or a
# test teardown that computes `kill -- -$pg` with pg=1 gets past it. Run such
# code under ~/.claude/bin/pidjail, where -1 reaches only the jail.
#
# The command is split into simple commands at ; & | ( ) ` and newlines and
# each is read as words, without real shell parsing: text inside a heredoc, a
# commit message or an echo can still be blocked. Reword it, or put it in a
# file. Needs jq; without it the hook lets everything through and says so on
# stderr.
#
# Settings (sync.sh merges this in):
#   "hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command",
#     "command": "bash ~/.claude/kill-guard-hook.sh"}]}]}

if ! command -v jq >/dev/null 2>&1; then
  echo "kill-guard: jq not found; broad kill commands are NOT being checked" >&2
  exit 0
fi
cmd="$(jq -r '.tool_input.command // empty' 2>/dev/null)"
[ -n "$cmd" ] || exit 0

block() {
  cat >&2 <<EOF
kill-guard: blocked. "$1" would signal every process this user owns, or end the login session: the desktop, the terminals and every other Claude session on the machine.
Signal specific pids, or one process group you started and checked (> 1); with pkill/killall, name the process. Code that must send broad signals (a test of a process supervisor, say) goes in a script run under ~/.claude/bin/pidjail. If the user really wants this, ask them to run it themselves.
EOF
  exit 2
}

# kill <args>: block when -1 is among the pids.
check_kill() {
  local first=1 a
  case "${1:-}" in -l|-L|--list|--table) return ;; esac
  # A leading -1 is a signal number (HUP), so `kill -1 1234` passes; a -1
  # after an option, after --, or after a pid is a pid.
  while [ $# -gt 0 ]; do
    a=$1; shift
    case $a in
      --) for a in "$@"; do [ "$a" = -1 ] && block "kill -- -1"; done; return ;;
      -s|-n|--signal|-q|--queue) shift; first=0 ;;
      -1) [ $first -eq 0 ] && block "kill -1 (every process)"; first=0 ;;
      -*) first=0 ;;
      *) for a in "$@"; do [ "$a" = -1 ] && block "kill ... -1"; done; return ;;
    esac
  done
}

# pkill / killall <args>: block a user filter with no name, or a match-all pattern.
check_pkill() {
  local name=$1 user=0 npat=0 a; shift
  while [ $# -gt 0 ]; do
    a=$1; shift
    case $a in
      -u|-U|--euid|--uid|--user) user=1; shift ;;
      -u*|-U*|--euid=*|--uid=*|--user=*) user=1 ;;
      -g|-G|-P|-s|-t|-F|-o|-y|-n|-Z|--signal|--group|--pgroup|--parent|--session|--terminal|--pidfile|--ns|--nslist|--older-than|--younger-than|--context) shift ;;
      --) for a in "$@"; do npat=$((npat + 1)); [ "$name" = pkill ] && case $a in .|'.*'|'^'|''|'^.*'|'$') block "pkill $a" ;; esac; done; break ;;
      -*) ;;
      *) npat=$((npat + 1))
         [ "$name" = pkill ] && case $a in .|'.*'|'^'|'^.*'|'$') block "pkill $a" ;; esac ;;
    esac
  done
  [ $user -eq 1 ] && [ $npat -eq 0 ] && block "$name -u (no process name)"
}

check_words() {
  local i w base
  local -a ws=("$@")
  for ((i = 0; i < ${#ws[@]}; i++)); do
    w=${ws[i]}; base=${w##*/}
    case $base in
      kill) check_kill "${ws[@]:i+1}"; return ;;
      pkill|killall) check_pkill "$base" "${ws[@]:i+1}"; return ;;
      killall5) block killall5 ;;
      loginctl) case "${ws[i+1]:-}" in terminate-user|terminate-session|terminate-seat|kill-user|kill-session|kill-seat) block "loginctl ${ws[i+1]}" ;; esac; return ;;
      hyprctl) [ "${ws[i+1]:-}" = dispatch ] && [ "${ws[i+2]:-}" = exit ] && block "hyprctl dispatch exit"; return ;;
      uwsm) [ "${ws[i+1]:-}" = stop ] && block "uwsm stop"; return ;;
      systemctl)
        local rest=" ${ws[*]:i+1} "
        [[ $rest == *" --user "* && $rest == *" exit "* ]] && block "systemctl --user exit"; return ;;
      # Wrappers that run the next word as the command.
      sudo|command|exec|nohup|nice|ionice|setsid|timeout|env|xargs|builtin|time) ;;
      *=*) ;;   # leading VAR=value
      -*|[0-9]*) ;;  # a wrapper's options or arguments (timeout 5, nice -n 5)
      *) return ;;
    esac
  done
}

# Inline Python.
if printf '%s' "$cmd" | grep -qE 'os\.kill\([[:space:]]*-1[[:space:]]*,|killpg\([[:space:]]*1[[:space:]]*,'; then
  block "os.kill(-1) / os.killpg(1)"
fi

set -f
while IFS= read -r seg; do
  # Quotes are dropped so "-1" and '-1' read as -1; spacing is all that splits words.
  seg=${seg//\"/}; seg=${seg//\'/}
  read -ra words <<< "$seg"
  [ ${#words[@]} -gt 0 ] && check_words "${words[@]}"
done < <(printf '%s\n' "$cmd" | sed -e 's/\$(/\n/g' -e 's/[;&|()`]/\n/g')
exit 0
