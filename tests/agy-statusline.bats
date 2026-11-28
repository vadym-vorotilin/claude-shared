#!/usr/bin/env bats
#
# agy-statusline.sh — translates agy's status-line JSON for statusline-command.sh.

load 'helpers/setup'

setup() {
  common_setup
  export STATUSLINE_NOW=1767225600            # 2026-01-01T00:00:00Z
}
teardown() { common_teardown; }

# The payload shape agy sends, with invented values.
agy_json() {
  jq -n '{
    cwd: "/tmp/proj", session_id: "", conversation_id: "",
    transcript_path: "/nonexistent/transcript.jsonl",
    model: {id: "Gemini 9 Demo (Medium)", display_name: "Gemini 9 Demo (Medium)", effort: "medium"},
    workspace: {current_dir: "/tmp/proj", project_dir: "/tmp/proj"},
    context_window: {used_percentage: 12.3456, context_window_size: 1048576},
    product: "antigravity",
    quota: {
      "3p-5h":        {remaining_fraction: 1,         reset_time: "1970-01-01T00:00:00Z", reset_in_seconds: 0},
      "3p-weekly":    {remaining_fraction: 0.5,       reset_time: "1970-01-01T00:00:00Z", reset_in_seconds: 0},
      "gemini-5h":    {remaining_fraction: 0.8,       reset_time: "2026-01-01T02:30:00Z", reset_in_seconds: 9000},
      "gemini-weekly":{remaining_fraction: 0.6875, reset_time: "2026-01-04T00:00:00Z", reset_in_seconds: 259200}
    }
  }' | jq -c "${1:-.}"
}

agy_line() { agy_json "${1:-.}" | bash "$REPO/agy/agy-statusline.sh" | sed $'s/\033\\[[0-9;]*m//g'; }

@test "shows the Gemini quota windows as used percent with 2 decimals and countdowns" {
  out="$(agy_line)"
  assert_contains "$out" "5h: 20.00% (-2h 30m)"
  assert_contains "$out" "1w: 31.25% (-3d 0h)"
}

@test "shows the context window with 2 decimals" {
  assert_contains "$(agy_line)" "ctx: 12.35%"
}

@test "moves the effort into its own segment and drops it from the model name" {
  assert_contains "$(agy_line)" "Gemini 9 Demo | medium ▃ | ctx:"
}

@test "keeps a parenthesis that is not the effort in the model name" {
  assert_contains "$(agy_line '.model.display_name = "Gemini 9 (Preview)"')" "Gemini 9 (Preview) | medium"
}

@test "a third-party model reads the third-party quota pool" {
  out="$(agy_line '.model = {display_name: "Claude Demo 9 (Thinking)", effort: "high"}')"
  assert_contains "$out" "5h: 0.00%"
  assert_contains "$out" "1w: 50.00%"
  refute_contains "$out" "(-"
}

@test "Orchestrator, which plans with a Gemini model, reads the Gemini quota pool" {
  out="$(agy_line '.model = {id: "Orchestrator (Demo)", display_name: "Orchestrator (Demo)", effort: "medium"}')"
  assert_contains "$out" "5h: 20.00% (-2h 30m)"
  assert_contains "$out" "1w: 31.25% (-3d 0h)"
}

@test "Orchestrator reads the Gemini pool even with a third-party family in its name" {
  out="$(agy_line '.model = {display_name: "Orchestrator (Claude Demo)", effort: "medium"}')"
  assert_contains "$out" "5h: 20.00%"
  assert_contains "$out" "1w: 31.25%"
}

@test "a family word inside a longer word does not pick the third-party pool" {
  out="$(agy_line '.model = {display_name: "Demo Opusculum", effort: "medium"}')"
  assert_contains "$out" "5h: 20.00%"
  assert_contains "$out" "1w: 31.25%"
}

@test "falls back to reset_in_seconds when reset_time does not parse" {
  out="$(agy_line '.quota["gemini-5h"].reset_time = "soon"')"
  assert_contains "$out" "5h: 20.00% (-2h 30m)"
}

@test "omits the quota line when agy sends no quota" {
  out="$(agy_line 'del(.quota)')"
  refute_contains "$out" "5h:"
  refute_contains "$out" "1w:"
}

@test "never writes Claude's rate-limits.json" {
  agy_line >/dev/null
  [ ! -e "$XDG_STATE_HOME/claude/rate-limits.json" ] || fail "rate-limits.json was written"
}

