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
   docs amendments become PRs the **orchestrator squash-merges itself**, after
   the paired engine PR (or immediately if standalone) — no held queue; code
   proceeds on the ruling. **Exception: an amendment that edits a FROZEN spec
   or contract still goes to the held-for-human list.** Escalate to the human
   only what is hard-to-reverse AND a real trade-off the specs don't already
   decide.
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
- Passing a reviewer's measurement to an adjudicator as an established premise rather than labelled unverified
- Re-nudging a stalled agent when what it's waiting for hasn't started — remove the dependency instead
- Treating an adjudicator's "not gated on" as clearance to run two issues on one file
- A new guard pinned by a **count** rather than by a property asserted over the whole set
- Adding a guard and not asking what it now covers **besides** the thing being guarded
- Treating the post-merge issue-state read as a gate — that read is racy; read the commit body
- Handing a fixer an issue's factual claim about a file as a given rather than as checkable
- Merging two green PRs that both touch one counted set — per-branch gates don't compose; serialise or rebase-and-rerun
- An agent reading a shared clone via FETCH_HEAD — brief it to pin every read to a resolved SHA
- Merging a squash-stacked PR's parent and assuming the child survives it — rebase `--onto`, then re-check the review
- Pausing the run by waiting for notifications — a pause needs an armed timer or monitor
- A progress stamp with a tool call after it — the stamp ends the turn, always
- Releasing a demo whose evidence census is all-Met and nobody has used the
  artifact as the end user would — presence is not acceptance
- A brief that says "no monitors" without naming the Monitor tool and `run_in_background`
- A scratch filename shared between cards — one PR body overwrote another's, twice
- Summing a runner's filtered chunks and calling it the suite — an exact-match filter drops everything nested below the named level
- A fixer-authored convention ("the spec is silent here, so I chose…") heading to merge without a ruling
- A third review of a content-identical rebase — diff-of-diffs is the orchestrator's check
- A new clip/filter merged with no test that actually walks its path — green proves nothing about code no case exercises
- Handing a fixer an adjudicator's cited number as settled fact rather than a hypothesis to verify

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
| "X already does this work, so my code can't be the one that fails" | Does X **carry the value forward, or ask again?** Five impossibility claims in one PR all slid over that step. |
| "The exception type proves the mechanism" | A wrong story that predicts the observation is not falsified by it. One survived three rounds. Take the stack trace. |
| "My fact pins it — the count is right" | A count stops discriminating the moment the code adds one. Assert over the whole set; then only placement can move the target. |
| "The issue says that file documents X, so I'll fix X" | It may not. Inventing a defect to match an issue is worse than the issue being wrong. Read the file first. |
| "The agent said `DEVIATIONS: none`" | It answered from intent. Make the return contract require **quoting the line**, not self-assessing compliance. |
| "I drove four rounds, so I can judge whether the diff sprawled" | You are the worst-placed reader of a diff you shaped. Ask the reviewer for the scope ruling. |
| "The filter's logic is right, it doesn't need its own test" | Right logic, no exercising case — one merged filter sat unpinned exactly this way until a later fixer's test finally walked the path. |
| "The adjudicator did the math, I can build on the number" | Ruling figures are hypotheses, not facts. In one run a census count, a measured dimension and an exception type all moved on verification; the fixer checks, then posts corrections after merge. |
| "The reviewer measured it, so the adjudicator can rule on it" | Hand it over labelled unverified and ask for contradictions. One ruling stood while its own headline number fell. |
| "The guard is narrow, it only catches the bad case" | Ask what else it now covers. One added so bad *data* would fail had engine setup inside it — the inversion it existed to prevent. |
| "The issue still reads OPEN, so the auto-close failed" | That read is racy. Read the squash commit body, or re-read after a beat, before writing either outcome into a permanent comment. |
| "Both PRs are green, so merging both is green" | Per-branch gates don't compose over a counted set. Serialise, or rebase and re-run one against the other. |
| "Same clone, FETCH_HEAD is fine" | Concurrent agents mutate it mid-read. Resolve the SHA once and pin every read in the brief to it. |
| "The parent merged, the child will just retarget" | It can be closed, or silently retargeted onto a base it was never reviewed against. Rebase `--onto`, then content-hash before carrying the review. |
| "I'll pick the run back up when the notification arrives" | A pause with no armed timer or monitor is a pause that runs long. Arm it, then pause. |
| "The brief said no monitors" | It read as a Bash rule. Name the Monitor tool; one fixer waited on one for an hour. |
| "It's a rebase, the review stands" | It stands only if the content is identical — prove it with diff-of-diffs, then merge without a third review. |
| "The spec is silent, so the fixer's convention is fine" | It is a design act. A short adjudication ratified two and relocated one in a single run. |
| "The suite is the sum of the filtered chunks" | Some runners' path/namespace filters are exact-match, and dropped a large slice of the suite silently. Run unfiltered, or split by test class. |
| "I stamped the progress, then dispatched the next agent" | Text before tool calls may never render. One run looked silent for four hours while reporting diligently. Stamp last. |
| "The census says every item is Met, the demo is done" | Met means the noun shipped. The operator walked the same artifact and found dozens of defects the census could not see. Walk it as the user first. |
