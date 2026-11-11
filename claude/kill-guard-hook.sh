#!/bin/bash
# PreToolUse hook for Bash: a tripwire for the few commands that signal every
# process you own or end the login session. It blocks, anywhere on the line
# (behind sudo or xargs, inside bash -c '...', after ; && | or $( ):
#   - kill with a pid of -1:  kill -9 -1, kill -KILL -- -1, kill -s TERM -1
#     (`kill -1 1234`, signal 1 to one pid, and `kill 0` pass);
#   - pkill / killall with a user and no process name:  pkill -u me,
#     killall -u me  (`pkill -u me node` passes);
#   - loginctl terminate-/kill- user, session or seat.
#
# It catches mistakes, not evasion: it reads only the text of the command, so
# a script that computes the pid at run time gets past it. Code that sends
# signals it reads or computes runs under ~/.claude/bin/pidjail instead.
# Text that only mentions these commands (a commit message, a heredoc) can be
# blocked too: put it in a file. Needs jq; without it, it lets everything
# through and says so (exit 1, a non-blocking error the user sees).
#
# Settings (sync.sh merges this in):
#   "hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command",
#     "command": "bash ~/.claude/kill-guard-hook.sh"}]}]}

if ! command -v jq >/dev/null 2>&1; then
  echo "kill-guard: jq not found; broad kill commands are NOT being checked" >&2
  exit 1
fi
cmd="$(jq -r '.tool_input.command // empty' 2>/dev/null)"
[[ $cmd == *kill* || $cmd == *loginctl* ]] || exit 0

block() {
  cat >&2 <<EOF
kill-guard: blocked. "$1" would signal every process this user owns, or end the login session: the desktop, the terminals and every other Claude session on the machine.
Signal specific pids, or one process group you started and checked (> 1); with pkill/killall, name the process. Code that must send broad signals goes in a script run under ~/.claude/bin/pidjail. If the user really wants this, ask them to run it themselves.
If this is only text that mentions such a command (a commit message, a heredoc), put the text in a file and run it again.
EOF
  exit 2
}

# Quotes become blanks, so a quoted command (bash -c '...') is read too; the
# separators become line breaks, one simple command per line. Each tool's
# arguments are read up to 15 words on, so a long line stays linear.
# (tr, not ${s//…}: bash's substitution is quadratic in the matches.)
s="$(printf '%s' "$cmd" | tr "'\";&|(){}\`" '  \n\n\n\n\n\n\n\n')"

while IFS= read -r line; do
  read -ra ws <<<"$line"; n=${#ws[@]}
  for ((i = 0; i < n; i++)); do
    w="${ws[i]#\\}"
    case "${w##*/}" in
      kill)
        # A first -1 is the signal HUP; a -1 after it is the pid -1.
        case "${ws[i+1]:-}" in -l|-L|--list|--table) continue ;; esac
        for ((j = i + 2; j < n && j < i + 16; j++)); do
          [[ ${ws[j]} == -*1* && ${ws[j]%%[<>]*} =~ ^-0*1$ ]] && block "kill ... -1"
        done ;;
      pkill|killall)
        user=0 name=0
        for ((j = i + 1; j < n && j < i + 16; j++)); do
          a="${ws[j]}"
          case "$a" in
            *[\<\>]) j=$((j + 1)) ;;                       # a redirection: > file
            *[\<\>]*) ;;                                   # >file
            -s|--signal) j=$((j + 1)) ;;                   # takes a value
            -[uU]|-[A-Za-z]*[uU]|--euid|--uid|--user) user=1; j=$((j + 1)) ;;
            -u?*|--euid=*|--uid=*|--user=*) user=1 ;;
            -*) ;;
            *) name=1 ;;
          esac
        done
        [ $user -eq 1 ] && [ $name -eq 0 ] && block "${w##*/} -u <user>" ;;
      loginctl)
        for ((j = i + 1; j < n && j < i + 16; j++)); do
          [[ ${ws[j]} == *-* && ${ws[j]} =~ ^(terminate|kill)-(user|session|seat)$ ]] && block "loginctl ${ws[j]}"
        done ;;
    esac
  done
done <<<"$s"
exit 0
