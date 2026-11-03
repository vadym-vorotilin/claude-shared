#!/usr/bin/env bats
#
# claude/checkpoint.sh — the Checkpoint note kept across compaction.
#
#   precompact  PreCompact hook: writes the Safety snapshot
#   restore     SessionStart hook (matcher "compact"): injects the note
#   rich        /checkpoint: writes the Rich section
#   delete      removes the session's note
#
# Every transcript here is synthetic JSONL shaped like Claude Code 2.1.306's.

load 'helpers/setup'
load 'helpers/extract'

setup() {
  common_setup
  SID="11111111-2222-3333-4444-555555555555"
  NOTE="$HOME/.claude/checkpoints/$SID.md"
  TR="$TEST_TMP/transcript.jsonl"
  : > "$TR"
  WORK="$TEST_TMP/work"
  mkdir -p "$WORK"
  # Never call a real model: the automatic Rich section is off unless a test
  # turns it on with a stub `claude`.
  export CHECKPOINT_AUTO_RICH=0
}
teardown() { common_teardown; }

# A stub `claude` for the automatic Rich section. It saves its arguments and
# stdin, then behaves as $STUB_MODE says.
stub_claude() { # ok|fail|nopos|slow
  STUB="$TEST_TMP/stub-claude"
  cat > "$STUB" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$TEST_TMP/stub-args"
cat > "$TEST_TMP/stub-stdin"
printf '%s' "\${CHECKPOINT_INNER:-}" > "$TEST_TMP/stub-inner"
case "$1" in
  ok)    printf 'Here is the note.\n\n### Goal\nShip it.\n\n### Position\nRun the tests.\n' ;;
  nopos) printf 'Sorry, I cannot.\n' ;;
  fail)  echo "stub error" >&2; exit 3 ;;
  slow)  sleep 30 ;;
esac
EOF
  chmod +x "$STUB"
  export CHECKPOINT_AUTO_RICH=1 CHECKPOINT_CLAUDE_BIN="$STUB"
}

CP() { bash "$REPO/claude/checkpoint.sh" "$@"; }

# ---- transcript builders (one JSONL line each) ----------------------------

human() { # text [timestamp]
  jq -nc --arg t "$1" --arg ts "${2:-2026-10-21T10:00:00.000Z}" \
    '{type:"user", origin:{kind:"human"}, timestamp:$ts, isSidechain:false,
      message:{role:"user", content:$t}}' >> "$TR"
}
queued() { # text — typed while the agent was working: only an attachment
  jq -nc --arg t "$1" \
    '{type:"attachment", timestamp:"2026-10-21T10:05:00.000Z",
      attachment:{type:"queued_command", commandMode:"prompt", prompt:$t,
                  origin:{kind:"human"}, timestamp:"2026-10-21T10:05:00.000Z"}}' >> "$TR"
}
noise() { # every kind of user-typed-looking entry that is NOT a user prompt
  {
    jq -nc '{type:"user", timestamp:"t", toolUseResult:{},
             message:{content:[{type:"tool_result", tool_use_id:"x", content:"NOISE-tool-result"}]}}'
    jq -nc '{type:"user", isMeta:true, timestamp:"t", message:{content:[{type:"text", text:"NOISE-meta"}]}}'
    jq -nc '{type:"user", isMeta:true, origin:{kind:"human"}, timestamp:"t", message:{content:"NOISE-meta-human"}}'
    jq -nc '{type:"attachment", attachment:{type:"queued_command", commandMode:"prompt", isMeta:true,
             prompt:"NOISE-queued-meta", origin:{kind:"human"}}}'
    jq -nc '{type:"user", timestamp:"t", message:{content:"<task-notification>NOISE-task</task-notification>"}}'
    jq -nc '{type:"user", isCompactSummary:true, timestamp:"t", message:{content:"NOISE-compact-summary"}}'
    jq -nc '{type:"user", isMeta:true, origin:{kind:"peer"}, timestamp:"t", message:{content:"NOISE-handback"}}'
    jq -nc '{type:"user", timestamp:"t", message:{content:"<local-command-stdout>NOISE-stdout</local-command-stdout>"}}'
    jq -nc '{type:"user", timestamp:"t", message:{content:"/compact NOISE-compact-command"}}'
    jq -nc '{type:"user", origin:{kind:"human"}, isSidechain:true, timestamp:"t", message:{content:"NOISE-sidechain"}}'
    jq -nc '{type:"attachment", attachment:{type:"queued_command", commandMode:"task-notification",
             prompt:"NOISE-queued-task", origin:{kind:"task-notification"}}}'
    jq -nc '{type:"attachment", attachment:{type:"hook_additional_context", content:["NOISE-hook"]}}'
    jq -nc '{type:"assistant", message:{content:[{type:"text", text:"NOISE-assistant"}]}}'
    printf '{"type":"user","origin":{"kind":"human"},"message":{"content":"NOISE-half-writ\n'
  } >> "$TR"
}

