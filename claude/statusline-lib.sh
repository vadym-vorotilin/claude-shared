# Shared helpers for the two status line scripts — the session's
# (statusline-command.sh) and the agent panel's (subagent-statusline-command.sh).
# Sourced, not run: it defines colors, the clock and the cache-TTL readings
# both lines use, so a column means the same thing on either.

CYAN=$'\033[36m'
GREEN=$'\033[32m'
MAGENTA=$'\033[35m'
YELLOW=$'\033[33m'
RED=$'\033[31m'
WHITE=$'\033[37m'
GRAY=$'\033[90m'
RESET=$'\033[0m'

# "now" is overridable via STATUSLINE_NOW so every clock reading is
# deterministically testable.
now=${STATUSLINE_NOW:-$(date +%s)}

TRANSCRIPT_TAIL=262144                        # bytes of a transcript scanned

# The session's effort level, as the main status line last saw it. The agent
# panel's input carries an effort only for an agent whose definition sets one;
# every other agent runs at the session's, which only the main status line is
# told. So that line records it here, one file per session, for the panel.
SESSION_EFFORT_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/cache/statusline-session-effort"

session_effort_file() { # session-id -> path, or nothing for an unusable id
  case "$1" in ''|*[!A-Za-z0-9_-]*) return 0 ;; esac
  printf '%s/%s' "$SESSION_EFFORT_DIR" "$1"
}

# GNU stat and BSD stat spell this differently; try each.
file_mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null; }

# ---- cache clock ----------------------------------------------------------
# Prompt caching is what makes a long context cheap to come back to, and a
# cache entry only outlives the request that wrote it by so much: five minutes
# for a subagent, an hour for a main session. So the reading worth watching
# isn't only how full a context is but how long it has been sitting — past the
# TTL the whole thing is re-sent at full price. Both are shown, on one clock.

# ISO-8601 UTC ("2026-01-01T00:00:00.000Z") -> epoch seconds. date(1) can't
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
  line=$(tail -c "$TRANSCRIPT_TAIL" "$1" 2>/dev/null \
    | grep -E 'ephemeral_(1h|5m)_input_tokens":[1-9]' | tail -n 1)
  case "$line" in
    '') printf '%s' "$2" ;;
    *'ephemeral_5m_input_tokens":'[1-9]*) printf '300' ;;
    *) printf '3600' ;;
  esac
}

# Every field on a line needs its own hue, or the eye can't pick one out of the
# run: the context reading is yellow, so the TTL takes white, which reads as
# neither. It carries one signal, turning red once the cache is nearly gone.
ttl_color() { # elapsed-percentage -> color escape
  if [ "$1" -ge 80 ]; then printf '%s' "$RED"; else printf '%s' "$WHITE"; fi
}

# Effort reads as a traffic light, cheap to costly, with a bar that carries the
# level without color. Fixed 256-color codes, so the theme can't shift them.
effort_color() { # level -> color escape, or nothing for a level not listed
  case "$1" in
    low)    printf '\033[38;5;30m' ;;
    medium) printf '\033[38;5;71m' ;;
    high)   printf '\033[38;5;136m' ;;
    xhigh)  printf '\033[38;5;166m' ;;
    max)    printf '\033[1;38;5;160m' ;;
    ultra)  printf '\033[1;38;5;91m' ;;
  esac
}

effort_bar() { # level -> bar glyph, or nothing for a level not listed
  case "$1" in
    low) printf '▁' ;; medium) printf '▃' ;; high) printf '▅' ;;
    xhigh) printf '▇' ;; max|ultra) printf '█' ;;
  esac
}

# A level this table doesn't know prints plain, so it never borrows another's
# look.
effort_seg() { # level -> colored "level bar"
  local bar
  bar=$(effort_bar "$1")
  if [ -n "$bar" ]; then
    printf '%s%s %s' "$(effort_color "$1")" "$1" "$bar"
  else
    printf '%s' "$1"
  fi
}

# Last assistant turn of a transcript, without reading a multi-megabyte file:
# scan only the tail, dropping its first (likely truncated) line. One tool
# result can outrun that tail on its own — a large file read lands as a single
# very long line — and then the tail holds no turn at all; only then read the
# whole file, since an agent with no turn would otherwise show no readings.
last_assistant() { # transcript -> one JSONL line, or nothing
  local f="$1" size line
  size=$(wc -c < "$f" 2>/dev/null) || return 0
  if [ "${size:-0}" -gt "$TRANSCRIPT_TAIL" ]; then
    line=$(tail -c "$TRANSCRIPT_TAIL" "$f" | tail -n +2 | grep '"type":"assistant"' | tail -n 1)
    if [ -n "$line" ]; then printf '%s' "$line"; return 0; fi
  fi
  grep '"type":"assistant"' "$f" 2>/dev/null | tail -n 1
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
