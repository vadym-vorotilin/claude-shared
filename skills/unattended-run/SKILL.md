---
name: unattended-run
description: Run a long task without the operator present — a solo session, or one that dispatches its own helper agents — and stop cleanly when nothing more can be done without them. Use when the user says "unattended", "continue unattended", "run until you need me", "keep going while I'm away", "work on this overnight", or leaves a long task running across a quota reset.
---

# Unattended run

**Unattended means no mid-run questions — not no approval.** The operator
approves the goal, the plan and the authority before leaving; after that the
session decides what it can, parks what it cannot, keeps a record a stranger
could resume from, and stops on its own with one message that says exactly what
waits on the operator.

This skill leans on two others; read them at the start:
- **`cache-warmth`** — waiting without paying for a cold cache, and the
  50-minute heartbeat that keeps the session warm while helpers run;
- **`context-ceiling`** — the session's own context number, the helpers'
  ceiling, and when to resume a dead helper or continue from its note.

## What this assumes

- **Claude Code**, with background Bash, the `Monitor` tool and, for helpers,
  subagents that can be resumed with `SendMessage`.
- **The `token-report` skill** for the budget figure. Without it, say in every
  report that spend is unmeasured rather than estimating it.
- **`git`** for the record and the state checks. A non-git task works, but the
  stop sequence's commit steps then become "write to disk".
- **An operator who reads a final message**, not a live dashboard.

## 1. Before going dark: goal, plan, authority

Get all three **before** starting, in one message, and wait for the answer. If
the operator said "unattended" with a task already agreed, confirm them in one
line each; do not start on an assumption.

- **The goal** — one sentence naming an observable outcome, testable by
  looking at the artifact: a page that loads, a report that opens, a command
  that passes. Every decision and the final message key on it.
- **The plan** — the items that close the goal, in order, and what is
  deliberately out.
- **The authority** — what the session may do alone. Ask about each one that
  applies; **anything not granted is reserved**:
  - commit, push, open PRs, merge, close issues;
  - deploy or publish anything;
  - delete branches, files or data; rewrite history;
  - spend above a stated token budget.

A project's `CLAUDE.md` or overlay can only narrow this, never widen it.

## 2. Decide or park — per item, never the run

- **Decide alone**, and log the decision with its reason, when it is reversible
  or already settled by the project's specs, docs or the plan.
- **Park the item** when it is hard to reverse **and** a real trade-off nothing
  written settles, or when it needs authority the operator did not grant. A
  parked item gets a line in the record and an entry on the **held list** —
  the question, the options, and what you would choose — and the run moves to
  the next item. One operator-only question never stops the run.

## 3. The record

A markdown file **on disk** — not a tmpfs `/tmp`, which can be cleared between
sessions — written **before** the first piece of work: the goal, the plan, the
authority, the held list, and one log line per meaningful event. It is
**append-only**; read its tail, never the whole file, and grep it by item.
Keep a line under ~300 characters: the detail goes in a file the line names.
After a compaction or a limit reset, trust the record and `git log` over
memory.

## 4. Progress stamps

The operator should never have to ask where the run is. After each meaningful
completion — an item done, a helper's result, a merge — emit exactly:

```
**<date and time> - Progress: Goal <met>/<total> · N%**
<one line about what just happened>
```

- **Goal items met / total first; the percentage second.** The percentage
  measures effort spent, not progress — a run can spend most of its effort
  while moving no goal item. Count the items once, at the start, and never
  re-cut the denominator. With no list, the goal is the single item.
- **Run `date` for every stamp, in the turn that emits it.** Never add elapsed
  time to the last stamp: reckoned stamps drift ahead of the clock unnoticed.
  The same goes for every time written in the record.
- **The stamp is the final text of its turn — no tool call after it.** Text
  followed by tool calls is not reliably rendered, and a run can look silent
  while reporting diligently. Order on a completion: budget read → record line
  → next action → stamp. If work remains, end the turn and continue on the next
  event.
- **Fix the weighting once and keep it.** Weight items by expected cost, not by
  count; unfinished is not done. A downward correction is fine — say so in the
  line. A number that only ever rises is not a measurement.