stdin_json() { # [extra fields, as a jq object literal]
  local extra="${1:-}"
  [ -n "$extra" ] || extra='{}'
  jq -nc --arg s "$SID" --arg tp "$TR" --arg cwd "$WORK" \
    "{session_id:\$s, transcript_path:\$tp, cwd:\$cwd, hook_event_name:\"PreCompact\",
      trigger:\"manual\", custom_instructions:null} + $extra"
}
precompact() { stdin_json "${1:-}" | CP precompact; }

restore() { # source [session-id]
  jq -nc --arg s "${2:-$SID}" --arg src "$1" --arg tp "$TR" --arg cwd "$WORK" \
    '{session_id:$s, transcript_path:$tp, cwd:$cwd, hook_event_name:"SessionStart", source:$src}' \
    | CP restore
}

# The lines of one section of the note, marker excluded.
section_body() { # rich|snapshot
  awk -v want="$1" '
    skip > 0 { if (keep) print; skip--; next }
    /^<!-- checkpoint:(rich|snapshot) lines=/ {
      n = $0; sub(/^.* lines=/, "", n); sub(/[^0-9].*$/, "", n)
      keep = index($0, "checkpoint:" want " ") > 0; skip = n + 0; next }
  ' "$NOTE"
}

# Set a file's mtime to N days ago (GNU or BSD date; local time, as touch -t).
age_days() { # file days
  local t=$(( $(date +%s) - $2 * 86400 )) stamp
  stamp=$(date -d "@$t" '+%Y%m%d%H%M.%S' 2>/dev/null || date -r "$t" '+%Y%m%d%H%M.%S')
  touch -t "$stamp" "$1"
}

# ------------------------------------------------------- SAFETY SNAPSHOT ----

@test "precompact writes the note with session, cwd, transcript, trigger and a timestamp" {
  human "hello"
  run precompact
  assert_equal "$status" 0
  assert_equal "$output" ""
  assert_file_exists "$NOTE"
  body="$(section_body snapshot)"
  assert_contains "$body" "Session: \`$SID\`"
  assert_contains "$body" "Working directory: \`$WORK\`"
  assert_contains "$body" "Transcript: \`$TR\`"
  assert_contains "$body" "trigger: manual"
  printf '%s\n' "$body" | grep -qE '^## Safety snapshot — [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$' \
    || fail "snapshot heading carries no UTC timestamp: $body"
  grep -qE '^<!-- checkpoint:snapshot lines=[0-9]+ written=[0-9T:Z-]+ -->$' "$NOTE" \
    || fail "no timestamped snapshot marker"
}

@test "snapshot keeps real user prompts, including queued ones, and skips everything else" {
  human "PROMPT-at-turn-start"
  noise
  queued "PROMPT-typed-mid-turn"
  precompact
  body="$(section_body snapshot)"
  assert_contains "$body" "PROMPT-at-turn-start"
  assert_contains "$body" "PROMPT-typed-mid-turn"
  refute_contains "$body" "NOISE"
}

