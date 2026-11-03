#!/usr/bin/env bash
#
# checkpoint.sh — keep a session's working state across compaction.
#
# One Checkpoint note per session: ~/.claude/checkpoints/<session-id>.md. It
# holds two sections, each replaced on its own and each with its own timestamp:
#
#   Rich section     written by the agent on /checkpoint   (`rich`), or by a
#                    headless model run inside the PreCompact hook when it is
#                    missing or stale (`precompact`)
#   Safety snapshot  written by the PreCompact hook          (`precompact`)
#
# After a compaction the SessionStart hook (matcher "compact") puts the note
# back into context (`restore`).
#
# Usage:
#   checkpoint.sh precompact            PreCompact hook; hook JSON on stdin
#   checkpoint.sh restore               SessionStart hook; hook JSON on stdin
#   checkpoint.sh rich   [session-id]   Rich section body on stdin
#   checkpoint.sh path   [session-id]   print the note's path
#   checkpoint.sh delete [session-id]   delete the note
#
# [session-id] defaults to $CLAUDE_CODE_SESSION_ID, which the Bash tool sets.
#
# Note format: each section starts with a marker line that carries the number
# of lines that follow it, e.g.
#   <!-- checkpoint:snapshot lines=42 written=2026-10-21T12:00:00Z -->
# The parser skips a section by that count, so text inside a section — the
# user's messages are quoted verbatim — can never be read as a marker.
#
# Portability: bash 3.2 and BSD tools (macOS) as well as bash 5 and GNU tools.
# No mapfile, no `date -d`, no `sed -i`; jq features up to 1.6.
#
# A PreCompact hook that exits 2 BLOCKS the compaction, so `precompact` always
# exits 0 — whatever goes wrong, the compaction must still happen.

set -u

NOTES_DIR="$HOME/.claude/checkpoints"
KEEP_DAYS=14     # notes not touched for longer than this are deleted
STATUS_CAP=30    # git status lines kept in the snapshot
MESSAGES=10      # user messages kept verbatim

# Automatic Rich section, written at compaction by a headless `claude -p`.
# Every knob is an environment variable so a test (or the user) can change it.
AUTO_RICH="${CHECKPOINT_AUTO_RICH:-1}"              # 0 turns it off
RICH_BIN="${CHECKPOINT_CLAUDE_BIN:-claude}"
RICH_MODEL="${CHECKPOINT_RICH_MODEL:-opus}"
RICH_EFFORT="${CHECKPOINT_RICH_EFFORT:-xhigh}"
RICH_TIMEOUT="${CHECKPOINT_RICH_TIMEOUT:-240}"      # seconds; the hook's own timeout must be larger
RICH_FRESH_MIN="${CHECKPOINT_RICH_FRESH_MIN:-15}"   # a Rich section newer than this is kept as is
DIGEST_CHARS="${CHECKPOINT_DIGEST_CHARS:-300000}"   # tail of the transcript digest sent to the model

now_utc() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }

# A session id becomes a file name: allow only a safe alphabet.
valid_id() {
  case "$1" in
    '' | .* | *[!A-Za-z0-9._-]*) return 1 ;;   # no leading dot: temp files have one
  esac
  return 0
}

note_path() { printf '%s/%s.md\n' "$NOTES_DIR" "$1"; }

# Print one section's block (marker line + its lines) from a note, or nothing.
section() { # note-file rich|snapshot
  [ -f "$1" ] || return 0
  awk -v want="$2" '
    skip > 0 { if (keep) print; skip--; next }
    /^<!-- checkpoint:(rich|snapshot) lines=[0-9]+( written=[^ ]*)? -->$/ {
      name = $0; sub(/^<!-- checkpoint:/, "", name); sub(/ .*$/, "", name)
      n = $0;    sub(/^.* lines=/, "", n);           sub(/[^0-9].*$/, "", n)
      keep = (name == want); skip = n + 0
      if (keep) print
      next
    }
  ' "$1"
}

# Print only a section's lines (no marker), or nothing.
section_lines() { # note-file rich|snapshot
  section "$1" "$2" | tail -n +2
}

