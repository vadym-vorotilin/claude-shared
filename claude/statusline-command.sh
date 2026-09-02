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

# Quota windows: 5-hour and 7-day share a shape (same float-rounding caveat).
five_pct=$(echo "$input" | jq -r '(.rate_limits.five_hour.used_percentage // empty) | round')
week_pct=$(echo "$input" | jq -r '(.rate_limits.seven_day.used_percentage // empty) | round')
five_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
week_reset=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')

# Time left until a quota window recycles: "-Xd Yh", "-Xh YYm", or "-Xm".
# resets_at is Unix epoch seconds; "now" is overridable via STATUSLINE_NOW so
# the countdown is deterministically testable. Integer printf (%02d) is safe
# under bash 3.2 — only %f floats fail.
now=${STATUSLINE_NOW:-$(date +%s)}

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

CYAN=$'\033[36m'
GREEN=$'\033[32m'
MAGENTA=$'\033[35m'
YELLOW=$'\033[33m'
RED=$'\033[31m'
WHITE=$'\033[37m'
GRAY=$'\033[90m'
RESET=$'\033[0m'
SEP="${RESET} | "

# ---- subagents ------------------------------------------------------------
# The harness sends main-loop state only: .model and .context_window always
# describe this session, never a Task subagent, and stepping into a subagent
# view doesn't re-run this script with different data. But since 2.1 each
# subagent keeps its own transcript beside the session's:
#
#   <projects>/<slug>/<session-id>/subagents/agent-<id>.jsonl
#   <projects>/<slug>/<session-id>/subagents/agent-<id>.meta.json
#
# so the live ones can be read off disk. Liveness is not mtime alone — an agent
# waiting on a long tool call goes quiet for minutes — so it is the plausibly
# live ones minus the ones the session transcript has already collected a
# result for. They render as one compact line, "S/34%/40% · O/11%/2%": a
# model initial, a context percentage and a cache TTL each, oldest-spawned
# first, matching the agent list the CLI shows below the prompt.
AGENT_WINDOW=${STATUSLINE_AGENT_WINDOW:-900}  # seconds since last write
AGENT_MAX=${STATUSLINE_AGENT_MAX:-8}          # entries before collapsing to "+N"
AGENT_TAIL=262144                             # bytes of agent transcript scanned
SESSION_TAIL=2097152                          # bytes of session transcript scanned

transcript=$(echo "$input" | jq -r '.transcript_path // empty')
agents_dir=""
[ -n "$transcript" ] && agents_dir="${transcript%.jsonl}/subagents"

# Context windows are per-model and not knowable from a transcript — Fable 5.1
# and the [1m] variants get 1M where most models get 200k. The harness sends
# the resolved size for the session's own model, so an agent on that same model
# can be measured exactly; anything else is a guess (see agent_limit).
main_model_id=$(echo "$input" | jq -r '.model.id // empty')
main_ctx_size=$(echo "$input" | jq -r '(.context_window.context_window_size // empty) | floor')
case "$main_ctx_size" in ''|*[!0-9]*) main_ctx_size="" ;; esac

# GNU stat and BSD stat spell this differently; try each.
file_mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null; }

# ---- cache clock ----------------------------------------------------------
# Prompt caching is what makes a long context cheap to come back to, and a
# cache entry only outlives the request that wrote it by so much: five minutes
# for a subagent, an hour for a main session. So the reading worth watching
# isn't only how full a context is but how long it has been sitting — past the
# TTL the whole thing is re-sent at full price. Both are shown, on one clock.

