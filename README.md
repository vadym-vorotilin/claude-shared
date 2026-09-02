# claude-shared

Shared [Claude Code](https://claude.com/claude-code) environment settings, synced
across machines via this git repo.

**What it's for.** Keeping a single source of truth for the parts of a Claude Code
setup that should be identical on every machine — the colored status line, a few
core `settings.json` keys, and a set of reusable skills — instead of hand-copying
dotfiles around.

**What it does.** `./sync.sh` deploys those pieces into `~/.claude` on whatever
machine you run it from: it's idempotent, merges rather than overwrites (so
machine-specific config is preserved), and backs up `settings.json` first. Clone
the repo on a new machine, run `sync.sh` once, and that machine's Claude
environment matches the others — after which you can manage everything from inside
Claude Code via the `/claude-shared` skill. See **What `sync.sh` writes** below for
the exact set of changes it makes.

## What's shared

| File | Deploys to | Contents |
|------|-----------|----------|
| `claude/statusline-command.sh` | `~/.claude/statusline-command.sh` | Colored status line: `dir \| branch \| model \| ctx% \| 5h%` + a live subagent line |
| `claude/settings.shared.json` | merged into `~/.claude/settings.json` | `model`, `effortLevel`, `enabledPlugins`, `statusLine` |
| `skills/*/` | symlinked into `~/.claude/skills/` | **All** shared skills (see below) |
| `claude/CLAUDE.snippet.md` | a managed block in `~/.claude/CLAUDE.md` | A `/claude-shared` pointer (see "What `sync.sh` writes") |
| — | `~/.claude/claude-shared-repo` | Records this repo's path so the skills can find it later |

### What `sync.sh` writes

Running `./sync.sh` touches your `~/.claude` in five ways. It is idempotent and
backs up `settings.json` before merging:

1. Copies the status line script to `~/.claude/statusline-command.sh`.
2. Deep-merges the shared keys into `~/.claude/settings.json` (local-only keys
   preserved; the prior file is backed up to `settings.json.bak.<timestamp>`).
3. Symlinks **every** `skills/*/` directory into `~/.claude/skills/` — the whole
   set listed under **Shared skills** below, not just one. A real (non-symlink)
   directory already at that name is left untouched, so an existing local copy of
   a skill shadows the shared one until you remove it.
4. Inserts/updates a small **managed block** in `~/.claude/CLAUDE.md` pointing at
   `/claude-shared`. The block is delimited by `<!-- >>> claude-shared … -->` /
   `<!-- <<< claude-shared <<< -->` markers; **only the text between those markers
   is ever changed** — the rest of your `CLAUDE.md` is left alone. If you don't
   have a `CLAUDE.md`, one is created with just that block.
5. Writes `~/.claude/claude-shared-repo` recording this checkout's path.

### Shared skills

- **`/claude-shared`** — the front door. Guided setup: detects what's already
  configured, asks what you want (status line, settings sync, install `/handoff`
  into a repo, pull/push), and delegates to the skills below. Start here.
- **`/sync-claude-env`** — pull the latest shared config and apply it on this machine.
- **`/add-handoff`** — install the reusable `/handoff` session-continuity skill
  into another project, tailored to that repo. The template lives in
  `templates/handoff/SKILL.md`.
- **`/add-work-on-gh-issue`** — install the reusable `/work-on-gh-issue` skill into
  another project. That skill implements one approved GitHub issue end-to-end via
  strict TDD (reproduce → fix → full suite → PR → review), and supports either
  label-based or GitHub-Projects-status-based issue tracking. The template lives in
  `templates/work-on-gh-issue/SKILL.md`.
- **`/orchestrating-issue-runs`** — run a backlog of GitHub issues through
  subagents end-to-end: scope for human approval, then approach → go-gate →
  fix → independent review → fix rounds → merge, per issue. Merges and closes
  issues autonomously once the scope is approved, so read
  `skills/orchestrating-issue-runs/runbook.md` → *What this assumes* first.
- **`/review-pr`** — review a GitHub PR against its spec, not just its diff:
  reads the PR, its linked issue and any design/plan doc it references, verifies
  the change is architecturally sound and actually wired up, sweeps for dangling
  references after deletions, then posts a GitHub review (summary body + inline
  comments). It **publishes to the PR**, so read *What this assumes* in
  `skills/review-pr/SKILL.md` first — it needs a `gh` token that can write
  reviews, and it echoes the target for your go-ahead before every post. Optional
  section for asset-based projects (Unity prefab/scene/GUID wiring). Re-reviews
  follow-up pushes, but never posts APPROVE / REQUEST_CHANGES on its own — the
  verdict stays yours.
