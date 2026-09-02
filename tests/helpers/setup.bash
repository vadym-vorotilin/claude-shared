# Common setup/teardown + assertion helpers, loaded by every .bats file.
#
# Isolation: each test gets a throwaway $HOME under a fresh temp dir, so
# sync.sh deploys into a sandbox ~/.claude and never touches the real one.

# Repo under test. Mounted read-only at /repo inside the container.
: "${REPO_ROOT:=/repo}"

common_setup() {
  TEST_TMP="$(mktemp -d)"
  export TEST_TMP
  export HOME="$TEST_TMP/home"
  mkdir -p "$HOME"
  export REPO="$REPO_ROOT"
}

common_teardown() {
  [ -n "${TEST_TMP:-}" ] && rm -rf "$TEST_TMP"
}

# ---- assertions ----------------------------------------------------------

fail() { echo "ASSERT FAILED: $*" >&2; return 1; }

assert_equal() { # actual expected
  [ "$1" = "$2" ] || fail "expected [$2] but got [$1]"
}

assert_contains() { # haystack needle
  case "$1" in
    *"$2"*) : ;;
    *) fail "expected output to contain [$2]; got: $1" ;;
  esac
}

refute_contains() { # haystack needle
  case "$1" in
    *"$2"*) fail "expected output NOT to contain [$2]; got: $1" ;;
    *) : ;;
  esac
}

assert_file_exists() { [ -e "$1" ] || fail "missing file: $1"; }
assert_symlink()     { [ -L "$1" ] || fail "not a symlink: $1"; }
assert_executable()  { [ -x "$1" ] || fail "not executable: $1"; }

# Count occurrences of a fixed string across a file.
count_occurrences() { # file needle
  grep -cF -- "$2" "$1" 2>/dev/null || true
}

# ---- fixture builders ----------------------------------------------------

# Initialize a git repo at $1 with one commit on branch main.
make_git_repo() { # dir
  local d="$1"
  mkdir -p "$d"
  git -C "$d" init -q -b main
  echo "seed" > "$d/seed.txt"
  git -C "$d" add seed.txt
  git -C "$d" commit -q -m "seed"
}

# Initialize $1 as a clone of a fresh bare upstream, returning a repo whose
# branch tracks origin/main. Used for ahead/behind statusline tests.
make_git_repo_with_upstream() { # workdir
  local work="$1"
  local bare="$TEST_TMP/upstream.git"
  git init -q --bare -b main "$bare"
  git clone -q "$bare" "$work"
  echo "seed" > "$work/seed.txt"
  git -C "$work" add seed.txt
  git -C "$work" commit -q -m "seed"
  git -C "$work" push -q -u origin main
}

# Create a subagent transcript where Claude Code writes them: beside the
# session transcript, under <session-id>/subagents/. An empty model argument
# fixtures an agent that hasn't taken a turn yet.
make_subagent() { # transcript-path id agent-type [model-id] [input-tokens] [spawn-depth]
  local tp="$1" id="$2" type="$3" model="${4:-}" tokens="${5:-0}" depth="${6:-1}"
  local dir="${tp%.jsonl}/subagents"
  mkdir -p "$dir"
  jq -cn --arg t "$type" --argjson d "$depth" \
    '{agentType:$t, description:"fixture", toolUseId:"toolu_fixture", spawnDepth:$d, model:"haiku"}' \
    > "$dir/agent-$id.meta.json"
  jq -cn '{type:"user", isSidechain:true, timestamp:"2026-01-01T00:00:00.000Z",
           message:{role:"user", content:"go"}}' \
    > "$dir/agent-$id.jsonl"
  [ -n "$model" ] || return 0
  jq -cn --arg m "$model" --argjson tk "$tokens" \
    '{type:"assistant", isSidechain:true, timestamp:"2026-01-01T00:00:10.000Z",
      message:{model:$m, usage:{
       input_tokens:1, cache_creation_input_tokens:0,
       cache_read_input_tokens:($tk-1), output_tokens:7}}}' \
    >> "$dir/agent-$id.jsonl"
}

# Append the line a session writes when it collects a tool's output: a user
# entry carrying toolUseResult. Naming an agent's id in one, at a timestamp
# after that agent's own last entry, is what means "finished".
make_session_ref() { # transcript-path agent-id iso-timestamp
  jq -cn --arg a "$2" --arg t "$3" \
    '{type:"user", timestamp:$t, toolUseResult:{agentId:$a, status:"completed"},
      message:{role:"user",
               content:[{type:"tool_result", tool_use_id:"toolu_fixture",
                         content:"agent \($a) finished"}]}}' \
    >> "$1"
}

# Append the notification a session receives when a background agent reports
# its task complete. Its tool result landed back at spawn, so this is the only
# entry that says it has finished.
make_session_notify() { # transcript-path agent-id iso-timestamp
  jq -cn --arg a "$2" --arg t "$3" \
    '{type:"user", timestamp:$t, origin:{kind:"task-notification"},
      promptSource:"system", userType:"external",
      message:{role:"user", content:"<task-notification>agent \($a) done</task-notification>"}}' \
    >> "$1"
}

# Append the entries a session writes when it queues a message for an agent
# that is already running. They name the agent and carry no result.
make_session_queue() { # transcript-path agent-id iso-timestamp
  jq -cn --arg a "$2" --arg t "$3" \
    '{type:"queue-operation", timestamp:$t, operation:"add",
      content:"message for agent \($a)"}' >> "$1"
  jq -cn --arg a "$2" --arg t "$3" \
    '{type:"attachment", timestamp:$t, attachment:{agentId:$a}}' >> "$1"
}
