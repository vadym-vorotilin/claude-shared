---
name: progress
description: Give a short, timestamped progress update — count, estimated percentage and ETA in one header line — then keep working. Load this skill rather than answering from memory; it injects the clock time when it loads. Use when the user asks "progress?", "ETA?", "progress, ETA?", "how far along?", "how long left?", or "/progress" — typically mid-task, while work is still running.
---

# progress — a glance, not a report

Assumes Claude Code skill shell injection, a POSIX `date`, and Bash. For a full
account of a long session, use `/short-brief` instead.

**Timestamp.** Rendered by `date` when this text loaded:

> !`date '+%Y-%m-%d %H:%M %Z'`

Use it only if this text arrived in this turn and the line shows a time;
otherwise run `date '+%Y-%m-%d %H:%M %Z'` with Bash. **Never write a
time that did not come from `date` output in this turn.**

**Shape** — nothing before it; omit any bullet with nothing to say (never
"Blocked: nothing"). **Every bullet under ~8 words, done and idle forms
included.**

```markdown
**<timestamp, verbatim> - Progress: <n/m> · ~<pct>% · ETA <~duration>**
- **Done:** <what finished>
- **Now:** <the one thing in hand, incl. running agents or CI>
- **Next:** <what remains>
- **Blocked:** <what — who unblocks>
- **ETA:** ≈<clock> · <high|medium|low> — <main unknown>
```

- The separator before `Progress` is a plain hyphen (` - `), as in the
  orchestrating-issue-runs and unattended-run progress lines, so one stamp
  check reads all three. Never an en or em dash.
- `n/m`: plan or task-list steps; else the steps behind Done, Now and Next.
- `~pct%`: estimated *work* done, not `n/m` as a fraction. Round to 5.
- ETA: wall-clock duration, a range if the spread is real. The bullet's clock
  time is the timestamp plus the duration (or the range's midpoint), rounded to
  5 min. Never "soon".
- If the last update's ETA differs, append it to the ETA bullet: `was ≈14:40`.
- Done: header `m/m · 100% · ETA done`, then only `Done` and `Next`.
- Idle (nothing started yet): `<timestamp> - Progress: idle`, then only
  `Next: you — <what>`, then stop.

**Then resume the work in the same turn.** No question, offer or summary after
the update.

Fictional example:

```markdown
**2026-04-14 14:32 CEST - Progress: 3/5 · ~55% · ETA ~20–30 min**
- **Done:** CSV parser, tests, `--strict` flag
- **Now:** parser into import command
- **Next:** `--strict` docs, full test run
- **ETA:** ≈14:55 · medium — suite unrun; was ≈14:40
```
