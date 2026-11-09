---
name: pause
description: Use when the user is ending work for now and wants the session drained, saved and ready to compact — "/pause", "pause", "drain", "start draining", "we're finishing at 13:00", "wrap for today", "I need to go to bed", "prepare for compaction", "prepare the compaction command". Takes an optional deadline ("/pause 13:00", "/pause in 20m").
---

# pause — drain, save, hand over the compact command

One request ends a working stretch: nothing left running, state saved outside
the conversation, and a ready-to-paste `/compact` line as the last thing in the
reply. The user should never have to ask twice ("drain", then "prepare the
command").

## What this assumes

- **Claude Code.** `/compact` is a built-in command only the user can type, so
  this skill writes it out; it never claims to have compacted.
- Helpers are subagents reachable with `SendMessage`; timers are `CronCreate`,
  `ScheduleWakeup` or `Monitor`. Skip what the session does not use.
- **git** is optional. Without it, "commit" below means "write to disk".
- A project **handoff** (a `/handoff` skill or a `docs/HANDOFF.md`) is optional.
  Without one, write the notes to a file on disk (not a tmpfs `/tmp`) and name it.

## 1. Read the clock, set the cutoff

Run `date '+%Y-%m-%d %H:%M %Z'` now. Every time you write comes from `date`
output in the same turn.

- **No deadline given:** the cutoff is now. Go to step 2.
- **A deadline given** (a clock time, or "in 20 min"): the **cutoff** is the
  deadline minus the time the wrap needs — about 15 min, or about 30 min when a
  helper or a test suite is expected to still be running at the cutoff.
- **A deadline with no time** ("before bed", "soon"): ask for the time in one
  line and keep working; with no answer, the cutoff is now.
- A deadline that has already passed counts as "now".

**Until the cutoff, keep working normally**, heartbeats included. Start an item
— yourself or by dispatching a helper — only if its estimate ends before the
cutoff; an item that would end after it waits for next session. Say in one
line: `Cutoff ≈12:35; wrap by 13:00. Until then: <what you start>.`

## 2. Drain

From the cutoff on, start nothing new: no agents, no background commands.

- **Running helpers:** tell each to commit only work that passes, write its
  handoff note, and stop by a stated clock time. Wait for every one to report.
  One still silent at the deadline is recorded as alive, with its worktree and
  last known state; do not wait past the deadline.
- **Long background commands** (a test suite, a training run): stop them, or
  leave them running detached when that is harmless and the result is wanted.
  Either way, record which, and where the log is.
- **Timers:** delete this session's crons, stop any `/loop` wakeup, and
  `TaskStop` heartbeats and monitors. A timer that fires after the pause
  re-reads the whole context for nothing.
- **Check:** list agents, background tasks and crons. Write down what is still
  alive and why; "nothing running" only after the check.

## 3. Save

1. Run the project's handoff (`/handoff wrap`, or update its handoff doc).
   Otherwise write the notes file: done, half-done and where, what is still
   running, the literal first step for next time, the decisions the user made.
   A fresh or already-compacted session takes "done" from the handoff and
   `git log`, not from memory.
2. Commit it if the project commits it. If nothing changed since the last
   commit, make no commit; the keep text names the actual `HEAD`.
3. **Push** only if the project's rules or this session's user allow it. If
   pushing needs a yes, ask once, in the final message (step 4), not mid-drain.

## 4. The final message

Nothing after the code block. Shape:

````markdown
**<timestamp from step 1's date> — Paused**
- **Done:** <what finished in this stretch>
- **Left:** <half-done work and where it sits>
- **Running:** <what is still alive, its log> — or "nothing"
- **Next:** <the literal first step next session>
- **You:** <decisions or acts waiting on the user, incl. push?>

Paste to compact:
```
/compact <keep text>
```
````

**Running** is always present, "nothing" included: it is the fact the next
session most needs. Omit any other bullet with nothing in it. A caveat — a
failing test, a red build — goes in **Left** or **You**. **The keep text** is
one paragraph,
self-contained for a reader with no memory of the session, under ~1,500
characters, in this order:

1. what the work is, and when it paused, with the reason only if the user gave
   one (`paused 2026-11-08 12:45 by the user, lunch`) — never an invented one;
2. where the state lives — handoff path, branch, head commit, pushed or not, other notes files;
3. done, then half-done with its location;
4. still running, with the log path to read — or `No agents, jobs or timers running.`;
5. next steps, literal and in order, starting with `Read <handoff path> first.`;
6. decisions the user made that are not yet written in a file.

Detail belongs in the handoff; the keep text points to it. Over the limit,
shorten the done list first; never drop items 2, 4 or 5.

## 5. After the compaction

On "continue" or "resume": read the handoff and the logs of anything left
running before acting. Trust them and `git log` over the summary.

## Red flags

| Thought | Reality |
|---|---|
| "They said drain, so I stop now" | A deadline gives a cutoff. Work until it. |
| "I'll describe what's saved; they can ask for the command" | The `/compact` block is always the last thing in the reply. |
| "I'll ask about pushing now and wait" | Drain first; the push question goes in the final message. |
| "The heartbeat will just notice we're done" | It costs a full context read. Stop it. |
| "Nothing's running, I'm fairly sure" | Check the agent, task and cron lists first. |
| "The summary will remember the SHAs" | The keep text names them; the summary may not. |

## Example (fictional)

~~~markdown
**2026-04-14 18:05 CEST — Paused**
- **Done:** CSV parser, `--strict` flag, tests green
- **Left:** import docs half-written, `docs/import.md`
- **Running:** nothing
- **Next:** finish `docs/import.md`, then open the PR
- **You:** push `feat/csv-import`?

Paste to compact:
```
/compact CSV import for the ledger CLI, paused 2026-04-14 18:05 by the user (end of day). State: docs/HANDOFF.md (committed 4f2a9c1, branch feat/csv-import, not pushed). Done: parser, --strict flag, 38 tests passing. Half-done: docs/import.md, examples section missing. No agents, jobs or timers running. Next: read docs/HANDOFF.md first, then finish docs/import.md, run the full suite, open the PR against main. User decided: --strict rejects blank rows rather than skipping them.
```
~~~
