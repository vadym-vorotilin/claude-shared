---
name: cache-warmth
description: Keep prompt caches warm while a session or its subagents wait — on a long command, a CI check, a dispatched agent, a merge, or an operator. Use when a session will wait more than a few minutes, runs long or unattended, dispatches subagents that build, test or render, or when writing a subagent brief; also when a wait "only takes six minutes" or a pause is about to rely on notifications alone.
---

# Cache warmth

An agent re-reads its whole context every turn. While the prompt cache is warm
that read is billed at the cache-read rate; once the cache expires, the next
turn rewrites the whole context at the cache-**write** rate — about ten reads'
worth. The expensive moment is not a long command but **idle time past the
cache's lifetime**, so waiting is where the cost hides.

There are two lifetimes and each gets its own rule:

| Who | Cache lifetime | The rule |
|---|---|---|
| A **subagent** | about **five minutes** idle | **Poll, do not block** — every wait call returns within about four minutes |
| The **main session** | about **an hour** | **Never take a turn to wait** — wake on a notification or a 50-minute heartbeat |

## What this assumes

- **Claude Code**, with the `Bash` tool's `run_in_background` and its exit
  notification, and the `Monitor` tool.
- **The two lifetimes above.** The harness and the plan set them, not you. If
  the main session is on the short cache too (it is when usage falls back to
  the five-minute TTL), the main-session rules collapse into the subagent ones:
  every wait returns within about four minutes. The shared status line shows
  each live agent's cache TTL.
- **GNU `timeout`** in the poll forms (`gtimeout` on macOS from coreutils).

The full reasoning, and why the obvious alternatives do not work, is in
[reference/why.md](reference/why.md). Read it when an agent argues the rule
does not apply to its role.

## Waiting in a subagent: poll, do not block

Anything expected to run longer than about four minutes runs **detached**, and
the agent polls it with a bounded wait per call:

```bash
timeout 230 bash -c 'until grep -qE "<done marker>" <log>; do sleep 15; done'; tail -3 <log>
```

- **The bound is a maximum, not an example.** Every poll call returns within
  about four minutes, whatever the command is expected to take. A longer bound
  never saves anything: each extra poll is one cache read, one bound past the
  lifetime is a full write.
- **It binds every role that waits**, not only the one that runs tests: a build,
  a checkout, a render, a browser session, a recording or a re-measured suite
  costs the same rewrite.
- **Verifying less is not the fix**, and neither is moving the slow command into
  another agent: someone still waits, and the waiting is what costs.
- **What stays banned is unpolled backgrounding** — `run_in_background` followed
  by a blind wait, or a `Monitor` armed and waited on.
- Set a long Bash timeout (e.g. `timeout: 600000`) so long commands are not
  auto-backgrounded behind the agent's back. It is a ceiling for a runaway
  command, never a poll cadence.

## Briefing a subagent

**Put [brief.md](brief.md) into every brief for a role that may wait**, verbatim
— `cat` it into the brief file rather than reading it into your own context.
A rule in a shared preamble the brief only points at gets skipped; the lines
have to be in the brief. A brief written ad hoc for a late or one-off role
(wrap, capture, board clean-up) is where the lines go missing most often.

Give the poll form, not just the ban — an agent told only what not to do
blocks anyway. And name the `Monitor` tool: "no monitors" on its own reads as a
Bash rule, and the agent then arms the tool and stalls on it.

## Waiting in the main session: never take a turn to wait

A foreground `until … sleep`, `tail`, `--watch` or task-output call in the main
session is one full context read to learn "not yet", and those reads come late,
at the largest context. Waiting has three shapes, and each has a form that costs
no turn:

| Waiting for | Form | Turns |
|---|---|---|
| a dispatched agent | its completion notification wakes you, **plus the heartbeat** below | 1 per 50 min |
| a condition on the world (a branch moved, a PR merged, a check landed, a log marker) | `Bash` with `run_in_background: true` running `timeout 3000 bash -c 'until <check>; do sleep 30; done'` — one notification when it exits; exits non-zero on expiry | 0 |
| a failure shape (a stalled or dead helper) | one persistent `Monitor` sweep that prints nothing while things look healthy — the unattended-run skill has the sweep | 0 |

