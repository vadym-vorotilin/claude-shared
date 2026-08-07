---
name: orchestrating-issue-runs
description: Use when the user asks to orchestrate execution of multiple spec-backed GitHub issues with subagents — implement, review, and merge across one or more repos, attended or unattended. Triggers - "orchestrate the open issues", "work the backlog with subagents", "run the pipeline by hand", "execute these issues in parallel streams".
---

# Orchestrating issue runs

Turn a backlog of spec-backed GitHub issues into merged PRs using subagents,
with exactly two kinds of human involvement: **scope approval before anything
runs**, and **gates the human genuinely owns** (spec freezes, machine changes,
external data, plan changes). Everything else — approaches, implementation,
review, fix rounds, merges — runs in the agent loop.

The orchestrator coordinates and decides; it never implements and never
reviews code itself. Its context is for coordination.

**REQUIRED READING before the first dispatch:** [runbook.md](runbook.md) —
phase mechanics, briefing templates, and the protocols below in full.

## The flow

```
Phase 0  SCOPE      read specs, ADRs, memory, issues, board, open PRs,
                    prior-run ledgers → dependency-ordered wave plan +
                    per-issue model tier + inconsistency sweep
         APPROVE    scope doc posted as a message; found inconsistencies
                    listed for approval before any issues are filed.
                    NO DISPATCH BEFORE THE USER APPROVES THE SCOPE.
Phase 1  RUN        per issue: approach → go-gate → fix (TDD, worktree)
                    → independent review → fix rounds (resume, cap 5)
                    → merge on clean → close, board sync, ledger, report
Phase 2  WRAP       run summary, memory update, deferred-minors register
                    carried into the next run's Phase 0, and the skill
                    self-update (runbook.md → Self-improvement)
```

## Iron rules

1. **No dispatch before scope approval.** "The user said unattended" is not
   approval of a scope they haven't seen. Present the scope doc, wait.
2. **Worktree per agent, always** — including coupled tasks. Coupling is
   handled by merge order and declared file surfaces, never a shared checkout.
3. **Verdicts are data; the orchestrator merges.** A reviewer never merges.
   An implementer never reviews its own diff. Merge = review clean + checks
   green + no open human gate.
4. **Design questions stop the issue, not the run.** A strong-model
   adjudicator rules with spec citations posted as a binding issue comment;
   docs amendments become PRs **held for the human**; code proceeds on the
   ruling. Escalate to the human only what is hard-to-reverse AND a real
   trade-off the specs don't already decide.
5. **Ledger before first dispatch** (scratchpad file: waves, per-issue state,
   rulings, deferred minors, resume queue). Survives compaction and limits.
   Dead agents are **resumed from their transcripts**, never re-dispatched.
   If the agent id is genuinely unrecoverable, re-dispatch with the ledger's
   state summary plus the worktree, branch and PR facts you verified yourself.
6. **Nothing deferred silently.** Every non-blocking finding: ledger entry +
   close-comment mention + follow-up issue (issues only after user approved
   creating them, per scope rules).
7. **Budget = graceful drain.** At the token target: start nothing new, let
   in-flight rounds finish, report, pause.
8. **Report progress after every substantial agent completion** — a stamped
   `**<date and time> - Progress: N%**` line plus one line of what happened.
   Weight by expected issue cost, never by count; unmerged is not done. See
   runbook.md → Reports.

## Model tiers (defaults; record per-issue tier in the scope doc)

| Work | Tier |
|---|---|
| Approaches, mechanical fixes, standard reviews, re-reviews | cheap/mid (Sonnet-class) |
| Load-bearing implement/review: core types, schema, cache/graph logic, anything that runs unattended with write access | top standard (Opus-class) |
| Design adjudication, contract/freeze drafts, Phase 0 scope | strongest available |
| Repeat of an already-merged pattern | one combined approach+fix agent, cheap tier |
| Doc/comment text + mechanical tests, zero non-comment production lines | orchestrator verifies instead of dispatching a review — confirm no production diff and no fixture bytes moved, then **re-apply a discriminating mutation yourself on a different axis than the fixer's**. The mutation is what makes it safe; the greps alone are not a gate. |

