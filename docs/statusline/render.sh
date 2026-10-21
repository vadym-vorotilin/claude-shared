#!/usr/bin/env bash
#
# Regenerate the status line renders in this folder. Runs the real scripts
# under claude/ against fictional fixtures — a throwaway $HOME, a made-up
# "demo-app" repo, hand-built transcripts and a pinned clock — and turns their
# ANSI output into SVG with ansi2svg.py. Re-run after changing either script so
# the README never shows a line the code no longer draws.
#
# Usage:
#   docs/statusline/render.sh [out-dir]     # default: beside this script
#
# Requires bash, git, jq and python3.
set -euo pipefail

HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
REPO="$(cd -P "$HERE/../.." >/dev/null 2>&1 && pwd)"
SESSION="$REPO/claude/statusline-command.sh"
PANEL="$REPO/claude/subagent-statusline-command.sh"
OUT="${1:-$HERE}"
mkdir -p "$OUT"
OUT="$(cd -P "$OUT" && pwd)"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME"

# Fixed identity, dates and config, so commit ids — and so the renders — are
# the same on every machine.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=demo GIT_AUTHOR_EMAIL=demo@example.com
export GIT_COMMITTER_NAME=demo GIT_COMMITTER_EMAIL=demo@example.com
export GIT_AUTHOR_DATE="2026-01-01T00:00:00Z" GIT_COMMITTER_DATE="2026-01-01T00:00:00Z"

export STATUSLINE_NOW=1767229200              # 2026-01-01T01:00:00Z
iso() { jq -rn --argjson e "$(( STATUSLINE_NOW - $1 ))" '$e | todate'; } # seconds-ago -> ISO

svg() { python3 "$HERE/ansi2svg.py" > "$OUT/$1"; echo "wrote $OUT/$1" >&2; }

# ---- fixtures -------------------------------------------------------------

# demo-app: on main, two commits ahead of origin, one staged, three modified,
# one untracked. A linked worktree on fix/search, and one detached.
git init -q --bare -b main "$TMP/origin.git"
git clone -q "$TMP/origin.git" "$TMP/demo-app" 2>/dev/null
A="$TMP/demo-app"
mkdir -p "$A/src/components"
for f in a b c d; do echo "$f" > "$A/src/components/$f.txt"; done
git -C "$A" add -A && git -C "$A" commit -q -m init && git -C "$A" push -q -u origin main 2>/dev/null
git -C "$A" worktree add -q -b fix/search "$TMP/search-fix" 2>/dev/null
git -C "$A" worktree add -q --detach "$TMP/review" HEAD 2>/dev/null
echo e > "$A/src/components/e.txt"; git -C "$A" add -A; git -C "$A" commit -q -m e
echo f > "$A/src/components/f.txt"; git -C "$A" add -A; git -C "$A" commit -q -m f
echo g > "$A/src/components/g.txt"; git -C "$A" add "$A/src/components/g.txt"
for f in a b c; do echo changed >> "$A/src/components/$f.txt"; done
echo h > "$A/src/components/h.txt"
mkdir -p "$HOME/Documents/notes"

# The session's transcript: one assistant turn that wrote the 1-hour cache.
session_transcript() { # path seconds-ago
  jq -cn --arg t "$(iso "$2")" '{type:"assistant", timestamp:$t, message:{
    model:"claude-opus-5-5", usage:{input_tokens:1, cache_creation_input_tokens:9,
    cache_read_input_tokens:100, output_tokens:7,
    cache_creation:{ephemeral_5m_input_tokens:0, ephemeral_1h_input_tokens:9}}}}' > "$1"
}

# A subagent's transcript, beside the session's: a turn that read <tokens> of
# context and wrote the 5-minute cache, <seconds-ago> before now.
agent_transcript() { # session-path id model tokens seconds-ago
  local dir="${1%.jsonl}/subagents"
  mkdir -p "$dir"
  jq -cn --arg t "$(iso "$5")" --arg m "$3" --argjson tk "$4" '{type:"assistant",
    isSidechain:true, timestamp:$t, message:{model:$m, usage:{input_tokens:1,
    cache_creation_input_tokens:1, cache_read_input_tokens:($tk - 2), output_tokens:7,
    cache_creation:{ephemeral_5m_input_tokens:1, ephemeral_1h_input_tokens:0}}}}' \
    > "$dir/agent-$2.jsonl"
}