# The "written=" value of a section's marker, or nothing.
written_at() { # note-file rich|snapshot
  section "$1" "$2" | head -1 | sed -n 's/^.* written=\([^ ]*\) -->$/\1/p'
}

# Print a block: the marker line, then the body file. The line count in the
# marker is taken from the body file at the moment it is written, so it always
# equals the lines that follow — never a number carried over from an older note.
emit_block() { # name body-file [written]
  local n
  # A body without a final newline would be counted one line short.
  if [ -s "$2" ] && [ -n "$(tail -c 1 "$2")" ]; then printf '\n' >> "$2"; fi
  n=$(wc -l < "$2" | tr -d ' ')
  if [ -n "${3:-}" ]; then
    printf '<!-- checkpoint:%s lines=%s written=%s -->\n' "$1" "$n" "$3"
  else
    printf '<!-- checkpoint:%s lines=%s -->\n' "$1" "$n"
  fi
  cat "$2"
}

# Fill a body file with the stand-in for a section not written yet.
placeholder_body() { # rich|snapshot body-file
  if [ "$1" = rich ]; then
    printf '## Rich section\n\n_Not written yet: the agent writes it on /checkpoint._\n' > "$2"
  else
    printf '## Safety snapshot\n\n_Not written yet: it is written before every compaction._\n' > "$2"
  fi
}

# Replace one section of a session's note with a new body, keeping the other
# section's lines and timestamp. Both markers are rebuilt from the bytes that
# are written. Atomic: the new note is written next to the old one and moved
# over it.
replace_section() { # session-id rich|snapshot new-body-file
  local note other tmp kept kept_at name rc
  note=$(note_path "$1")
  if [ "$2" = rich ]; then other=snapshot; else other=rich; fi
  mkdir -p "$NOTES_DIR" || return 1
  tmp=$(mktemp "$NOTES_DIR/.$1.XXXXXX") || return 1
  kept=$(mktemp "${TMPDIR:-/tmp}/checkpoint-kept.XXXXXX") || { rm -f "$tmp"; return 1; }
  # Lines go file to file: a $(…) capture would drop trailing blank lines.
  if [ -n "$(section "$note" "$other" | head -1)" ]; then
    section_lines "$note" "$other" > "$kept"
    kept_at=$(written_at "$note" "$other")
  else
    placeholder_body "$other" "$kept"
    kept_at=""
  fi
  {
    printf '# Checkpoint note — %s\n\n' "$1"
    for name in rich snapshot; do
      if [ "$name" = "$2" ]; then
        emit_block "$name" "$3" "$(now_utc)"
      else
        emit_block "$name" "$kept" "$kept_at"
      fi
      if [ "$name" = rich ]; then printf '\n'; fi
    done
  } > "$tmp" && mv -f "$tmp" "$note"
  rc=$?
  rm -f "$tmp" "$kept"
  return $rc
}