@test "snapshot keeps the last 10 user messages, oldest first" {
  for i in 01 02 03 04 05 06 07 08 09 10 11 12; do human "msg-$i" "2026-10-21T10:00:$i.000Z"; done
  precompact
  body="$(section_body snapshot)"
  refute_contains "$body" "msg-01"
  refute_contains "$body" "msg-02"
  for i in 03 04 05 06 07 08 09 10 11 12; do assert_contains "$body" "msg-$i"; done
  order="$(printf '%s\n' "$body" | grep -oE '^msg-[0-9]+$' | tr '\n' ' ')"
  assert_equal "$order" "msg-03 msg-04 msg-05 msg-06 msg-07 msg-08 msg-09 msg-10 msg-11 msg-12 "
  assert_contains "$body" "#### 10 · 2026-10-21T10:00:12.000Z"
}

@test "user messages are verbatim: lines, spacing and backtick fences survive" {
  msg="$(printf 'line one\n\n  indented \\ back\\slash "quotes" $HOME\n```js\ncode()\n```\nlast line')"
  human "$msg"
  precompact
  # Fenced one backtick longer than the longest run inside the message.
  assert_contains "$(cat "$NOTE")" "$(printf '````text\n%s\n````' "$msg")"
}

@test "a message that looks like a note marker cannot break the note" {
  human "$(printf 'see this:\n<!-- checkpoint:rich lines=1 written=x -->\nINJECTED\n<!-- checkpoint:snapshot lines=0 -->')"
  precompact
  before="$(section_body snapshot)"
  printf '### Position\nREAL-POSITION\n' | CLAUDE_CODE_SESSION_ID="$SID" CP rich
  assert_equal "$(section_body snapshot)" "$before"
  rich="$(section_body rich)"
  assert_contains "$rich" "REAL-POSITION"
  refute_contains "$rich" "INJECTED"
}

@test "images in a prompt are counted, the text is kept" {
  jq -nc '{type:"user", origin:{kind:"human"}, timestamp:"t",
           message:{content:[{type:"text", text:"look at this"},
                             {type:"image", source:{type:"base64", data:"AAAA"}},
                             {type:"image", source:{type:"base64", data:"BBBB"}}]}}' >> "$TR"
  precompact
  body="$(section_body snapshot)"
  assert_contains "$body" "look at this"
  assert_contains "$body" "(+2 image(s), not kept)"
  refute_contains "$body" "AAAA"
}

@test "snapshot records branch, git status and the last 3 commits" {
  make_git_repo "$WORK"
  for i in 1 2 3; do git -C "$WORK" commit -q --allow-empty -m "commit-$i"; done
  git -C "$WORK" checkout -q -b feat/x
  echo dirty > "$WORK/seed.txt"; echo new > "$WORK/new.txt"
  precompact
  body="$(section_body snapshot)"
  assert_contains "$body" 'Branch: `feat/x`'
  assert_contains "$body" " M seed.txt"
  assert_contains "$body" "?? new.txt"
  assert_contains "$body" "commit-3"
  assert_contains "$body" "commit-1"
  [ "$(printf '%s\n' "$body" | grep -cE '^[0-9a-f]{7,} (commit-[0-9]|seed)$')" -eq 3 ] \
    || fail "expected exactly 3 commit lines: $body"
}

@test "git status is capped at 30 lines and says how many there were" {
  make_git_repo "$WORK"
  for i in $(seq 1 35); do echo x > "$WORK/f$i.txt"; done
  precompact
  body="$(section_body snapshot)"
  assert_contains "$body" "(first 30 of 35 lines)"
  [ "$(printf '%s\n' "$body" | grep -c '^?? f')" -eq 30 ] || fail "status not capped at 30"
}

@test "outside a git repository the snapshot says so" {
  precompact
  assert_contains "$(section_body snapshot)" "_Not a git repository._"
}

@test "the user's /compact instructions are kept verbatim" {
  precompact '{custom_instructions:"Keep: PR #12 and the `x` flag"}'
  assert_contains "$(section_body snapshot)" "$(printf '```text\nKeep: PR #12 and the `x` flag\n```')"
}

@test "precompact inside a subagent writes nothing (its transcript has the parent's id)" {
  human "parent prompt"
  run precompact '{agent_id:"a123", agent_type:"Explore"}'
  assert_equal "$status" 0
  [ ! -e "$NOTE" ] || fail "subagent wrote the parent's note"
}

