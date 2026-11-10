---
name: smart-compact
description: Use when the user wants to compact the conversation and keep working — "/smart-compact", "compact", "give me the compact command", "prepare for compaction", "write the /compact line", "context is getting big, let's compact". Writes a ready-to-paste /compact line whose keep text carries every running agent, job and timer through the compaction. Stops nothing. For ending work (drain, save, stop helpers) use /pause instead.
---

# smart-compact — a /compact line that keeps the work running

The user wants a smaller context, not a stop. Helpers, background commands,
monitors and loops stay exactly as they are; the job is a keep text good enough
that the compacted session still knows what is in flight and how to reach it.

## What this assumes

- **Claude Code.** `/compact` is a built-in command only the user can type, so
  this skill writes it out; it never claims to have compacted.
- Helpers are subagents reachable with `SendMessage`; timers are `CronCreate`,
  `ScheduleWakeup` (inside `/loop`), `Monitor`, or a background Bash `sleep`
  heartbeat (`cache-warmth`). Skip what the session does not use.
- A project **handoff** (a `/handoff` skill or a `docs/HANDOFF.md`) and **git**
  are optional.

## Never

- Stop, `TaskStop`, `CronDelete` or message a helper to wind down.
- Start new work to "finish before compacting".
- Push. Commit only what the project already commits (a handoff doc), and only
  if the user's rules allow committing without asking.

If the user also says the work ends — "pause" or "/pause", "drain", "wrap up",
"stop", "for today", "heading off", or a deadline — this is a pause: use
`/pause`.

## 1. Read the clock and take inventory

Run `date '+%Y-%m-%d %H:%M %Z'`. Then list what is alive, by named means, not
from memory — and touch none of it:

- each agent with no final report yet: agent ID or name (what `SendMessage`
  needs), worktree or branch, what it is doing;
- each background command: task ID, command, log or output path;
- each timer: `CronList` for crons (with IDs), a `/loop` and its prompt, each
  `Monitor` or heartbeat task ID and what it watches.

Look in this session's own tool calls and, after an earlier compaction, in the
previous keep text's or summary's running list — a second compaction must not
drop what the first one carried. Confirm each item by its handle (task status,
agent output). For a heartbeat or detached process whose launch is out of view,
`pgrep -fl '<the command it ran>'` (e.g. `'sleep 3000'`); list a hit as
`unconfirmed PID <n>` and do not kill it: the pattern can match another
session's process, and a process with no task ID never notifies this session,
so it does not count as this session's heartbeat.

Found nothing? Say `No agents, jobs or timers running.` — after the check.

## 2. Put state on disk (optional, quick)

The compaction summary is lossy; files are not. If the project has a handoff
and this stretch changed things it does not record, update it (`/handoff`, or
edit the doc) — a few lines, not a wrap. Skip it when nothing durable changed.
Note the current branch and `HEAD` if git is in use.

## 3. The reply

One header line from a fresh `date` in this turn, at most a few lines on what
was checked, then the code block. Nothing after the code block.

````markdown
**<timestamp> — Ready to compact** (work keeps running)

```
/compact <keep text>
```
````

**The keep text** is one paragraph, self-contained for a reader with no memory
of the session, under ~1,500 characters, in this order:

1. what the work is, and `compacted <timestamp>, work still running` (or
   `nothing running`);
2. where the state lives — handoff path, branch, `HEAD`, other notes files;
3. done, then in progress with its location;
4. **still running**, every item from step 1 with the handle needed to reach
   it after compaction: agent ID or name and worktree; task ID and log path;
   cron ID; loop prompt; monitor task ID. Add `Do not restart these; wait for
   their reports.` For a timer, say how it keeps going:
   `heartbeat <task ID> (<command>, armed <time>): re-arm when it fires
   (cache-warmth)` — the ID is its current one, since a re-arm refreshes the
   line (below). Write `no heartbeat: arm one (cache-warmth)` when work is
   running and no heartbeat ID is confirmed running by task status. One that
   cannot be checked is listed as `unconfirmed` (do not kill it) and does not
   count, so the arm line is still written. For a loop: `/loop: keep calling
   ScheduleWakeup with <prompt>`;
5. next steps, literal and in order — usually what to do when each running
   item reports;
6. decisions the user made that are not yet written in a file.

Over the limit, shorten the done list first; never drop items 2, 4 or 5.

**The line goes stale.** It is a snapshot, and the session keeps working until
the user pastes it. If a helper reports, a command ends or a timer fires
before then and the state changes — a re-armed heartbeat counts, since its
task ID changed — end that reply with a refreshed `/compact` line and say the
earlier one is stale.

## 4. After the compaction

Before acting, confirm each running item by its handle (task status, agent
output, `CronList`); trust those, the handoff and `git log` over the summary.
A helper that reported during compaction has its report waiting — read it
before re-dispatching anything.

## Red flags

| Thought | Reality |
|---|---|
| "Compaction is cleaner with nothing running" | The user asked to compact, not stop. Leave it all running. |
| "I'll wait for the agents to finish first" | Don't. The keep text carries them. |
| "The summary will remember the agent IDs" | Maybe not. The keep text names every handle. |
| "Nothing's running, I'm fairly sure" | Check with `CronList`, the IDs this session launched, the last keep text's list, and `pgrep`. |
| "After compacting I'll re-dispatch the stuck one" | Check its handle first; it may have reported. |

## Example (fictional)

~~~markdown
**2026-04-14 15:20 CEST — Ready to compact** (work keeps running)

```
/compact CSV import for the ledger CLI, compacted 2026-04-14 15:20, work still running. State: docs/HANDOFF.md, branch feat/csv-import, HEAD 4f2a9c1, not pushed. Done: parser, --strict flag. In progress: docs/import.md (examples section missing). Still running: agent "csv-tests" (worktree ../ledger-csv-tests) writing fuzz tests for the parser; background task b7 running the full suite, log /var/tmp/ledger-suite.log; cron c3 every 20 min checks CI on the PR. Do not restart these; wait for their reports. Next: when csv-tests reports, review its branch and merge into feat/csv-import; when b7 ends, read the log tail; then finish docs/import.md. User decided: --strict rejects blank rows rather than skipping them.
```
~~~
