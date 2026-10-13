# Red flags — stop, you are about to violate the flow

The full set. SKILL.md keeps the ten that fire most often; every other row is
here, and none has been deleted. Read this file once at run start, and again at
any wave boundary where the run has changed shape — a new lane, a scope change,
an operator ruling.

Each row is a representative paraphrase of a failure pattern — illustrative,
not a quote — of the kind an agent falls into while believing it is following
the flow.

## Scope and authority

- About to dispatch a fixer and the user hasn't approved a scope doc
- About to `git checkout` in a shared clone instead of `git worktree add`
- A reviewer prompt that says "merge if clean"
- Fixing a finding yourself in the orchestrator session
- Re-dispatching a task whose agent died instead of resuming it
- An agent report mentions a spec gap and you're about to "pick something sensible" instead of routing it to adjudication
- Closing an issue whose review findings aren't in the ledger
- The orchestrator reading the specs, issues and PRs itself in Phase 0 — that survey belongs to the dispatched scope agent, which returns the doc and takes the context away with it

## Goal focus

- A run with no **goal line** — one sentence naming the observable outcome,
  written before Phase 0 and testable by looking at the artifact, not at the
  board
- A wave whose card set is larger than the minimum that closes the goal line,
  with nothing naming the rest as out of the wave
- Filing a card for a finding that moves nothing on the goal line — that is a
  close-comment line, not a card
- A run past its filing budget and still filing, with no operator ruling
- Asking the operator to rule on a question no probe has been run against —
  one probe per card comes first, and a time or budget question gets a
  full-length run, never a shortened probe's extrapolated ratio
- Writing a durable design record (an ADR or equivalent) for a question that
  does not change the milestone's Exit
- A follow-on milestone most of whose cards descend from its predecessor's —
  that is a stop signal, not a backlog; the direction question goes to the
  operator before dispatch
- A run whose filed-to-merged ratio is above 1 for the second run running — the
  deferred register has started generating work
- More than roughly two rulings per merged card — the spec is the defect;
  propose the spec change as one batch instead of ruling case by case
- A self-improvement pass that only adds rows — every rule added retires or
  merges one

## Waiting, cache and context

Rows about waiting and the prompt cache moved to the `cache-warmth` skill's
Red flags, rows about the context ceiling to the `context-ceiling` skill's, and
rows about stamps, the sweep, stalls and the quota to the `unattended-run`
skill's; none was deleted.

- A brief that does not ban the agent dispatching its own subagents — forked helpers can clobber each other's single output file
- Starting a wave or a fix round without checking the run's spend against the target

## Dispatch and briefing

- Handing an agent a suite count, baseline or hash you didn't make it re-measure — or proposing a gate change whose baseline was measured before the interface it samples from changed, or ruling on a failing variant before asking whether the evaluation harness still assumes the old interface
- Handing a fixer an issue's factual claim about a file as a given rather than as checkable
- An agent reading a shared clone at all — FETCH_HEAD, a submodule checkout, a file on disk — brief it to pin every read to a resolved SHA in its own worktree
- A scratch filename shared between cards — one card's PR body overwrites another's
- Summing a runner's filtered chunks and calling it the suite — an exact-match filter drops everything nested below the named level
- Handing a fixer an adjudicator's cited number as settled fact rather than a hypothesis to verify
- A reviewer brief that names no diff and no resolved SHA — the reviewer will read the whole repo instead of the change

## Review, guards and evidence

- A reviewer brief on a position-sensitive card that doesn't require mutating **position** (move one element, shift it, reflect or rotate the whole fixture, bracket both sides)
- Accepting a compile-only red as TDD evidence
- Two issues splitting one convention and neither owning the parent document
- A new guard whose first test case isn't the shape your own diff introduces
- Passing a reviewer's proposed remedy to a fixer as an instruction rather than a hypothesis
- Patching hole N+1 in a path that has already produced N of the same shape
- Passing a reviewer's measurement to an adjudicator as an established premise rather than labelled unverified
- Treating an adjudicator's "not gated on" as clearance to run two issues on one file
- A new guard pinned by a **count** rather than by a property asserted over the whole set
- Adding a guard and not asking what it now covers **besides** the thing being guarded
- Releasing a demo whose evidence checklist is all-Met and nobody has used the
  artifact as the end user would — presence is not acceptance
- A third review of a content-identical rebase — diff-of-diffs is the orchestrator's check
- A new filter merged with no test that actually walks its path — green proves nothing about code no case exercises
- A reviewer brief that does not quote the card's Exit clause — the deliverable may be correct and composed into nothing
- An acceptance property like "byte-identical except the version" handed to a fixer without checking what the serializer actually emits for an absent member

## Merge, board and reporting

- Merging without posting the close comment **separately** — the PR auto-closes the issue and `gh issue close --comment` silently does nothing
- Treating the post-merge issue-state read as a gate — that read is racy; read the commit body
- Merging two green PRs that both touch one counted set — per-branch gates don't compose; serialise or rebase-and-rerun
- Merging a squash-stacked PR's parent and assuming the child survives it — rebase `--onto`, then re-check the review
- Squash-merging `main` into an integration branch — main's closing keywords ride along
- A deferred register handed over flat instead of grouped by what can close in-branch now
- Editing a branch and merging it in the same shell call — a failed edit that `set -e` does not catch gets merged

## Rules, specs and model-facing records

- A fixer-authored convention ("the spec is silent here, so I chose…") heading to merge without a ruling
- Escalating a fixer's "the requested design is infeasible" before the conflict is **named** (leave-one-out over the constraint set) — the rule is often the defect, not the design
- A leave-one-out that names a **rule** as the conflict, and a menu with no
  DEMOTE option — hard → soft, or soft → advisory, is always on the menu, and
  where the spec states its own cutting order, that order is quoted
- A field in a record a model fills that the model is supposed to leave
  empty — showing it is an invitation to fill it; remove the field
- A schema change to an agent-facing record shipped without briefing the
  re-capture with it — the record is part of the prompt, so the change is a prompt change
- A fresh orchestrator past ~80k before its first dispatch, or a Read of the ledger, a phase file or a brief it wrote (phase1-loop.md → "The resume packet")
