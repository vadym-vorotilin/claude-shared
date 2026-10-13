---
name: context-ceiling
description: Bound how large a session's or a subagent's context grows, with a measured ceiling and a checkpoint note that lets work continue in a fresh agent. Use when a session or the agents it dispatches run long, when deciding whether to resume a dead agent or start a continuation, when writing a brief for a long-running subagent, or when asked "how big is my context" or "should I hand over".
---

# Context ceiling

An agent re-reads its whole context on every turn, so cost grows with
**context × turns**. The expensive failure is the long-lived agent, not the
chatty one: its last turns are its dearest, while a continuation starts at a
fraction of that size. A ceiling stops the growth — **if something can measure
it**.

**A threshold ships with the instrument that reads it.** No agent can see its
own context size: the harness does not report it and `/context` belongs to the
operator. "Stop at N tokens" is a rule its subject cannot obey, so it gets
breached silently and by a wide margin. Every ceiling here comes with its
instrument; a threshold without one is decoration, and worse than none, because
it reads as a control that is working.

| Who | Ceiling | Instrument | Past it |
|---|---|---|---|
| A **dispatched agent** doing the work | soft ~150k, hard ~200k | `hooks/agent-ceiling.py`, a `PreToolUse` hook (install it with `/add-context-ceiling`) | writes a checkpoint note and returns it |
| The **main session**, coordinating | soft 200k, hard 500k by default | `tools/context-size.py`, read at every progress report | offers a handover at the next natural boundary; stops at the hard one |
| A **reviewer** | none — a verdict does not split | a **turn budget** in its brief | reports what it could not cover |

## What this assumes

- **Claude Code transcripts** under `~/.claude/projects/<project>/`, with
  subagent transcripts in a `subagents/` directory beside the session's (the
  layout since CLI 2.1). Both tools read them; neither calls an API.
- **`python3` 3.9 or newer** on `PATH`.
- **The hook is installed per project** by `/add-context-ceiling`. Without it,
  a dispatched agent's ceiling is a brief line only — say so, do not treat it
  as enforced.
- Resume and continue decisions depend on cache lifetimes; the
  **`cache-warmth`** skill covers those.

## A dispatched agent: stop at the ceiling, write a checkpoint note

**Put [brief.md](brief.md) in every brief for a long-running agent**, verbatim —
`cat` it into the brief file. It carries the ceiling, the note's template and
when to finish rather than stop. The hook enforces the same numbers: on the
first tool call past each threshold it blocks once with the ceiling message,
then gets out of the way.

**The ceiling is a checkpoint, not a guillotine.** Writing the note is
unconditional — it is cheap, and it is what survives if the agent dies.
Returning is not:

- **More than a few turns of work left, or a design question open → return
  the note.** This is the case the ceiling exists for.
- **A bounded finish → finish, and say so in the note.** "Bounded" is evidence,
  not a feeling: the tests are already green, one named deliverable remains, no
  decision is open. Hard stop at ~200k whatever the state.