- **`/token-report`** — measure where token spend actually goes across this
  machine's transcripts: by day, model, project, subagent and context size, with
  a `--json` total for scripted budget checks. Read-only, and local — it walks
  `~/.claude/projects` and never calls an API. `/orchestrating-issue-runs`
  depends on it for its budget rule; see *What this assumes* in
  `skills/token-report/SKILL.md` (notably the hand-maintained price table).
- **`/short-brief`** — a one-screen status brief that replaces reading a long
  session, rather than summarising it.

## Adding /handoff to another project

Inside Claude Code, run the **`/add-handoff`** skill, e.g. _"add /handoff to repo
~/projects/foo"_. It will:

1. Inspect the target repo (submodules, a tasks/backlog file, the test command)
   and fill the template at `templates/handoff/SKILL.md` accordingly.
2. Write `<target>/.claude/skills/handoff/SKILL.md` (default handoff doc:
   `docs/HANDOFF.md`).
3. Add a `SessionStart` hook to `<target>/.claude/settings.json` so `/handoff`
   **auto-resumes at the start of every session** in that repo (opt-out, and only
   fires once `docs/HANDOFF.md` exists).

Commit both files in the target repo so collaborators and other machines get them.

Only the **shared keys** are touched in `settings.json`. Any machine-specific
keys already present are preserved (deep, non-destructive merge), and the prior
file is backed up first.

## Adding /work-on-gh-issue to another project

Inside Claude Code, run the **`/add-work-on-gh-issue`** skill, e.g. _"add
/work-on-gh-issue to repo ~/projects/foo"_. It asks whether the repo tracks issue
state with **labels** or a **GitHub Projects v2 Status field**, inspects the repo
(submodules, test command, Copilot reviewer), fills
`templates/work-on-gh-issue/SKILL.md`, and writes
`<target>/.claude/skills/work-on-gh-issue/SKILL.md`. No `SessionStart` hook is added
— the skill is on-demand (`/work-on-gh-issue <number>`, or bare to pick the next
eligible issue). Commit the written file in the target repo.

## Set up on a new machine

```bash
git clone <this-repo-url> ~/projects/claude-shared
cd ~/projects/claude-shared
./sync.sh
```

