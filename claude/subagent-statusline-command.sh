#!/bin/bash
# Claude Code per-subagent status line — one row per agent in the panel below
# the prompt, in the session line's columns and colors:
#
#   Explore#1 | O 5.5 | h ▅ |  22% |  10% | Finding where the TTL is computed
#
# agent | model | effort | context | cache TTL | what it is doing.
#
# The harness runs this once per refresh with every row as JSON on stdin —
# {columns, tasks:[{id, name, agentType, status, model, effort,
# contextWindowSize, tokenCount, label, description, startTime, ...}]} — and
# reads back one {"id","content"} line per row. A row it gets no line for keeps
# the CLI's own rendering, so failing quietly is always safe. An empty content
# hides the row instead, so one is never printed.
input=$(cat)

# Without its helpers, print nothing: the panel then keeps its own rows.
. "$(dirname "${BASH_SOURCE[0]}")/statusline-lib.sh" 2>/dev/null || exit 0

SEP="${GRAY} | ${RESET}"

columns=$(echo "$input" | jq -r '(.columns // empty) | floor')
case "$columns" in ''|*[!0-9]*) columns=120 ;; esac

# Each agent's transcript sits beside the session's:
#   <projects>/<slug>/<session-id>/subagents/agent-<id>.jsonl
# and an agent's task id is its agent id. The cache clock and the exact context
# reading both come from there.
transcript=$(echo "$input" | jq -r '.transcript_path // empty')
session_id=$(echo "$input" | jq -r '.session_id // empty')

# An agent whose definition sets no effort runs at the session's, which the
# main status line records per session.
session_effort=""
effort_file=$(session_effort_file "$session_id")
[ -z "$effort_file" ] || session_effort=$(cat "$effort_file" 2>/dev/null)
agents_dir=""
if [ -n "$transcript" ]; then
  agents_dir="${transcript%.jsonl}/subagents"
elif [ -n "$effort_file" ]; then           # a session id safe to put in a path
  for d in "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/projects/*/"$session_id"/subagents; do
    [ -d "$d" ] && { agents_dir="$d"; break; }
  done
fi

# "claude-opus-5-5" -> "O 5.5", "claude-haiku-4-5-20251001" -> "H 4.5",
# "claude-sonnet-5[1m]" -> "S 5". A bare alias ("haiku") keeps its initial.
model_label() { # model-id -> label, "?" when unknown
  local id="$1" fam letter ver seg
  id=${id%%'['*}
  id=${id#claude-}
  fam=${id%%-*}
  if [ -z "$fam" ]; then printf '?'; return 0; fi
  letter=$(printf '%s' "$fam" | cut -c1 | tr 'a-z' 'A-Z')
  ver=""
  case "$id" in
    *-*)
      for seg in $(printf '%s' "${id#*-}" | tr '-' ' '); do
        case "$seg" in
          [0-9]|[0-9][0-9]) ver="${ver:+$ver.}$seg" ;;
          *) break ;;
        esac
      done ;;
  esac
  printf '%s%s' "$letter" "${ver:+ $ver}"
}

# One letter per level and the session line's bar and color, so "h ▅" reads as
# "high ▅" at a glance. max is a capital M, which its bold red and full bar keep
# apart from medium.
effort_letter() { # level -> letter, or nothing for a level not listed
  case "$1" in
    low) printf 'l' ;; medium) printf 'm' ;; high) printf 'h' ;;
    xhigh) printf 'x' ;; max) printf 'M' ;; ultra) printf 'u' ;;
  esac
}

repeat() { # count char -> the char, count times
  local i=0
  while [ "$i" -lt "$1" ]; do printf '%s' "$2"; i=$(( i + 1 )); done
}