# Session line input: cwd, model, effort, context %, transcript, quotas.
session_json() { # cwd effort ctx% transcript [5h% 5h-reset-in 1w% 1w-reset-in]
  jq -n --arg c "$1" --arg e "$2" --argjson u "$3" --arg tp "$4" \
        --arg f "${5:-}" --arg fr "${6:-}" --arg w "${7:-}" --arg wr "${8:-}" \
        --argjson now "$STATUSLINE_NOW" '
    {session_id:"demo-session", cwd:$c, transcript_path:$tp,
     model:{display_name:"Opus 5.5"}, context_window:{used_percentage:$u}}
    + (if $e == "" then {} else {effort:{level:$e}} end)
    + (if $f == "" then {} else {rate_limits:{
         five_hour:{used_percentage:($f|tonumber), resets_at:($now + ($fr|tonumber))},
         seven_day:{used_percentage:($w|tonumber), resets_at:($now + ($wr|tonumber))}}} end)'
}
session() { session_json "$@" | bash "$SESSION"; }
line() { sed -n "${1}p"; }

TP="$TMP/projects/demo/demo-session.jsonl"
mkdir -p "${TP%/*}"

# ---- the session line -----------------------------------------------------

session_transcript "$TP" 1200                 # 20 minutes into the hour
session "$A" high 22 "$TP" 42 7980 18 277200 | svg session.svg

{
  session "$TMP/search-fix" high 22 "$TP" | line 1
  session "$A" high 22 "$TP" | line 1
  session "$A/src/components" high 22 "$TP" | line 1
  session "$TMP/review" high 22 "$TP" | line 1
  session "$HOME/Documents/notes" high 22 "$TP" | line 1
} | svg location.svg

for e in low medium high xhigh max; do
  session "$A" "$e" 22 "$TP" | line 2
done | svg effort.svg

{
  session_transcript "$TP" 1200; session "$A" high 22 "$TP" | line 2
  session_transcript "$TP" 3000; session "$A" high 22 "$TP" | line 2
  session_transcript "$TP" 4200; session "$A" high 22 "$TP" | line 2
} | svg ttl.svg

# ---- the agent panel ------------------------------------------------------

# The session ran at high, which the session line has now recorded for
# agents whose definition sets no effort of their own.
agent_transcript "$TP" a1 claude-opus-5-5 220000 30
agent_transcript "$TP" a2 claude-sonnet-5 120000 280
agent_transcript "$TP" a4 claude-haiku-4-5-20251001 40000 9
agent_transcript "$TP" a5 claude-sonnet-5 64000 150

panel_json() { # columns
  jq -n --arg tp "$TP" --argjson c "$1" '{session_id:"demo-session",
    transcript_path:$tp, columns:$c, tasks:[
    {id:"a1", agentType:"Explore", status:"running", model:"claude-opus-5-5",
     contextWindowSize:1000000, label:"Finding where the TTL is computed", startTime:1},
    {id:"a2", name:"builder", agentType:"general-purpose", status:"running",
     model:"claude-sonnet-5", effort:"medium", contextWindowSize:1000000,
     label:"Waiting on the test suite", startTime:2},
    {id:"a3", name:"reviewer", agentType:"code-reviewer", status:"running",
     model:"claude-opus-5-5", effort:"xhigh", contextWindowSize:1000000,
     description:"Review the diff", startTime:3},
    {id:"a4", agentType:"Explore", status:"completed", model:"claude-haiku-4-5-20251001",
     effort:"low", contextWindowSize:1000000, label:"Listing callers", startTime:4},
    {id:"a5", agentType:"plugin:migrator", status:"failed", model:"claude-sonnet-5",
     effort:"max", contextWindowSize:1000000, label:"Schema migration dry run", startTime:5}]}'
}
panel() { panel_json "$1" | bash "$PANEL" | jq -r '.content'; }

panel 100 | svg panel.svg
panel 46 | svg panel-narrow.svg