Requires [`jq`](https://jqlang.github.io/jq/) (used to merge `settings.json`).
Restart Claude Code afterwards so the status line takes effect.

`sync.sh` also symlinks the shared skills into `~/.claude/skills/`, so from then
on you can manage everything from inside Claude Code by running **`/claude-shared`**
(guided), or `/sync-claude-env` to re-sync directly.

## Pull the latest

```bash
./sync.sh --pull          # git pull, then deploy
```

…or, inside Claude Code, run the **`/sync-claude-env`** skill.

## Push a local change

Edited your status line or core settings on one machine and want the others to
get it?

```bash
cp ~/.claude/statusline-command.sh claude/statusline-command.sh
# for settings: hand-edit claude/settings.shared.json to match the changed keys
git add -A && git commit -m "update shared claude env" && git push
```

Then run `./sync.sh --pull` (or `/sync-claude-env`) on the other machines.

## How the merge works

```
~/.claude/settings.json   (existing, local)
        *                 (jq deep merge — shared keys win)
claude/settings.shared.json
        =
~/.claude/settings.json   (shared keys applied, local-only keys kept)
```

The status line script is portable on its own — it reads `$HOME` at runtime, so
no paths are hardcoded.

### The subagent line

Claude Code only ever hands the status line **main-loop** state: `model` and
`context_window` describe the session, never a Task subagent, and stepping into
a subagent view doesn't re-run the script with different data. So that readout
is derived from disk instead — since 2.1 each subagent keeps its own transcript
beside the session's:

```
~/.claude/projects/<slug>/<session-id>/subagents/agent-<id>.jsonl
~/.claude/projects/<slug>/<session-id>/subagents/agent-<id>.meta.json
```

`transcript_path` in the status line input locates that directory. They render
as one compact line under the session, in spawn order — oldest first, matching
the agent list the CLI shows below the prompt:

```
S/34% · S/27% · O/11% · F/5% · H/88%
```

A model initial and a context percentage each — enough to see a fan-out's shape
and spot the agent about to run out of room, without a line per agent. The
initial takes the session model's violet, the percentage green, the slash the
gray of the receding weekly quota. An agent that hasn't taken its first turn
yet shows its initial alone; past eight agents the rest collapse into `+N`.

Ordering is by `meta.json`'s mtime, written once when the agent spawns — not by
the transcript's, which every running agent bumps constantly and which
reshuffled the line about once a second.

Which agents are live is decided by what has *finished*, not by what has
written recently. A running agent goes quiet for minutes waiting on a long tool
call — 1% of the gaps between a running agent's own transcript entries run past
170s — so a window tight enough to retire finished agents promptly drops live
ones instead. When an agent finishes, the session collects its result and the
session transcript names that agent again, after the agent's own last entry;
that ordering is the signal, and it held for 169 of 173 agents measured, the
four exceptions being the ones still running. `STATUSLINE_AGENT_WINDOW`
(seconds, default 900) remains only as a backstop for an agent whose result
never lands.

Two kinds of entry say "done", and each covers a case the other misses:

- **`toolUseResult`** — what a session writes when it collects a tool's output.
  The marker for an agent it waited on.
- **A task-notification** (`"origin":{"kind":"task-notification"}`) — what a
  session receives when a background agent reports its task complete. A
  background agent's tool result lands back at *spawn* ("launched
  successfully"), long before it finishes, so nothing else ever retires one.

Nothing else counts. A session names an agent for other reasons: queueing a
message for one writes a `queue-operation` and an `attachment` naming it, and an
agent idling on that queued message has by definition not written since, so the
mention lands after its last entry and is indistinguishable from a result by
timestamp alone. Counting those would retire live agents mid-run — the one
shape this rule must never get wrong, since an agent wrongly kept on the line
is a stale reading you can see, while one wrongly dropped is invisible while it
burns context. An agent given more work writes past its own notification and
returns to the line on the next repaint, so the ordering keeps working for a
background agent that is reused rather than finished.

The percentage is the harness's own arithmetic — input + cache-creation +
cache-read tokens over the model's context window. That window is per-model,
moves with the lineup (Sonnet crossed to 1M at 5, Opus at 4.7), and isn't
recorded in a transcript, so it comes from five places, in order:

1. `context_window.context_window_size` from the harness, when the agent's
   model id is exactly the session's. Agents do inherit the model, but a
   transcript often records a dated id where the harness reports an undated
   one, and then this misses and the table below answers.
2. An explicit `[1m]` suffix on the model id, which names the window outright.
3. The model table inside the installed CLI's own bundle, extracted with a
   `grep`/`awk` pair and cached at `~/.claude/cache/statusline-model-windows`
   against the binary's mtime and size, so it re-reads only after an upgrade.
   The CLI is located through `/proc` (the status line runs as its descendant)
   and falls back to `PATH`; `STATUSLINE_MODEL_WINDOWS` pins a table file
   instead, for a machine where neither finds it. It prefix-matches, so a
   dated id still resolves here.
4. A built-in list of the 1M models as of 2.1.258, for when that table can't be
   read at all.
5. The reading itself — a turn can't exceed its own window, so anything past
   200k is proof of a larger one.

Two env knobs beyond those, read at render time: `STATUSLINE_AGENT_MAX`
(default 8) caps the entries before the `+N`, and `STATUSLINE_CLAUDE_BIN` pins
the CLI binary for a machine where neither `/proc` nor `PATH` finds it.
(`STATUSLINE_NOW` exists as well, but only so the tests can fix the clock.)

Keeping it live needs a `refreshInterval` in the `statusLine` block, which the
shared `settings.json` sets to 15 seconds. Without one the status line repaints
only when the main loop moves — `tokenUsage`, `mainLoopModel`, permission mode,
the last assistant message id — none of which change while a subagent is
working, so a fan-out would only appear once the agents had already returned.
Every repaint runs the script, and a second-by-second cadence buys nothing over
15s: what it reports is silence, measured against windows five minutes and an
hour long.

One thing it can't do: it shows which agents are *live*, not the one you
stepped into. The UI leaks no focus signal to the status line.

## Tests

`tests/` holds a containerized [bats](https://github.com/bats-core/bats-core)
suite covering `sync.sh`, the status line, and the `/add-handoff` hook-merge.

```bash
./tests/run.sh
```

Requires Docker. The repo is mounted read-only and every test runs against a
throwaway `$HOME`, so the suite never touches your real `~/.claude`.

## Licence

MIT — see [LICENSE](LICENSE).
