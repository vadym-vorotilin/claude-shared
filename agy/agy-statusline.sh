#!/bin/bash
# Status line for agy (the Antigravity CLI): turns the JSON agy sends a
# custom status line into the shape statusline-command.sh reads, then draws it
# with that script, so both CLIs share one look. agy runs it from
# settings.json:  "statusLine": {"type": "command", "command": "<this file>"}
#
# What changes on the way:
#   model.effort            -> effort.level, and a display name ending in the
#                              same effort, "Gemini X (Medium)", loses that
#                              ending, which the effort segment already shows
#   quota["<pool>-5h"],     -> rate_limits.five_hour / .seven_day:
#   quota["<pool>-weekly"]     used_percentage = (1 - remaining_fraction) * 100,
#                              resets_at = reset_time as epoch seconds (or now
#                              + reset_in_seconds). The pool is "gemini" for a
#                              name with Gemini or Orchestrator in it (the
#                              Orchestrator plans with a Gemini model), "3p"
#                              for one naming a third-party family (Claude,
#                              GPT, ...), and "gemini" for any other.
#   (added)                 -> cache_reading: {hit_percentage, last_call_at},
#                              the share of the last model call's input read
#                              from cache and when that call finished (when
#                              known), from agy's conversation database by
#                              agy-cache.py. Drawn in
#                              place of the cache clock: Gemini's caching has
#                              no published lifetime to count down.
#   everything else Claude-specific is dropped: session_id (no effort or
#   progress files for agy), transcript_path (agy's log is not a Claude
#   transcript).
# Percentages print with 2 decimals, and the quota reading is kept out of
# Claude's rate-limits.json, which is Claude's quota, not Gemini's.
here=$(dirname "${BASH_SOURCE[0]}")
# Installed, statusline-command.sh sits beside this script in ~/.claude; in
# the repo, this script is in agy/ and the status line in claude/.
statusline="$here/statusline-command.sh"
# The fallback is taken only inside the repo (sync.sh one level up), so an
# installed copy never runs some unrelated ../claude/ script.
if [ ! -f "$statusline" ] && [ -f "$here/../sync.sh" ]; then
  statusline="$here/../claude/statusline-command.sh"
fi
input=$(cat)
now=${STATUSLINE_NOW:-$(date +%s)}

# The conversation's cache reading, "<hit%>" or "<hit%> <epoch>", or nothing
# when the id is missing or odd, python3 is absent, or the database cannot be
# read. A malformed hit drops the reading; a malformed time drops only the time.
conv=$(printf '%s' "$input" | jq -r '[.conversation_id, .session_id] | map(strings | select(. != "")) | first // empty' 2>/dev/null)
cache_out=""
case "$conv" in
  ''|*[!A-Za-z0-9-]*) ;;
  *) command -v python3 >/dev/null 2>&1 \
       && cache_out=$(python3 -I "$here/agy-cache.py" "$conv" 2>/dev/null) ;;
esac
cache_hit=${cache_out%% *}
cache_at=""; [ "$cache_hit" = "$cache_out" ] || cache_at=${cache_out#* }
case "$cache_hit" in ''|*[!0-9.]*|*.*.*|.*) cache_hit="" ;; esac
case "$cache_at" in *[!0-9]*) cache_at="" ;; esac

translated=$(printf '%s' "$input" | jq -c --argjson now "$now" \
  --arg hit "$cache_hit" --arg at "$cache_at" '
  def epoch: if type == "string"
             then sub("\\.[0-9]+"; "") | try fromdateiso8601 catch null
             else null end;
  def win($q):
    if ($q | type) == "object" and ($q.remaining_fraction | type) == "number" then
      {used_percentage: ((1 - ([[$q.remaining_fraction, 0] | max, 1] | min)) * 100)}
      + (($q.reset_time | epoch) as $r
         | if ($r | type) == "number" and $r > 0 then {resets_at: $r}
           elif ($q.reset_in_seconds | type) == "number" and $q.reset_in_seconds > 0
           then {resets_at: ($now + ($q.reset_in_seconds | floor))}
           else {} end)
    else null end;
  (.model.display_name // .model.id // "") as $name
  | (.model.effort // null) as $eff
  | (if $name | test("\\b(gemini|orchestrator)\\b"; "i") then "gemini"
     elif $name | test("\\b(claude|opus|sonnet|haiku|fable|gpt|llama|mistral|grok|deepseek|qwen)\\b"; "i")
     then "3p" else "gemini" end) as $pool
  | ({five_hour: win(.quota[$pool + "-5h"]?), seven_day: win(.quota[$pool + "-weekly"]?)}
     | with_entries(select(.value != null))) as $rl
  | {cwd: (.cwd // .workspace.current_dir // ""),
     workspace: (.workspace // {}),
     model: {display_name:
       (if ($eff | type) == "string"
           and ($name | ascii_downcase | endswith(" (" + ($eff | ascii_downcase) + ")"))
        then $name[:-($eff | length + 3)] else $name end)},
     context_window: {used_percentage: (.context_window.used_percentage // null)}}
  + (if ($eff | type) == "string" and $eff != "" then {effort: {level: $eff}} else {} end)
  + (if $rl == {} then {} else {rate_limits: $rl} end)
  + (if $hit == "" then {} else
       {cache_reading: ({hit_percentage: ($hit | tonumber)}
                        + (if $at == "" then {} else {last_call_at: ($at | tonumber)} end))} end)
' 2>/dev/null) || translated=''
[ -n "$translated" ] || translated='{}'

printf '%s' "$translated" \
  | STATUSLINE_PCT_DECIMALS=2 STATUSLINE_NO_RATE_FILE=1 bash "$statusline"
