# Red flags — stop, you are about to violate the flow

The full set. SKILL.md keeps the ten that fire most often; every other row is
here, and none has been deleted. Read this file once at run start, and again at
any wave boundary where the run has changed shape — a new lane, a scope change,
an operator ruling.

Each row is something that was actually done, in a real run, by an agent that
believed it was following the flow.

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
  one probe per card comes first
- Writing a durable design record (an ADR or equivalent) for a question that
  does not change the milestone's Exit
- A progress stamp that leads with card cost instead of Exit items met / total
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

- A brief that lets an agent **block** on a command expected to outlast its
  prompt cache (~5 minutes idle) — the next turn then rewrites the whole
  context at the cache-write rate; poll instead
- A poll form given as an example with no maximum — the bound gets stretched
  toward the Bash timeout to save turns, and past the cache lifetime it costs a
  full rewrite; say "every poll call returns within four minutes"
- A live agent's transcript untouched for five minutes — its cache is gone;
  correct its poll bound rather than reading the silence as health
- A waiting role briefed without the poll rule because it is "not a fixer" —
  reviewers re-measuring a suite, screenshot and recording agents, and wrap
  agents pay the identical rewrite
- A stall sweep whose interval is longer than the orchestrator's own cache
  lifetime — the sweep then pays the rewrite it exists to save
- An agent measured at more than twice its stated ceiling written up as a
  ledger note — that is a broken instrument, fixed before the next dispatch,
  not an observation
- Re-nudging a stalled agent when what it's waiting for hasn't started — remove the dependency instead
- Pausing the run by waiting for notifications — a pause needs an armed timer or monitor
- A brief that says "no monitors" without naming the Monitor tool and *unpolled* `run_in_background`
- A brief that does not ban the agent dispatching its own subagents — one forked four helpers that clobbered each other's single output file
- Starting a new card after the operator has called the quota — the wind-down finishes in-flight work, parks green PRs with rebase notes, and demos as a pre-release
- A fixer past the ~150k ceiling still going — it should have stopped at the ceiling and returned a handoff note
- Resuming a cold agent that is already over the ceiling — that is a continuation from its handoff note, not a resume
- Arming a check-up timer per agent — one silent sweep covers every in-flight agent and wakes you only on a stall
- Starting a wave or a fix round without checking the run's spend against the target

## Dispatch and briefing

- Handing an agent a suite count, baseline or hash you didn't make it re-measure
- Handing a fixer an issue's factual claim about a file as a given rather than as checkable
- An agent reading a shared clone at all — FETCH_HEAD, a submodule checkout, a file on disk — brief it to pin every read to a resolved SHA in its own worktree
- A scratch filename shared between cards — one PR body overwrote another's, twice
- Summing a runner's filtered chunks and calling it the suite — an exact-match filter drops everything nested below the named level
- Handing a fixer an adjudicator's cited number as settled fact rather than a hypothesis to verify
- A reviewer brief that names no diff and no resolved SHA — the reviewer will read the whole repo instead of the change

## Review, guards and evidence

- A reviewer brief on a position-sensitive card that doesn't require mutating **position** (mirror, transpose, shift, bracket both sides)
- Accepting a compile-only red as TDD evidence
- Two issues splitting one convention and neither owning the parent document
- A new guard whose first test case isn't the shape your own diff introduces
- Passing a reviewer's proposed remedy to a fixer as an instruction rather than a hypothesis
- Patching hole N+1 in a path that has already produced N of the same shape
- Passing a reviewer's measurement to an adjudicator as an established premise rather than labelled unverified
- Treating an adjudicator's "not gated on" as clearance to run two issues on one file
- A new guard pinned by a **count** rather than by a property asserted over the whole set
- Adding a guard and not asking what it now covers **besides** the thing being guarded
- Releasing a demo whose evidence census is all-Met and nobody has used the
  artifact as the end user would — presence is not acceptance
- A third review of a content-identical rebase — diff-of-diffs is the orchestrator's check
- A new clip/filter merged with no test that actually walks its path — green proves nothing about code no case exercises
- A reviewer brief that does not quote the card's Exit clause — the deliverable may be correct and composed into nothing
- An acceptance property like "byte-identical except the version" handed to a fixer without checking what the serializer actually emits for an absent member

## Merge, board and reporting

- Merging without posting the close comment **separately** — the PR auto-closes the issue and `gh issue close --comment` silently does nothing
- Treating the post-merge issue-state read as a gate — that read is racy; read the commit body
- Merging two green PRs that both touch one counted set — per-branch gates don't compose; serialise or rebase-and-rerun
- Merging a squash-stacked PR's parent and assuming the child survives it — rebase `--onto`, then re-check the review
- A progress stamp with a tool call after it — the stamp ends the turn, always
- Squash-merging `main` into an integration branch — main's closing keywords ride along
- A deferred register handed over flat instead of grouped by what can close in-branch now
- A ledger time or progress stamp extrapolated from the previous one instead of read from `date` in that same turn — one run's stamps drifted 77 minutes ahead of the clock
- Editing a branch and merging it in the same shell call — a failed edit that `set -e` did not catch merged twice

## Rules, specs and model-facing records

- A fixer-authored convention ("the spec is silent here, so I chose…") heading to merge without a ruling
- Escalating a fixer's "the requested design is infeasible" before the conflict is **named** (leave-one-out over the constraint set) — the rule was the defect, not the design, both times it happened
- A leave-one-out that names a **rule** as the conflict, and a menu with no
  DEMOTE option — hard → soft, or soft → advisory, is always on the menu, and
  where the spec states its own cutting order, that order is quoted
- A field advertised in a model's output schema that the model is supposed to
  leave empty — advertising it is an invitation to fill it; remove the field
- A schema act on an agent-facing record shipped without re-briefing the
  recording — the record is part of the prompt, so the act is a prompt change
