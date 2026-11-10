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

# ---- progress -------------------------------------------------------------
# Two readings, both drawn by the session's status line:
#  - the estimate: how far a task is, as a /progress update last put it. It
#    comes from the transcript, or from `statusline-progress.sh estimate`, and
#    the newer one wins. It is cached per session, so it outlives both the
#    transcript tail and a compaction;
#  - jobs: real percentages from long commands that statusline-progress.sh
#    ran or watched, one file per job.
# Files are keyed by session id: the one in the status line's input, which
# Claude Code also exports to every command it runs as CLAUDE_CODE_SESSION_ID.
PROGRESS_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/cache/statusline-progress"

progress_estimate_file() { # session-id -> path, or nothing for an unusable id
  case "$1" in ''|*[!A-Za-z0-9_-]*) return 0 ;; esac
  printf '%s/%s.estimate' "$PROGRESS_DIR" "$1"
}

progress_jobs_dir() { # session-id -> path, or nothing for an unusable id
  case "$1" in ''|*[!A-Za-z0-9_-]*) return 0 ;; esac
  printf '%s/%s.jobs' "$PROGRESS_DIR" "$1"
}

# A progress file worth opening: a regular file, not a link. A FIFO or a
# device would block the read or never end it, and a link reads, or is
# written through to, whatever it points at.
progress_regular() { [ -f "$1" ] && [ ! -L "$1" ]; }

# Write a file whole or not at all, so a refresh never reads half of one.
# Anything that can write the cache dir can plant files in it, so the temp
# file is created exclusively under a random name (noclobber opens it
# O_EXCL, so a planted link fails rather than being written through), and a
# target or a dir that is a link, or a target that isn't a regular file, is
# refused rather than replaced.
write_atomic() { # path content
  local dir="${1%/*}" tmp
  mkdir -p "$dir" 2>/dev/null || return 1
  [ ! -L "$dir" ] && [ ! -L "$1" ] || return 1
  [ ! -e "$1" ] || [ -f "$1" ] || return 1
  tmp=$(mktemp -u "$1.tmp.XXXXXX" 2>/dev/null) && [ -n "$tmp" ] || return 1
  [ ! -e "$tmp" ] && [ ! -L "$tmp" ] || return 1
  if ( set -C; printf '%s\n' "$2" > "$tmp" ) 2>/dev/null \
     && mv -f "$tmp" "$1" 2>/dev/null; then
    return 0
  fi
  rm -f "$tmp" 2>/dev/null
  return 1
}

# Drop files a month stale. The status line does this when it caches a new
# estimate, and the writer when it starts a session's first estimate or job.
progress_prune() { find "$PROGRESS_DIR" -mindepth 1 -mtime +30 -delete 2>/dev/null; }

# A field read from a progress file, checked. Every such field passes one of
# these before it reaches $(( )) or test: bash evaluates a variable's value
# in $(( )) as an expression, array subscripts and $(...) included, and
# anything that can write the cache dir could plant one. The progress_is_*
# tests fork nothing, for the status line's reads on every refresh.
progress_is_uint() { # string -> true for a plain decimal integer
  case "$1" in ''|*[!0-9]*) return 1 ;; esac
  [ "${#1}" -le 18 ]
}
progress_is_pct() { # string -> true for an integer 0..100
  progress_is_uint "$1" && [ "$(( 10#$1 ))" -le 100 ]
}
progress_is_nm() { # string -> true for "n/m", both plain integers
  case "$1" in */*/*|/*|*/) return 1 ;; */*) ;; *) return 1 ;; esac
  progress_is_uint "${1%/*}" && progress_is_uint "${1#*/}"
}

progress_uint() { # string -> integer, or nothing
  progress_is_uint "$1" || return 0
  printf '%s' "$(( 10#$1 ))"
}
progress_pct() { # string -> pct 0..100, or nothing
  progress_is_pct "$1" || return 0
  printf '%s' "$(( 10#$1 ))"
}
progress_nm() { # string -> n/m, or nothing
  progress_is_nm "$1" || return 0
  printf '%s/%s' "$(( 10#${1%/*} ))" "$(( 10#${1#*/} ))"
}

# Text safe to print into the terminal: control characters dropped (an
# escape can set the title or the clipboard, a \r overdraws the line), C1
# controls too, tabs and newlines as spaces, and cut to <max> characters on
# a UTF-8 character boundary.
progress_clean() { # max-chars; stdin -> stdout
  LC_ALL=C awk -v max="$1" '
    BEGIN { for (i = 128; i < 192; i++) cont = cont sprintf("%c", i) }
    { s = (NR > 1 ? s " " : "") $0 }
    END {
      gsub(/\t/, " ", s)
      gsub(/[\001-\037\177]/, "", s)
      gsub(/\302[\200-\237]/, "", s)
      out = ""; n = 0
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (!index(cont, c) && ++n > max) break
        out = out c
      }
      printf "%s", out
    }'
}

# A local wall-clock reading of an epoch. BSD date spells it -r, GNU -d @.
local_clock() { # epoch strftime-format -> string
  date -r "$1" "+$2" 2>/dev/null || date -d "@$1" "+$2" 2>/dev/null
}

