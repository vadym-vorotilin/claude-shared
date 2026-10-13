---
name: orchestrating-issue-runs
description: Use when the user asks to orchestrate execution of multiple spec-backed GitHub issues with subagents — implement, review, and merge across one or more repos, attended or unattended. Triggers - "orchestrate the open issues", "work the backlog with subagents", "run the pipeline by hand", "execute these issues in parallel streams".
---

# Orchestrating issue runs

> **Project overlay — read `project.md` FIRST if one sits in *this project's*
> skill directory.** Where the overlay or the repo's `CLAUDE.md` conflicts with
> anything here, they win. **The most dangerous thing an overlay can carry is a
> narrower authority than this skill assumes** — this skill assumes the
> orchestrator merges; check the overlay for acts reserved to a human before the
> first dispatch. Installing an overlay, and what this skill assumes about the
> toolchain: [INSTALL.md](INSTALL.md).

Turn a backlog of spec-backed GitHub issues into merged PRs using subagents,
with exactly two kinds of human involvement: **scope approval before anything
runs**, and **gates the human genuinely owns** (spec freezes, machine changes,
external data, plan changes). Everything else — approaches, implementation,
review, fix rounds, merges — runs in the agent loop.

The orchestrator coordinates and decides; it never implements and never
reviews code itself. Its context is for coordination.

**Model check at run start.** Run the orchestrator on the **top standard tier
(Opus-class)** — its turns are dispatch and bookkeeping, and the strongest tier
costs about twice as much per token for nothing there. It cannot switch its own
model: on a pricier tier, ask the operator to run `/model opus` **before the
scope dispatch**.

**"The operator"** is the human who owns the run — the same person the rules
call "the user": the one who approves the scope, owns the held-for-human gates,
and rules on filings.

## Which file to read, and when

Each file is sized to be **read whole, once, at the moment it applies** — never
read a file the current phase does not need.

**Every path below is relative to `$S`, the directory this `SKILL.md` really
lives in** — resolve it once at run start, before reading anything else:

```bash
S="$(dirname "$(readlink -f <path to this SKILL.md>)")"
```

In a project overlay `SKILL.md` is a symlink, so `$S` is the shared copy, where
every file below and the sibling skills (`$S/../cache-warmth`,
`$S/../context-ceiling`, `$S/../unattended-run`) exist. Only `project.md` is
read from the project's own skill directory.

Read the sibling skills **by section** — the orchestrator needs about a third
of each. Print one section with:

```bash
sec() { # sec <file> "<title>" — prints that section; says so if it is gone
  awk -v h="$2" '/^## /{p = index($0, h) > 0; if (p) f = 1} p; END {exit !f}' "$S/$1" \
    || echo "SECTION MISSING: $1 → $2 — read the file's headings instead" >&2
}
```

| When | Read |
|---|---|
| First run on a project or machine | [INSTALL.md](INSTALL.md) — overlay install and what this skill assumes |
| Run start, before the scope dispatch | [phase0-scope.md](phase0-scope.md); `../cache-warmth/SKILL.md` → "Waiting in the main session"; `../unattended-run/SKILL.md` → "Progress stamps" and "Budget" |
| Scope approved | [phase1-loop.md](phase1-loop.md); `../unattended-run/SKILL.md` → "Helpers"; `../context-ceiling/SKILL.md` → "Resume under the ceiling", "The main session" and "An agent measured past twice" |
| The operator says "unattended" | `../unattended-run/SKILL.md` → "When to stop" and "The stop" |
| A fresh orchestrator taking a run over | `phase1-loop.md` → "The resume packet" first; nothing else before the first dispatch |
| A card touches a persisted field, a version constant or an agent-facing record | [reference/schema-changes.md](reference/schema-changes.md) |
| A fixer authored a convention, or calls a requested design infeasible | [reference/conventions.md](reference/conventions.md) |
| Run start, and a wave boundary where the run changed shape | [reference/red-flags.md](reference/red-flags.md) |
| Last card merged, quota called, or an unattended run stopping | [phase2-wrap.md](phase2-wrap.md) |
| A rule seems not to apply, or you are changing one | [reference/why-rules.md](reference/why-rules.md) |
| Changing a brief block | [reference/why-briefs.md](reference/why-briefs.md) |

**Never read** `briefs/` — the orchestrator assembles briefs from it with `cat`
(`phase1-loop.md` → "Briefs").

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
Phase 2  WRAP       demo evidence + walkthrough review, demo document,
                    milestone closed, deferred register → operator ruling →
                    filing, board sweep, run summary, memory, and the skill's
                    self-update (phase2-wrap.md)