# ISO-8601 UTC ("2026-09-02T11:16:07.527Z") -> epoch seconds. date(1) can't
# parse that portably (GNU spells it -d, BSD -j -f), so convert here with the
# usual civil-to-days arithmetic. 10# forces base ten: "08" isn't valid octal.
iso_epoch() { # timestamp -> epoch seconds, or nothing
  local s="$1" y mo d h mi sec era yoe doy doe days
  case "$s" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]*) ;;
    *) return 0 ;;
  esac
  y=$((  10#${s:0:4}  )); mo=$(( 10#${s:5:2}  )); d=$((   10#${s:8:2}  ))
  h=$(( 10#${s:11:2} )); mi=$(( 10#${s:14:2} )); sec=$(( 10#${s:17:2} ))
  [ "$mo" -gt 2 ] || y=$(( y - 1 ))
  era=$(( y / 400 ))
  yoe=$(( y - era * 400 ))
  if [ "$mo" -gt 2 ]; then
    doy=$(( (153 * (mo - 3) + 2) / 5 + d - 1 ))
  else
    doy=$(( (153 * (mo + 9) + 2) / 5 + d - 1 ))
  fi
  doe=$(( yoe * 365 + yoe / 4 - yoe / 100 + doy ))
  days=$(( era * 146097 + doe - 719468 ))
  printf '%s' $(( days * 86400 + h * 3600 + mi * 60 + sec ))
}

# Compact duration: "45s", "20m", "1h", "1h05m". A whole hour drops its zero
# minutes; past that they're padded so the field doesn't change width as it
# counts down.
fmt_dur() { # seconds -> string
  local s="$1" m
  if [ "$s" -lt 60 ]; then
    printf '%ss' "$s"
  elif [ "$s" -lt 3600 ]; then
    printf '%sm' $(( s / 60 ))
  else
    m=$(( (s % 3600) / 60 ))
    if [ "$m" -eq 0 ]; then
      printf '%sh' $(( s / 3600 ))
    else
      printf '%sh%02dm' $(( s / 3600 )) "$m"
    fi
  fi
}

# How long this transcript's cache lives. Every turn reports which bucket it
# wrote — ephemeral_5m for a subagent, ephemeral_1h for a main session — so
# read that rather than assume it, and the reading survives the harness
# changing its mind. Zero-token buckets say nothing about the TTL, so the
# search skips them and walks back to a turn that actually wrote cache.
cache_ttl() { # transcript default-seconds -> seconds
  local line
  line=$(tail -c "$AGENT_TAIL" "$1" 2>/dev/null \
    | grep -E 'ephemeral_(1h|5m)_input_tokens":[1-9]' | tail -n 1)
  case "$line" in
    '') printf '%s' "$2" ;;
    *'ephemeral_5m_input_tokens":'[1-9]*) printf '300' ;;
    *) printf '3600' ;;
  esac
}

# Every field on a line needs its own hue, or the eye can't pick one out of the
# run: the context reading is green on an agent entry and yellow on the session
# line, so the TTL takes white, which reads as neither. It carries one signal,
# turning red once the cache is nearly gone.
ttl_color() { # elapsed-percentage -> color escape
  if [ "$1" -ge 80 ]; then printf '%s' "$RED"; else printf '%s' "$WHITE"; fi
}

