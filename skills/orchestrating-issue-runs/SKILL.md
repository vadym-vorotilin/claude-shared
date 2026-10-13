---
name: orchestrating-issue-runs
description: Use when the user asks to orchestrate execution of multiple spec-backed GitHub issues with subagents — implement, review, and merge across one or more repos, attended or unattended. Triggers - "orchestrate the open issues", "work the backlog with subagents", "run the pipeline by hand", "execute these issues in parallel streams".
---

# Orchestrating issue runs

> **Read `project.md` FIRST if one sits in *this project's* skill directory.**
> The overlay and the repo's `CLAUDE.md` win over anything here. Check them for
> acts reserved to a human (this skill assumes the orchestrator merges) before
> the first dispatch. Installing an overlay, and what this skill assumes:
> [INSTALL.md](INSTALL.md).

Turn a backlog of spec-backed GitHub issues into merged PRs using subagents.
The operator — the human who owns the run — is involved twice: **approving the
scope before anything runs**, and **the gates they genuinely own** (spec
freezes, machine changes, external data, plan changes). Everything else runs in
the agent loop. **The orchestrator coordinates and decides; it never
implements and never reviews code itself.**

**Run on the top standard tier (Opus-class).** The orchestrator cannot switch
its own model: on a pricier tier, ask the operator to run `/model opus` before
the scope dispatch.

## Which file to read, and when

Each file is read **whole, once, when it applies** — and nothing else. Paths are
relative to `$S`, the directory this `SKILL.md` really lives in (in a project
overlay it is a symlink, so `$S` is the shared copy):
`S="$(dirname "$(readlink -f <path to this SKILL.md>)")"`. Only `project.md` is
read from the project's own directory.

| Every run | Read |
|---|---|
| Run start, before the scope dispatch | [phase0-scope.md](phase0-scope.md) |
| Scope approved, or a fresh orchestrator taking a run over | [phase1-loop.md](phase1-loop.md) |
| Last card merged, quota called, or an unattended run stopping | [phase2-wrap.md](phase2-wrap.md) |

| Only when | Read |
|---|---|
| First run on a project or machine | [INSTALL.md](INSTALL.md) |
| The operator says "unattended" | `../unattended-run/SKILL.md` → "When to stop" and "The stop" |
| The first budget check | `../unattended-run/SKILL.md` → "Budget" (the command) |
| A card touches a persisted field, a version constant or an agent-facing record | [reference/schema-changes.md](reference/schema-changes.md) |
| A fixer authored a convention, calls a requested design infeasible, or a capture is retried | [reference/conventions.md](reference/conventions.md) |
| A wave boundary where the run changed shape | [reference/red-flags.md](reference/red-flags.md) |
| A rule is unclear, or you are changing one | `reference/full/` (the reasoning), [reference/why-rules.md](reference/why-rules.md) |

**Never read `briefs/`** or the sibling skills' `brief.md` — they are assembled
into briefs below.

## Run state

One directory per run: `RUN=<repo>/.orchestration/<run>` (`<run>` = a short
name for the milestone or wave; tracked mode moves it, INSTALL.md → "Run
state"). It holds `ledger.md`, `INTRO.md`, `briefs/` (every assembled brief and
its spec part) and `reports/`: each brief names its absolute
`$RUN/reports/<leg>.md`, `<leg>` = `<issue>-<role>-<n>` (`n` counts that role's
dispatches on the issue — rounds, parts) or the role's name for a run-wide leg.
**Before the first write, always** append `.orchestration/` to
`$(git rev-parse --git-path info/exclude)`. If `git ls-files .orchestration`
prints anything and the overlay does not say `run state: tracked`, stop and
ask the operator: an exclude does not untrack. Worktrees and experiments go in `$SCRATCH`, **outside** the repo.

## Briefs

The agent-facing rules live in `briefs/` and the sibling skills, in the agent's
own voice. You write only the issue-specific part (phase1-loop.md → "Briefs")
and join it to the blocks:

```bash
: "${RUN:?set RUN to <repo>/.orchestration/<run>}"
brief() { # brief <out> <block>... — refuses a missing or empty block; never leaves a stale brief
  local out="$1"; shift; rm -f "$out"
  [ $# -ge 2 ] || { echo "brief: needs at least two blocks" >&2; return 1; }
  for f in "$@"; do [ -s "$f" ] || { echo "brief: missing or empty block $f" >&2; return 1; }; done
  for f in "$@"; do cat "$f"; echo; done > "$out"
}
brief "$RUN/briefs/brief-<issue>-fixer.md" "$S/briefs/common.md" "$S/briefs/issue.md" \
  "$S/../cache-warmth/brief.md" "$S/../context-ceiling/brief.md" "$S/briefs/fixer.md" \
  "$RUN/briefs/spec-<issue>-fixer.md" || echo "STOP: fix the brief before dispatching"
```

