#!/bin/bash
# PreToolUse hook for Bash: block a command that would signal every process
# you own, or end your login session, before it runs.
#
# Blocked, when they appear literally in the command:
#   - kill with -1 as its target: `kill -9 -1`, `kill -KILL -- -1`, `kill -s TERM -1`
#     (`kill -1 <pid>`, signal 1 to one pid, is allowed), and os.kill(-1, ...)
#     or os.killpg(1, ...) in inline Python
#   - pkill / killall by user (-u, -U, --user), and killall5
#   - loginctl terminate-/kill- user, session or seat
#   - hyprctl dispatch exit, uwsm stop, systemctl --user exit
#
# A tripwire, not a sandbox: it reads only the command line, so a script or a
# test teardown that computes `kill -- -$pg` with pg=1 gets past it. Run such
# code under ~/.claude/bin/pidjail, where -1 reaches only the jail.
#
# A false positive (the text inside a heredoc, a commit message, a grep
# pattern) is blocked too; reword it, or put it in a file. Needs jq; without
# it the hook lets everything through.
#
# Settings (sync.sh merges this in):
#   "hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command",
#     "command": "bash ~/.claude/kill-guard-hook.sh"}]}]}

command -v jq >/dev/null 2>&1 || exit 0
cmd="$(jq -r '.tool_input.command // empty' 2>/dev/null)"
[ -n "$cmd" ] || exit 0

# Word start: line start or a character that cannot be part of a name.
W='(^|[^[:alnum:]_./-])'
patterns=(
  "${W}kill([[:space:]]+(-[[:alnum:]]+|-[sn][[:space:]]+[[:alnum:]]+|--))+[[:space:]]+[\"']?-1[\"']?([^[:alnum:]]|$)"
  "os\.kill\([[:space:]]*-1[[:space:]]*,"
  "killpg\([[:space:]]*1[[:space:]]*,"
  "${W}(pkill|killall)([[:space:]][^;&|]*)?[[:space:]](-u|-U|--user)([[:space:]=]|$)"
  "${W}killall5([^[:alnum:]]|$)"
  "${W}loginctl[[:space:]]+(terminate|kill)-(user|session|seat)"
  "${W}hyprctl[[:space:]]+dispatch[[:space:]]+exit([^[:alnum:]]|$)"
  "${W}uwsm[[:space:]]+stop([^[:alnum:]]|$)"
  "${W}systemctl[[:space:]]+--user[[:space:]]+exit([^[:alnum:]]|$)"
)

for p in "${patterns[@]}"; do
  if hit="$(printf '%s\n' "$cmd" | grep -m1 -oE -- "$p")"; then
    hit="$(printf '%s' "$hit" | sed -E 's/^[^[:alnum:]]//; s/[^[:alnum:]]$//')"
    cat >&2 <<EOF
kill-guard: blocked. "$hit" would signal every process this user owns, or end the login session: the desktop, the terminals and every other Claude session on the machine.
Signal specific pids, or one process group you started and checked (> 1). Code that must send broad signals (a test of a process supervisor, say) goes in a script run under ~/.claude/bin/pidjail. If the user really wants this, ask them to run it themselves.
EOF
    exit 2
  fi
done
exit 0
