# Why the brief lines are there

The rules themselves are in `briefs/` (agent voice) and `phase1-loop.md` →
"Briefs" (the orchestrator's side). This file keeps the reasoning and the
failure each line was written against, as it stood when the lines moved. Read
it when changing a brief block, or when an agent argues a line does not apply.

**Agent briefs — three run-stopping rules.** (1) Name the Monitor tool and
*unpolled* `run_in_background` explicitly as banned, for **every dispatched
agent** — "no monitors" alone can be read as a Bash-only rule, and a fixer
then stalls on a Monitor. Detached-and-polled work is the permitted form (the cache-warmth
brief lines, Briefing rules below). The orchestrator's own liveness sweep is the only Monitor
any agent may rely on; it is the orchestrator's, and no brief may grant it.
(2) Scratch filenames are card-scoped
(`pr-<issue>-<repo>.md`); two agents sharing one filename can propagate one
card's PR body onto another card's PR, and every `gh pr edit N` is preceded by
`gh pr view N --json title,headRefName`. (3) A tool that syncs a contract into a
sibling checkout runs only on the schema card, and its **output path is a
worktree, never the shared clone**. After any schema card, check the shared
clones with `git -C <clone> status --porcelain` and **report a dirty one to the
operator — never reset it**; the uncommitted work in it may be theirs.

**Briefing rules.** Every brief: **the run's goal line**, role, ONE issue,
binding comments listed by name, repo + worktree instructions, concurrent-agent
file surfaces to avoid, the return contract (data for the orchestrator, incl. a
STATUS line). **A ban goes in every brief it binds, not only in a shared
preamble the brief points at** — a shared preamble can ban a destructive git
command and a short fix round use it anyway; the orchestrator's post-merge
check (the command's own list is empty) is what makes it harmless. Repeat the
bans verbatim in each brief and check their trace after each return.

**The return contract has a shape, and it is short.** A return is at most
about 40 lines: STATUS, GOAL, the quoted numbers (suite line, counts, SHAs), PR
number and head, DEVIATIONS, DESIGN_QUESTIONS, and one path to a report file in
the run's scratch directory that holds everything else. The orchestrator greps
the report for a named question and does not read it; a 200-line return is
read at whatever context the orchestrator has reached, on every later turn.
**The goal line goes in the brief and comes back in the return contract.** Add
a line to every return contract — *"GOAL: what your deliverable moved on the
run's goal line, in one sentence, or `nothing`"*. Two things fall out of it and
both are the point. An agent that cannot answer has usually built something
correct and adjacent, which is a scope conversation to have before the review,
not after the merge. And a **finding that moves nothing on the goal is a
close-comment line, never a card** — say that in the brief, in those words,
because "nothing deferred silently" is otherwise read as "everything deferred
is filed" (iron rule 6).

**Reviewer brief template.** On top of the rules above, every reviewer brief
carries:

- *"Post a GitHub review whose body literally contains
  `VERDICT: APPROVED | CHANGES_REQUESTED`"* — in the posted body, not only in
  your return to the orchestrator.
- *"Prove each new guard would fail if the thing it guards stopped being
  true"* — vacuous assertions pass green in more ways than one.
- *"Review PR #N at head `<sha>`, base `<sha>` — these files. Open anything
  outside the diff only to verify a specific claim you are making."* Resolve
  the SHAs yourself and pin them; a shared clone moves under concurrent agents.
- *"Rule on scope: is this still one change, and what should be split?"*
- *"Quote the card's Exit clause and name what composes each deliverable"* —
  a sink approved as "correct, not user-facing" was wired into nothing; a
  feature nobody reaches is not shipped.
- *"For every comparison against a reference, confirm the reference's answer
  is derivable from the input the compared variant receives"* — a check can
  score one variant's output against a reference whose value lived only in an
  input that variant was never given; no variant could pass, and it decided
  the verdict.
- For a **docs PR paired with a ruling**, add a `DOCS_PR_MATCH` section on
  top of the `VERDICT:` line, never instead of it: **check each clause of the
  docs PR against the ruling it implements and against the code that actually
  shipped, and report `DOCS_PR_MATCH: MATCH` or the list of mismatches.** The
  merge agent merges the docs PR only on `MATCH`; the code PR's gate stays the
  literal `VERDICT:` line.

**Return contracts must force quoting, not self-assessment.** An agent asked "did you
comply?" answers from intent — an agent can return `DEVIATIONS: none` having
missed an explicit instruction. Ask it to **quote the line** (the closing keyword, the shipped
wording, the measured number) and it answers from the file instead.

**Tell fixers an issue's factual claims are checkable, not givens.** An issue can
assert that a file documents a command a certain way when it documents no such
thing — the claim generalised from the orchestrator's own failed invocation.
The fixer should read the file, find no defect to correct, verify real
behaviour and document that instead.
**Inventing a defect to match an issue is worse than the issue being wrong.**
`gh` comments with literal backticks: always `--body-file`, and write the file
with a **quoted** heredoc (`<<'EOF'`) — `--body` runs command substitution, and
so does an *unquoted* heredoc, which is the same bug one step later.

**The standing brief lines.** Each earned its place by catching something a
brief without it missed:

1. **"Re-measure the baseline yourself; do not carry a number across."** Agents
   catch stale suite counts handed to them by the orchestrator. Never state a
   number the agent can measure.
2. **"If any part of the ruling turns out wrong, or more expensive than it
   looked, say so explicitly — do not quietly drop it."** A reported deviation
   is usually the right call, including one that corrects a ruling's stated
   premise by measurement while still following the ruling.
3. **"Any sentence asserting something is impossible or cannot be tested is a
   hypothesis. Test it before you write it."** **The highest-yield line here, by a
   wide margin.** A single pull request can carry several false impossibility
   claims — some refuted by a reviewer building the thing, some caught by the
   author in its own drafts because it ran the sabotage instead of trusting the
   paragraph it had just written. All written honestly by strong agents. The
   diagnosis generalises: reasoning about what a call does is not running it.

   Carry the sharpened form into briefs as well, because it names the step they
   all slid over: **when a claim rests on another component already doing the same work,
   the load-bearing question is whether that component carries the value forward or
   asks again.** Nothing usually requires two answers to agree.

   And when a claim survives a round because the evidence fits it: **a wrong story
   that predicts the observation correctly is not falsified by that observation.**
   An exception type is evidence; a stack frame is the measurement.

   **The plan's own claims are hypotheses of the same kind** — "this test goes
   red under that mutation", "the size stays flat". Brief the implementer to
   run the named mutation, and when the plan's test stays green, to add a test
   that does go red rather than ship the plan's. Plans are wrong this way often enough that the agent catches it only
   because the brief told it to run the mutation instead of trusting the plan.
4. To a **fixer building a guard**: *"the first shape to test your guard against
   is the shape your own diff introduces."* Two more, learned the same way:
   **pin it with a property over the whole set, never a count** — a test asserting
   "exactly N items" stops discriminating the moment the code makes N+1, whereas
   one asserting "every item, wherever it lands" can only be moved by placement;
   and **ask what the new guard now covers besides the thing being guarded** — a
   guard added so bad *input* fails a check can have *infrastructure* setup
   inside it, which is the same inversion the guard existed to prevent,
   reintroduced by the change implementing it.
5. To a **fixer receiving a reviewer's remedy**: *"verify it, do not copy it —
   a right finding can carry a wrong fix."*
6. To a **fixer on any position- or orientation-sensitive card**: *"use an
   ASYMMETRIC fixture and a hand-typed candidate oracle from day one."*
   Fixture-blindness repeats by axis. Tests stay green under a whole-fixture
   transform because the fixture is symmetric, and a directional filter passes
   because the fixture has no variation on the axis it filters. The
   position-mutation review battery catches this, but the fixture requirement
   catches it a round earlier.

   **A rule about a relation between two objects needs a mutation that moves
   only one of them.** Whole-thing transforms — shift, rotate, reflect — move
   both, and every one of them can leave the suite green while the rule under
   test is broken. Only a mutation that
   moves one of the two objects and leaves the other where it is discriminates
   a working rule from a broken one; no whole-thing transform can.
7. To **any long-running dispatched agent**: the context-ceiling brief lines
   (`$S/../context-ceiling/brief.md`), verbatim. Reviewers get the opposite line:
   one verdict on the whole diff, never split. Do not copy the fixer's numbers
   into the orchestrator's ledger, or the other way round (iron rule 9).
8. To **every waiting role**: the cache-warmth brief lines (`brief.md`),
   verbatim (Briefing rules, above).
9. **The goal line, and the `GOAL:` return line.** Every brief carries the
   run's goal line; every return contract asks what the deliverable moved on
   it, or `nothing`. A finding that moves nothing is a close-comment line, not
   a card.

**Clean-env rule.** Any shell script an agent writes gets verified in a
clean environment (a clean container image, or `env -i HOME=$(mktemp -d)`),
not just the dev machine. The three bug families that only reproduce on
clean/fast runners: second-granularity timestamp collisions, `/dev/stderr`
redirects (ENXIO on Linux when stderr is a pipe), ambient git
identity/config. CI's first run on a repo WILL find this class — treat each
find as its own issue assigned to the code's owning agent, not a drive-by.
**"Deterministic" is a per-platform claim until it has been measured
elsewhere.** A computation that is deterministic on one platform can diverge
on another at a threshold, and a code comment claiming "reproducible on any
machine" is not evidence of it — measure on a second platform before an
adjudicator cites it. The fix lands as its own correction, never as a
re-baseline of frozen evidence.
