#!/usr/bin/env bash
# handoff-checkpoint.sh — Claude Code Stop hook.
#
# After every turn, snapshot deterministic git state + the last user/assistant
# messages into a gitignored autosave next to the repo's handoff doc, so a
# session cut off before a manual wrap-up can still be resumed.
#
# Pure shell + jq. No LLM, no token cost. Never blocks, never prints to stdout,
# always exits 0 — a failed checkpoint must never break the session.
set -u

HANDOFF_DOC="${HANDOFF_DOC:-docs/HANDOFF.md}"

input="$(cat)"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
transcript="$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)"
[ -n "$cwd" ] || exit 0

root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)" || exit 0
[ -n "$root" ] || exit 0

autosave="$root/${HANDOFF_DOC%.md}.autosave.md"
mkdir -p "$(dirname "$autosave")" 2>/dev/null || exit 0

branch="$(git -C "$root" rev-parse --abbrev-ref HEAD 2>/dev/null)"
head="$(git -C "$root" rev-parse --short HEAD 2>/dev/null)"
tracking="$(git -C "$root" status -sb 2>/dev/null | head -1)"
dirty="$(git -C "$root" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
# Staged + unstaged, relative to HEAD (plain `diff --stat` omits staged changes,
# so a fully-staged tree would show an empty diffstat next to "Dirty files: N").
# Bounded so a large working tree can't bloat the autosave.
diffstat="$(git -C "$root" diff --stat --stat-count=40 HEAD 2>/dev/null)"

# Extract last user / assistant text from the transcript tail (fast on long logs).
# Parse per line (jq -R + fromjson?) so a single malformed line degrades to being
# skipped rather than failing the whole slurp and zeroing out both messages.
extract_last() { # role
  tail -n 400 "$transcript" 2>/dev/null \
    | jq -R --arg role "$1" '
        fromjson?
        | select(.message.role? == $role)
        | (.message.content
            | if type == "array" then map(.text? // empty) | join("")
              else (. // "") end) // ""' 2>/dev/null \
    | tail -n 1 \
    | jq -r . 2>/dev/null
}
last_user=""; last_assistant=""
if [ -n "$transcript" ] && [ -f "$transcript" ]; then
  last_user="$(extract_last user)"
  last_assistant="$(extract_last assistant)"
fi

{
  printf '# Handoff autosave (live)\n\n'
  printf '> Auto-written by the Stop hook every turn. Gitignored, local-only.\n'
  printf '> Curated state lives in `%s`; this is the raw safety net.\n\n' "$HANDOFF_DOC"
  printf -- '- **Saved:** %s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')"
  printf -- '- **cwd:** %s\n' "$cwd"
  printf -- '- **Repo root:** %s\n' "$root"
  printf -- '- **Branch:** %s  (HEAD %s)\n' "$branch" "$head"
  printf -- '- **Tracking:** %s\n' "$tracking"
  printf -- '- **Dirty files:** %s (staged + unstaged + untracked)\n' "$dirty"
  printf -- '- **Transcript:** %s\n\n' "$transcript"
  printf '## git diff --stat\n\n```\n%s\n```\n\n' "$diffstat"
  printf '## Last user message\n\n%s\n\n' "$last_user"
  printf '## Last assistant message\n\n%s\n' "$last_assistant"
} > "$autosave" 2>/dev/null || exit 0

# Locally ignore the autosave (per-clone; never touches tracked .gitignore).
# rev-parse --git-path resolves info/exclude correctly even in linked worktrees.
rel="${autosave#"$root"/}"
exclude="$(git -C "$root" rev-parse --git-path info/exclude 2>/dev/null)"
case "$exclude" in
  /*) : ;;                       # already absolute
  *)  exclude="$root/$exclude" ;;# make relative git-path absolute
esac
if [ -n "$exclude" ]; then
  mkdir -p "$(dirname "$exclude")" 2>/dev/null || true
  if ! grep -qxF "$rel" "$exclude" 2>/dev/null; then
    printf '%s\n' "$rel" >> "$exclude" 2>/dev/null || true
  fi
fi

exit 0
