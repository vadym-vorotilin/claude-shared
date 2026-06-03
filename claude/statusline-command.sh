#!/bin/bash
# Claude Code status line — mirrors key p10k prompt elements:
# dir | git branch+status | model
input=$(cat)

cwd=$(echo "$input" | jq -r '.cwd // .workspace.current_dir // ""')
model=$(echo "$input" | jq -r '.model.display_name // ""')

# Shorten home directory to ~
# (Note: ${cwd/#$home/~} can't be used — bash tilde-expands the replacement
# back to $HOME, so the prefix gets rewritten to itself instead of "~".)
home="$HOME"
short_cwd="$cwd"
if [ -n "$home" ]; then
  case "$cwd" in
    "$home")    short_cwd="~" ;;
    "$home"/*)  short_cwd="~${cwd#"$home"}" ;;
  esac
fi

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

# Context window. Round in jq, not bash printf: macOS /bin/bash is 3.2, whose
# builtin printf has no %f float support and errors on any non-integer value.
used=$(echo "$input" | jq -r '(.context_window.used_percentage // empty) | round')

# 5-hour quota (same float-rounding caveat as above)
five_pct=$(echo "$input" | jq -r '(.rate_limits.five_hour.used_percentage // empty) | round')

# Time left until the 5-hour window recycles. resets_at is Unix epoch seconds;
# "now" is overridable via STATUSLINE_NOW so the countdown is deterministically
# testable. Integer printf (%02d) is safe under bash 3.2 — only %f floats fail.
five_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
five_left=""
if [ -n "$five_reset" ]; then
  now=${STATUSLINE_NOW:-$(date +%s)}
  rem=$(( five_reset - now ))
  if [ "$rem" -gt 0 ]; then
    h=$(( rem / 3600 ))
    m=$(( (rem % 3600) / 60 ))
    if [ "$h" -gt 0 ]; then
      five_left="-${h}h $(printf '%02d' "$m")m"
    else
      five_left="-${m}m"
    fi
  fi
fi

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
  printf "%sctx: %s%%%s" "${SEP}${YELLOW}" "$used" "$RESET"
fi
if [ -n "$five_pct" ]; then
  five_seg="5h: ${five_pct}%"
  [ -n "$five_left" ] && five_seg="${five_seg} (${five_left})"
  printf "%s%s%s" "${SEP}${WHITE}" "$five_seg" "$RESET"
fi
printf "%s" "$RESET"
