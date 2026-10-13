---
name: orchestrating-issue-runs
description: Use when the user asks to orchestrate execution of multiple spec-backed GitHub issues with subagents — implement, review, and merge across one or more repos, attended or unattended. Triggers - "orchestrate the open issues", "work the backlog with subagents", "run the pipeline by hand", "execute these issues in parallel streams".
---

# Orchestrating issue runs

> **Project overlay — read `project.md` FIRST if one sits in *this project's*
> skill directory.**
> A project keeps its overlay at
> `<project>/.claude/skills/orchestrating-issue-runs/project.md` — in the
> project's own skill directory, never inside the shared `claude-shared`
> checkout, which is public and is where an overlay's private gates would be
> published. Read it before the runbook and before Phase 0. **Where the overlay
> or the repo's `CLAUDE.md` conflicts with anything here, they win** — this
> skill is generic and a project knows its own gates.
>
> The overlay is a separate file **by convention, so this one never has to be
> edited to install it.** An install that edits the shared files cannot be
> updated without a merge, so it rots — and a rotted overlay fails silently:
> the project's own overrides stop loading while everything still looks
> installed — and what stops loading could be a rule reserving merges to a
> human. Give the project its own skill directory, symlink
> `SKILL.md`, `runbook.md` **and `reference/`** there from the shared copy so
> they stay byte-identical — the two `reference/` files hold the full red-flag
> and rationalization sets that SKILL.md only samples, and an install that
> symlinks the first two alone leaves those pointers dangling in exactly the
> way nobody notices. Put every local difference in `project.md`, which stays
> with the project. Install the **`cache-warmth`** skill beside it too
> (symlinked the same way), with **`context-ceiling`** and **`unattended-run`**:
> the runbook's briefs `cat` their `brief.md` files, and its sweep, stamps and
> stop live in `unattended-run`. The ceiling hook is not installed by any
> symlink — run **`/add-context-ceiling`** on the project.
>
> **Verify the overlay actually loaded before the first dispatch** — ask the
> session to quote a line that exists only in `project.md`. A machine that has
> run `sync.sh` already carries this skill under the same name in
> `~/.claude/skills/`, and which copy wins is not something this skill can
> promise; if the project's does not, give the project directory a distinct
> name and point the operator at it.
>
> **The most dangerous thing an overlay can carry is a narrower authority than
> this skill assumes.** This skill assumes the orchestrator merges. If a
> project reserves merges, deploys, or any other act to a human, that is in
> the overlay, and it is the first thing to check before dispatching.

Turn a backlog of spec-backed GitHub issues into merged PRs using subagents,
with exactly two kinds of human involvement: **scope approval before anything
runs**, and **gates the human genuinely owns** (spec freezes, machine changes,
external data, plan changes). Everything else — approaches, implementation,
review, fix rounds, merges — runs in the agent loop.

The orchestrator coordinates and decides; it never implements and never
reviews code itself. Its context is for coordination.

**Model check at run start.** Orchestration is coordination, not the run's
hardest thinking — the strongest tiers are dispatched per the table below,
while the orchestrator's own turns are mostly dispatch and bookkeeping that
re-read its context. Run the orchestrator session on the **top standard tier
(Opus-class)**: the strongest tier lists at roughly twice the rate per token
and buys nothing on a ledger turn. A session inherits the user's default model,
which is how a run ends up on the priciest tier with nobody having decided to.
**The orchestrator cannot switch its own model** — if it finds itself on a
pricier tier it asks the user to run `/model opus` **before dispatching the
scope agent**, not in the message that posts the scope: dispatching the survey
and reviewing what it returns are already paid at the session's own tier.

**REQUIRED READING before the first dispatch:** [runbook.md](runbook.md) —
phase mechanics, briefing templates, and the protocols below in full.
Open it **by section** — list the headings, then read the range you need. A
session that Reads it whole carries all of it on every later turn; the
resume packet rule (runbook → "The resume packet") bounds what a fresh
orchestrator reads before its first dispatch.

## The flow