# The user's last N messages from a transcript, as Markdown. Real user prompts
# only: entries a human typed (origin.kind == "human") — sent at a turn's start
# (type "user") or typed mid-turn and queued (a "queued_command" attachment).
# That drops tool results, isMeta and hook-injected entries, task notifications,
# subagent hand-backs, compact summaries and command-output wrappers. Lines
# that are not valid JSON (a line still being written) are skipped.
user_messages() { # transcript
  jq -cR '
    def tx:
      if type == "string" then {t: ., i: 0}
      elif type == "array" then
        {t: ([.[] | select(.type? == "text") | .text] | join("\n\n")),
         i: ([.[] | select(.type? == "image")] | length)}
      else {t: "", i: 0} end;
    fromjson? | objects
    | select((.isSidechain // false) | not)
    | if .type == "user"
         and ((.origin | objects | .kind) // "") == "human"
         and ((.isMeta // false) | not)
      then (.message.content | tx) + {ts: .timestamp}
      elif .type == "attachment"
         and ((.attachment | objects | .type) // "") == "queued_command"
         and ((.attachment.origin | objects | .kind) // "") == "human"
         and ((.attachment.isMeta // false) | not)
      then (.attachment.prompt | tx) + {ts: (.attachment.timestamp // .timestamp)}
      else empty end
    | select(.t != "" or .i > 0)
  ' "$1" 2>/dev/null | tail -n "$MESSAGES" | jq -rs '
    # A fence one backtick longer than the longest run inside the text, so the
    # text is quoted verbatim whatever it contains.
    def fence: ([scan("`+") | length] | max // 0) as $m
               | "`" * ([$m + 1, 3] | max);
    if length == 0 then "_No user messages found in the transcript._\n"
    else
      to_entries | map(
        (.value.t | fence) as $f
        | "#### \(.key + 1) · \(.value.ts // "no timestamp")\n\n"
          + (if .value.t != "" then "\($f)text\n\(.value.t)\n\($f)\n" else "" end)
          + (if .value.i > 0 then "\n_(+\(.value.i) image(s), not kept)_\n" else "" end)
      ) | join("\n")
    end
  '
}

git_block() { # cwd
  local branch status total
  if [ -z "$1" ] || [ ! -d "$1" ] \
     || ! git -C "$1" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf '_Not a git repository._\n'
    return 0
  fi
  branch=$(git -C "$1" symbolic-ref --short -q HEAD 2>/dev/null) \
    || branch="(detached at $(git -C "$1" rev-parse --short HEAD 2>/dev/null))"
  status=$(GIT_OPTIONAL_LOCKS=0 git -C "$1" status --short 2>/dev/null)
  if [ -n "$status" ]; then total=$(printf '%s\n' "$status" | wc -l | tr -d ' '); else total=0; fi
  printf -- '- Branch: `%s`\n' "$branch"
  if [ "$total" -eq 0 ]; then
    printf -- '- `git status --short`: clean\n'
  else
    if [ "$total" -gt "$STATUS_CAP" ]; then
      printf -- '- `git status --short` (first %s of %s lines):\n\n' "$STATUS_CAP" "$total"
    else
      printf -- '- `git status --short` (%s lines):\n\n' "$total"
    fi
    printf '~~~text\n%s\n~~~\n' "$(printf '%s\n' "$status" | head -n "$STATUS_CAP")"
  fi
  printf '\n- Last 3 commits:\n\n~~~text\n%s\n~~~\n' \
    "$(git -C "$1" log --oneline -3 2>/dev/null || echo '(no commits)')"
}

# A plain-text digest of the main conversation, for the model that writes the
# Rich section: what the user said, what the agent said and which tools it ran
# (inputs and results cut short). An earlier compaction's summary is kept, since
# it carries the state from before it. Subagent (sidechain) entries are dropped.
transcript_digest() { # transcript
  jq -rR '
    def cut($n): if length > $n then .[0:$n] + " …[cut]" else . end;
    def str: if type == "string" then .
             elif type == "array" then [.[] | select(.type? == "text") | .text] | join("\n")
             else tostring end;
    fromjson? | objects
    | select((.isSidechain // false) | not)
    | if .type == "user" and (.isCompactSummary // false) then
        "=== SUMMARY OF EARLIER CONVERSATION ===\n" + (.message.content | str)
      elif .type == "user" and ((.isMeta // false) | not) then
        .message.content
        | if type == "string" then "USER: " + cut(6000)
          elif type == "array" then
            .[] | if .type? == "text" then "USER: " + (.text | cut(6000))
                  elif .type? == "tool_result" then "RESULT: " + (.content | str | cut(800))
                  else empty end
          else empty end
      elif .type == "attachment"
         and ((.attachment | objects | .type) // "") == "queued_command" then
        "USER (typed mid-turn): " + (.attachment.prompt | str | cut(6000))
      elif .type == "assistant" then
        .message.content
        | if type == "array" then
            .[] | if .type? == "text" then "ASSISTANT: " + (.text | cut(6000))
                  elif .type? == "tool_use" then "TOOL " + .name + ": " + (.input | tostring | cut(500))
                  else empty end
          else empty end
      else empty end
  ' "$1" 2>/dev/null
}

# Seconds since a section was written, or nothing when it never was.
section_age() { # note-file rich|snapshot
  local at
  at=$(written_at "$1" "$2")
  [ -n "$at" ] || return 0
  jq -nr --arg at "$at" --argjson now "$(date -u +%s)" \
    '($now - ($at | fromdateiso8601)) | floor' 2>/dev/null
}

# One line per automatic run, so a missing Rich section can be explained.
rich_log() { # session-id message
  mkdir -p "$NOTES_DIR" 2>/dev/null || return 0
  printf '%s %s %s\n' "$(now_utc)" "$1" "$2" >> "$NOTES_DIR/auto-rich.log"
  # Keep the log short: the last 200 runs.
  if [ "$(wc -l < "$NOTES_DIR/auto-rich.log")" -gt 400 ]; then
    tail -n 200 "$NOTES_DIR/auto-rich.log" > "$NOTES_DIR/auto-rich.log.tmp" \
      && mv -f "$NOTES_DIR/auto-rich.log.tmp" "$NOTES_DIR/auto-rich.log"
  fi
}

# Write the Rich section with a headless model run, unless it is turned off,
# fresh enough already, or the run fails. Never fails the hook: on any problem
# the old Rich section (or the placeholder) stays, and the log says why.
auto_rich() { # session-id transcript cwd custom-instructions snapshot-body-file
  local sid="$1" tp="$2" cwd="$3" ci="$4" snap="$5"
  local note age work prompt out err pid watch rc started
  [ "$AUTO_RICH" = 1 ] || return 0
  note=$(note_path "$sid")
  age=$(section_age "$note" rich)
  if [ -n "$age" ] && [ "$age" -lt $((RICH_FRESH_MIN * 60)) ]; then
    rich_log "$sid" "skipped: Rich section is ${age}s old"
    return 0
  fi
  if ! command -v "$RICH_BIN" >/dev/null 2>&1; then
    rich_log "$sid" "skipped: $RICH_BIN not found"
    return 0
  fi
  if [ -z "$tp" ] || [ ! -f "$tp" ]; then
    rich_log "$sid" "skipped: transcript not found"
    return 0
  fi

  # The model runs in an empty directory, so no project CLAUDE.md is loaded.
  work=$(mktemp -d "${TMPDIR:-/tmp}/checkpoint-rich.XXXXXX") || return 0
  prompt="$work/prompt.md"; out="$work/out.md"; err="$work/err.txt"
  {
    cat <<'EOF'
You write the Rich section of a Checkpoint note for a Claude Code session that is
about to be compacted. After the compaction, the same agent reads this note to
continue the work exactly where it stopped. The compaction summary keeps the gist;
your note must keep what a summary loses: the exact next step, rejected options and
why, the user's corrections, failed attempts, and what is still running.

Rules:
- Use only facts from the material below. Where something cannot be known from it,
  write "not checked".
- Position is ONE line: the exact next step, concrete enough that a fresh agent can
  do it without asking (a command, a file and a function, or a question to put to
  the user). If the agent was waiting for the user's answer, say which question.
- Quote the user's corrections in their own words when they are short.
- Name rejected options under "Decisions and why", or they will be proposed again.
- Output ONLY the Markdown below, starting with the line "### Goal". No preamble.

### Goal
What the user wants at the end of this session, in one or two lines.

### Position
The exact next step, in one line.

### Unfinished work
- item — status (done / in progress / not started / blocked on …)

### Decisions and why
- decision — why; rejected: option — why not

### User's corrections this session
- what the user corrected, in their words where short

### Failed attempts
- what was tried — why it failed

### Live things
- Pull requests: number, URL, state
- Branches and worktrees: name, path
- Background processes: PID, command, what it is for
- Test and scratch directories: path

==================== MATERIAL ====================
EOF
    printf '\nWorking directory: %s\n' "$cwd"
    if [ -n "$ci" ]; then
      printf '\nThe user ran /compact with these instructions (give them priority):\n%s\n' "$ci"
    fi
    printf '\n----- Safety snapshot (git state and the last user messages) -----\n\n'
    cat "$snap"
    printf '\n----- Conversation digest (oldest first; long items cut) -----\n\n'
    transcript_digest "$tp" | tail -c "$DIGEST_CHARS"
  } > "$prompt"

  started=$(date -u +%s)
  # CHECKPOINT_INNER stops this script's own hooks from running inside the
  # model run; --setting-sources "" also skips every other hook and plugin.
  ( cd "$work" && exec env CHECKPOINT_INNER=1 "$RICH_BIN" -p \
      --model "$RICH_MODEL" --effort "$RICH_EFFORT" \
      --tools "" --setting-sources "" --strict-mcp-config \
      --disable-slash-commands --no-session-persistence \
      < "$prompt" > "$out" 2> "$err" ) &
  pid=$!
  # No `timeout` on stock macOS: a watcher kills the run when time is up.
  ( sleep "$RICH_TIMEOUT" & s=$!; trap 'kill $s 2>/dev/null; exit 0' TERM
    wait $s; kill -TERM "$pid" 2>/dev/null ) &
  watch=$!
  wait "$pid"; rc=$?
  kill -TERM "$watch" 2>/dev/null; wait "$watch" 2>/dev/null

  if [ $rc -ne 0 ]; then
    rich_log "$sid" "failed: exit $rc after $(( $(date -u +%s) - started ))s: $(head -c 300 "$err" | tr '\n' ' ')"
  elif ! grep -q '^### Position' "$out"; then
    rich_log "$sid" "failed: output has no '### Position' heading"
  else
    # Drop anything the model wrote before "### Goal".
    awk 'f || /^### Goal/ { f = 1; print }' "$out" > "$out.trim"
    { printf '_Written automatically at compaction by %s (effort %s) from the transcript; check it against reality._\n\n' \
        "$RICH_MODEL" "$RICH_EFFORT"
      cat "$out.trim"; } > "$out"
    if cmd_rich "$sid" < "$out" >/dev/null; then
      rich_log "$sid" "written in $(( $(date -u +%s) - started ))s"
    else
      rich_log "$sid" "failed: could not write the note"
    fi
  fi
  rm -rf "$work"
  return 0
}

cmd_precompact() {
  local input sid tp cwd trigger ci body
  input=$(cat)
  [ -z "${CHECKPOINT_INNER:-}" ] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  # A subagent's transcript carries its parent's session id: a snapshot taken
  # there would overwrite the parent's note.
  [ "$(printf '%s' "$input" | jq -r '.agent_id // empty' 2>/dev/null)" = "" ] || return 0
  sid=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
  valid_id "$sid" || return 0
  tp=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)
  cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
  trigger=$(printf '%s' "$input" | jq -r '.trigger // "unknown"' 2>/dev/null)
  # "/compact Keep: …" is not a human-origin transcript entry; its text arrives here.
  ci=$(printf '%s' "$input" | jq -r '.custom_instructions // empty' 2>/dev/null)

  body=$(mktemp "${TMPDIR:-/tmp}/checkpoint-body.XXXXXX") || return 0
  {
    printf '## Safety snapshot — %s\n\n' "$(now_utc)"
    printf 'Written mechanically before a compaction (trigger: %s), with no judgment.\n\n' "$trigger"
    printf -- '- Session: `%s`\n' "$sid"
    printf -- '- Working directory: `%s`\n' "$cwd"
    printf -- '- Transcript: `%s`\n' "$tp"
    if [ -n "$ci" ]; then
      printf -- '- Compaction instructions from the user (verbatim):\n\n'
      printf '%s' "$ci" | jq -Rrs '([scan("`+") | length] | max // 0) as $m
        | ("`" * ([$m + 1, 3] | max)) as $f | "\($f)text\n\(.)\n\($f)"'
    fi
    printf '\n### Git\n\n'
    git_block "$cwd"
    printf "\n### The user's last %s messages (verbatim, oldest first)\n\n" "$MESSAGES"
    if [ -n "$tp" ] && [ -f "$tp" ]; then
      user_messages "$tp"
    else
      printf '_Transcript not found._\n'
    fi
  } > "$body"
  replace_section "$sid" snapshot "$body"
  auto_rich "$sid" "$tp" "$cwd" "$ci" "$body"
  rm -f "$body"

  # Retention: no cron — every compaction sweeps notes untouched for 14+ days,
  # and temp files a killed write left behind (.<session-id>.XXXXXX) after a day.
  find "$NOTES_DIR" -maxdepth 1 -type f -name '*.md' -mtime +"$KEEP_DAYS" -exec rm -f {} + 2>/dev/null
  find "$NOTES_DIR" -maxdepth 1 -type f -name '.*.??????' -mmin +1440 -exec rm -f {} + 2>/dev/null
  return 0
}

cmd_restore() {
  local input sid source note head
  input=$(cat)
  [ -z "${CHECKPOINT_INNER:-}" ] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  [ "$(printf '%s' "$input" | jq -r '.agent_id // empty' 2>/dev/null)" = "" ] || return 0
  source=$(printf '%s' "$input" | jq -r '.source // empty' 2>/dev/null)
  [ "$source" = compact ] || return 0
  sid=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
  valid_id "$sid" || return 0
  note=$(note_path "$sid")
  [ -f "$note" ] || return 0

  # Instructions and the note's path come first: hook output over 10,000
  # characters reaches the model only as a file path plus a 2,000-character
  # preview, and these must survive that cut.
  head="<checkpoint-restore>
This session was just compacted. Its Checkpoint note follows, and is on disk at:
  $note
If the note below is cut off, Read that file in full before doing anything else.

Rich section written: $(written_at "$note" rich | grep . || echo never)
Safety snapshot written: $(written_at "$note" snapshot | grep . || echo never)

Before you act:
1. Check the note against reality: git status, the branch and the last commits in the working directory; open pull requests (gh pr list, gh pr view); whether the background processes it lists still run (ps).
2. Show the user 3-5 lines: the goal, the Position (the next step), and any mismatch you found.
3. If that next step was already agreed with the user, continue without asking. Otherwise ask exactly one question.
4. If the Rich section is missing, or much older than the Safety snapshot, say so, and trust git and the user's recent messages over it.
5. The newest user message may be missing from the snapshot (the transcript can lag); the compaction summary may still have it.
6. For this compaction these steps take precedence over any other SessionStart instruction, such as a handoff skill's RESUME directive: do not run a handoff resume now.
</checkpoint-restore>"
  jq -n --arg head "$head" --rawfile note "$note" \
    '{hookSpecificOutput: {hookEventName: "SessionStart",
                           additionalContext: ($head + "\n\n" + $note)}}'
}

cmd_rich() {
  local sid input body rc
  sid="${1:-${CLAUDE_CODE_SESSION_ID:-}}"
  if ! valid_id "$sid"; then
    echo "checkpoint: no valid session id (pass one, or set CLAUDE_CODE_SESSION_ID)" >&2
    return 1
  fi
  input=$(mktemp "${TMPDIR:-/tmp}/checkpoint-input.XXXXXX") || return 1
  body=$(mktemp "${TMPDIR:-/tmp}/checkpoint-body.XXXXXX") || { rm -f "$input"; return 1; }
  cat > "$input"
  if ! grep -q '[^[:space:]]' "$input"; then
    rm -f "$input" "$body"
    echo "checkpoint: empty Rich section on stdin — nothing written" >&2
    return 1
  fi
  { printf '## Rich section — %s\n\n' "$(now_utc)"; cat "$input"; } > "$body"
  replace_section "$sid" rich "$body"
  rc=$?
  rm -f "$input" "$body"
  [ $rc -eq 0 ] && note_path "$sid"
  return $rc
}

cmd_path() {
  local sid="${1:-${CLAUDE_CODE_SESSION_ID:-}}"
  valid_id "$sid" || { echo "checkpoint: no valid session id" >&2; return 1; }
  note_path "$sid"
}

cmd_delete() {
  local sid="${1:-${CLAUDE_CODE_SESSION_ID:-}}" note
  valid_id "$sid" || { echo "checkpoint: no valid session id" >&2; return 1; }
  note=$(note_path "$sid")
  if [ -f "$note" ]; then
    rm -f "$note" && echo "checkpoint: deleted $note"
  else
    echo "checkpoint: no note for this session ($note)"
  fi
}

case "${1:-}" in
  precompact) cmd_precompact; exit 0 ;;
  restore)    cmd_restore;    exit 0 ;;
  rich)       shift; cmd_rich "$@" ;;
  path)       shift; cmd_path "$@" ;;
  delete)     shift; cmd_delete "$@" ;;
  *)
    echo "usage: checkpoint.sh precompact|restore|rich|path|delete [session-id]" >&2
    exit 64 ;;
esac