- **A job that outlasts the agent → launch it detached and return `running`**,
  with the log path, the done marker and the job's PID verified against
  `/proc/<pid>/exe` (Linux; use your platform's equivalent) — `$!` is often the
  wrapper shell. A finisher is dispatched when the job is done.

**Make it cheap by construction.** Brief work the plan says is large as parts
from the start (A, B, then a finisher), each committing and pushing after every
step. The checkpoint note then reduces to "head, steps done, the one open
question", and a continuation starts from a pushed head instead of a transcript.

### The checkpoint note

```
FILES TOUCHED   path — what changed, and what is half-done
DECISIONS       each decision and why, including options considered and dropped
REMAINING       the concrete next step, then the rest, in order
STATE           repo, branch, worktree path, PR number, resolved base SHA
GOTCHAS         what surprised you: a flaky test, a slow command, a wrong claim
                in the task
```

The agent writes it to `CHECKPOINT.md` in its worktree **and** returns it with
`STATUS: CHECKPOINT` — a note that exists only in a returned message dies with
an agent that never returns. Write one **before a deliberate pause** too,
rather than leaving a large-context agent to thaw at full size later.

It is not `/handoff`: that skill keeps one living document per repo for the
next *session*; a checkpoint note hands one task to the next *agent*.

**The continuation gets the note verbatim**, plus the standard brief. Do not
summarise it — summarising is where the one detail the next agent needed gets
lost. Verify the STATE lines yourself first: worktree present, branch pushed,
PR open, SHA resolvable. A lossy note makes the continuation redo work, which
no token count shows: read the first few notes before dispatching from them,
and when a continuation had to re-derive something, add the missing heading.

## Resume under the ceiling; continue above it

When an agent dies (limits, an API error, a crash), the cheap path depends on
its size and its cache:

- **Under the ceiling, recently active → resume it** (`SendMessage` to the same
  agent id). It keeps its task context for a fraction of the price. Verify the
  worktree, branch and PR state yourself and hand those facts back in the
  message, with "recreate the worktree at a fresh path if it is gone".
- **Past ~150k, or cold for more than a few minutes with a large context →
  continue instead**: dispatch a fresh agent from its last checkpoint note, or
  failing that from your own record plus the facts you verified. Both paths pay
  one full cache write at that moment; only the resume keeps paying for the
  bloat on every turn after it.

## The main session: measure, then offer a handover

The hook exempts the main session by construction, so its number comes from
the tool:

```bash
python3 <this skill>/tools/context-size.py
# → context current 140,000 · peak 170,000 · avg 100,000 over 60 turns · under-soft (soft 200k / hard 500k)
```

It sums `input_tokens + cache_read_input_tokens + cache_creation_input_tokens`
for each turn of the session's own transcript — the prompt the model was given,
which is the context — and counts a turn written over several lines once. It
picks the newest transcript for the current project (`--transcript`,
`--session` or `--project-dir` to point elsewhere; `--json` for a record) and
exits 0 / 1 / 2 for under-soft / past-soft / past-hard. **Read it at every
progress report and record the figure.** An estimate drifts, and nothing flags
it.

**Why the main session's numbers are higher.** A session that coordinates —
dispatching, recording, merging — takes turns over a context already in a warm
cache, so its cost per turn grows at the cache-read rate, about a tenth of the
write rate. Held to an agent's number it would hand over before doing anything
substantial, and every handover costs a cold write plus a re-orientation, which
is where details get lost. **A main session doing the heavy work itself**
(reading code, running tests, re-deriving a diff) is in the agent's position:
pass `--soft 150 --hard 200`.

**Past the soft ceiling, do not stop — offer a handover at the next natural
boundary** (a finished task, a merge, a decision point) and keep going until
the operator answers. **Hard is a stop.** The offer says where the work stands,
what is in flight, where the durable record is, and the literal instruction a
fresh session needs: *"read `<record>`, verify the state with `git`/`gh` before
trusting it, then continue at `<next step>`"*. **Agent handles are
session-scoped**: a fresh session cannot message the old one's agents, so with
agents running, compacting keeps the rescue path; with nothing in flight, a
fresh session is cheapest.

## An agent measured past twice its ceiling is an instrument failure

Not a note in a report — the ceiling did not bind that agent, so it is not
binding any other agent under the same rule either. Fix it before the next
dispatch: is the hook in the project's `.claude/settings.json` inside the
top-level `"hooks"` object, were the thresholds exported before the CLI
started, and does a probe agent still come back blocked
(`/add-context-ceiling` → "Prove it fires")? Re-verify by dispatching the
probe, not by reading the settings file.

The hook cannot tell a reviewer from an implementer, and its thresholds come
from the CLI's environment, so they cannot be raised for one agent mid-run. Set
them for the longest reviewer you dispatch, and let the reviewer's turn budget
bound it. A review that runs many times its budget has stopped judging a diff
and started redoing the work.

## Red flags

- A ceiling in a brief with no hook installed and nothing saying so
- A long-running agent past ~150k still going instead of returning its note
- Resuming a cold agent that is already over the ceiling — that is a
  continuation from its checkpoint note
- A continuation briefed from a *summary* of the note
- An agent measured past twice its ceiling written up as an observation
- The main session's context figure estimated instead of read
- Copying an agent's numbers onto a coordinating main session, or the other
  way round
- A reviewer told to hand off mid-review

## Common rationalizations

| Excuse | Reality |
|---|---|
| "It's nearly done, it can push past the ceiling" | "Nearly done" is the estimate most often wrong, so make it evidential: tests green, one named deliverable left, no open decision. That finishes (hard stop ~200k). Anything else writes the note and returns. |
| "A fresh agent is cleaner than resuming" | True above the ceiling. Below it a resume keeps the task context for a fraction of the price. |
| "The main session is past its ceiling, hand over now" | Past the soft one you **offer** a handover at the next natural boundary, and the operator decides; you do not stop mid-task. |
| "The agent ran to several times its ceiling but it finished, so note it" | The rule did not bind, which means every other agent under it is unmeasured too. Fix the instrument before the next dispatch. |