@test "writes no effort record: agy has no Claude session id" {
  agy_line '.session_id = "abc"' >/dev/null
  [ -z "$(ls -A "$HOME/.claude/cache/statusline-session-effort" 2>/dev/null)" ] || fail "effort record written"
}

@test "input that is not JSON still prints a line and exits 0" {
  run bash -c "printf 'not json' | bash '$REPO/agy/agy-statusline.sh'"
  assert_equal "$status" 0
  assert_contains "$output" "⠀"
}

@test "the Claude line keeps whole percentages" {
  out="$(jq -n '{cwd:"/tmp", model:{display_name:"M"}, context_window:{used_percentage:41.6},
                 rate_limits:{five_hour:{used_percentage:20.5}}}' \
         | bash "$REPO/claude/statusline-command.sh" | sed $'s/\033\\[[0-9;]*m//g')"
  assert_contains "$out" "ctx: 42%"
  assert_contains "$out" "5h: 21%"
}

@test "STATUSLINE_PCT_DECIMALS pads short readings and ignores bad values" {
  json='{"cwd":"/tmp","model":{"display_name":"M"},"context_window":{"used_percentage":0.05}}'
  out="$(printf '%s' "$json" | STATUSLINE_PCT_DECIMALS=2 bash "$REPO/claude/statusline-command.sh" | sed $'s/\033\\[[0-9;]*m//g')"
  assert_contains "$out" "ctx: 0.05%"
  out="$(printf '%s' "$json" | STATUSLINE_PCT_DECIMALS=x bash "$REPO/claude/statusline-command.sh" | sed $'s/\033\\[[0-9;]*m//g')"
  assert_contains "$out" "ctx: 0%"
}

# ---- cache reading, from a fictional agy conversation database --------------

# make_conv <id> <step>... where a step is "fresh:cached[:finished-epoch|bad]" (a
# model call; a zero count is left out, as protobuf does, and "-" leaves fresh
# out), "other" (a step with no usage) or "junk" (metadata that is not protobuf).
make_conv() {
  export AGY_CONVERSATIONS_DIR="${CONV_DIR:-$TEST_TMP/convs}"; mkdir -p "$AGY_CONVERSATIONS_DIR"
  python3 -I - "$AGY_CONVERSATIONS_DIR/$1.db" "${@:2}" <<'PY'
import sqlite3, sys
def vi(n):
    out = b""
    while True:
        b = n & 0x7f; n >>= 7
        if n: out += bytes([b | 0x80])
        else: return out + bytes([b])
def num(f, v): return vi(f << 3) + vi(v) if v else b""
def sub(f, m): return vi(f << 3 | 2) + vi(len(m)) + m
db = sqlite3.connect(sys.argv[1])
db.execute("create table steps (idx integer primary key, step_type integer, metadata blob)")
for i, s in enumerate(sys.argv[2:]):
    if s == "other":  md = sub(1, num(1, 1767225000)) + num(3, 2)
    elif s == "junk": md = b"\xff\xff\xff"
    else:
        fresh, cached, *at = s.split(":")
        usage = num(1, 7) + (b"" if fresh == "-" else vi(2 << 3) + vi(int(fresh))) + num(3, 50) + num(5, int(cached))
        done = b"" if not at else sub(7, b"\xff") if at[0] == "bad" else sub(7, num(1, int(at[0])))
        md = sub(1, num(1, 1767225000)) + done + sub(9, usage)
    db.execute("insert into steps values (?, 15, ?)", (i, md))
db.commit()
PY
}

@test "cache: shows the last call's cache share with 2 decimals and how long ago it finished" {
  make_conv conv-1 "1000:0:1767225000" "2500:97500:1767225420" other
  out="$(agy_line '.conversation_id = "conv-1"')"
  assert_contains "$out" "ctx: 12.35% | cache: 97.50% (3m)"
  refute_contains "$out" "ago"
}

@test "cache: a call with no finish time shows the share alone" {
  make_conv conv-1b "2500:97500"
  out="$(agy_line '.conversation_id = "conv-1b"')"
  assert_contains "$out" "cache: 97.50%"
  refute_contains "$out" "97.50% ("
}

@test "cache: a finish-time field that does not parse drops only the time" {
  make_conv conv-1d "2500:97500:bad"
  out="$(agy_line '.conversation_id = "conv-1d"')"
  assert_contains "$out" "cache: 97.50%"
  refute_contains "$out" "97.50% ("
}