@test "precompact never fails: bad id, missing transcript, garbage stdin" {
  run bash -c "printf '{\"session_id\":\"../evil\",\"transcript_path\":\"$TR\"}' | bash '$REPO/claude/checkpoint.sh' precompact"
  assert_equal "$status" 0
  [ ! -e "$HOME/.claude/evil.md" ] || fail "path traversal through the session id"
  run bash -c "printf 'not json' | bash '$REPO/claude/checkpoint.sh' precompact"
  assert_equal "$status" 0
  rm -f "$TR"
  run precompact
  assert_equal "$status" 0
  assert_contains "$(section_body snapshot)" "_Transcript not found._"
}

# ------------------------------------------------- TWO WRITERS, ONE FILE ----

@test "/checkpoint replaces only the Rich section; a compaction replaces only the snapshot" {
  human "FIRST-PROMPT"
  precompact
  printf '### Goal\nRICH-ONE\n' | CLAUDE_CODE_SESSION_ID="$SID" CP rich >/dev/null
  snap1="$(section_body snapshot)"
  assert_contains "$snap1" "FIRST-PROMPT"
  assert_contains "$(section_body rich)" "RICH-ONE"

  printf '### Goal\nRICH-TWO\n' | CLAUDE_CODE_SESSION_ID="$SID" CP rich >/dev/null
  assert_equal "$(section_body snapshot)" "$snap1"
  assert_contains "$(section_body rich)" "RICH-TWO"
  refute_contains "$(cat "$NOTE")" "RICH-ONE"

  rich2="$(section_body rich)"
  human "SECOND-PROMPT"
  precompact
  assert_equal "$(section_body rich)" "$rich2"
  assert_contains "$(section_body snapshot)" "SECOND-PROMPT"
  assert_equal "$(grep -c '^<!-- checkpoint:rich ' "$NOTE")" 1
  assert_equal "$(grep -c '^<!-- checkpoint:snapshot ' "$NOTE")" 1
  printf '%s\n' "$(section_body rich)" | grep -qE '^## Rich section — [0-9T:Z-]+$' \
    || fail "Rich section has no timestamp"
}

# Raw bytes of one section in the note, marker line included: rich runs up to
# the line before the snapshot marker, the snapshot to the end of the file.
# A plain scan, independent of the script's line-count parser; valid because
# these fixtures carry no marker-looking text.
region() { # rich|snapshot out-file
  if [ "$1" = rich ]; then
    awk '/^<!-- checkpoint:rich /{on=1} /^<!-- checkpoint:snapshot /{on=0} on' "$NOTE" > "$2"
  else
    awk '/^<!-- checkpoint:snapshot /{on=1} on' "$NOTE" > "$2"
  fi
}

# Every marker's lines=N equals the lines that really follow it.
counts_match() {
  awk '
    /^<!-- checkpoint:rich lines=/     { r = NR; rn = $0; sub(/^.* lines=/, "", rn); rn += 0 }
    /^<!-- checkpoint:snapshot lines=/ { s = NR; sn = $0; sub(/^.* lines=/, "", sn); sn += 0 }
    END {
      if (!r || !s) { print "missing marker"; exit 1 }
      if (s - r - 2 != rn) { print "rich says " rn ", has " s - r - 2; exit 1 }
      if (NR - s != sn)    { print "snapshot says " sn ", has " NR - s; exit 1 }
    }' "$NOTE" || fail "marker count does not match the note: $(cat "$NOTE")"
}

rich_with_blanks() { # trailing-blank-lines text
  { printf '### Goal\n%s\n' "$2"; i=0; while [ $i -lt "$1" ]; do printf '\n'; i=$((i+1)); done; } \
    | CLAUDE_CODE_SESSION_ID="$SID" CP rich >/dev/null
}

@test "a Rich section ending in blank lines keeps the snapshot through compaction and the next /checkpoint" {
  printf '### Goal\nG\n\n\n' | CLAUDE_CODE_SESSION_ID="$SID" CP rich >/dev/null
  human "KEEP-ME"
  precompact
  out="$(restore compact | jq -r .hookSpecificOutput.additionalContext)"
  refute_contains "$out" "Safety snapshot written: never"
  printf '### Goal\nG2\n' | CLAUDE_CODE_SESSION_ID="$SID" CP rich >/dev/null
  assert_contains "$(cat "$NOTE")" "KEEP-ME"
}

