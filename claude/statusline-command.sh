#!/bin/bash
# Claude Code status line — mirrors key p10k prompt elements:
# repo or dir | git branch+status | model
input=$(cat)

# Colors, the clock and the cache-TTL readings, shared with the agent panel's
# script so a column means the same thing on either line.
if ! . "$(dirname "${BASH_SOURCE[0]}")/statusline-lib.sh" 2>/dev/null; then
  printf 'statusline-lib.sh is missing beside this script; re-run sync.sh'
  exit 0
fi

cwd=$(echo "$input" | jq -r '.cwd // .workspace.current_dir // ""')
model=$(echo "$input" | jq -r '.model.display_name // ""')
# Absent when the model has no effort setting, so the segment drops out.
effort=$(echo "$input" | jq -r '.effort.level // empty')

# Hand the effort to the agent panel, whose agents inherit it. Written only
# when it changes, and dropped when the model has none; files a month stale
# are pruned on the way.
effort_file=$(session_effort_file "$(echo "$input" | jq -r '.session_id // empty')")
if [ -n "$effort_file" ]; then
  if [ -z "$effort" ]; then
    rm -f "$effort_file" 2>/dev/null
  elif [ "$(cat "$effort_file" 2>/dev/null)" != "$effort" ]; then
    mkdir -p "$SESSION_EFFORT_DIR" 2>/dev/null \
      && printf '%s\n' "$effort" > "$effort_file" 2>/dev/null
    find "$SESSION_EFFORT_DIR" -type f -mtime +30 -exec rm -f {} + 2>/dev/null
  fi
fi

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

# Abbreviate a path fish-style: every folder but the last cut to its first
# letter, or two for a leading "." or "_" so hidden folders stay told apart.
# Letters are cut by character under a UTF-8 locale; under LC_ALL=C a
# multibyte first letter is cut mid-byte.
abbrev_path() { # path -> abbreviated path
  local p="$1" rest part out=""
  case "$p" in */*) ;; *) printf '%s' "$p"; return ;; esac
  rest="${p%/*}/"
  while [ -n "$rest" ]; do
    part="${rest%%/*}"; rest="${rest#*/}"
    case "$part" in
      ''|'~') ;;
      [._]?*) part="${part:0:2}" ;;
      *)      part="${part:0:1}" ;;
    esac
    out="$out$part/"
  done
  printf '%s%s' "$out" "${p##*/}"
}

# Location: inside git, the repo's name rather than its path, so a long
# checkout path never pushes the branch off the line. A linked worktree reads
# "repo:worktree", naming the main repo it belongs to. Any subfolder follows,
# abbreviated. Outside git, the whole path is abbreviated, as it is inside a
# .git dir, which has no top level to name. An empty cwd is skipped: git -C ""
# would read the repo the status line happens to run from.
location=$(abbrev_path "$short_cwd")
if [ -n "$cwd" ] && git_info=$(git -C "$cwd" rev-parse --show-toplevel --git-common-dir --show-prefix 2>/dev/null); then
  { IFS= read -r top; IFS= read -r common; IFS= read -r prefix; } <<EOF
$git_info
EOF
  case "$common" in /*) ;; *) common="$cwd/$common" ;; esac
  common=$(cd "$common" 2>/dev/null && pwd -P)
  wt_name="${top##*/}"
  if [ "${common##*/}" = .git ]; then
    # A non-bare repo: its main checkout holds the shared .git.
    main_root="${common%/*}"; repo_name="${main_root##*/}"
  elif [ -n "$common" ]; then
    # A bare repo, or a submodule's dir under .git/modules.
    main_root=""; repo_name="${common##*/}"; repo_name="${repo_name%.git}"
  else
    main_root=""; repo_name="$wt_name"
  fi
  location="$repo_name"
  if [ -n "$main_root" ]; then
    [ "$top" = "$main_root" ] || location="$location:$wt_name"
  else
    [ "$wt_name" = "$repo_name" ] || location="$location:$wt_name"
  fi
  [ -n "$prefix" ] && location="$location/$(abbrev_path "${prefix%/}")"
fi

# Git branch and status
branch=""
if [ -n "$cwd" ] && git_branch=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null); then
  branch="$git_branch"