@test "cache: a finish time that is not a plausible epoch is dropped, the share kept" {
  make_conv conv-1c "2500:97500:12345"
  out="$(agy_line '.conversation_id = "conv-1c"')"
  assert_contains "$out" "cache: 97.50%"
  refute_contains "$out" "97.50% ("
}

@test "cache: steps that are not model calls are skipped" {
  make_conv conv-2 "100:300" other other
  assert_contains "$(agy_line '.conversation_id = "conv-2"')" "cache: 75.00%"
}

@test "cache: a newer step that does not parse shows nothing, not an older call" {
  make_conv conv-2b "100:300" junk other
  refute_contains "$(agy_line '.conversation_id = "conv-2b"')" "cache:"
}

@test "cache: a last call without its uncached count shows nothing, not 100%" {
  make_conv conv-2c "100:300" "-:500"
  refute_contains "$(agy_line '.conversation_id = "conv-2c"')" "cache:"
}

@test "cache: falls back to session_id when conversation_id is empty" {
  make_conv conv-3 "1:999"
  assert_contains "$(agy_line '.session_id = "conv-3"')" "cache: 99.90%"
}

@test "cache: no database, no segment" {
  export AGY_CONVERSATIONS_DIR="$TEST_TMP/none"
  out="$(agy_line '.conversation_id = "conv-x"')"
  refute_contains "$out" "cache:"
  assert_contains "$out" "ctx: 12.35%"
}

@test "cache: a database that is not agy's prints no segment and exits 0" {
  export AGY_CONVERSATIONS_DIR="$TEST_TMP/convs"; mkdir -p "$AGY_CONVERSATIONS_DIR"
  printf 'not sqlite' > "$AGY_CONVERSATIONS_DIR/conv-4.db"
  run bash -c "$(declare -f agy_json agy_line); REPO='$REPO' agy_line '.conversation_id = \"conv-4\"'"
  assert_equal "$status" 0
  refute_contains "$output" "cache:"
}

@test "cache: a conversation id with a path in it is never looked up" {
  make_conv conv-5 "1:1"
  mkdir -p "$TEST_TMP/convs/sub"; cp "$TEST_TMP/convs/conv-5.db" "$TEST_TMP/convs/sub/x.db"
  refute_contains "$(agy_line '.conversation_id = "sub/x"')" "cache:"
}

@test "cache: a ? in the folder path is read, read-only, and creates nothing" {
  CONV_DIR="$TEST_TMP/c?y" make_conv conv-7 "1:3"
  assert_contains "$(agy_line '.conversation_id = "conv-7"')" "cache: 75.00%"
  [ ! -e "$TEST_TMP/c" ] || fail "an empty database was created at the cut-off path"
}

@test "cache: statusline-command.sh draws cache_reading when there is no cache clock" {
  out="$(jq -n '{cwd:"/tmp", model:{display_name:"M"}, cache_reading:{hit_percentage:88.4, last_call_at:1767225540}}' \
         | bash "$REPO/claude/statusline-command.sh" | sed $'s/\033\\[[0-9;]*m//g')"
  assert_contains "$out" "M | cache: 88% (1m)"
}

@test "cache: a last call with nothing read from cache shows 0.00%, not an older call" {
  make_conv conv-6 "0:900" "1200:0"
  assert_contains "$(agy_line '.conversation_id = "conv-6"')" "cache: 0.00%"
}

@test "quota: a remaining fraction just over 1 reads 0.00%, never negative" {
  assert_contains "$(agy_line '.quota["gemini-5h"].remaining_fraction = 1.0000001')" "5h: 0.00%"
}

@test "STATUSLINE_PCT_DECIMALS holds readings to 0..1000000" {
  for v in -0.001 -5 1e20; do
    out="$(jq -n --argjson v "$v" '{cwd:"/tmp", model:{display_name:"M"}, context_window:{used_percentage:$v}}' \
           | STATUSLINE_PCT_DECIMALS=2 bash "$REPO/claude/statusline-command.sh" | sed $'s/\033\\[[0-9;]*m//g')"
    case "$v" in 1e20) want="ctx: 1000000.00%" ;; *) want="ctx: 0.00%" ;; esac
    assert_contains "$out" "$want"
  done
}