- Record the session's context figure (`context-ceiling` → `context-size.py`)
  in the record beside each stamp.

## 5. Budget

Read the spend, never guess it — between items and before any expensive step:

```bash
python3 ~/.claude/skills/token-report/token_audit.py --since <run-start> --json \
  | python3 -c 'import json,sys
d = json.load(sys.stdin)
if d["root_missing"] or d["turns"] == 0:
    sys.exit("token-report: no transcripts counted (check --root / --since); refusing to report $0")
print(d["usd"])'
```

`--since` is day-granular (`YYYY-MM-DD`). A zero is a claim to check, not a
result: a mistyped window and a mistyped `--root` both total zero. Record the
figure beside the stamp so a drain is decided on a trend.

**At the budget, or when the operator calls the quota, drain:** start nothing
new, let in-flight work finish, leave each unfinished item in a state the next
session can pick up (committed, its facts written down), and stop (§8).

## 6. Helpers

When the run dispatches agents:

- **Brief them** with the `cache-warmth` and `context-ceiling` brief blocks,
  verbatim, plus a ban on dispatching their own subagents — forked helpers
  writing one shared output file clobber each other.
- **Never take a turn to wait on them** (`cache-warmth`): their completion
  wakes you; the heartbeat covers a helper that outlasts the hour.
- **Watch for silent death with one sweep, not a timer per helper** — below.
- **Rescue a dead helper** by resuming it with `SendMessage` to the same agent
  id, after verifying its worktree, branch and PR state yourself and handing
  those facts back ("recreate the worktree at a fresh path if it is gone").
  Above its ceiling, or cold with a large context, continue from its checkpoint
  note instead (`context-ceiling`). Re-dispatch fresh only when the resume
  itself fails. **If the session itself crashes, resume that same session** —
  agent handles are session-scoped, so only it can message its helpers.
- **A stalled helper** that says it is "waiting for the background task": tell
  it to poll with the bounded form from its brief, then finish and return.
- **When the nudge fails, remove the dependency.** If what it waits on has not
  started — a queued CI run, a job with no runner — a better wait stalls it
  again. Take the gate off it: have it return with the gate's state, and own
  that gate yourself.
- **While one helper runs, prepare the next brief** instead of waiting.

### The liveness sweep

Helpers die silently — a quota, a mid-stream API error, a stalled wait — and
the run reads as "still working". A timer per helper pays a full context read
on every firing to learn "still alive". Instead arm **one** persistent
`Monitor` at the first dispatch that **prints nothing while things look
healthy**:

```bash
: "${SCRATCH:?set SCRATCH to the directory holding the helper worktrees}"  # no silent no-op
# Assumes: each helper works in a directory matching $WATCH (default: $SCRATCH/wt-*/)
# and GNU find (-newermt with a relative date; on BSD/macOS use -mmin -$STALE_MIN).
shopt -s nullglob
WATCH="${WATCH:-wt-*/}"      # glob, relative to $SCRATCH
STALE_MIN="${STALE_MIN:-30}" # 15 fires on healthy test runs; see below
INTERVAL="${INTERVAL:-120}"  # seconds between passes
GRACE=3                      # passes to allow before the first directory exists
said=""                      # directories already reported, so each STALL is said once
armed=0; empty=0
while true; do
  dirs=()
  for d in "$SCRATCH"/$WATCH; do [ -d "$d" ] && dirs+=("$d"); done   # a literal WATCH can name a missing dir
  if [ ${#dirs[@]} -eq 0 ]; then
    empty=$((empty + 1))
    # Speak once the sweep has ever seen a directory (they vanished), or once
    # the grace period is up (it was armed on the wrong path) — then STOP.
    if [ $armed -eq 1 ] || [ $empty -gt $GRACE ]; then
      echo "SWEEP DOWN: nothing matches $SCRATCH/$WATCH — not watching anything"
      exit 1
    fi
    sleep "$INTERVAL"; continue
  fi
  armed=1; empty=0
  for d in "${dirs[@]}"; do
    if find "$d" -name .git -prune -o -newermt "-${STALE_MIN} minutes" \
         -print -quit 2>/dev/null | grep -q .; then
      said="${said//"|$d|"/}"       # healthy again: a later stall is news
      continue
    fi
    case "$said" in *"|$d|"*) continue ;; esac
    said="$said|$d|"
    echo "STALL: $(basename "$d") — nothing written for ${STALE_MIN}m"
  done
  sleep "$INTERVAL"
done
```

