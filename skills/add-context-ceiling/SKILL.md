---
name: add-context-ceiling
description: Install the context-ceiling hook into a project so every subagent dispatched there is told when its context passes the ceiling. Use when the user says "add the context ceiling to <repo>", "install the agent ceiling hook", or before a long multi-agent run in a project that does not have it yet.
---

# add-context-ceiling — install the ceiling hook into a project

The `context-ceiling` skill asks long-running agents to stop at ~150k and write
a checkpoint note. No agent can see its own context, so without this hook that
is a brief line only. The hook (`context-ceiling/hooks/agent-ceiling.py`) is a
`PreToolUse` hook: it reads the calling agent's transcript and, on the first
tool call past each threshold, blocks once with the ceiling message. It exempts
the main session, and it **fails open** — a bug in it must never halt a run.

## What this assumes — verify these, or the hook is a silent no-op

- **Subagent transcripts under a `subagents/` directory** beside the session's,
  the layout the CLI has written since 2.1. Where it differs, the hook never
  recognises an agent and returns 0 on every call: a gate that always passes.
- **The transcript directory is writable** — the hook records each crossing in
  a dot-file beside the transcript, and where it cannot, it stays silent rather
  than block again.
- **`python3` 3.9 or newer** on `PATH`, and **`jq`** for the settings merge.
- **The `context-ceiling` skill installed**, by default at
  `~/.claude/skills/context-ceiling` (where `sync.sh` puts it). Elsewhere, set
  `CEILING_HOOK` to the hook's real path before step 2.
- **The operator approves the project hook** on first use; until then it is
  inert.

## 1. Resolve the target

From the user's request; ask if it is not given. Make it absolute and confirm
it is a git repo: `git -C "<target>" rev-parse --show-toplevel`.

## 2. Install

This links the hook rather than copying it — a copy stops taking fixes, and a
stale hook still looks like it is working. The link points into this machine's
home directory, so it and the settings entry go in **per-clone, uncommitted**
files: `.claude/settings.local.json`, with both paths added to
`.git/info/exclude`. A committed settings entry would reach clones without the
hook, where it would do nothing and look installed.

```bash
cd "<target>"
CEILING_HOOK="${CEILING_HOOK:-$HOME/.claude/skills/context-ceiling/hooks/agent-ceiling.py}"
# Run the block as one bash command: the exit stops it before anything is written.
test -r "$CEILING_HOOK" || { echo "hook not found at $CEILING_HOOK — set CEILING_HOOK"; exit 1; }

# 1. Link the hook. ln -s accepts a missing target silently, hence the check
#    above; -fn makes a re-run replace the link instead of failing.
mkdir -p .claude/hooks
ln -sfn "$CEILING_HOOK" .claude/hooks/agent-ceiling.py

# 2. Merge the PreToolUse entry into settings.local.json (idempotent; the
#    marker is the script name). The [ -r ] guard matters: python3 on a missing
#    file exits 2, and for a PreToolUse hook exit 2 BLOCKS the call — with
#    matcher "*" that is every call, main session included.
SETTINGS=.claude/settings.local.json
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
cp "$SETTINGS" "$SETTINGS.bak.$(date +%Y%m%d%H%M%S)"
HOOK_CMD='sh -c '"'"'[ -r "$CLAUDE_PROJECT_DIR/.claude/hooks/agent-ceiling.py" ] || exit 0; exec python3 "$CLAUDE_PROJECT_DIR/.claude/hooks/agent-ceiling.py"'"'"
tmp=$(mktemp)
jq --arg cmd "$HOOK_CMD" '
  .hooks.PreToolUse |= (
    [ .[]? | select( any(.hooks[]?; (.command // "") | contains("agent-ceiling.py")) | not ) ]
    + [ { "matcher": "*", "hooks": [ { "type": "command", "command": $cmd } ] } ]
  )
' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"

# 3. Keep the link, the settings and its backups out of commits (per-clone;
#    never touches a tracked .gitignore).
EXCLUDE="$(git rev-parse --git-path info/exclude 2>/dev/null)"
if [ -n "$EXCLUDE" ]; then
  mkdir -p "$(dirname "$EXCLUDE")"
  for p in .claude/hooks/agent-ceiling.py .claude/settings.local.json '.claude/settings.local.json.bak.*'; do
    grep -qxF "$p" "$EXCLUDE" 2>/dev/null || printf '%s\n' "$p" >> "$EXCLUDE"
  done
fi
```

The entry has to sit inside the top-level `"hooks"` object, as the merge puts
it; at the top level it is valid JSON the harness silently ignores.

## 3. Thresholds

Defaults: soft **150000**, hard **200000** tokens. Override with
`AGENT_CEILING_SOFT` / `AGENT_CEILING_HARD`, **exported before the CLI
starts** — the hook inherits the CLI's environment, so a value set mid-session
never reaches it. The hook cannot tell a reviewer from an implementer: set the
thresholds high enough for the longest reviewer you dispatch, and bound
reviewers by a turn budget instead.

## 4. Prove it fires

Do not let it bound a run until you have seen it work. Start the CLI in the
target with `AGENT_CEILING_SOFT=1` exported, dispatch a throwaway agent, and
check that its **first tool call comes back blocked** with the
`CONTEXT CEILING — SOFT` message. Then restart without the variable. If it does
not block, the ceiling is not enforced here — find out why (hook approved?
entry inside `"hooks"`? `python3` on `PATH`?) before relying on it, and keep
the ceiling line in every brief regardless.

## 5. Uninstall

Remove the settings entry **first**, then the link:

```bash
cd "<target>"
tmp=$(mktemp)
jq '.hooks.PreToolUse |= [ .[]? | select( any(.hooks[]?; (.command // "") | contains("agent-ceiling.py")) | not ) ]' \
  .claude/settings.local.json > "$tmp" && mv "$tmp" .claude/settings.local.json
rm -f .claude/hooks/agent-ceiling.py
```

## 6. Report

Tell the user: where the link and the settings entry were written, that both
are per-clone and excluded from commits (another clone or machine needs its own
install), that the hook needs approving on first use, the thresholds in force,
and whether step 4's probe came back blocked — or that it has not been run yet.