```
Phase 0  GOAL       one sentence, written FIRST: the observable outcome this
                    run must produce, testable by looking at the artifact
                    (iron rule 11). It bounds the wave, every brief and the
                    progress stamp.
         SCOPE      a DISPATCHED agent reads specs, ADRs, memory, issues,
                    board, open PRs, prior-run ledgers → returns the MINIMUM
                    dependency-ordered wave plan that closes the goal, what it
                    leaves out by name, per-issue model tier, a filing budget,
                    and an inconsistency sweep. The orchestrator reads the doc,
                    not the sources.
         APPROVE    scope doc posted as a message; found inconsistencies
                    listed for approval before any issues are filed.
                    NO DISPATCH OF RUN WORK BEFORE THE USER APPROVES.
Phase 1  RUN        per issue: approach → go-gate → fix (TDD, worktree)
                    → independent review → fix rounds (resume,
                    budget-capped, hard cap 5)
                    → merge on clean → close, board sync, ledger, report
Phase 2  WRAP       demo evidence + domain walkthrough review (an agent uses
                    the artifact as the end user would; rubric lives in
                    the project repo, never here) + demo document
                    (published as a release if
                    the run's memory says demos are published — asked at
                    Phase 0, answer saved to memory), milestone CLOSED,
                    deferred register → operator ruling → filing, then the
                    board-consistency sweep as the run's last board action
                    (whatever the operator defers instead carries into the
                    next run's Phase 0), run summary, memory update, and the
                    skill self-update (runbook.md → Self-improvement)
```

## Unattended mode

When the operator says "unattended", the run follows the **`unattended-run`**
skill: run until nothing more can be done without the operator or a ceiling is
reached, then stop with one message naming exactly what waits on them. How it
maps onto this skill:
- **Approval before going dark is the scope approval** (iron rule 1); the
  **authority** is the scope doc plus the overlay's human gates.
- **A design question goes to the adjudicator** (iron rule 4), not to the
  operator. **An operator-only question parks its card** (label `needs-human`,
  a ledger line, the held list); the rest of the wave keeps going.
- **The record is the ledger**; the stop runs the project's handoff wrap. See
  runbook → "Unattended mode".

**Waiting, attended or not, follows the `cache-warmth` skill.** The
orchestrator never takes a turn to wait, and it arms that skill's 50-minute
heartbeat in the same turn as the first dispatch, re-arming it until the wrap.
Every brief for a role that waits carries its `brief.md` lines verbatim. See
runbook → "The orchestrator never takes a turn to wait" and "Heartbeat".

## Iron rules

1. **No dispatch of run work before scope approval.** "The user said
   unattended" is not approval of a scope they haven't seen. Present the scope
   doc, wait. The Phase 0 scope agent is the one exception, because it is what
   produces the doc being approved — nothing downstream of it moves until the
   user has.
2. **Worktree per agent, always** — including coupled tasks. Coupling is
   handled by merge order and declared file surfaces, never a shared checkout.
3. **Verdicts are data; the orchestrator merges — unless the project says
   otherwise.** Check `project.md` and `CLAUDE.md` for a human merge gate
   before the first dispatch, and put it on the held-for-human list if there is
   one; a run that merges through a gate the project reserved cannot be undone
   by noticing later. A reviewer never merges.
   An implementer never reviews its own diff. Merge = review clean + checks
   green + no open human gate.
4. **Design questions stop the issue, not the run.** A strong-model
   adjudicator rules with spec citations posted as a binding issue comment;
   docs amendments become PRs the **orchestrator squash-merges itself** —
   after the gate in rule 3, and after the paired code PR (or immediately if
   standalone) — no held queue; code proceeds on the ruling. **Exception: an amendment that edits a FROZEN spec
   or contract still goes to the held-for-human list.** Escalate to the human
   only what is hard-to-reverse AND a real trade-off the specs don't already
   decide.
