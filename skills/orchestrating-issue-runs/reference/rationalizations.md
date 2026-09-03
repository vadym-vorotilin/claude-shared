# Common rationalizations

The full set. SKILL.md keeps the ten that fire most often; every other row is
here, and none has been deleted.

Each left-hand column is a sentence an agent actually wrote, or would have
written, on its way to the mistake in the right-hand column. Read the left
column when something feels obviously fine.

## The standing set

| Excuse | Reality |
|---|---|
| "User said unattended, so start now" | Unattended = no mid-run questions, not no scope gate. Present scope first. |
| "These two issues are coupled, share the checkout" | That's how two agents corrupted each other's trees. Worktrees + merge order. |
| "Review was clean, the reviewer can merge" | Verdict ≠ decision. Gates (human labels, groups, freezes) live above the reviewer. |
| "The spec gap is obvious, I'll just decide" | Cheap now, contradiction later. Adjudicator + citation + binding comment costs one dispatch. |
| "Fresh agent is cleaner than resuming" | True below the ceiling — there a resume keeps the task context for a fraction of the price. Above it both paths pay the same cache write, and the resumed one re-reads a bloated context on every turn after it. |
| "Minor finding, not worth a follow-up" | Silent discards are how the next run re-finds it at 10x cost. |
| "Tests are green, the constraint works" | Green survives mirrored, transposed, self-paired and shifted inputs. Mutate position, not just structure — and where the rule is about *which of two objects* is involved, a whole-structure mirror/transpose/shift moves both at once and stayed green on two cards while the rule was broken. Move one of them. |
| "It compiled red first, that's my TDD evidence" | A compile error proves the file was absent. Go green, then mutate the load-bearing decision back to naive and quote that red. |
| "The fixer says it reproduced my sabotage" | Re-apply it yourself. One reviewer doing that found the fix still passed a subtler mutation. |
| "My README documents it correctly" | The parent doc may still contradict you, and you can't see it until the sibling merges. Second-merged owns the parent. |
| "The issue is small, a cheap review will do" | A one-constraint issue behind a reviewed seam still took three rounds, all real position bugs. Size ≠ review risk. |
| "My guard can't go blind, it scans everything" | It was blind to the idiom the same PR introduced. Test your guard against your own diff's shape first. |
| "The reviewer told me how to fix it" | Its remedy caught 9 of 10 shapes. A later one was not merely vacuous but **false at the correct value** and would have shipped red. Measure it before adopting it; a right finding can carry a wrong fix, and measuring changed the fix all three times in one run. |
| "That's the fifth hole, I'll patch it too" | Four of the five were one mistake. Ship an invariant with a named outside, not enumeration N+1. |
| "The adjudicator says they're independent" | Independent contracts, same file, same function. Re-check file surfaces yourself. |
| "It's still queued, I'll nudge it to wait properly" | Nothing has started. A better nudge stalls it again — take the gate off the agent. |
| "The suite was 1000 last I looked" | It moved by 8 when a sibling merged. Make every agent re-measure; two caught this in one run. |
| "CI is red, the branch is broken" | One was a cancelled job, one an Actions outage at setup. `gh api .../jobs` before believing a red. |
| "The agent didn't follow my instruction" | Check whether it was right. Three deviations this run were all correct, and all reported up front. The same holds in reverse: two reviewers retracted their own findings — one blocking — in the review body after measuring. "You were right and I was wrong" is the gate working, not a reviewer to distrust. |
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
| "Same clone, FETCH_HEAD is fine" | Concurrent agents mutate it mid-read, and a superproject's submodules go stale while still reading as authoritative — one session took a stale count and a "the fix never landed" verdict off one. Resolve the SHA once and pin every read in the brief to it, in the agent's own worktree. |
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
| "I made the edit, so it is in the diff" | Not if you later ran `git checkout -- <that file>` in a mutation-revert loop on it. One fixer reported a corrected doc paragraph as landed and its own revert had eaten it. Commit the edit before you start mutating that file, or re-read it from `git diff` — never from the edit. |
| "Two cards decided the same question opposite ways, one of them is wrong" | Look for the experiment that distinguishes them first. A reviewer ran the one neither card had — restore the removed input, re-run the derivation, diff — and one output was unchanged while the other rebuilt wholesale. One rule covered both; neither card was inconsistent. |

## Goal focus, waiting and cost

| Excuse | Reality |
|---|---|
| "The scope doc lists the open cards, that is the plan" | A card list is not a goal. Write one observable outcome first — a report, a screen, a recording — then derive the minimum card set that closes it and name the rest as out of the wave. Otherwise every card that exists reads as in scope. |
| "The finding is real, so it gets a card" | Real and irrelevant to the goal is a close-comment line, not a card. A register that files every real finding is a register that generates work: measure filed-to-merged, and two runs above 1 says the mechanism is producing the cards, not the backlog. |
| "It's a follow-on milestone, so the backlog says what to do next" | Compute the lineage — what share of its cards descend from the previous milestone's. Above about half, the predecessor did not close its question and this one will re-cut the same defects. That is a direction question for the operator, asked before dispatch, not a wave plan. |
| "Every ruling deserves a durable design record" | One written for a question that does not change the Exit costs a doc PR, a review, a merge and an operator read, and moves nothing anyone can see. Size the record by the goal. Above roughly two rulings per merged card the spec itself is the defect — propose the change as one batch. |
| "The rule is in the spec, so the choice is amend it or re-author the inputs" | There is a third, and leave-one-out is what earns it: **demote** the rule — hard to soft, soft to advisory. Demotion is always on the menu when leave-one-out names a rule as the conflict, and where the spec states its own cutting order, quote that order instead of inventing one. |
| "The command only takes six minutes, I'll wait for it" | Six idle minutes is past a subagent's prompt-cache lifetime, so the next turn rewrites the entire context at the write rate — more than an order of magnitude above what the poll turns would have cost. Detach and poll. |
| "This agent isn't a fixer, so the poll rule doesn't apply" | It applies to whoever waits. A reviewer re-measuring a suite, a screenshot agent driving a browser, a recording agent and a wrap agent all pay the identical rewrite; the one that proved it was a post-run capture agent whose ad-hoc brief omitted the line. |
| "The orchestrator is past its ceiling, hand over now" | The orchestrator's ceiling and a fixer's are different numbers for different reasons (iron rule 9). Past the soft one you **offer** a handover at the next natural boundary — a merge, a wave end, a ruling — and the operator decides; you do not stop mid-wave. |
| "The agent ran to several times its ceiling but it finished, so note it" | An agent measured past twice its ceiling is an instrument failure, not an observation: the rule did not bind, which means every other agent under it is unmeasured too. Fix the instrument before the next dispatch. |
| "The schema has a field for it, so the model may fill it" | A field advertised in a model's output schema is an invitation to fill it; a field the model must leave empty does not belong in the schema. And a schema act on an agent-facing record is a **prompt** change — brief it with the re-record rather than treating it as data plumbing. |