# The epoch of a local date and time, or nothing. BSD date parses with
# -j -f (given the seconds, or it takes the current ones), GNU with -d.
local_epoch() { # YYYY-MM-DD HH:MM -> epoch, or nothing
  progress_uint "$(date -j -f '%Y-%m-%d %H:%M:%S' "$1 $2:00" +%s 2>/dev/null \
    || date -d "$1 $2" +%s 2>/dev/null)"
}

# "HH:MM" on the local clock, as the first such moment no earlier than an
# hour before the reference: an ETA of 00:20 written at 23:50 is tomorrow.
# date resolves it on the reference's day, so a DST change in between is
# counted; if date can't (a time the change skips), it is reckoned from the
# reference's wall clock instead.
clock_epoch() { # HH:MM reference-epoch -> epoch, or nothing
  local hm="$1" ref day noon hms rh rm rs eh em eta
  case "$hm" in [0-9]:[0-5][0-9]|[01][0-9]:[0-5][0-9]|2[0-3]:[0-5][0-9]) ;; *) return 0 ;; esac
  ref=$(progress_uint "$2"); [ -n "$ref" ] || return 0
  day=$(local_clock "$ref" '%Y-%m-%d')
  eta=$(local_epoch "$day" "$hm")
  if [ -n "$eta" ] && [ "$eta" -lt $(( ref - 3600 )) ]; then
    # Tomorrow: the day of today's noon plus a day, which no DST change moves
    # off that day.
    noon=$(local_epoch "$day" 12:00)
    [ -n "$noon" ] && eta=$(local_epoch "$(local_clock $(( noon + 86400 )) '%Y-%m-%d')" "$hm")
  fi
  if [ -z "$eta" ]; then
    hms=$(local_clock "$ref" '%H %M %S') || return 0
    read -r rh rm rs <<EOF
$hms
EOF
    rh=$(progress_uint "$rh"); rm=$(progress_uint "$rm"); rs=$(progress_uint "$rs")
    [ -n "$rh" ] && [ -n "$rm" ] && [ -n "$rs" ] || return 0
    eh=$(( 10#${hm%%:*} )); em=$(( 10#${hm##*:} ))
    eta=$(( ref - rh * 3600 - rm * 60 - rs + eh * 3600 + em * 60 ))
    [ "$eta" -ge $(( ref - 3600 )) ] || eta=$(( eta + 86400 ))
  fi
  printf '%s' "$eta"
}

# The last progress update in a transcript's tail: a /progress header
# ("Progress: 3/5 · ~55% · ETA …", with its ETA bullet's "≈14:55"), an
# /unattended-run or /orchestrating-issue-runs stamp ("Progress: Goal 3/5 ·
# 60%", "Progress: Exit 3/5 · 60%"), or "Progress: idle".
# Only a whole line counts, in the shape the skills mandate: bold
# ("**<time> - Progress: …**", " — " also read for the dash), and for idle
# also the plain line /progress specifies ("<time> - Progress: idle", the
# time starting with a digit). And only in the session's own assistant
# text: prose that quotes a header, a skill quoting the format, a file being
# written, or a sidechain never reads as an update.
# Prints "timestamp<TAB>pct<TAB>n/m<TAB>HH:MM", "-" for a part not given; an
# idle update prints pct "-".
progress_stamp() { # transcript -> line, or nothing
  local f="$1" size
  size=$(wc -c < "$f" 2>/dev/null) || return 0
  {
    if [ "${size:-0}" -gt "$TRANSCRIPT_TAIL" ]; then
      tail -c "$TRANSCRIPT_TAIL" "$f" | tail -n +2
    else
      cat "$f"
    fi
  } 2>/dev/null | grep '"type":"assistant"' | grep -F 'Progress: ' | tail -n 20 \
    | jq -rs '
      def header: "^(?:\\*\\*[^*]+ (?:—|-) Progress: (?:(?:Goal |Exit )?(?<n>[0-9]+)/(?<m>[0-9]+) · ~?(?<p>[0-9]+)%[^*]*|idle)\\*\\*|[0-9][^*`]* (?:—|-) Progress: idle)\\s*$";
      [ .[] | select(.type == "assistant" and .isSidechain != true)
        | { ts: .timestamp,
            lines: ([.message.content[]? | select(.type == "text") | .text]
                    | join("\n") | split("\n")) }
        | . as $e
        | ([range(0; $e.lines | length)] | map(select($e.lines[.] | test(header))) | last) as $i
        | select($i != null)
        | ($e.lines[$i] | capture(header)) as $h
        | ([$e.lines[$i + 1:][] | select(test("ETA:\\*\\* *≈[0-9]{1,2}:[0-9]{2}"))]
           | first // "" | (capture("≈(?<c>[0-9]{1,2}:[0-9]{2})").c // "-")) as $eta
        | [ $e.ts, ($h.p // "-"),
            (if $h.n then "\($h.n)/\($h.m)" else "-" end), $eta ]
      ] | last // empty | @tsv' 2>/dev/null
}
