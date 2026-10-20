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

**Read the shared settings before you sync.** The keys in
`claude/settings.shared.json` (`model`, `effortLevel`, `enabledPlugins`) are the
maintainer's personal preferences, and `sync.sh` copies them onto every machine
that runs it — over whatever you had set. Fork the repo and edit that file to
your own taste before running it. `settings.json` is backed up before the merge;
`CLAUDE.md` is not (only the text between the managed-block markers changes, but
there is no copy to restore from).

## What's shared

| File | Deploys to | Contents |
|------|-----------|----------|
| `claude/statusline-command.sh` | `~/.claude/statusline-command.sh` | Colored status line: `dir \| branch \| model \| effort \| ctx% \| cache TTL \| 5h%` |
| `claude/subagent-statusline-command.sh` | `~/.claude/subagent-statusline-command.sh` | One row per live subagent in the agent panel: `agent \| model \| effort \| ctx% \| cache TTL \| details` |
| `claude/statusline-lib.sh` | `~/.claude/statusline-lib.sh` | Colors, clock and cache-TTL helpers both scripts source |
| `claude/settings.shared.json` | merged into `~/.claude/settings.json` | `model`, `effortLevel`, `enabledPlugins` (the maintainer's personal preferences — see above), `statusLine`, `subagentStatusLine` |
| `skills/*/` | symlinked into `~/.claude/skills/` | **All** shared skills (see below) |
| `claude/CLAUDE.snippet.md` | a managed block in `~/.claude/CLAUDE.md` | A `/claude-shared` pointer (see "What `sync.sh` writes") |
| — | `~/.claude/claude-shared-repo` | Records this repo's path so the skills can find it later |

### What `sync.sh` writes

Running `./sync.sh` touches your `~/.claude` in five ways. It is idempotent and
backs up `settings.json` before merging:

1. Copies the status line scripts and their shared helpers to `~/.claude/`.
2. Deep-merges the shared keys into `~/.claude/settings.json` (local-only keys
   preserved; the prior file is backed up to `settings.json.bak.<timestamp>`).
   The shared keys win on conflict, so a local `model` or `effortLevel` is
   overwritten.
3. Symlinks **every** `skills/*/` directory into `~/.claude/skills/` — the whole
   set listed under **Shared skills** below, not just one. A real (non-symlink)
   directory already at that name is left untouched, so an existing local copy of
   a skill shadows the shared one until you remove it.
4. Inserts/updates a small **managed block** in `~/.claude/CLAUDE.md` pointing at
   `/claude-shared`. The block is delimited by `<!-- >>> claude-shared … -->` /
   `<!-- <<< claude-shared <<< -->` markers; **only the text between those markers
   is ever changed** — the rest of your `CLAUDE.md` is left alone. If you don't
   have a `CLAUDE.md`, one is created with just that block. Unlike
   `settings.json`, `CLAUDE.md` is not backed up first.
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
  `skills/orchestrating-issue-runs/INSTALL.md` → *What this assumes* first.
- **`/unattended-run`** — run a long task without you there, solo or with its
  own helper agents: you approve the goal, the plan and what it may do alone
  (push, merge, deploy…) before it starts; it decides what it can, parks what it
  can't, stamps progress, watches its helpers with one silent sweep, and stops
  with one message listing exactly what waits on you.
- **`/cache-warmth`** — keep prompt caches warm while a session or its
  subagents wait: subagents poll instead of blocking (their cache lasts minutes),
  the main session never spends a turn waiting and keeps a 50-minute heartbeat
  (its cache lasts about an hour). Its `brief.md` is the block to paste into any
  subagent brief. `/orchestrating-issue-runs` depends on it, on
  `/context-ceiling` and on `/unattended-run`.
- **`/context-ceiling`** — bound how large a session's or a subagent's context
  grows. Dispatched agents stop at ~150k and return a checkpoint note a fresh
  agent continues from; the main session reads its own size with
  `tools/context-size.py` and offers a handover past its soft ceiling. Its
  `brief.md` is the block to paste into a long-running subagent's brief.
- **`/add-context-ceiling`** — install the ceiling hook into a project, per clone
  and uncommitted, so every subagent dispatched there is told when it passes
  the ceiling. Prove it fires before relying on it (step 4).
- **`/review-pr`** — review a GitHub PR against its spec, not just its diff:
  reads the PR, its linked issue and any design/plan doc it references, verifies
  the change is architecturally sound and actually wired up, sweeps for dangling
  references after deletions, then posts a GitHub review (summary body + inline
  comments). It **publishes to the PR**, so read *What this assumes* in
  `skills/review-pr/SKILL.md` first — it needs a `gh` token that can write
  reviews, and it echoes the target for your go-ahead before every post. Optional
  section for serialized asset/scene wiring checks (e.g. a game engine's
  prefab/scene references). Re-reviews
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
for f in statusline-command.sh subagent-statusline-command.sh statusline-lib.sh; do
  cp ~/.claude/"$f" claude/"$f"
done
# for settings: hand-edit claude/settings.shared.json to match the changed keys
git status                                   # confirm only the files you meant to change
git add claude/statusline-command.sh claude/settings.shared.json   # name the files you changed
git commit -m "update shared claude env"
```

Pushing is a separate decision: look at `git diff --cached` first, and push only
when you are happy with it. The repo may be public, so nothing that identifies a
private project, path or machine belongs in it.

Then, once the change is pushed, run `./sync.sh --pull` (or `/sync-claude-env`) on the other machines.

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

### The agent panel

Live subagents get a row each in the agent panel below the prompt, laid out in
the session line's columns and colors:

```
Explore#1        | O 5.5 | h ▅ |  22% |  10% | Finding where the TTL is computed
builder          | S 5   | m ▃ |  12% |  93% | Waiting on the test suite
reviewer         | O 5.5 | x ▇ |    — |    — | Review the diff
Explore#2        | H 4.5 |     |   4% |   3% | ✓ Listing callers
```

Agent, model, effort, context, cache TTL (see **The cache clock** below), and
what the agent is doing. Claude Code's `subagentStatusLine` setting runs
`subagent-statusline-command.sh` once per refresh with every row as JSON on
stdin — `columns`, `transcript_path`, and `tasks[]` carrying each agent's `id`,
`name`, `agentType`, `status`, `model`, `effort`, `contextWindowSize`,
`tokenCount` and progress `label` — and takes back one `{"id","content"}` line
per row. A row it gets no line for keeps the CLI's own rendering, so a failing
script degrades to the stock panel; an empty `content` hides the row, so the
script never prints one.

The setting needs a Claude Code that knows `subagentStatusLine` (2.1.304 does);
without it the panel keeps its stock rows.

- **Agent** — the agent's name if it has one, otherwise its type minus any
  plugin prefix. A type that appears more than once gets `#N` in spawn order.
- **Model** — family initial and version: `claude-opus-5-5` → `O 5.5`,
  `claude-haiku-4-5-20251001` → `H 4.5`.
- **Effort** — the level's initial with the session line's bar and color.
  `max` is a bold `M █`, which its color and bar keep apart from `m ▃`. The
  panel's input carries an effort only for an agent whose definition sets one;
  every other agent runs at the session's, so the session's status line records
  its effort per session under `~/.claude/cache/statusline-session-effort/` and
  the panel falls back to that. The column drops out when no agent has an
  effort either way.
- **Context** — every input token of the agent's last turn, over the window
  the harness sends for its model. The task's own `tokenCount` also adds every
  output token the agent has written, so it overstates a long-running agent and
  stands in only before a transcript can be read. Yellow, as on the session
  line.
- **Cache TTL** — the one reading that still comes from disk: the agent's
  transcript sits at `<session-id>/subagents/agent-<id>.jsonl` beside the
  session's, and an agent's task id is its agent id.
- **Details** — the live progress label, falling back to the spawn
  description; cut to the width that is left.

Before an agent's first turn, context and TTL read `—` rather than 0%. A
finished row turns gray behind a ✓ or ✗; its TTL keeps counting, since a
follow-up message lands on a warm cache only while it lasts. On a narrow panel
the details shrink first and drop below 12 cells, then the effort letter goes
and its bar stays, then the agent name is cut.

The session's status line used to carry these readings as one compact line,
`O/22%/48% · S/12%/100%`, scraped from the transcripts on disk. The panel
supplies the agent list itself now, so that line, and the liveness and
model-window guessing behind it, are gone.

### The cache clock

A context is only cheap to come back to while its prompt cache is alive, and
that cache outlives the request that wrote it by a fixed TTL — five minutes for
a subagent, an hour for a main session. Past it the whole context is re-sent at
full price. So how full a context is only tells half the story; the other half
is how long it has been sitting there. The session line and every agent row
carry it:

```
Opus 5 | ctx: 22% | TTL: 33% (-40m)
Explore | O 5.5 | h ▅ |  11% |  40% | Reading the parser
```

`TTL` is the share of that window the silence since the last turn has spent,
and the countdown what is left of it. It renders white and turns red from 80%
on — the one signal worth a color change, in a hue no context percentage uses,
so no field reads as part of the one before it. Once the cache is gone the
percentage sticks at 100% and the countdown disappears.

Two things make the reading trustworthy rather than assumed:

- **The TTL is read, not hardcoded.** Every turn's `usage.cache_creation`
  reports which bucket it wrote — `ephemeral_5m_input_tokens` or
  `ephemeral_1h_input_tokens` — so the window comes from the transcript and
  survives the harness changing its mind. A turn that wrote no cache says
  nothing, so the search walks back to one that did; failing that it falls back
  to five minutes for an agent, an hour for a session.
- **The clock runs from the last assistant turn**, the last moment a request is
  *known* to have refreshed the cache. That reads conservatively on purpose: a
  turn still streaming hasn't been written yet, so a long one counts as silence
  until it lands. The cache is never claimed to be fresher than the transcript
  can prove.

Timestamps are converted with plain integer arithmetic rather than `date -d`,
which GNU and BSD spell differently.

Keeping the session's reading live needs a `refreshInterval` in the
`statusLine` block, which the shared `settings.json` sets to 15 seconds.
Without one the status line repaints only when the main loop moves, and a
session sitting idle is exactly when its TTL is running down. A second-by-second
cadence buys nothing over 15s: what it reports is silence, measured against a
window an hour long. The agent panel needs no such setting; the CLI re-runs
its command on its own timer while any agent row is showing.

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