```

## Unattended mode

When the operator says "unattended", the run follows the **`unattended-run`**
skill, with scope approval and the overlay's gates as its authority — see
`phase1-loop.md` → "Unattended mode".

**Waiting, attended or not, follows the `cache-warmth` skill.** The
orchestrator never takes a turn to wait, and it arms that skill's 50-minute
heartbeat in the same turn as the first dispatch, re-arming it until the wrap.
Every brief for a role that waits carries its `brief.md` lines verbatim. See
phase1-loop.md → "The orchestrator never takes a turn to wait" and "Heartbeat".

## Iron rules

The full text, with the reasoning behind each, is in
[reference/why-rules.md](reference/why-rules.md).

1. **No dispatch of run work before scope approval.** "Unattended" is not
   approval of a scope the operator has not seen. The Phase 0 scope agent is
   the one exception — it produces the doc being approved.
2. **Worktree per agent, always** — including coupled tasks. Coupling is
   handled by merge order and declared file surfaces, never a shared checkout.
3. **Verdicts are data; the orchestrator merges — unless the project says
   otherwise.** Check `project.md` and `CLAUDE.md` for a human merge gate before
   the first dispatch. A reviewer never merges; an implementer never reviews its
   own diff. Merge = review clean + checks green + no open human gate.
4. **Design questions stop the issue, not the run.** A strong-model adjudicator
   rules with spec citations in a binding issue comment; the docs amendment is a
   PR the orchestrator squash-merges itself, after rule 3's gate and the paired
   code PR. **An amendment to a FROZEN spec or contract goes to the
   held-for-human list.** Escalate only what is hard to reverse AND a real
   trade-off the specs do not decide.
5. **Ledger before first dispatch** — waves, per-issue state, rulings,
   deferred minors, resume queue. Dead agents are resumed from their
   transcripts under the ceiling and continued from their checkpoint note above
   it (`context-ceiling`).
6. **Nothing deferred silently — and not everything deferred becomes a card.**
   Every non-blocking finding gets a ledger entry and a close-comment line; a
   follow-up issue only when it moves the goal line and the operator approved
   it. Set a **filing budget** in the scope doc and report **filed-to-merged**
   at the wrap — two runs above 1 means the register is producing the backlog.
7. **Budget = graceful drain**, measured, never estimated
   (phase1-loop.md → Budget check). At the target: start nothing new, let
   in-flight rounds finish, report, pause.
8. **Report progress after every substantial agent completion** — the stamp in
   phase1-loop.md → "Progress line": Exit items first, time from `date` in the
   same turn, the stamp last in its turn, and `context-size.py`'s `current`
   in the ledger beside it.
9. **Context is a budget, and the orchestrator's is not the fixer's**
   (`context-ceiling`):
   - **fixers and other long-running agents stop at ~150k** (hard ~200k) and
     return a checkpoint note, enforced by the hook `/add-context-ceiling`
     installs;
   - **the orchestrator: soft 200k / hard 500k**, read with `context-size.py`
     at each stamp; past soft it **offers a handover** at the next natural
     boundary;
   - **reviewers: no ceiling, a turn budget** — keep them on the stronger tier
     and bound their length.
10. **A threshold ships with the instrument that reads it**, or is restated as
    something the agent can see — a turn count, a boundary, a deliverable. A
    threshold with no instrument is decoration that reads as a working control.
    An agent measured past **twice** its ceiling is an instrument that did not
    bind — fix it before the next dispatch.
11. **The run has one goal line, written before Phase 0** — an observable
    outcome, testable by looking at the artifact, not at the board. The scope
    derives the minimum card set that closes it and names the rest as out;
    every brief carries it and every return says what moved it; the stamp
    leads with it; rulings are sized by it (above ~2 rulings per merged card,
    the spec is the defect). A run that ends with the cards closed and the goal
    unmoved has diverged.

## Model tiers (defaults; record per-issue tier in the scope doc)

| Work | Tier |
|---|---|
| Approaches, mechanical fixes, standard reviews, re-reviews | cheap/mid (Sonnet-class) |
| Load-bearing implement/review: core types, schema, cache/graph logic, anything that runs unattended with write access | top standard (Opus-class) |
| Design adjudication | strongest (Fable-class) — requires the scoped brief in phase1-loop.md → Adjudication |
| Contract/freeze drafts, Phase 0 scope | strongest available |
| Repeat of an already-merged pattern | one combined approach+fix agent, cheap tier |
| Doc/comment text + mechanical tests, zero non-comment production lines | orchestrator verifies instead of dispatching a review — confirm no production diff and no fixture bytes moved, then **re-apply a discriminating mutation yourself on a different axis than the fixer's**. The mutation is what makes it safe; the greps alone are not a gate. |

## Red flags — stop, you are about to violate the flow

**The full set is [reference/red-flags.md](reference/red-flags.md)** — 55 rows,
grouped, none deleted; the waiting and cache rows are in the `cache-warmth`
skill, the ceiling rows in `context-ceiling`, the stamp, sweep and quota rows
in `unattended-run`. Read it at run start and at any wave boundary where the
run changed shape. The five that fire most often:

- Dispatching a fixer before the operator approved a scope doc
- A run with no goal line, or a wave larger than the minimum card set that
  closes it
- Filing a card for a finding that moves nothing on the goal line
- The orchestrator reading specs, issues and PRs itself in Phase 0 — that
  survey belongs to the dispatched scope agent
- A reviewer told to merge, or the orchestrator fixing a finding itself

## Common rationalizations

**The full set is [reference/rationalizations.md](reference/rationalizations.md)**
— 49 rows, none deleted; the waiting and cache rows are in the `cache-warmth`
skill, the ceiling rows in `context-ceiling`, the unattended rows in
`unattended-run`. The five that fire most often:

| Excuse | Reality |
|---|---|
| "User said unattended, so start now" | Unattended = no mid-run questions, not no scope gate. Present scope first. |
| "The scope doc lists the open cards, that is the plan" | A card list is not a goal. Write the outcome first, derive the minimum card set that closes it, and name the rest as out. |
| "The finding is real, so it gets a card" | Real and irrelevant to the goal is a close-comment line. Measure filed-to-merged. |
| "The spec gap is obvious, I'll just decide" | Cheap now, contradiction later. Adjudicator + citation + binding comment costs one dispatch. |
| "Tests are green, the constraint works" | Green survives inputs the check is blind to. Mutate — and for a rule about two objects, move only one of them. |