# Rows in spawn order. A named agent keeps its name; an unnamed one shows its
# type, minus any plugin prefix, and only a type that repeats gets #N. The
# built-in general-purpose type reads as "general": it is the most common row,
# and eight cells is a lot on a narrow panel. Fields are joined with a unit
# separator, which no label carries, so a tab or a backslash in a label
# survives as itself.
rows=$(echo "$input" | jq -r '
  def kind: (.agentType // .type // "agent") | tostring | sub("^.*:"; "")
    | if . == "general-purpose" then "general" else . end;
  def named: ((.name // "") | tostring) != "";
  [.tasks // [] | .[] | select(.id != null)] | sort_by(.startTime // 0) as $t
  | ([$t[] | select(named | not) | kind] | group_by(.)
     | map({key: .[0], value: length}) | from_entries) as $count
  | reduce $t[] as $x ({seen: {}, out: []};
      if ($x | named) then .out += [$x + {disp: $x.name}]
      else ($x | kind) as $k
        | .seen[$k] = ((.seen[$k] // 0) + 1)
        | .out += [$x + {disp: (if $count[$k] > 1 then "\($k)#\(.seen[$k])" else $k end)}]
      end)
  | .out[]
  | [.id, .disp, (.status // ""), (.model // ""), (.effort // ""),
     ((.contextWindowSize // 0) | floor | tostring),
     ((.tokenCount // 0) | floor | tostring),
     ((.label // .description // "") | tostring | gsub("[\\n\\r\\t]+"; " "))]
  | map(tostring | gsub("\u001f"; " ")) | join("\u001f")' 2>/dev/null)
[ -n "$rows" ] || exit 0

n=0
while IFS=$'\x1f' read -r id disp status model effort window tokcount details; do
  [ -n "$id" ] || continue
  f=""
  [ -n "$agents_dir" ] && [ -f "$agents_dir/agent-$id.jsonl" ] && f="$agents_dir/agent-$id.jsonl"

  # The context reading is the harness's own arithmetic for the main window —
  # every input token, cached or not — off the agent's last turn. The task's
  # tokenCount adds every output token the agent has ever written on top, so it
  # only stands in before a transcript can be read.
  turn_model=""; tokens=""
  if [ -n "$f" ]; then
    IFS=$'\t' read -r turn_model tokens <<EOF
$(last_assistant "$f" | jq -r '[(.message.model // ""),
   (((.message.usage // {}) | (.input_tokens//0)+(.cache_creation_input_tokens//0)+(.cache_read_input_tokens//0)) | tostring)]
   | @tsv' 2>/dev/null)
EOF
  fi
  [ -n "$model" ] || model="$turn_model"
  if [ -z "$model" ] && [ -n "$f" ]; then
    model=$(jq -r '.model // empty' "${f%.jsonl}.meta.json" 2>/dev/null)
  fi
  case "$tokens" in ''|0|*[!0-9]*) tokens="" ;; esac
  if [ -z "$tokens" ] && [ "${tokcount:-0}" -gt 0 ] 2>/dev/null; then tokens="$tokcount"; fi

  # The harness sends the window for the agent's model. Without one, a [1m] id
  # names it, and a turn past 200k proves the larger one.
  case "$window" in ''|0|*[!0-9]*) window="" ;; esac
  if [ -z "$window" ]; then
    case "$model" in
      *'[1m]'*) window=1000000 ;;
      *) if [ "${tokens:-0}" -gt 200000 ]; then window=1000000; else window=200000; fi ;;
    esac
  fi
  ctx=""
  if [ -n "$tokens" ]; then
    ctx=$(( (tokens * 100 + window / 2) / window ))
    [ "$ctx" -le 100 ] || ctx=100
  fi

  # Five minutes after an agent's last turn, the context it assembled has to be
  # paid for again — so each row carries how much of that TTL has gone.
  ttl=""
  if [ -n "$f" ]; then
    IFS=' ' read -r ttl _ <<EOF
$(ttl_of "$f" 300)
EOF
  fi

  [ -n "$effort" ] || effort="$session_effort"

  ids[$n]="$id"; names[$n]="$disp"; states[$n]="$status"
  models[$n]=$(model_label "$model"); efforts[$n]="$effort"
  ctxs[$n]="$ctx"; ttls[$n]="$ttl"; dets[$n]="$details"
  n=$(( n + 1 ))
done <<EOF
$rows
EOF
[ "$n" -gt 0 ] || exit 0

# Column widths, shared by every row so the panel reads as a table. Labels are
# ASCII, so a byte count is a cell count.
# The two percentages keep a fixed four cells, room for "100%": sized to their
# widest value, every column after them would shift a cell the moment one TTL
# ran out.
name_w=0; model_w=0; eff_w=0; ctx_w=4; ttl_w=4
i=0
while [ "$i" -lt "$n" ]; do
  [ "${#names[$i]}" -le "$name_w" ] || name_w=${#names[$i]}
  [ "${#models[$i]}" -le "$model_w" ] || model_w=${#models[$i]}
  if [ -n "$(effort_letter "${efforts[$i]}")" ]; then w=3; else w=${#efforts[$i]}; fi
  [ "$w" -le "$eff_w" ] || eff_w=$w
  i=$(( i + 1 ))
done
[ "$name_w" -le 18 ] || name_w=18

# What fits. The panel spends four cells on its pointer and status circle before
# the content and keeps two clear after it, and truncates whatever overflows.
# Details shrink first and drop below 8 cells; past that the effort letter goes
# and the bar stays, then the agent name is cut.
avail=$(( columns - 6 ))
fixed=$(( name_w + 3 + model_w + ctx_w + 3 + ttl_w ))
[ "$eff_w" -eq 0 ] || fixed=$(( fixed + 3 + eff_w ))
fixed=$(( fixed + 3 ))
detail_w=$(( avail - fixed - 3 ))
short_eff=""
if [ "$detail_w" -lt 8 ]; then
  detail_w=0
  if [ "$fixed" -gt "$avail" ] && [ "$eff_w" -eq 3 ]; then
    short_eff=1; eff_w=1; fixed=$(( fixed - 2 ))
  fi
  if [ "$fixed" -gt "$avail" ]; then
    name_w=$(( name_w - (fixed - avail) ))
    [ "$name_w" -ge 6 ] || name_w=6
  fi
fi

i=0
while [ "$i" -lt "$n" ]; do
  case "${states[$i]}" in
    completed) done_mark="${GREEN}✓ " ;;
    failed|killed|cancelled|error) done_mark="${RED}✗ " ;;
    *) done_mark="" ;;
  esac
  # A finished row goes gray, so the live ones stand out; its TTL still counts,
  # since a follow-up message lands on a warm cache only while it lasts.
  if [ -n "$done_mark" ]; then
    c_name=$GRAY; c_model=$GRAY; c_ctx=$GRAY; c_ttl=$GRAY
  else
    c_name=$WHITE; c_model=$MAGENTA; c_ctx=$YELLOW
    c_ttl=$WHITE; [ -n "${ttls[$i]}" ] && c_ttl=$(ttl_color "${ttls[$i]}")
  fi

  name=${names[$i]}
  if [ "${#name}" -gt "$name_w" ]; then name="${name:0:$(( name_w - 1 ))}…"; vis=$name_w; else vis=${#name}; fi
  row="${c_name}${name}$(repeat $(( name_w - vis )) ' ')${RESET}${SEP}"
  row="${row}${c_model}${models[$i]}$(repeat $(( model_w - ${#models[$i]} )) ' ')${RESET}"

  if [ "$eff_w" -gt 0 ]; then
    lvl=${efforts[$i]}; letter=$(effort_letter "$lvl")
    if [ -n "$letter" ]; then
      if [ -n "$short_eff" ]; then e=$(effort_bar "$lvl"); vis=1; else e="$letter $(effort_bar "$lvl")"; vis=3; fi
      if [ -n "$done_mark" ]; then e="${GRAY}$e"; else e="$(effort_color "$lvl")$e"; fi
    else
      e="${GRAY}${lvl}"; vis=${#lvl}
    fi
    row="${row}${SEP}${e}${RESET}$(repeat $(( eff_w - vis )) ' ')"
  fi

  # Numbers right-aligned; an agent with no turn yet reads "—", never 0%.
  for cell in "${c_ctx}|${ctx_w}|${ctxs[$i]}" "${c_ttl}|${ttl_w}|${ttls[$i]}"; do
    color=${cell%%|*}; rest=${cell#*|}; width=${rest%%|*}; val=${rest#*|}
    if [ -n "$val" ]; then txt="${val}%"; vis=${#txt}; else txt="—"; vis=1; fi
    row="${row}${SEP}$(repeat $(( width - vis )) ' ')${color}${txt}${RESET}"
  done

  tail=""; detail_w_row=0
  if [ "$detail_w" -gt 0 ] && [ -n "${dets[$i]}${done_mark}" ]; then
    tail="${SEP}${done_mark}${GRAY}"
    detail_w_row=$detail_w
    [ -z "$done_mark" ] || detail_w_row=$(( detail_w - 2 ))
  fi

  # Cut the details in jq, which counts characters rather than bytes, so a
  # label is never split mid-character.
  jq -nc --arg id "${ids[$i]}" --arg row "$row" --arg tail "$tail" \
    --arg d "${dets[$i]}" --argjson w "$detail_w_row" --arg reset "$RESET" '
    {id: $id,
     content: ($row + (if $w > 0 then
       $tail + (if ($d | length) > $w then $d[0:($w - 1)] + "…" else $d end) + $reset
       else "" end))}'
  i=$(( i + 1 ))
done