@test "a compaction leaves the Rich section byte-for-byte, with 0 to 3 trailing blank lines" {
  for k in 0 1 2 3; do
    rm -f "$NOTE"
    human "P$k"
    rich_with_blanks "$k" "RICH-$k"
    counts_match
    region rich "$TEST_TMP/before"
    precompact
    counts_match
    region rich "$TEST_TMP/after"
    cmp "$TEST_TMP/before" "$TEST_TMP/after" || fail "k=$k: Rich section changed: $(cat "$NOTE")"
    precompact
    region rich "$TEST_TMP/again"
    cmp "$TEST_TMP/before" "$TEST_TMP/again" || fail "k=$k: Rich section changed on the 2nd compaction"
  done
}

@test "/checkpoint leaves the Safety snapshot byte-for-byte, whatever the Rich section ends with" {
  for k in 0 1 2 3; do
    rm -f "$NOTE"
    human "P$k"
    precompact
    region snapshot "$TEST_TMP/before"
    rich_with_blanks "$k" "RICH-$k"
    counts_match
    region snapshot "$TEST_TMP/after"
    cmp "$TEST_TMP/before" "$TEST_TMP/after" || fail "k=$k: snapshot changed: $(cat "$NOTE")"
    rich_with_blanks "$k" "RICH-$k-again"
    counts_match
    region snapshot "$TEST_TMP/again"
    cmp "$TEST_TMP/before" "$TEST_TMP/again" || fail "k=$k: snapshot changed on the 2nd /checkpoint"
  done
}

@test "a Rich section written before any compaction gets a snapshot placeholder" {
  out="$(printf '### Goal\nG\n' | CLAUDE_CODE_SESSION_ID="$SID" CP rich)"
  assert_equal "$out" "$NOTE"
  assert_contains "$(section_body snapshot)" "Not written yet"
}

@test "rich refuses empty input and a missing session id" {
  run bash -c "printf '\n  \n' | CLAUDE_CODE_SESSION_ID=$SID bash '$REPO/claude/checkpoint.sh' rich"
  [ "$status" -ne 0 ] || fail "accepted an empty Rich section"
  [ ! -e "$NOTE" ] || fail "wrote a note for empty input"
  run bash -c "printf 'x\n' | env -u CLAUDE_CODE_SESSION_ID bash '$REPO/claude/checkpoint.sh' rich"
  [ "$status" -ne 0 ] || fail "accepted a missing session id"
}

# ---------------------------------------------------------------- RESTORE ----

@test "restore on compact injects the note as additionalContext" {
  human "THE-PROMPT"
  precompact
  printf '### Position\nTHE-NEXT-STEP\n' | CLAUDE_CODE_SESSION_ID="$SID" CP rich >/dev/null
  run restore compact
  assert_equal "$status" 0
  assert_equal "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.hookEventName')" "SessionStart"
  ctx="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')"
  assert_contains "$ctx" "THE-NEXT-STEP"
  assert_contains "$ctx" "THE-PROMPT"
  assert_contains "$ctx" "$(cat "$NOTE")"
}

@test "restore puts the instructions and the note path inside the first 2,000 characters" {
  # Over 10,000 characters the model sees only a 2,000-character preview.
  big="$(head -c 12000 /dev/zero | tr '\0' 'x')"
  human "$big"
  precompact
  run restore compact
  ctx="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')"
  [ "${#ctx}" -gt 10000 ] || fail "fixture should overflow the 10k cap"
  first="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext[0:2000]')"
  assert_contains "$first" "<checkpoint-restore>"
  assert_contains "$first" "$NOTE"
  assert_contains "$first" "</checkpoint-restore>"
  assert_contains "$first" "continue without asking"
  assert_contains "$first" "much older than the Safety snapshot"
  assert_contains "$first" "RESUME directive"
}

@test "restore reports each section's time, and 'never' for a missing one" {
  precompact
  ctx="$(restore compact | jq -r '.hookSpecificOutput.additionalContext')"
  assert_contains "$ctx" "Rich section written: never"
  printf '%s\n' "$ctx" | grep -qE '^Safety snapshot written: [0-9]{4}-[0-9T:-]+Z$' \
    || fail "no snapshot time in: $ctx"
}