5. **Ledger before first dispatch** (scratchpad file: waves, per-issue state,
   rulings, deferred minors, resume queue). Survives compaction and limits.
   Dead agents are **resumed from their transcripts** — while they are still
   under the context ceiling (rule 9). Above it, or with a cold cache, **continue
   from its checkpoint note instead** (`context-ceiling` → "Resume under the
   ceiling; continue above it"). If the agent
   id is genuinely unrecoverable, dispatch with the ledger's state summary plus
   the worktree, branch and PR facts you verified yourself.
6. **Nothing deferred silently — and not everything deferred becomes a card.**
   Every non-blocking finding gets a ledger entry and a close-comment mention.
   A **follow-up issue** on top of that only when the finding moves the run's
   goal line (rule 11), and only after the user approved creating it, per scope
   rules. "Nothing deferred silently" is easily read as "everything deferred is
   filed", and the register then manufactures work: a run can file more cards
   than it merges, every one a real finding and none of them on the goal.
   **Set a filing budget in the scope doc and report filed-to-merged in the
   wrap.** Two runs above 1 means the mechanism is producing the backlog.
7. **Budget = graceful drain.** At the token target: start nothing new, let
   in-flight rounds finish, report, pause. **Measure it, don't estimate it** —
   `/token-report`'s `--json` total between waves and before each fix round
   (runbook → Budget check). A budget rule with no instrument is a wish.
8. **Report progress after every substantial agent completion** — a stamped
   `**<date and time> - Progress: Exit <met>/<total> · N%**` line plus one line
   of what happened. **The time comes from `date` in that same turn, never
   from reckoning** — an estimated stamp drifts from the clock, and a stamp the
   reader cannot trust is worse than none. **Exit items first, card cost second**: the percentage
   measures spend consumed, and a run can consume most of its cards without
   moving a single Exit item. Weight the percentage by expected issue cost,
   never by count; unmerged is not done. Read `context-size.py` (`context-ceiling` skill) in
   the same turn and record its `current` in the ledger — that is the orchestrator's
   own context instrument (rule 9). See runbook.md → Reports.
9. **Context is a budget, and the orchestrator's is not the fixer's** — the
   **`context-ceiling`** skill holds the rule, the instruments and the
   checkpoint note. Its numbers, as this run uses them:
   - **Fixers and other long-running dispatched agents stop at ~150k, write a
     checkpoint note, and return it** (hard stop ~200k), enforced by the hook
     `/add-context-ceiling` installs; the orchestrator dispatches a
     continuation from that note.
   - **The orchestrator's ceiling is soft 200k / hard 500k**, read with
     `context-size.py` **at each progress stamp** into the ledger. Past the soft
     one it does not stop — it **offers the operator a handover at the next
     natural boundary**: a merge, a wave end, a ruling.
   - **Reviewers are exempt from the ceiling but not from a budget** — a verdict
     does not split; a reviewer gets a **turn budget** and reports what it could
     not cover. Its length is a larger lever on cost than its tier, so keep
     reviewers on the stronger tier and bound their length — save on length,
     not on tier.

10. **A threshold ships with the instrument that reads it.** No agent can see
    its own context size: the harness does not report it and `/context` belongs
    to the operator, so "stop at N tokens" is a rule its subject cannot obey and
    it will be breached silently, and by a wide margin. Every threshold in a
    brief must therefore come with a way to read the quantity, or be restated as
    something the agent can already see: a turn count, a wave boundary, a
    deliverable.
    Where no instrument exists, build one — a `PreToolUse` hook receives the
    transcript path, so it can measure the agent and inject the warning, which
    turns instruction into enforcement. **A threshold with no instrument is
    decoration, and worse than none: it reads as a control that is working.**
    An agent measured past **twice** its stated ceiling is an instrument that
    did not bind — fix it before the next dispatch.
11. **The run has one goal line, and it is written before Phase 0.** One
    sentence naming the observable outcome — a report that opens, a screen
    that loads, a recording someone can watch — testable by looking at the
    artifact, not at the board. Everything downstream keys on it:
    - the **scope agent derives the minimum card set that closes it** and names
      everything else as out of the wave, by name, in the doc;
    - **every brief carries the goal line**, and the return contract asks what
      the deliverable moved on it;
    - the **progress stamp reports Exit items met / total FIRST**, card cost
      second (runbook → Progress line);
    - **rulings are sized by the goal.** A question that does not change the
      Exit does not get a durable design record; one probe is run per card
      before the operator is asked anything. Above roughly two rulings per
      merged card, the spec is the defect — propose the change as one batch.

    Without it the unit of work is the card, and a backlog will always supply
    more cards than a goal needs. A run that ends with the Exit unmoved and the
    cards closed has diverged, however well the loop ran.

## Model tiers (defaults; record per-issue tier in the scope doc)

| Work | Tier |
|---|---|
| Approaches, mechanical fixes, standard reviews, re-reviews | cheap/mid (Sonnet-class) |
| Load-bearing implement/review: core types, schema, cache/graph logic, anything that runs unattended with write access | top standard (Opus-class) |
| Design adjudication | strongest (Fable-class) — requires the scoped brief in runbook → Adjudication |
| Contract/freeze drafts, Phase 0 scope | strongest available |
| Repeat of an already-merged pattern | one combined approach+fix agent, cheap tier |
| Doc/comment text + mechanical tests, zero non-comment production lines | orchestrator verifies instead of dispatching a review — confirm no production diff and no fixture bytes moved, then **re-apply a discriminating mutation yourself on a different axis than the fixer's**. The mutation is what makes it safe; the greps alone are not a gate. |

## Red flags — stop, you are about to violate the flow

**The full set is [reference/red-flags.md](reference/red-flags.md)** — 55 rows,
grouped, none deleted; the waiting and cache rows are in the `cache-warmth`
skill, the ceiling rows in `context-ceiling`, the stamp, sweep and quota rows
in `unattended-run`. Read it once at run start and again at any wave boundary
where the run changed shape. These ten fire the most often:

- About to dispatch a fixer and the user hasn't approved a scope doc
- A run with no goal line — or a wave larger than the minimum card set that
  closes it, with nothing naming the rest as out of the wave
- Filing a card for a finding that moves nothing on the goal line — that is a
  close-comment line, not a card
- A follow-on milestone most of whose cards descend from its predecessor's —
  a stop signal, not a backlog; the direction question goes to the operator
  before dispatch
- The orchestrator reading the specs, issues and PRs itself in Phase 0 — that
  survey belongs to the dispatched scope agent, which takes the context away
  with it
- A reviewer prompt that says "merge if clean", or fixing a finding yourself in
  the orchestrator session
- A brief that lets an agent **block** on a command expected to outlast its
  prompt cache (~5 min idle), or that says "no monitors" without naming the
  Monitor tool and *unpolled* `run_in_background`, or that does not ban the
  agent dispatching its own subagents
- Re-dispatching a task whose agent died instead of resuming it — and, the
  other way, resuming a cold agent already over the ceiling, which is a
  continuation from its checkpoint note
- Escalating a fixer's "the requested design is infeasible" before leave-one-out
  has **named** the conflict — and a menu that omits DEMOTING the rule it names
- A progress stamp with a tool call after it, or one that leads with card cost
  instead of Exit items met / total

## Common rationalizations

**The full set is [reference/rationalizations.md](reference/rationalizations.md)**
— 49 rows, none deleted; the waiting and cache rows are in the `cache-warmth`
skill, the ceiling rows in `context-ceiling`, the unattended rows in
`unattended-run`. These ten fire the most often:

| Excuse | Reality |
|---|---|
| "User said unattended, so start now" | Unattended = no mid-run questions, not no scope gate. Present scope first. |
| "The scope doc lists the open cards, that is the plan" | A card list is not a goal. Write one observable outcome first, then derive the minimum card set that closes it and name the rest as out of the wave. Otherwise every card that exists reads as in scope. |
| "The finding is real, so it gets a card" | Real and irrelevant to the goal is a close-comment line. A register that files every real finding generates work: measure filed-to-merged, and two runs above 1 says the mechanism is producing the backlog. |
| "It's a follow-on milestone, so the backlog says what to do next" | Compute the lineage — what share of its cards descend from the predecessor's. Above about half, the predecessor did not close its question and this one will re-cut the same defects. Ask the operator before dispatch. |
| "The command only takes six minutes, I'll wait for it" | Six idle minutes is past a subagent's prompt-cache lifetime, so the next turn rewrites the entire context at the write rate — more than an order of magnitude above what polling costs. Detach and poll. |
| "The spec gap is obvious, I'll just decide" | Cheap now, contradiction later. Adjudicator + citation + binding comment costs one dispatch. |
| "The rule is in the spec, so the choice is amend it or re-author the inputs" | There is a third: **demote** it — hard to soft, soft to advisory. Demotion is always on the menu when leave-one-out names a rule as the conflict, and where the spec states its own cutting order, quote that order. |
| "Tests are green, the constraint works" | Green survives inputs the check is blind to — a symmetric, self-paired or uniformly shifted case. Mutate position — and where the rule is about *which of two objects* is involved, a whole-structure transform moves both at once and can stay green while the rule is broken. Move one of them. |
| "The reviewer told me how to fix it" | A remedy that covers most shapes of a defect can still be **false at the correct value** and ship red. A right finding can carry a wrong fix; measure the remedy before adopting it. |
| "X already does this work, so my code can't be the one that fails" | Does X **carry the value forward, or ask again?** An impossibility claim usually slides over exactly that step. |