**Bound every background wait at 50 minutes**, inside the main cache's hour, so
the wake reads the cache instead of rewriting it. **On expiry:** one
field-selecting read of the cause (the PR's state, the check's status), then
re-arm the same wait once. A second expiry is a stall — record it and ask, do
not arm a third wait.

### The heartbeat: from the first wait until the last

Completion notifications alone are not enough: a helper's run can outlast the
main session's hour, and the notification then lands on a cold cache. So **in
the same turn that starts the first long wait** (usually the first dispatch),
arm a one-shot 50-minute timer:

    Bash run_in_background: sleep 3000; echo "HEARTBEAT $(date +%H:%M)"

When it fires, **re-arm it first**, then do the cheap check your supervision
needs — file mtimes, `pgrep`, never a transcript read. If nothing moved, reply
with one line. Keep it through every wait, including a deliberate pause at an
operator gate or a quota drain: **a pause needs an armed timer, not a hope that
a notification arrives.** One pending background wait can stand in for it,
since it shares the 50-minute bound.

**Stop re-arming it when the session stops on purpose** — a finished run, or an
unattended run that has wrapped. A parked session that will be resumed fresh
does not need a warm cache, and a heartbeat that keeps firing after the wrap
pays for nothing. Say in the final message that it is off.

The form is chosen against these alternatives:
- **cron** fires at wall-clock minutes, so `7,47` gives uneven 20- and 40-minute
  gaps, which wake too often;
- **`Monitor`** is capped at 30 minutes, so a 50-minute timer cannot be one;
- **`ScheduleWakeup`** works only inside `/loop`.

## Red flags

- A brief that lets an agent **block** on a command expected to outlast its
  five-minute cache — the next turn rewrites the whole context at the write rate
- A poll form given as an example with no maximum — the bound gets stretched
  toward the Bash timeout to save turns; say "every poll call returns within
  four minutes"
- A live agent's transcript untouched for five minutes — its cache is gone;
  correct its poll bound rather than reading the silence as health
- A waiting role briefed without the poll rule because it "only reviews" or
  "only records" — every role that waits pays the identical rewrite
- A brief that says "no monitors" without naming the `Monitor` tool and
  *unpolled* `run_in_background`
- A `sleep`, `until`, `tail -f`, `--watch` or task-output call in the main
  session's own turn — the wait belongs in a background `until`, a sweep or
  the heartbeat
- A stall sweep or background wait whose interval is longer than the main
  session's cache — it pays the rewrite it exists to save
- Pausing by waiting for notifications — a pause needs an armed timer
- A long wait started with no 50-minute heartbeat armed in the same turn, or a
  heartbeat still re-arming after the session wrapped

## Common rationalizations

| Excuse | Reality |
|---|---|
| "The command only takes six minutes, I'll wait for it" | Six idle minutes is past a subagent's cache lifetime, so the next turn rewrites the entire context at the write rate — more than an order of magnitude above what the poll turns would have cost. Detach and poll. |
| "The command takes ten minutes, so a longer poll bound saves turns" | Each extra poll is one cache read. One bound past the lifetime is a full write — about ten reads' worth — so the longer bound can cost more than every poll it saved. The bound is a maximum, never an example. |
| "This agent doesn't run tests, so the poll rule doesn't apply" | It applies to whoever waits. A reviewer re-measuring a suite, a screenshot agent driving a browser, a recording agent and a wrap agent all pay the identical rewrite. |
| "The brief said no monitors" | It read as a Bash rule. Name the `Monitor` tool, or an agent blocks on one like any other wait. |
| "I'll pick it back up when the notification arrives" | A pause with no armed timer is a pause that runs past the cache. Arm the heartbeat, then pause. |