# The clock runs from the last assistant turn — the last moment a request is
# known to have refreshed the cache. That reads conservatively on purpose: a
# turn still streaming hasn't been written yet, so a long one counts as idle
# until it lands, and the cache is never claimed fresher than the transcript
# can prove.
ttl_of() { # transcript default-ttl -> "spent-pct seconds-left", or nothing
  local f="$1" epoch idle ttl pct
  epoch=$(iso_epoch "$(last_assistant "$f" | sed -n 's/.*"timestamp":"\([^"]*\)".*/\1/p')")
  [ -n "$epoch" ] || return 0
  idle=$(( now - epoch ))
  [ "$idle" -ge 0 ] || idle=0
  ttl=$(cache_ttl "$f" "$2")
  pct=$(( idle * 100 / ttl ))
  [ "$pct" -le 100 ] || pct=100
  printf '%s %s' "$pct" "$(( ttl - idle ))"
}

# Context windows move with the model lineup — Sonnet crossed to 1M at 5, Opus
# at 4.7 — so read them out of the installed CLI instead of carrying a table
# that quietly goes stale. Its bundle embeds the model list; extraction takes
# ~0.2s on a warm cache, so it's cached against the binary's mtime and size and
# only re-read after an upgrade. STATUSLINE_MODEL_WINDOWS pins a table file
# instead, for a machine where the CLI can't be located.
MODEL_WINDOWS_CACHE="$HOME/.claude/cache/statusline-model-windows"

# The status line runs as a descendant of the CLI, so on Linux /proc names the
# exact binary in use; elsewhere fall back to whatever is on PATH.
claude_binary() {
  local p="${PPID:-}" i=0 exe
  if [ -n "${STATUSLINE_CLAUDE_BIN:-}" ]; then printf '%s' "$STATUSLINE_CLAUDE_BIN"; return 0; fi
  while [ -n "$p" ] && [ "$i" -lt 4 ]; do
    exe=$(readlink "/proc/$p/exe" 2>/dev/null)
    case "$exe" in
      */claude|*claude-code*) printf '%s' "$exe"; return 0 ;;
    esac
    p=$(sed -n 's/^PPid:[[:space:]]*//p' "/proc/$p/status" 2>/dev/null)
    i=$(( i + 1 ))
  done
  command -v claude 2>/dev/null
}

# Cache of "<model-id> <window>" lines, refreshed when the CLI changes. Prints
# nothing if the binary can't be found or doesn't parse — every caller falls
# back rather than failing.
model_windows_file() {
  local bin sig tmp
  bin=$(claude_binary)
  [ -n "$bin" ] && [ -r "$bin" ] || return 0
  sig="$(file_mtime "$bin")-$(wc -c < "$bin" 2>/dev/null | tr -d ' ')"
  if [ -s "$MODEL_WINDOWS_CACHE" ] && [ "$(head -n 1 "$MODEL_WINDOWS_CACHE")" = "$sig" ]; then
    printf '%s' "$MODEL_WINDOWS_CACHE"; return 0
  fi
  mkdir -p "${MODEL_WINDOWS_CACHE%/*}" 2>/dev/null || return 0
  tmp="$MODEL_WINDOWS_CACHE.$$"
  # Each model reads {id:"...",family:"...", ... context:{window:N}}. ERE has no
  # lazy quantifier to span that in one match (and BSD grep has no -P), so pull
  # both anchors in order and pair them up.
  { printf '%s\n' "$sig"
    grep -a -o -E 'id:"claude-[a-z0-9.-]+",family:"|context:\{window:[0-9]+(e[0-9]+)?' "$bin" 2>/dev/null \
      | awk -F'"' '/^id:/ { id=$2; next }
                   /^context:/ { if (id != "") { w=$0; sub(/.*window:/, "", w); print id, w+0; id="" } }'
  } > "$tmp" 2>/dev/null
  if [ "$(wc -l < "$tmp" 2>/dev/null | tr -d ' ')" -gt 4 ]; then
    mv "$tmp" "$MODEL_WINDOWS_CACHE" 2>/dev/null \
      && { printf '%s' "$MODEL_WINDOWS_CACHE"; return 0; }
  fi
  rm -f "$tmp" 2>/dev/null
}

# Transcripts record a dated id ("claude-haiku-4-5-20251001") where the table
# has the family entry, so match on the longest id that prefixes it. The
# signature line has one field and is skipped by the same test.
model_window() { # model-id -> context window size, or nothing
  [ -s "$model_windows" ] || return 0
  awk -v q="$1" '
    NF == 2 && $2 ~ /^[0-9]+$/ && index(q, $1) == 1 && length($1) > n { n=length($1); w=$2 }
    END { if (n) print w }' "$model_windows" 2>/dev/null
}

# "claude-haiku-4-5-20251001" -> H, "claude-sonnet-5[1m]" -> S. One letter is
# all the space a compact line has, and the families in play don't collide.
model_letter() { # model-id -> uppercase family initial, "?" when unknown
  local id="$1" fam
  id=${id%%'['*}
  id=${id#claude-}
  fam=${id%%-*}
  if [ -z "$fam" ]; then printf '?'; return 0; fi
  printf '%s' "$fam" | cut -c1 | tr 'a-z' 'A-Z'
}

# Newest timestamp near the end of a transcript. The last line isn't always a
# timestamped one, hence the small tail rather than exactly one line.
last_ts() { # transcript -> ISO-8601 timestamp, or nothing
  tail -n 3 "$1" 2>/dev/null | sed -n 's/.*"timestamp":"\([^"]*\)".*/\1/p' | tail -n 1
}

# Last assistant turn of a transcript, without reading a multi-megabyte file:
# scan only the tail, dropping its first (likely truncated) line.
last_assistant() { # transcript -> one JSONL line, or nothing
  local f="$1" size
  size=$(wc -c < "$f" 2>/dev/null) || return 0
  if [ "${size:-0}" -gt "$AGENT_TAIL" ]; then
    tail -c "$AGENT_TAIL" "$f" | tail -n +2 | grep '"type":"assistant"' | tail -n 1
  else
    grep '"type":"assistant"' "$f" 2>/dev/null | tail -n 1
  fi
}

# Context window to measure an agent against, best source first: the size the
# harness sent (exact, but only on an exact id match, which a dated agent id
# misses), then an explicit [1m] suffix on the id, then the CLI's own model
# table, then a built-in list of the 1M models as of 2.1.258 for when that
# table can't be read — and failing all of that, the reading itself, since a
# turn can never exceed its own window.
agent_limit() { # model-id total-input-tokens -> context window size
  local id="$1" tokens="$2" w
  if [ -n "$main_ctx_size" ] && [ -n "$id" ] && [ "$id" = "$main_model_id" ]; then
    printf '%s' "$main_ctx_size"; return 0
  fi
  case "$id" in *'[1m]'*) printf '1000000'; return 0 ;; esac
  w=$(model_window "$id")
  case "$w" in ''|*[!0-9]*) w="" ;; esac
  if [ -n "$w" ]; then printf '%s' "$w"; return 0; fi
  case "$id" in
    claude-fable-*|claude-mythos-*|\
    claude-opus-4-7*|claude-opus-4-8*|claude-opus-5*|claude-sonnet-5*)
      printf '1000000'; return 0 ;;
  esac
  if [ "$tokens" -gt 200000 ]; then printf '1000000'; else printf '200000'; fi
}