| Role | Blocks after `briefs/common.md` and `../cache-warmth/brief.md` |
|---|---|
| fixer, continuation | `briefs/issue.md`, `../context-ceiling/brief.md`, `briefs/fixer.md` |
| combined approach+fix | `briefs/issue.md`, `briefs/approach.md`, `../context-ceiling/brief.md`, `briefs/fixer.md` |
| approach, adjudicator | `briefs/issue.md`, `briefs/approach.md` or `briefs/adjudicator.md` (+ ceiling block if the leg can run long) |
| reviewer | `briefs/issue.md`, `briefs/reviewer.md` — never the ceiling block |
| scope | `../context-ceiling/brief.md`, `briefs/scope.md` |
| merge mechanics | `briefs/merge.md` |
| demo, walkthrough, register, filing, board sweep | `briefs/wrap.md`, the spec part naming the role (+ ceiling block if the leg can run long) |

Dispatch with only: *"Your brief is `<file>`. Read it in full before anything
else; it is your complete brief."*

## The flow

```
Phase 0  GOAL → SCOPE (dispatched agent) → receipt check → APPROVAL
         no run work is dispatched before the operator approves
Phase 1  per issue: approach → go-gate → fix (TDD, worktree) → review
         → fix rounds (same agents; budget-capped, cap 5) → merge → close
Phase 2  demo, walkthrough, milestone closed, register → operator ruling →
         filing, board sweep, summary, memory, self-improvement
```

## Iron rules

1. **No dispatch of run work before scope approval.** "Unattended" is not
   approval of a scope the operator has not seen. The scope agent is the one
   exception.
2. **Worktree per agent, always**, coupled tasks included — coupling is handled
   by merge order and declared file surfaces.
3. **Verdicts are data; the orchestrator merges — unless the project or the
   scope's Authority line reserves it.** A reviewer never merges; an
   implementer never reviews its own diff. Merge = posted `VERDICT` clean +
   checks green + no open human gate.
4. **Design questions stop the issue, not the run.** A strong-tier
   adjudicator rules with citations in a binding comment. An amendment to a
   FROZEN spec or contract goes to the held-for-human list. Escalate only what
   is hard to reverse AND a real trade-off the specs do not decide.
5. **Ledger before the first dispatch.**
6. **Nothing deferred silently — and not everything deferred becomes a card.**
   A finding that moves nothing on the goal line is a close-comment line. File
   only within the scope's filing budget, after the operator approves; report
   filed-to-merged at the wrap.
7. **Budget = graceful drain**, measured, never estimated: at the target, start
   nothing new, let in-flight rounds finish, report, pause.
8. **Report progress after every substantial completion** (phase1-loop.md →
   "Progress line").
9. **Context is a budget** (the `context-ceiling` skill): dispatched agents stop
   at ~150k (hard ~200k) and return a checkpoint note; the orchestrator's soft
   200k / hard 500k is read with `$S/../context-ceiling/tools/context-size.py`;
   reviewers get a turn budget, not a ceiling.
10. **A threshold ships with the instrument that reads it**, or is restated as
    something the agent can see. An agent measured past twice its ceiling is an
    instrument that did not bind — fix it before the next dispatch.
11. **One goal line, written before Phase 0** — an observable outcome. The
    scope derives the minimum card set that closes it; every brief carries it;
    the stamp leads with it; rulings are sized by it.

## Model tiers (defaults; the scope doc records each issue's)

| Work | Tier |
|---|---|
| Approaches, mechanical fixes, standard reviews, re-reviews | cheap/mid (Sonnet-class) |
| Load-bearing implement/review: core types, schema, cache/graph logic, anything running unattended with write access | top standard (Opus-class) |
| Design adjudication, contract/freeze drafts, Phase 0 scope | strongest available |
| Repeat of an already-merged pattern | one combined approach+fix agent, cheap tier |

## Red flags — stop

- Dispatching a fixer before the operator approved a scope doc
- A run with no goal line, or a wave larger than the minimum that closes it
- Filing a card for a finding that moves nothing on the goal line
- Reading specs, issues, PRs or `briefs/` yourself
- A reviewer told to merge, or the orchestrator fixing a finding itself

The full sets: [reference/red-flags.md](reference/red-flags.md) and
[reference/rationalizations.md](reference/rationalizations.md), plus each
sibling skill's own.
