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

# Keep the last quota reading on disk, for tools that run outside a session
# (a scheduler checking the weekly cap before it starts one). The file is
#   ${XDG_STATE_HOME:-$HOME/.local/state}/claude/rate-limits.json
# with the windows the harness sent (unrounded), session_id, the session's
# main-conversation request count when the input carries one
# (prompt_cache.requests), and two clocks:
#   written_at  - a session last ran this script with this reading: some
#                 session is alive, not necessarily the one named.
#   observed_at - the reading last changed, or the request count went up.
#                 This script re-runs on a timer with the
#                 last data it was given, so "now" on every run would stamp a
#                 frozen number as fresh. A reader judges staleness by this.
# Another session's reading replaces the file only when neither live window in
# the file is newer (a later reset, or the same reset at a higher share; within
# a window, use only rises), so a session holding an old reading cannot roll
# either window back. A window already past its reset never blocks. The block
# prints nothing and never changes the status line's output or exit code.
persist_rate_limits() {
  local dir="${XDG_STATE_HOME:-$HOME/.local/state}/claude"
  local file="$dir/rate-limits.json" prev="" next tmp
  [ -r "$file" ] && prev=$(cat "$file" 2>/dev/null)
  next=$(printf '%s' "$input" | jq -c --arg prev "$prev" --argjson now "$now" '
    def win($w): if ($w | type) == "object" and ($w.used_percentage | type) == "number"
                 then {used_percentage: $w.used_percentage, resets_at: $w.resets_at}
                 else null end;
    def same_vals($a; $b): ($a.seven_day == $b.seven_day) and ($a.five_hour == $b.five_hour);
    (.rate_limits // {}) as $rl
    | ({} + (if win($rl.seven_day) then {seven_day: win($rl.seven_day)} else {} end)
          + (if win($rl.five_hour) then {five_hour: win($rl.five_hour)} else {} end)) as $wins
    | if $wins == {} then empty else
      ($prev | try fromjson catch null) as $old
      | ($wins + {session_id: (.session_id // ""),
                  requests: (.prompt_cache.requests // null),
                  observed_at: $now, written_at: $now}) as $new
      | if ($old | type) != "object" then $new
        elif $old.session_id == $new.session_id then
          # Same session: its own latest reading always lands. The data time
          # carries over unless the reading changed or a request went out.
          if same_vals($old; $new)
             and ($new.requests == null or ($old.requests // -1) >= $new.requests)
          then $new + {observed_at: ($old.observed_at // $now)}
          else $new end
        elif same_vals($old; $new) then
          # Another session with the very same reading: the file stays with
          # the session that wrote it, and only the liveness clock moves.
          $old + {written_at: $now}
        else
          # Another session, a different reading: it lands only when no window
          # in the file is newer than its own (a later reset, or the same reset
          # at a higher share) and it drops no live window the file has. A
          # window past its reset never counts, or it would pin the file.
          def older($o; $n): ($o | type) == "object"
            and (($o.resets_at | type) != "number" or $o.resets_at > $now)
            and (($n | type) != "object"
                 or ($o.resets_at // 0) > ($n.resets_at // 0)
                 or (($o.resets_at // 0) == ($n.resets_at // 0)
                     and $o.used_percentage > $n.used_percentage));
          if older($old.seven_day; $new.seven_day) or older($old.five_hour; $new.five_hour)
          then empty else $new end
        end
      end' 2>/dev/null) || return 0
  [ -n "$next" ] || return 0
  mkdir -p "$dir" 2>/dev/null || return 0
  tmp=$(mktemp "$dir/.rate-limits.json.XXXXXX" 2>/dev/null) || return 0
  if printf '%s\n' "$next" > "$tmp" 2>/dev/null && mv -f "$tmp" "$file" 2>/dev/null; then
    return 0
  fi
  rm -f "$tmp" 2>/dev/null
  return 0
}
persist_rate_limits 2>/dev/null

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

# Line 4: progress, at most one line, printed only when there is something
# to show: the task estimate, then the newest running job, then counters for
# jobs finished in the last half hour, joined with " · " (see
# statusline-lib.sh for both readings). The line refreshes on a timer, but a
# reading only moves when something writes it, so one over 5 minutes old
# (a running job: 15) says how old. Every field read from those files is
# checked before use: they can be written by commands this line never sees.
session_id=$(echo "$input" | jq -r '.session_id // empty')
est_file=$(progress_estimate_file "$session_id")
jobs_dir=$(progress_jobs_dir "$session_id")
prog_line=""
prog_add() { # segment
  if [ -n "$prog_line" ]; then prog_line="${prog_line}${RESET} · $1"; else prog_line="$1"; fi
}

# The estimate. A /progress update in the transcript newer than the cached
# reading replaces it, so the cache holds the latest of either source.
if [ -n "$est_file" ]; then
  est_w=""; est_pct=""; est_nm=""; est_eta=""
  progress_regular "$est_file" \
    && IFS='	' read -r est_w est_pct est_nm est_eta 2>/dev/null < "$est_file"
  progress_is_uint "$est_w" && est_w=$(( 10#$est_w )) || est_w=""
  if [ -n "$transcript" ] && [ -s "$transcript" ]; then
    st_ts=""; st_pct=""; st_nm=""; st_eta=""
    IFS='	' read -r st_ts st_pct st_nm st_eta <<EOF
$(progress_stamp "$transcript")
EOF
    st_w=$(iso_epoch "$st_ts")
    if [ -n "$st_w" ] && [ "$st_w" -gt "${est_w:-0}" ]; then
      st_eta_epoch=$(clock_epoch "$st_eta" "$st_w")
      est_w="$st_w"; est_pct="$st_pct"; est_nm="$st_nm"; est_eta="${st_eta_epoch:--}"
      write_atomic "$est_file" "$est_w	$est_pct	$est_nm	$est_eta"
      progress_prune
    fi
  fi
  est_w=${est_w:-0}
  # The ETA is an epoch: the writer resolves a hand-written HH:MM when it
  # writes it, so no refresh has to. The n/m count is kept in the file but
  # not drawn.
  progress_is_uint "$est_eta" && est_eta=$(( 10#$est_eta )) || est_eta=""
  progress_is_pct "$est_pct" && est_pct=$(( 10#$est_pct )) || est_pct=""
  est_age=$(( now - est_w )); [ "$est_age" -ge 0 ] || est_age=0
  # Shown while under 4 hours old; a finished task, for half an hour.
  if [ -n "$est_pct" ] && [ "$est_age" -lt 14400 ] \
     && { [ "$est_pct" -lt 100 ] || [ "$est_age" -lt 1800 ]; }; then
    if [ "$est_age" -ge 1800 ]; then c="$GRAY"; else c="$WHITE"; fi
    if [ "$est_pct" -ge 100 ]; then
      seg="${c}100% done"
    else
      seg="${c}${est_pct}%"
      # A passed ETA is the same clock, in red.
      if [ -n "$est_eta" ]; then
        if [ "$est_eta" -ge "$now" ]; then
          seg="$seg ≈$(fmt_clock "$est_eta")"
        else
          seg="$seg ${RED}≈$(fmt_clock "$est_eta")${c}"
        fi
      fi
    fi
    [ "$est_age" -lt 300 ] || seg="$seg ${GRAY}($(fmt_dur "$est_age") ago)"
    prog_add "$seg"
  fi
fi

# Jobs: the most recently written running one, with how many more run, then
# counts of the jobs that finished in the last half hour. A running job goes
# gray after 15 silent minutes and away after 6 hours. A row names the
# process that wrote it, with its PID namespace on Linux; if that process is
# gone with the row still running, the writer was killed, and the job counts
# as failed. A session can leave many rows, so each is checked without a
# fork, its age first: ls -t lists the newest first, so once a row is past
# 6 hours, all the rest are too.
if [ -n "$jobs_dir" ] && [ -d "$jobs_dir" ]; then
  my_ns=""; n_run=0; n_ok=0; n_bad=0; n_end=0
  top_name=""; top_pct=""; top_age=""
  for jf in $(ls -t "$jobs_dir" 2>/dev/null); do
    case "$jf" in *.tmp.*) continue ;; esac
    progress_regular "$jobs_dir/$jf" || continue
    j_w=""; j_pct=""; j_state=""; j_name=""; j_pid=""; j_ns=""
    IFS='	' read -r j_w j_pct j_state j_name j_pid j_ns 2>/dev/null < "$jobs_dir/$jf" || continue
    progress_is_uint "$j_w" || continue
    j_age=$(( now - 10#$j_w )); [ "$j_age" -ge 0 ] || j_age=0
    [ "$j_age" -lt 21600 ] || break
    case "$j_state" in
      run|done|end|fail:sig) ;;
      fail:*) progress_is_uint "${j_state#fail:}" || continue ;;
      *) continue ;;
    esac
    # "-" is a running job that has printed no percentage yet.
    if [ "$j_pct" != - ] || [ "$j_state" != run ]; then
      progress_is_pct "$j_pct" || continue
    fi
    if [ "$j_state" = run ] && progress_is_uint "$j_pid"; then
      [ -n "$my_ns" ] || my_ns=$(readlink /proc/self/ns/pid 2>/dev/null || echo -)
      if [ "${j_ns:--}" = "$my_ns" ] && ! kill -0 "$(( 10#$j_pid ))" 2>/dev/null; then
        j_state=gone
      fi
    fi
    if [ "$j_state" = run ]; then
      n_run=$(( n_run + 1 ))
      if [ "$n_run" -eq 1 ]; then
        top_name="$j_name"; top_pct="$j_pct"; top_age="$j_age"
        [ "$top_pct" = - ] || top_pct=$(( 10#$top_pct ))
      fi
      continue
    fi
    [ "$j_age" -lt 1800 ] || continue
    case "$j_state" in
      done) n_ok=$(( n_ok + 1 )) ;;
      end)  n_end=$(( n_end + 1 )) ;;
      *)    n_bad=$(( n_bad + 1 )) ;;      # exit N, killed, gone
    esac
  done
  if [ "$n_run" -gt 0 ]; then
    top_name=$(printf '%s' "$top_name" | progress_clean 20)
    if [ "$top_pct" = - ]; then
      # No percentage yet: the row was written at the start, so its age is
      # how long the job has run.
      seg="${WHITE}${top_name} ${GRAY}$(fmt_dur "$top_age")"
    elif [ "$top_age" -ge 900 ]; then
      seg="${GRAY}${top_name} ${top_pct}% ($(fmt_dur "$top_age") ago)"
    else
      seg="${WHITE}${top_name} ${CYAN}${top_pct}%"
    fi
    [ "$n_run" -lt 2 ] || seg="$seg ${GRAY}+$(( n_run - 1 ))"
    prog_add "$seg"
  fi
  seg=""
  [ "$n_ok" -eq 0 ]  || seg="${GREEN}✓${n_ok}"
  [ "$n_bad" -eq 0 ] || seg="${seg:+$seg }${RED}✗${n_bad}"
  [ "$n_end" -eq 0 ] || seg="${seg:+$seg }${GRAY}■${n_end}"
  [ -z "$seg" ] || prog_add "$seg"
fi
[ -z "$prog_line" ] || printf "\n%s%s" "$prog_line" "$RESET"

# Trailing spacer line so the status doesn't visually glue to the CLI chrome
# below. Claude Code trims trailing whitespace-only lines, so the spacer is
# U+2800 BRAILLE PATTERN BLANK — renders as a blank cell but isn't whitespace.
printf "%s\n⠀" "$RESET"
