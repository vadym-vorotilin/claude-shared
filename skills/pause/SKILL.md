---
name: pause
description: Use when the user is ending work for now and wants the session drained, saved and ready to compact — "/pause", "pause", "drain", "start draining", "we stop at 17:30", "wrap up for today", "I'm heading off soon". Takes an optional deadline ("/pause 17:30", "/pause in 30m"). Not for compacting alone: "compact", "give me the compact command" or "prepare for compaction" without ending work is /smart-compact, which keeps everything running.
---

# pause — drain, save, hand over the compact command

One request ends a working stretch: nothing left running, state saved outside
the conversation, and a ready-to-paste `/compact` line as the last thing in the
reply. The user should never have to ask twice ("drain", then "prepare the
command").

## Compacting without pausing

A request to compact is not a request to stop. Without "/pause", "drain",
"wrap up", "stop" or a deadline, use `smart-compact` instead: it writes the
`/compact` line and stops nothing. If unsure, that is the default — a drain
cannot be undone.

## What this assumes

- **Claude Code.** `/compact` is a built-in command only the user can type, so
  this skill writes it out; it never claims to have compacted.
- Helpers are subagents reachable with `SendMessage`; timers are `CronCreate`,
  `ScheduleWakeup` (inside `/loop`), `Monitor`, or a background Bash `sleep`
  heartbeat (`cache-warmth`). Skip what the session does not use.
- **git** is optional. Without it, "commit" below means "write to disk".
- A project **handoff** (a `/handoff` skill or a `docs/HANDOFF.md`) is optional.
  Without one, write the notes to a file on disk (not a tmpfs `/tmp`) and name it.

## 1. Read the clock, set the cutoff

Run `date '+%Y-%m-%d %H:%M %Z'` now. Every time you write comes from `date`
output in the same turn, so step 4 runs it again.

- **No deadline given:** the cutoff is now. Go to step 2.
- **A deadline given** (a clock time, or "in 30 min"): the **cutoff** is the
  deadline minus the time the wrap needs — about 15 min, or about 30 min when a
  helper or a test suite is expected to still be running at the cutoff.
- **A deadline with no time** ("later", "soon"): ask for the time in one
  line and keep working; with no answer, the cutoff is now.
- A deadline that has already passed counts as "now".

**Until the cutoff, keep working normally**, heartbeats included. Start an item
— yourself or by dispatching a helper — only if its estimate ends before the
cutoff; an item that would end after it waits for next session. In the same
turn, say in one line `Cutoff ≈17:15; wrap by 17:30. Until then: <what you
start>.` and arm a one-shot wake at the cutoff, in the `cache-warmth` form:

    Bash run_in_background: sleep <seconds to the cutoff, ≤3000>; echo "CUTOFF $(date +%H:%M)"

An idle session otherwise hears nothing until the next notification, maybe
after the deadline. A cutoff over 50 min out: when the wake fires early, re-arm
it for the time left. Work that runs out before the cutoff starts the drain
then; do not invent work to fill the time.

## 2. Drain

From the cutoff on, start nothing new: no agents, no background commands. In
this order:

1. **Wind down, with the heartbeat and the liveness sweep still armed** — a
   report can outlast the cache's hour, and the sweep notices a helper that
   dies (`cache-warmth`, `unattended-run`).
   - **Helpers:** give each a stop time — ~10 min before the deadline,
     or with none, now plus ~10 min. Before it, the helper commits only work that passes, on its own
     branch or worktree as the project's rules allow (otherwise it leaves it
     uncommitted and reports the path), and writes its checkpoint note
     (`CHECKPOINT.md`, returned with `STATUS: CHECKPOINT`, per
     `context-ceiling`). Wait for every report, not past the stop time. One
     still silent then is recorded as alive: agent ID or name, worktree, last
     known state.
   - **Background commands:** only those this session started, by task ID —
     never by process-name pattern (`pkill`), which can hit a run the user
     started. When the result is wanted, leave it running detached; `TaskStop`
     it only if it would interfere (writes into the tree, holds a lock).
     Record each one kept: task ID, command, log path.
2. **Then stop the timers**, once every helper has reported or the stop time
   has passed: `CronDelete` this session's crons; end a `/loop` by not calling
   `ScheduleWakeup` again, and say in **You** that it has ended; `TaskStop` the
   heartbeat, the cutoff wake, the sweep and any other `Monitor`. A timer that
   fires after the pause re-reads the whole context for nothing.
3. **Check, by named means, not from memory:** `CronList` for crons; every task
   and agent ID this session launched, found in its own tool calls or, after a
   compaction, in the handoff's or summary's running list, each confirmed by
   its status or output; `pgrep -f '<the command it launched>'` for a detached
   process, and `pgrep -fl 'sleep 3000|sweep\.sh'` for a heartbeat or liveness
   sweep whose launch is no longer in view — report any hit by PID, do not kill
   it: the pattern can match another session's timer. Write down what is
   still alive and why; "nothing running" only after the check. In **You**,
   ask the user to confirm with `/tasks`.

## 3. Save

**Inside an unattended run**, its record is the state: write the RESUME PACKET
and save it per `unattended-run` §8 steps 2–4, in place of this step, folding
any push or commit offer the handoff makes into **You**. Name the record as the
state in step 4, and add §8 step 6's goal line (items met) to **Done** and its
held items to **You**. Step 2 above covers §8's drain and timer stop.

1. Run the project's handoff (`/handoff wrap`, or update its handoff doc), and
   fold any push or commit offer it makes into **You** rather than asking now.
   Otherwise write the notes file: done, half-done and where, what is still
   running, the literal first step for next time, the decisions the user made.
   A fresh or already-compacted session takes "done" from the handoff and
   `git log`, not from memory.
2. Commit it if the project commits it. If nothing changed since the last
   commit, make no commit; the keep text names the actual `HEAD`.
3. **Push** only if the project's rules or this session's user allow it. If
   pushing needs a yes, ask once, in the final message (step 4), not mid-drain.

## 4. The final message

Run `date` again first: the header and the keep text's pause time come from
this turn, not step 1's. Nothing after the code block. Shape:

````markdown
**<timestamp from a fresh date in this final turn> — Paused**
- **Done:** <what finished in this stretch>
- **Left:** <half-done work and where it sits>
- **Running:** <each helper alive: ID or name, worktree, last state; each kept
  command: task ID, log> — or "nothing"
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
   one (`paused 2026-04-14 12:45 by the user, lunch`) — never an invented one;
2. where the state lives — handoff path, branch, head commit, pushed or not, other notes files;
3. done, then half-done with its location;
4. still running: each helper with its agent ID or name, worktree and last
   known state, each kept command with its log path — or `No agents, jobs or
   timers running.`;
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
| "They asked to compact, so I drain first" | Compacting alone keeps work running. Drain only on pause, drain or wrap-up. |
| "They said drain, so I stop now" | A deadline gives a cutoff. Work until it. |
| "I'll describe what's saved; they can ask for the command" | The `/compact` block is always the last thing in the reply. |
| "I'll ask about pushing now and wait" | Drain first; the push question goes in the final message. |
| "The heartbeat will just notice we're done" | It costs a full context read. Stop it — after the helpers report. |
| "Nothing's running, I'm fairly sure" | Check with `CronList`, the IDs this session launched, and `pgrep`. |
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