agent_line=""
if [ -n "$agents_dir" ] && [ -d "$agents_dir" ]; then
  model_windows=${STATUSLINE_MODEL_WINDOWS:-$(model_windows_file)}

  # Order by spawn, not by last write. meta.json is written once when the agent
  # starts; the transcript is appended to constantly, so sorting on that
  # reshuffled the line every second. Oldest first, matching the agent list the
  # CLI shows below the prompt, with the path breaking same-second ties.
  fresh=$(for f in "$agents_dir"/agent-*.jsonl; do
    [ -f "$f" ] || continue
    active=$(file_mtime "$f")
    [ -n "$active" ] || continue
    [ $(( now - active )) -le "$AGENT_WINDOW" ] || continue
    spawn=$(file_mtime "${f%.jsonl}.meta.json")
    [ -n "$spawn" ] || spawn=$active
    printf '%s\t%s\n' "$spawn" "$f"
  done | sort -t"$(printf '\t')" -k1,1n -k2,2)

  # Which of those have finished. Recent writes can't answer that: a running
  # agent goes quiet for minutes waiting on a long tool call, and 1% of the
  # gaps between a running agent's own entries run past 170s — a window tight
  # enough to retire finished agents promptly would drop live ones. But when an
  # agent finishes, the session collects its result, and the session transcript
  # records the agent's id again, after that agent's own last entry. So take
  # every plausibly-live agent above and subtract those. One pass over the tail
  # of the session transcript covers all of them; anything older than that tail
  # is long finished, and the window backstops it.
  #
  # Two kinds of entry say an agent is done, and each covers a case the other
  # misses. "toolUseResult" is what the session writes when it collects a tool's
  # output — the marker for an agent it waited on. A background agent's result
  # lands at spawn instead ("launched successfully"), long before it finishes,
  # so the thing that retires that one is the task-notification the session
  # receives when the agent reports its task complete.
  #
  # Nothing else counts. Queueing a message for a running agent writes a
  # queue-operation and an attachment naming it, and an agent sitting idle
  # waiting for that message has by definition not written since, so the
  # mention lands after its last entry and reads exactly like a result. That
  # retired live agents mid-run. An agent given more work writes past its own
  # notification and comes back on the next repaint, so the ordering keeps
  # working for a background agent that is reused rather than finished.
  refs=""
  if [ -s "$transcript" ]; then
    set --
    while IFS=$'\t' read -r _ f; do
      [ -n "$f" ] || continue
      aid=${f##*/agent-}
      set -- "$@" -e "${aid%.jsonl}"
    done <<EOF
$fresh
EOF
    [ "$#" -gt 0 ] && refs=$(tail -c "$SESSION_TAIL" "$transcript" 2>/dev/null \
      | grep -E '"toolUseResult"|"kind":"task-notification"' | grep -F "$@" 2>/dev/null)
  fi

  shown=0
  total=0
  while IFS=$'\t' read -r _ f; do
    [ -n "$f" ] || continue

    # Timestamps are ISO-8601 UTC, so they order as plain strings.
    aid=${f##*/agent-}; aid=${aid%.jsonl}
    agent_ts=$(last_ts "$f")
    ref_ts=$(printf '%s\n' "$refs" | grep -F "$aid" \
      | sed -n 's/.*"timestamp":"\([^"]*\)".*/\1/p' | tail -n 1)
    if [ -n "$agent_ts" ] && [ -n "$ref_ts" ] && [[ ! $ref_ts < $agent_ts ]]; then
      continue
    fi

    total=$(( total + 1 ))
    [ "$shown" -lt "$AGENT_MAX" ] || continue
    shown=$(( shown + 1 ))

    # Prefer the model the turn actually ran on; meta records only the spec
    # ("haiku", or nothing at all when the agent inherits the parent's model).
    line=$(last_assistant "$f")
    model_id=""; tokens=""
    if [ -n "$line" ]; then
      IFS=$'\t' read -r model_id tokens <<EOF
$(printf '%s' "$line" | jq -r '[(.message.model // ""),
   (((.message.usage // {}) | (.input_tokens//0)+(.cache_creation_input_tokens//0)+(.cache_read_input_tokens//0)) | tostring)]
   | @tsv' 2>/dev/null)
EOF
    fi
    [ -n "$model_id" ] || model_id=$(jq -r '.model // empty' "${f%.jsonl}.meta.json" 2>/dev/null)

    # Same arithmetic the harness uses for the main window: every input token,
    # cached or not, over the model's context size.
    agent_pct=""
    case "$tokens" in ''|*[!0-9]*) tokens="" ;; esac
    if [ -n "$tokens" ]; then
      limit=$(agent_limit "$model_id" "$tokens")
      agent_pct=$(( (tokens * 100 + limit / 2) / limit ))
      [ "$agent_pct" -gt 100 ] && agent_pct=100
    fi

    # The cache is the perishable half of what an agent has built: five minutes
    # after its last turn, the context it assembled has to be paid for again.
    # So each entry carries how much of that TTL has gone.
    agent_ttl_pct=""
    IFS=' ' read -r agent_ttl_pct _ <<EOF
$(ttl_of "$f" 300)
EOF

    # An agent that hasn't taken a turn yet has a model but no usage: show the
    # initial alone rather than a percentage that would read as zero context.
    entry="${MAGENTA}$(model_letter "$model_id")${RESET}"
    [ -n "$agent_pct" ] && entry="${entry}${GRAY}/${GREEN}${agent_pct}%${RESET}"
    [ -n "$agent_ttl_pct" ] && \
      entry="${entry}${GRAY}/$(ttl_color "$agent_ttl_pct")${agent_ttl_pct}%${RESET}"
    [ -n "$agent_line" ] && agent_line="${agent_line}${GRAY} · ${RESET}"
    agent_line="${agent_line}${entry}"
  done <<EOF
$fresh
EOF

  if [ "$total" -gt "$shown" ]; then
    agent_line="${agent_line}${GRAY} · +$(( total - shown ))${RESET}"
  fi
fi


# Line 1: location — dir + git
printf "%s%s%s" "$CYAN" "$short_cwd" "$RESET"
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
if [ -n "$used" ]; then
  printf "%sctx: %s%%%s" "${SEP}${YELLOW}" "$used" "$RESET"
fi
if [ -n "$main_ttl_pct" ]; then
  printf "%s%sTTL: %s%%" "$SEP" "$(ttl_color "$main_ttl_pct")" "$main_ttl_pct"
  [ "${main_ttl_left:-0}" -gt 0 ] && printf " (-%s)" "$(fmt_dur "$main_ttl_left")"
  printf "%s" "$RESET"
fi

# Live subagents, one compact entry each, under the session that spawned them.
if [ -n "$agent_line" ]; then
  printf "\n%s" "$agent_line"
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
