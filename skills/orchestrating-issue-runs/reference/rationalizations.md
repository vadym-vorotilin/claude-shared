# Common rationalizations

The full set. SKILL.md keeps the ten that fire most often; every other row is
here, and none has been deleted. Rows about waiting and the prompt cache
moved to the `cache-warmth` skill, and rows about the context ceiling to the
`context-ceiling` skill.

Each left-hand column is a representative paraphrase — illustrative, not a
quote — of the sentence an agent tends to reach for on its way to the mistake
in the right-hand column. Read the left column when something feels obviously
fine.

## The standing set

| Excuse | Reality |
|---|---|
| "User said unattended, so start now" | Unattended = no mid-run questions, not no scope gate. Present scope first. |
| "These two issues are coupled, share the checkout" | Two agents in one tree corrupt each other's work. Worktrees + merge order. |
| "Review was clean, the reviewer can merge" | Verdict ≠ decision. Gates (human labels, groups, freezes) live above the reviewer. |
| "The spec gap is obvious, I'll just decide" | Cheap now, contradiction later. Adjudicator + citation + binding comment costs one dispatch. |
| "Minor finding, not worth a follow-up" | Silent discards are how the next run re-finds it at a higher cost. |
| "Tests are green, the constraint works" | Green survives inputs the check is blind to — a symmetric, self-paired or uniformly shifted case. Mutate position, not just structure — and where the rule is about *which of two objects* is involved, a whole-structure transform moves both at once and can stay green while the rule is broken. Move one of them. |
| "It compiled red first, that's my TDD evidence" | A compile error proves the file was absent. Go green, then mutate the load-bearing decision back to naive and quote that red. |
| "The fixer says it reproduced my sabotage" | Re-apply it yourself. A fix that defeats the first mutation can still pass a subtler one. |
| "My README documents it correctly" | The parent doc may still contradict you, and you can't see it until the sibling merges. Second-merged owns the parent. |
| "The issue is small, a cheap review will do" | A one-constraint issue can still take several rounds of real position bugs. Size ≠ review risk. |
| "My guard can't go blind, it scans everything" | It can be blind to the idiom the same PR introduces. Test your guard against your own diff's shape first. |
| "The reviewer told me how to fix it" | A remedy that covers most shapes of a defect can be not merely vacuous but **false at the correct value**, and ship red. Measure it before adopting it; a right finding can carry a wrong fix. |
| "That's the fifth hole, I'll patch it too" | Most holes in one path are one mistake. Ship an invariant with a named outside, not enumeration N+1. |
| "The adjudicator says they're independent" | Independent contracts, same file, same function. Re-check file surfaces yourself. |
| "It's still queued, I'll nudge it to wait properly" | Nothing has started. A better nudge stalls it again — take the gate off the agent. |
| "The suite count was right last I looked" | It moves whenever a sibling merges. Make every agent re-measure rather than quote a count. |
| "CI is red, the branch is broken" | A red can be a cancelled job or a CI outage at setup. `gh api .../jobs` before believing a red. |
| "The agent didn't follow my instruction" | Check whether it was right. A deviation is often correct, and reported up front. The same holds in reverse: a reviewer may retract its own finding — even a blocking one — in the review body after measuring. "You were right and I was wrong" is the gate working, not a reviewer to distrust. |
| "X already does this work, so my code can't be the one that fails" | Does X **carry the value forward, or ask again?** An impossibility claim usually slides over exactly that step. |
| "The exception type proves the mechanism" | A wrong story that predicts the observation is not falsified by it, and can survive several rounds. Take the stack trace. |
| "My fact pins it — the count is right" | A count stops discriminating the moment the code adds one. Assert over the whole set; then only placement can move the target. |
| "The issue says that file documents X, so I'll fix X" | It may not. Inventing a defect to match an issue is worse than the issue being wrong. Read the file first. |
| "The agent said `DEVIATIONS: none`" | It answered from intent. Make the return contract require **quoting the line**, not self-assessing compliance. |
| "I drove four rounds, so I can judge whether the diff sprawled" | You are the worst-placed reader of a diff you shaped. Ask the reviewer for the scope ruling. |
| "The filter's logic is right, it doesn't need its own test" | Right logic, no exercising case — a filter can merge unpinned exactly this way and stay so until a later test finally walks the path. |
| "The adjudicator did the math, I can build on the number" | Ruling figures are hypotheses, not facts. Counts, measured quantities and exception types can all move on verification; the fixer checks, then posts corrections after merge. |
| "The sink/guard is correct, wiring is another card's" | Correct and unreached is not shipped. The review quotes the Exit clause and names what composes it. |
| "The rule compares to the reference, so it's fair" | Only if the reference's answer is derivable from the input the variant sees. A clause that is not derivable is unpassable by anyone and can still decide a verdict. |
| "The reviewer measured it, so the adjudicator can rule on it" | Hand it over labelled unverified and ask for contradictions. A ruling can stand while its own headline number falls. |
| "The guard is narrow, it only catches the bad case" | Ask what else it now covers. A guard added so bad *data* fails can have the test's own setup inside it, failing for the wrong reason — the inversion it existed to prevent. |
| "The issue still reads OPEN, so the auto-close failed" | That read is racy. Read the squash commit body, or re-read after a beat, before writing either outcome into a permanent comment. |
| "Both PRs are green, so merging both is green" | Per-branch gates don't compose over a counted set. Serialise, or rebase and re-run one against the other. |
| "Same clone, FETCH_HEAD is fine" | Concurrent agents mutate it mid-read, and nested checkouts go stale while still reading as authoritative — yielding stale counts and a false "the fix never landed" verdict. Resolve the SHA once and pin every read in the brief to it, in the agent's own worktree. |
| "The parent merged, the child will just retarget" | It can be closed, or silently retargeted onto a base it was never reviewed against. Rebase `--onto`, then content-hash before carrying the review. |
| "It's a rebase, the review stands" | It stands only if the content is identical — prove it with diff-of-diffs, then merge without a third review. |
| "The spec is silent, so the fixer's convention is fine" | It is a design act. A short adjudication is the cheap way to ratify it or relocate it. |
| "The suite is the sum of the filtered chunks" | Some runners' filters are exact-match and silently drop everything nested below the named level. Run unfiltered, or split by test class. |
| "I stamped the progress, then dispatched the next agent" | Text before tool calls may never render, so a run can look silent while reporting diligently. Stamp last. |
| "The checklist says every item is Met, the demo is done" | Met means the noun shipped. An operator walking the same artifact can find defects the checklist cannot see. Walk it as the user first. |
| "The constraint check says the requested design is infeasible, so the design must change" | Name the conflict first (drop one constraint at a time). Often the named rule is the defect — an assumption baked into the constraint set — and the design stands. Escalate the *rule*, with options, not the design. |
| "Two agents measured the same thing and disagree, I'll relay both" | Reconcile arithmetically before relaying: a difference that factors cleanly (a per-item weight times a count) says one input differed between the two measurements. A reconciled number is a fact; two numbers are a question. |
| "The reviewer can't request changes, so it's a comment" | Same-account PRs refuse `--request-changes`. The verdict is the literal `VERDICT:` line in the body, whatever GitHub calls the review. |
| "The source data says X, the requested design says Y — one correction" | Check the whole frame: which parts match. A single reported mismatch often hides several wrong input fields; each correction moves a different downstream number. |
| "Round 5 is just another round" | A late round on a resumed agent costs a multiple of round 1 for a same-sized fix. Price the round before spending it; when the budget says stop, adjudicate the open findings instead. |
| "The check-up timer is cheap insurance" | Per agent, on a fixed interval, it re-reads the entire orchestrator context to learn "still alive" — and still finds a stall up to a full interval late. One silent sweep is cheaper and faster. |
| "I made the edit, so it is in the diff" | Not if you later ran `git checkout -- <that file>` in a mutation-revert loop on it. A fixer can report a corrected paragraph as landed when its own revert has eaten it. Commit the edit before you start mutating that file, or re-read it from `git diff` — never from the edit. |
| "Two cards decided the same question opposite ways, one of them is wrong" | Look for the experiment that distinguishes them first. Run the one neither card had — restore the removed input, re-run, diff — and a single rule may explain both outcomes; neither card was inconsistent. |

