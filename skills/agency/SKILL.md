---
name: agency
description: Use when a session will dispatch subagents or workflow agents and must choose each one's model and effort, when starting a subagent-driven session, or when asked which model or effort fits a task — Haiku, Sonnet, Opus or Fable, low to xhigh — or whether to switch the session's own model. Also read by skills that dispatch (orchestrating-issue-runs, research, grill-review) before their first dispatch.
---

# agency — the right model and effort for each piece of work

A subagent dispatched without `model` and `effort` **inherits the session's**.
A session on the top tier at high effort then runs every helper there,
including the ones that only grep, read a log or rename a symbol. Sessions left
to choose also choose differently each time: the same caller survey goes out
cheap/low in one session and mid/medium in the next.

**Core rule: every dispatch names its model and its effort, taken from a row of
[matrix.md](matrix.md), before it goes out.** Read `matrix.md` now, whole; it
holds the tiers, the rows and the escalation rule. This skill is the explicit
instruction the Agent tool's `effort` setting asks for.

**Priorities, in order:** nothing bad ships, then quota. Start low where a
wrong guess is caught before it ships — by a test, a review or you. Start high
where it would not be: load-bearing code, and any review that gates a merge.

## What this assumes

- **Claude Code** with the Agent tool's `model` and `effort` settings (and
  Workflow `agent()` options, where workflows run). Elsewhere, map the classes
  cheap / mid / top / strongest onto the models the harness offers.
- No strongest tier on the user's plan → top stands in for it.

## For the whole session

Once loaded, this holds for the rest of the session, for every dispatch —
not only the next one. When the conversation is compacted, carry the line
"`/agency` in force: dispatches take model and effort from
`agency/matrix.md`" into the summary.

**Before each dispatch, write its line** in the reply:

    task — agent type — model / effort — matrix row

**Escalate one task, not the set** (matrix.md → "Escalation"): a thin or unsure
result reruns alone, one tier and one effort level up, with what the first try
found.

## Recommending the session's own tier

The session cannot change its own model or effort; the user can. When the
shape of the work changes, say so **once**, in one line, with the command:

- A long mechanical or locating stretch begins, and the session's own turns
  are mostly dispatch: "The rest is mechanical; `/model sonnet` would do for
  overseeing it."
- A call comes up that the session cannot settle confidently, and no advisor
  dispatch fits (it is the session's own judgment, not a ruling to hand off):
  "This design call is past what I settle confidently; `/model fable` for it,
  then back."
- The session is on the strongest tier for routine orchestration:
  "Orchestrating doesn't need Fable; `/model opus` would do."

Then carry on. Never repeat it after the user has chosen, and never claim a
switch the user has not made.

## Red flags — stop

- A dispatch with no `model` or no `effort`
- A cheap-tier agent writing files, or the session doing a mechanical
  multi-file change itself on a pricier tier
- A merge-gating review below top, to save quota
- A version-specific or recent-facts web lookup at low effort
- Escalating every task because one came back weak; escalating effort two
  levels at once
- Escalating a question about *what is wanted* to a bigger implementer
- The strongest tier implementing, reviewing or orchestrating — it advises
- A model recommendation repeated, or one every turn
