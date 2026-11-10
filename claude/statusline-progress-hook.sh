#!/bin/bash
# PostToolUse hook for Bash: show a background command's progress in the
# status line, read from the output file Claude Code already writes for it.
#
# It starts `statusline-progress.sh follow` detached and returns at once. The
# command, its permissions and its output are untouched: nothing is rewritten,
# and nothing is printed back to the session. A foreground command is left
# alone; it is not long-running from the status line's point of view.
#
# Assumes Claude Code's layout for background output, which is not a
# documented interface: <tmp>/claude-<uid>/<project>/<session>/tasks/<id>.output,
# <project> being the name of the transcript's directory, and a closing
# "[exited with code N]" or "[killed]" line. If the file is not there, the
# follower gives up after 15 seconds and the row reads ended at 0%.
#
# A command that itself prints a closing line ("\n[exited with code 0]\n",
# say by catting another task's output) and then stays quiet for a second
# reads done while it still runs: the file alone cannot tell the two apart.
#
# Settings (sync.sh merges this in):
#   "hooks": {"PostToolUse": [{"matcher": "Bash", "hooks": [{"type": "command",
#     "command": "bash ~/.claude/statusline-progress-hook.sh"}]}]}

here="$(dirname "${BASH_SOURCE[0]}")"
command -v jq >/dev/null 2>&1 || exit 0

row=$(jq -r '
  select(.tool_input.run_in_background == true)
  | [ (.tool_response.backgroundTaskId // ""), (.session_id // ""),
      (.transcript_path // ""),
      ((.tool_input.description // "") | if . == "" then "background" else . end) ]
  | map(tostring | gsub("[\n\r]"; " "))[]' 2>/dev/null) || exit 0
[ -n "$row" ] || exit 0
# One field per line, read as is: @tsv would escape a backslash in the name.
{ IFS= read -r id; IFS= read -r sid; IFS= read -r transcript; IFS= read -r name; } <<<"$row"

case "$id" in ''|*[!A-Za-z0-9]*) exit 0 ;; esac
case "$sid" in ''|*[!A-Za-z0-9-]*) exit 0 ;; esac
project=$(basename "$(dirname "$transcript")")
case "$project" in ''|.|..|*/*) exit 0 ;; esac

file="/tmp/claude-$(id -u)/$project/$sid/tasks/$id.output"

# The session's own process is this hook's parent; the follower stops with it.
CLAUDE_CODE_SESSION_ID="$sid" nohup bash "$here/statusline-progress.sh" \
  follow "$name" "bg-$id" "$file" "$PPID" </dev/null >/dev/null 2>&1 &
exit 0