## Red flags — stop, you are about to violate the flow

- About to dispatch a fixer and the user hasn't approved a scope doc
- About to `git checkout` in a shared clone instead of `git worktree add`
- A reviewer prompt that says "merge if clean"
- Fixing a finding yourself in the orchestrator session
- Re-dispatching a task whose agent died instead of resuming it
- An agent report mentions a spec gap and you're about to "pick something sensible" instead of routing it to adjudication
- Closing an issue whose review findings aren't in the ledger
- Merging without posting the close comment **separately** — the PR auto-closes the issue and `gh issue close --comment` silently does nothing
- A solver/geometry reviewer brief that doesn't require mutating **position** (mirror, transpose, shift, bracket both sides)
- Accepting a compile-only red as TDD evidence
- Two issues splitting one convention and neither owning the parent document
- A new guard whose first test case isn't the shape your own diff introduces
- Passing a reviewer's proposed remedy to a fixer as an instruction rather than a hypothesis
- Patching hole N+1 in a path that has already produced N of the same shape
- Handing an agent a suite count, baseline or hash you didn't make it re-measure
- Re-nudging a stalled agent when what it's waiting for hasn't started — remove the dependency instead
- Treating an adjudicator's "not gated on" as clearance to run two issues on one file

## Common rationalizations

| Excuse | Reality |
|---|---|
| "User said unattended, so start now" | Unattended = no mid-run questions, not no scope gate. Present scope first. |
| "These two issues are coupled, share the checkout" | That's how two agents corrupted each other's trees. Worktrees + merge order. |
| "Review was clean, the reviewer can merge" | Verdict ≠ decision. Gates (human labels, groups, freezes) live above the reviewer. |
| "The spec gap is obvious, I'll just decide" | Cheap now, contradiction later. Adjudicator + citation + binding comment costs one dispatch. |
| "Fresh agent is cleaner than resuming" | Resume keeps the task context and costs a fraction. Fresh agents re-derive everything. |
| "Minor finding, not worth a follow-up" | Silent discards are how the next run re-finds it at 10x cost. |
| "Tests are green, the constraint works" | Green survives mirrored, transposed, self-paired and shifted geometry. Mutate position, not just structure. |
| "It compiled red first, that's my TDD evidence" | A compile error proves the file was absent. Go green, then mutate the load-bearing decision back to naive and quote that red. |
| "The fixer says it reproduced my sabotage" | Re-apply it yourself. One reviewer doing that found the fix still passed a subtler mutation. |
| "My README documents it correctly" | The parent doc may still contradict you, and you can't see it until the sibling merges. Second-merged owns the parent. |
| "The issue is small, a cheap review will do" | A one-constraint issue behind a reviewed seam still took three rounds, all real position bugs. Size ≠ review risk. |
| "My guard can't go blind, it scans everything" | It was blind to the idiom the same PR introduced. Test your guard against your own diff's shape first. |
| "The reviewer told me how to fix it" | Its remedy caught 9 of 10 shapes. Measure it before adopting it; a right finding can carry a wrong fix. |
| "That's the fifth hole, I'll patch it too" | Four of the five were one mistake. Ship an invariant with a named outside, not enumeration N+1. |
| "The adjudicator says they're independent" | Independent contracts, same file, same function. Re-check file surfaces yourself. |
| "It's still queued, I'll nudge it to wait properly" | Nothing has started. A better nudge stalls it again — take the gate off the agent. |
| "The suite was 1000 last I looked" | It moved by 8 when a sibling merged. Make every agent re-measure; two caught this in one run. |
| "CI is red, the branch is broken" | One was a cancelled job, one an Actions outage at setup. `gh api .../jobs` before believing a red. |
| "The agent didn't follow my instruction" | Check whether it was right. Three deviations this run were all correct, and all reported up front. |