elif [ -n "$cwd" ] && git_commit=$(git -C "$cwd" rev-parse --short HEAD 2>/dev/null); then
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

# Quota windows: 5-hour and 7-day share a shape (same float-rounding caveat).
five_pct=$(echo "$input" | jq -r '(.rate_limits.five_hour.used_percentage // empty) | round')
week_pct=$(echo "$input" | jq -r '(.rate_limits.seven_day.used_percentage // empty) | round')
five_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
week_reset=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')

# Time left until a quota window recycles: "-Xd Yh", "-Xh YYm", or "-Xm".
# resets_at is Unix epoch seconds, read against the lib's "now". Integer printf
# (%02d) is safe under bash 3.2 — only %f floats fail.
time_left() { # resets_at-epoch -> countdown string (empty if past or unset)
  local reset="$1" rem d h m
  [ -n "$reset" ] || return 0
  rem=$(( reset - now ))
  [ "$rem" -gt 0 ] || return 0
  d=$(( rem / 86400 ))
  h=$(( (rem % 86400) / 3600 ))
  m=$(( (rem % 3600) / 60 ))
  if [ "$d" -gt 0 ]; then
    echo "-${d}d ${h}h"
  elif [ "$h" -gt 0 ]; then
    echo "-${h}h $(printf '%02d' "$m")m"
  else
    echo "-${m}m"
  fi
}
five_left=$(time_left "$five_reset")
week_left=$(time_left "$week_reset")

SEP="${RESET} | "

# The session's own transcript, which dates its last turn for the cache clock.
# Live subagents are drawn in the agent panel by subagent-statusline-command.sh.
transcript=$(echo "$input" | jq -r '.transcript_path // empty')

# Line 1: location — repo or dir + git
printf "%s%s%s" "$CYAN" "$location" "$RESET"
if [ -n "$branch" ]; then
  branch_part="${git_status# | }"
  printf "%s%s%s%s" "$SEP" "$GREEN" "$branch_part" "$RESET"
fi
printf "\n"

# Line 2: session — model + context window + cache TTL. The session's cache
# lives an hour where an agent's lives five minutes, so the same silence reads
# very differently here, off the same measurement.
main_ttl_pct=""; main_ttl_left=""
if [ -n "$transcript" ] && [ -s "$transcript" ]; then
  IFS=' ' read -r main_ttl_pct main_ttl_left <<EOF
$(ttl_of "$transcript" 3600)
EOF
fi

printf "%s%s%s" "$MAGENTA" "$model" "$RESET"
if [ -n "$effort" ]; then
  printf "%s%s%s" "$SEP" "$(effort_seg "$effort")" "$RESET"
fi
if [ -n "$used" ]; then
  printf "%sctx: %s%%%s" "${SEP}${YELLOW}" "$used" "$RESET"
fi
if [ -n "$main_ttl_pct" ]; then
  printf "%s%sTTL: %s%%" "$SEP" "$(ttl_color "$main_ttl_pct")" "$main_ttl_pct"
  [ "${main_ttl_left:-0}" -gt 0 ] && printf " (-%s)" "$(fmt_dur "$main_ttl_left")"
  printf "%s" "$RESET"
fi

# Line 3: quotas — only when the harness sent rate-limit data. The 5h window
# is the one you actively burn through, so it stays white; the slow-moving
# weekly window renders in dark gray to recede next to it.
quota_line=""
if [ -n "$five_pct" ]; then
  quota_line="${WHITE}5h: ${five_pct}%"
  [ -n "$five_left" ] && quota_line="${quota_line} (${five_left})"
  quota_line="${quota_line}${RESET}"
fi
if [ -n "$week_pct" ]; then
  week_seg="${GRAY}1w: ${week_pct}%"
  [ -n "$week_left" ] && week_seg="${week_seg} (${week_left})"
  [ -n "$quota_line" ] && quota_line="${quota_line} | "
  quota_line="${quota_line}${week_seg}${RESET}"
fi
if [ -n "$quota_line" ]; then
  printf "\n%s" "$quota_line"
fi

# Trailing spacer line so the status doesn't visually glue to the CLI chrome
# below. Claude Code trims trailing whitespace-only lines, so the spacer is
# U+2800 BRAILLE PATTERN BLANK — renders as a blank cell but isn't whitespace.
printf "%s\n⠀" "$RESET"