@test "restore is silent on startup, resume, clear and fork" {
  precompact
  for src in startup resume clear fork ""; do
    run restore "$src"
    assert_equal "$status" 0
    assert_equal "$output" ""
  done
}

@test "restore is silent when there is no note, or the id is unsafe" {
  run restore compact
  assert_equal "$status" 0
  assert_equal "$output" ""
  run restore compact "../$SID"
  assert_equal "$status" 0
  assert_equal "$output" ""
}

# ---------------------------------------------------------------- CLEANUP ----

@test "a compaction deletes notes older than 14 days and keeps younger ones" {
  dir="$HOME/.claude/checkpoints"
  mkdir -p "$dir"
  echo old > "$dir/old-session.md";   age_days "$dir/old-session.md" 16
  echo young > "$dir/young-session.md"; age_days "$dir/young-session.md" 13
  precompact
  [ ! -e "$dir/old-session.md" ] || fail "16-day-old note survived"
  assert_file_exists "$dir/young-session.md"
  assert_file_exists "$NOTE"
}

@test "a compaction deletes temp files a killed write left behind, only in the notes dir" {
  dir="$HOME/.claude/checkpoints"
  mkdir -p "$dir/sub"
  echo t > "$dir/.$SID.Ab12Cd";      age_days "$dir/.$SID.Ab12Cd" 2
  echo t > "$dir/.$SID.Fresh1"                         # a write in progress right now
  echo t > "$HOME/.claude/.x.Ab12Cd"; age_days "$HOME/.claude/.x.Ab12Cd" 2
  echo t > "$dir/sub/.x.Ab12Cd";      age_days "$dir/sub/.x.Ab12Cd" 2
  precompact
  [ ! -e "$dir/.$SID.Ab12Cd" ] || fail "2-day-old temp file survived"
  assert_file_exists "$dir/.$SID.Fresh1"
  assert_file_exists "$HOME/.claude/.x.Ab12Cd"
  assert_file_exists "$dir/sub/.x.Ab12Cd"
  assert_file_exists "$NOTE"
}

# ------------------------------------------------- DOCUMENTED COMMAND BLOCKS ----

deploy_script() { mkdir -p "$HOME/.claude" && cp "$REPO/claude/checkpoint.sh" "$HOME/.claude/checkpoint.sh"; }

@test "/checkpoint's documented command writes every Rich heading and keeps the snapshot" {
  deploy_script
  human "KEPT-PROMPT"
  precompact
  block="$(extract_code_block "$REPO/skills/checkpoint/SKILL.md" "## Write the note" bash)"
  [ -n "$block" ] || fail "no bash block under '## Write the note'"
  CLAUDE_CODE_SESSION_ID="$SID" bash -c "$block" >/dev/null
  rich="$(section_body rich)"
  for h in "### Goal" "### Position" "### Unfinished work" "### Decisions and why" \
           "### User's corrections this session" "### Failed attempts" "### Live things"; do
    assert_contains "$rich" "$h"
  done
  assert_contains "$(section_body snapshot)" "KEPT-PROMPT"
}



# ----------------------------------------------- AUTOMATIC RICH SECTION ----

@test "auto rich: precompact writes the Rich section from a headless model run" {
  human "USER-SAID-THIS"
  jq -nc '{type:"assistant", message:{content:[{type:"text", text:"AGENT-SAID-THIS"},
           {type:"tool_use", name:"Bash", input:{command:"git status"}}]}}' >> "$TR"
  stub_claude ok
  run precompact '{custom_instructions:"keep the PR number"}'
  assert_equal "$status" 0
  assert_equal "$output" ""
  body="$(section_body rich)"
  assert_contains "$body" "### Position"
  assert_contains "$body" "Run the tests."
  assert_contains "$body" "Written automatically at compaction by opus (effort xhigh)"
  refute_contains "$body" "Here is the note."
  assert_contains "$(section_body snapshot)" "USER-SAID-THIS"
  args="$(cat "$TEST_TMP/stub-args")"
  assert_contains "$args" "$(printf -- '--model\nopus')"
  assert_contains "$args" "$(printf -- '--effort\nxhigh')"
  assert_contains "$args" "$(printf -- '--tools\n\n')"
  assert_contains "$args" "--setting-sources"
  stdin="$(cat "$TEST_TMP/stub-stdin")"
  assert_contains "$stdin" "USER: USER-SAID-THIS"
  assert_contains "$stdin" "ASSISTANT: AGENT-SAID-THIS"
  assert_contains "$stdin" "TOOL Bash:"
  assert_contains "$stdin" "keep the PR number"
  assert_equal "$(cat "$TEST_TMP/stub-inner")" "1"
  grep -q "$SID written in" "$HOME/.claude/checkpoints/auto-rich.log" || fail "no log line"
}