- **Silent while healthy, and each STALL said once** — otherwise it is the
  per-helper timer again, wearing a loop. A directory that recovers and stalls
  again is reported again. **It speaks on every failure shape you would act on.** Add
  signals to suit the run: a helper transcript not written to for 30 minutes
  (`COLD: <agent>`, once per agent), a PR that should exist by now.
- **The thresholds are not arbitrary.** At 15 minutes on files or 5 on a
  transcript, the sweep fires on healthy work, and every wake is a full-context
  turn. `.git` is pruned on purpose: index churn from a stuck command is not
  progress.
- **It says `SWEEP DOWN` once and exits** — on an empty match after the grace
  period, or at once when directories it saw have vanished. That is an action,
  not a notification: fix what it names (usually `$SCRATCH` pointing at the
  wrong path), check the helpers by hand once, and **arm a new sweep**. Until
  then nothing is watching, and silence means nothing.
- **On `STALL`, verify before acting** — commit time, `git status`, the PR,
  the transcript's last write, running processes — and rescue only what is
  genuinely dead. A long helper is not a dead one. `TaskStop` the sweep when the
  run ends.

## 7. When to stop

Stop at the first of these:

1. **every remaining item needs the operator** — a parked decision, a reserved
   act, a release;
2. **the session's soft context ceiling** (`context-ceiling`), at the next
   natural boundary. Attended, that means offering a handover; unattended, it
   means taking it;
3. **the budget** (§5): drain, then stop;
4. **a stall that survived one rescue.**

## 8. The stop

In one turn, in this order:

1. **Drain**: let in-flight helpers finish; start nothing new.
2. **Write the RESUME PACKET into the record**: the goal line and items met,
   what is done (with commits, PRs), what is in flight or half-done and where,
   the held list, and the literal first step for the next session.
3. **Commit the record** — and push it **only if pushing was granted** in §1;
   otherwise say in the final message that it is committed locally.
4. **Run the project's own handoff, if it has one** (`/handoff wrap`, or its
   handoff doc), and commit that too.
5. **Stop re-arming the heartbeat** and `TaskStop` the sweep. A stopped run does
   not keep its cache warm: the next session starts fresh from the record.
6. **Send the final message**: what is done, the goal line with items met,
   **exactly what waits on the operator** — each held item with the decision it
   needs — the record's path, and that the heartbeat is off. Any extra task the
   operator attached (a report, an analysis) comes after the stop, in this same
   message.

## Red flags

- Starting on "unattended" before the operator approved goal, plan and authority
- An act the operator did not grant, done because nobody was there to ask
- Stopping the whole run for one operator-only question
- A progress stamp with a tool call after it — the stamp ends the turn, always
- A stamp or record time extrapolated from the previous one instead of read from
  `date` in that same turn
- A stamp that leads with effort spent instead of goal items met
- Arming a check-up timer per helper — one silent sweep covers them all
- Re-nudging a stalled helper when what it waits on has not started — remove
  the dependency instead
- Starting new work after the operator called the quota
- A heartbeat still firing after the stop, or a record pushed without push
  authority

## Common rationalizations

| Excuse | Reality |
|---|---|
| "User said unattended, so start now" | Unattended = no mid-run questions, not no approval. Get goal, plan and authority first. |
| "Nobody is here to ask, so I'll decide" | Reversible or already settled: decide and log. Hard to reverse and a real trade-off, or not granted: park the item and move on. |
| "I stamped the progress, then dispatched the next helper" | Text before tool calls may never render, so a run can look silent while reporting. The stamp is the last thing in the turn. |
| "The check-up timer is cheap insurance" | Per helper, on a fixed interval, it re-reads the whole context to learn "still alive" — and still finds a stall up to a full interval late. One silent sweep is cheaper and faster. |
| "It's still queued, I'll nudge it to wait properly" | Nothing has started. A better nudge stalls it again — take the gate off the helper and own it. |
