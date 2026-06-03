#!/bin/bash
# Claude Code status line — mirrors key p10k prompt elements:
# dir | git branch+status | model
input=$(cat)

cwd=$(echo "$input" | jq -r '.cwd // .workspace.current_dir // ""')
model=$(echo "$input" | jq -r '.model.display_name // ""')

# Shorten home directory to ~
home="$HOME"
short_cwd="$cwd"
[ -n "$home" ] && short_cwd="${cwd/#$home/~}"

# Git branch and status
branch=""
if git_branch=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null); then
  branch="$git_branch"
elif git_commit=$(git -C "$cwd" rev-parse --short HEAD 2>/dev/null); then
  branch="@$git_commit"
fi

git_status=""
if [ -n "$branch" ]; then
  # staged, unstaged, untracked indicators (like p10k: +N !N ?N)
  staged=$(git -C "$cwd" diff --cached --name-only 2>/dev/null | wc -l | tr -d ' ')
  unstaged=$(git -C "$cwd" diff --name-only 2>/dev/null | wc -l | tr -d ' ')
  untracked=$(git -C "$cwd" ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')
  ahead=$(git -C "$cwd" rev-list --count @{u}..HEAD 2>/dev/null || echo 0)
  behind=$(git -C "$cwd" rev-list --count HEAD..@{u} 2>/dev/null || echo 0)

  git_status=" | $branch"
  [ "$ahead" -gt 0 ] 2>/dev/null && git_status="$git_status ⇡$ahead"
  [ "$behind" -gt 0 ] 2>/dev/null && git_status="$git_status ⇣$behind"
  [ "$staged" -gt 0 ] 2>/dev/null && git_status="$git_status +$staged"
  [ "$unstaged" -gt 0 ] 2>/dev/null && git_status="$git_status !$unstaged"
  [ "$untracked" -gt 0 ] 2>/dev/null && git_status="$git_status ?$untracked"
fi

# Context window
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

# 5-hour quota
five_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')

CYAN=$'\033[36m'
GREEN=$'\033[32m'
MAGENTA=$'\033[35m'
YELLOW=$'\033[33m'
WHITE=$'\033[37m'
RESET=$'\033[0m'
SEP="${RESET} | "

printf "%s%s%s" "$CYAN" "$short_cwd" "$RESET"
if [ -n "$branch" ]; then
  branch_part="${git_status# | }"
  printf "%s%s%s%s" "$SEP" "$GREEN" "$branch_part" "$RESET"
fi
printf "%s%s%s%s" "$SEP" "$MAGENTA" "$model" "$RESET"
if [ -n "$used" ]; then
  printf "%sctx: $(printf '%.0f' "$used")%%%s" "${SEP}${YELLOW}" "$RESET"
fi
if [ -n "$five_pct" ]; then
  printf "%s5h: $(printf '%.0f' "$five_pct")%%%s" "${SEP}${WHITE}" "$RESET"
fi
printf "%s" "$RESET"