## Goal focus, waiting and cost

| Excuse | Reality |
|---|---|
| "The scope doc lists the open cards, that is the plan" | A card list is not a goal. Write one observable outcome first — a report, a screen, a recording — then derive the minimum card set that closes it and name the rest as out of the wave. Otherwise every card that exists reads as in scope. |
| "The finding is real, so it gets a card" | Real and irrelevant to the goal is a close-comment line, not a card. A register that files every real finding is a register that generates work: measure filed-to-merged, and two runs above 1 says the mechanism is producing the cards, not the backlog. |
| "It's a follow-on milestone, so the backlog says what to do next" | Compute the lineage — what share of its cards descend from the previous milestone's. Above about half, the predecessor did not close its question and this one will re-cut the same defects. That is a direction question for the operator, asked before dispatch, not a wave plan. |
| "Every ruling deserves a durable design record" | One written for a question that does not change the Exit costs a doc PR, a review, a merge and an operator read, and moves nothing anyone can see. Size the record by the goal. Above roughly two rulings per merged card the spec itself is the defect — propose the change as one batch. |
| "The rule is in the spec, so the choice is amend it or re-author the inputs" | There is a third, and leave-one-out is what earns it: **demote** the rule — hard to soft, soft to advisory. Demotion is always on the menu when leave-one-out names a rule as the conflict, and where the spec states its own cutting order, quote that order instead of inventing one. |
| "The schema has a field for it, so the model may fill it" | A field the model is meant to leave empty is an invitation to fill it; it does not belong in the record the model sees. And a schema change to an agent-facing record is a **prompt** change — brief it with the re-capture rather than treating it as data plumbing. |