@test "auto rich: model and effort come from the environment" {
  human "hi"
  stub_claude ok
  CHECKPOINT_RICH_MODEL=sonnet CHECKPOINT_RICH_EFFORT=high precompact
  args="$(cat "$TEST_TMP/stub-args")"
  assert_contains "$args" "$(printf -- '--model\nsonnet')"
  assert_contains "$args" "$(printf -- '--effort\nhigh')"
}

@test "auto rich: a fresh Rich section written by /checkpoint is kept and no model runs" {
  human "hi"
  printf '### Goal\nHAND-WRITTEN\n' | CP rich "$SID" >/dev/null
  stub_claude ok
  precompact
  assert_contains "$(section_body rich)" "HAND-WRITTEN"
  [ ! -e "$TEST_TMP/stub-args" ] || fail "model ran although the Rich section was fresh"
  grep -q "skipped: Rich section is" "$HOME/.claude/checkpoints/auto-rich.log" || fail "no skip logged"
}

@test "auto rich: a stale Rich section is replaced" {
  human "hi"
  printf '### Goal\nOLD\n' | CP rich "$SID" >/dev/null
  stub_claude ok
  CHECKPOINT_RICH_FRESH_MIN=0 precompact
  body="$(section_body rich)"
  refute_contains "$body" "OLD"
  assert_contains "$body" "Run the tests."
}

@test "auto rich: a failing model run keeps the old section, logs why, and exits 0" {
  human "hi"
  stub_claude fail
  run precompact
  assert_equal "$status" 0
  assert_contains "$(section_body rich)" "Not written yet"
  assert_contains "$(section_body snapshot)" "Safety snapshot"
  grep -q "failed: exit 3.*stub error" "$HOME/.claude/checkpoints/auto-rich.log" || fail "no failure logged"
}

@test "auto rich: output without a Position heading is rejected" {
  human "hi"
  stub_claude nopos
  precompact
  assert_contains "$(section_body rich)" "Not written yet"
  grep -q "no '### Position' heading" "$HOME/.claude/checkpoints/auto-rich.log" || fail "no rejection logged"
}

@test "auto rich: a model run past the time limit is stopped and the hook still finishes" {
  human "hi"
  stub_claude slow
  start=$(date +%s)
  CHECKPOINT_RICH_TIMEOUT=1 precompact
  [ $(( $(date +%s) - start )) -lt 10 ] || fail "hook waited for the slow model"
  assert_contains "$(section_body rich)" "Not written yet"
  assert_contains "$(section_body snapshot)" "Safety snapshot"
}

@test "auto rich: a missing claude binary is skipped quietly" {
  human "hi"
  export CHECKPOINT_AUTO_RICH=1 CHECKPOINT_CLAUDE_BIN="$TEST_TMP/no-such-claude"
  run precompact
  assert_equal "$status" 0
  grep -q "skipped: .* not found" "$HOME/.claude/checkpoints/auto-rich.log" || fail "no skip logged"
}

@test "inside the model run (CHECKPOINT_INNER) precompact and restore do nothing" {
  human "hi"
  CHECKPOINT_INNER=1 precompact
  [ ! -e "$NOTE" ] || fail "precompact wrote a note inside the model run"
  precompact
  run env CHECKPOINT_INNER=1 bash -c "$(declare -f restore CP); REPO='$REPO' TR='$TR' WORK='$WORK' SID='$SID'; restore compact"
  assert_equal "$output" ""
}
