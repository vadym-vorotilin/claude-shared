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

## The flow

```
Phase 0  SCOPE      a DISPATCHED agent reads specs, ADRs, memory, issues,
                    board, open PRs, prior-run ledgers → returns a
                    dependency-ordered wave plan + per-issue model tier +
                    inconsistency sweep. The orchestrator reads the doc,
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

## Iron rules

1. **No dispatch of run work before scope approval.** "The user said
   unattended" is not approval of a scope they haven't seen. Present the scope
   doc, wait. The Phase 0 scope agent is the one exception, because it is what
   produces the doc being approved — nothing downstream of it moves until the
   user has.
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
   Dead agents are **resumed from their transcripts** — while they are still
   under the context ceiling (rule 9). Above it, or with a cold cache (a
   subagent idle past ~5 minutes), **continue from the handoff note instead**:
   both paths pay a full cache write at that point, and the fresh agent then
   re-reads a fraction of the context on every turn that follows. If the agent
   id is genuinely unrecoverable, dispatch with the ledger's state summary plus
   the worktree, branch and PR facts you verified yourself.
6. **Nothing deferred silently.** Every non-blocking finding: ledger entry +
   close-comment mention + follow-up issue (issues only after user approved
   creating them, per scope rules).
7. **Budget = graceful drain.** At the token target: start nothing new, let
   in-flight rounds finish, report, pause. **Measure it, don't estimate it** —
   `/token-report`'s `--json` total between waves and before each fix round
   (runbook → Budget check). A budget rule with no instrument is a wish.
8. **Report progress after every substantial agent completion** — a stamped
   `**<date and time> - Progress: N%**` line plus one line of what happened.
   Weight by expected issue cost, never by count; unmerged is not done. See
   runbook.md → Reports.
9. **Context is a budget.** An agent re-reads its whole context every turn, so
   cost grows with context × turns and the expensive failure mode is the
   long-lived agent, not the chatty one. Fixers and other long-running agents
   **stop at ~150k, write a handoff note, and return it**; the orchestrator
   dispatches a continuation from that note. The orchestrator holds itself to
   the same ceiling, using the ledger as its own handoff note. **Reviewers are
   exempt** — a review is one whole-diff verdict and is never split. The
   threshold is a default to tune after a wave (runbook → Handoff note).

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

- About to dispatch a fixer and the user hasn't approved a scope doc
- About to `git checkout` in a shared clone instead of `git worktree add`
- A reviewer prompt that says "merge if clean"
- Fixing a finding yourself in the orchestrator session
- Re-dispatching a task whose agent died instead of resuming it
- An agent report mentions a spec gap and you're about to "pick something sensible" instead of routing it to adjudication
- Closing an issue whose review findings aren't in the ledger
- Merging without posting the close comment **separately** — the PR auto-closes the issue and `gh issue close --comment` silently does nothing
- A reviewer brief on a position-sensitive card that doesn't require mutating **position** (mirror, transpose, shift, bracket both sides)
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
- A reviewer brief that does not quote the card's Exit clause — the deliverable may be correct and composed into nothing
- Squash-merging `main` into an integration branch — main's closing keywords ride along
- A deferred register handed over flat instead of grouped by what can close in-branch now
- Escalating a fixer's "the requested design is infeasible" before the conflict is **named** (leave-one-out over the constraint set) — the rule was the defect, not the design, both times it happened
- An acceptance property like "byte-identical except the version" handed to a fixer without checking what the serializer actually emits for an absent member
- A ledger timestamp written from memory instead of `date` — they run ahead of the clock
- Editing a branch and merging it in the same shell call — a failed edit that `set -e` did not catch merged twice
- Starting a new card after the operator has called the quota — the wind-down finishes in-flight work, parks green PRs with rebase notes, and demos as a pre-release
- A fixer past the ~150k ceiling still going — it should have stopped at the ceiling and returned a handoff note
- Resuming a cold agent that is already over the ceiling — that is a continuation from its handoff note, not a resume
- The orchestrator reading the specs, issues and PRs itself in Phase 0 — that survey belongs to the dispatched scope agent, which returns the doc and takes the context away with it
- A reviewer brief that names no diff and no resolved SHA — the reviewer will read the whole repo instead of the change
- Arming a check-up timer per agent — one silent sweep covers every in-flight agent and wakes you only on a stall
- Starting a wave or a fix round without checking the run's spend against the target

## Common rationalizations

| Excuse | Reality |
|---|---|
| "User said unattended, so start now" | Unattended = no mid-run questions, not no scope gate. Present scope first. |
| "These two issues are coupled, share the checkout" | That's how two agents corrupted each other's trees. Worktrees + merge order. |
| "Review was clean, the reviewer can merge" | Verdict ≠ decision. Gates (human labels, groups, freezes) live above the reviewer. |
| "The spec gap is obvious, I'll just decide" | Cheap now, contradiction later. Adjudicator + citation + binding comment costs one dispatch. |
| "Fresh agent is cleaner than resuming" | True below the ceiling — there a resume keeps the task context for a fraction of the price. Above it both paths pay the same cache write, and the resumed one re-reads a bloated context on every turn after it. |
| "Minor finding, not worth a follow-up" | Silent discards are how the next run re-finds it at 10x cost. |
| "Tests are green, the constraint works" | Green survives mirrored, transposed, self-paired and shifted inputs. Mutate position, not just structure. |
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
| "The sink/guard is correct, wiring is another card's" | Correct and unreached is not shipped. The review quotes the Exit clause and names what composes it. |
| "The rule compares to the reference recording, so it's fair" | Only if the reference's answer is derivable from the input the variant sees. One clause was unpassable by any model and decided a verdict. |
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
| "The constraint check says the requested design is infeasible, so the design must change" | Name the conflict first (drop one constraint at a time). Twice the named rule was the defect — a per-unit floor, a single-hub assumption — and the design stood. Escalate the *rule*, with options, not the design. |
| "Two agents measured the same thing and disagree, I'll relay both" | Reconcile arithmetically before relaying: one pair differed by exactly weight × count, which said the tie-break pass had run at one budget and not the other. A reconciled number is a fact; two numbers are a question. |
| "The reviewer can't request changes, so it's a comment" | Same-account PRs refuse `--request-changes`. The verdict is the literal `VERDICT:` line in the body, whatever GitHub calls the review. |
| "The source data says X, the requested design says Y — one correction" | Check the whole frame: which parts match. One run found three input fields wrong after being told about one; each correction moved a different downstream number. |
| "It's nearly done, it can push past the ceiling" | "Nearly done" has been the wrong estimate all run, so make it evidential: suite green, one named deliverable left, no open decision. That finishes (hard stop ~200k). Anything else writes the note and returns. |
| "Round 5 is just another round" | A late round on a resumed agent costs a multiple of round 1 for a same-sized fix. Price the round before spending it; when the budget says stop, adjudicate the open findings instead. |
| "The check-up timer is cheap insurance" | Per agent, every 45 minutes, it re-reads the entire orchestrator context to learn "still alive" — and still finds a stall up to 45 minutes late. One silent sweep is cheaper and faster. |
