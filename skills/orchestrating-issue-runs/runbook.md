# Runbook — orchestrating issue runs

Mechanics for each phase. SKILL.md holds the rules; this holds the how.
Distilled from real multi-repo runs. Every figure below is one project group's
observation — **recalibrate on your own first run.**

**"The operator"** here is the human who owns the run — the same person the
rules call "the user". Both words appear below; they mean one person: the one
who approves the scope, owns the held-for-human gates, and rules on filings.

## What this assumes

Check these before Phase 0; the skill will mislead you where they do not hold.

- **GitHub + `gh`**, with issues as the unit of work and PRs as the unit of
  delivery. Nothing here translates to another tracker unchanged.
- **A subagent harness that can resume an agent from its transcript.** Several
  protocols (fix rounds, rescue) assume it. If yours cannot, see Iron rule 5's
  fallback and expect fix rounds to cost full price.
- **`git worktree`**, and a scratch directory outside the repo.
- **Merge rights that do not need a second human approval.** Reviewer and
  author share one account here, so the verdict line *is* the record. On a repo
  with required approvals or CODEOWNERS the orchestrator's merge will fail —
  **verify branch protection and the repo's merge method at Phase 0** and put
  both in the scope doc.
- **Issues backed by citable specs.** Adjudication rules *against documents*.
  With a backlog of three-line issues and no specs, the adjudicator has nothing
  to cite: have it **recommend, and record the decision as the new spec**,
  rather than pretend to rule.
- **A production/test split you can diff.** Checks phrased as "zero non-comment
  production lines" assume you can name the production path and recognise a
  comment. Restate them in your own layout's terms rather than copying.

**Before the first unattended run:** try this on a repo where an autonomous
squash-merge to the default branch is acceptable. This skill merges and closes
issues on its own once the scope is approved.

## Phase 0 — Scope

One strongest-tier agent + the orchestrator. Inputs: specs/ADRs/glossary,
project memory, ALL open issues + labels + board state, open PRs, CI state
per repo, prior-run ledgers/deferred-minors.

**If this run's wrap will produce a demo artifact, ask once — before
presenting the scope doc — whether to publish it as a release**, and SAVE the
answer to project memory so later runs read it instead of re-asking. Re-ask
only if memory holds no answer. The run's memory is also what says *how* demos
are published: which repo, which tag scheme, whether the milestone description
links the asset.

Produce the scope doc (posted as a message, not a file the user must open):

1. **Waves** — dependency-ordered issue groups; what parallelizes, what
   serializes, and why (file surfaces, contract dependencies).
2. **Per-issue**: model tier, risk class, expected human gates, rough token
   cost. **Estimate the agent's cumulative total including its fix and
   re-review rounds** — that is what you actually buy, and a per-dispatch
   figure will read about half the true cost. Roughly: a review round costs a
   quarter of the original fixer, because resume keeps the context. **Take your
   own numbers from your first run; a band from someone else's stack will not
   transfer.**
   As a shape rather than a size, one run's split: fixers ~45%, reviewers ~25%,
   approaches ~25%, adjudication ~5%. **A card carrying both an adjudication
   and a contract act (schema/version-constant change, cross-repo pin) costs
   well above its plain implementation estimate** — in one run, four such cards
   each landed at roughly twice their estimate. Treat that multiplier the way
   you treat the split above: a shape to confirm against your own first run,
   not a band to import. **Count seams, not bullets.** A card that lands a new
   transport, a repo-wide guard, or a routing/identity function is a
   milestone-sized card however few bullets it has: each such seam took 3–5
   review rounds in one run (a guard alone took five), and the card landed at
   roughly three times its bullet-count estimate.
3. **Re-estimate when an approach refutes a premise you priced on.** If an
   issue was budgeted as a cross-repo schema chain and its approach proves the
   chain does not exist, the estimate is stale — being wrong in the user's
   favour is still being wrong. **Any refuted premise that touched an estimate
   gets the estimate restated in the next report.**
4. **Scope added mid-run is unestimated by construction — say so.** Issues
   added after approval have no number attached, and one of them may be the
   most expensive of the run. When the user approves a scope change, give it
   its own estimate in the same message.
5. **Diff what the milestone promises to show against the cards' outputs.**
   Per noun in the milestone's own Demo/Measure line: which card makes THIS
   visible, and does that card's exit assertion actually reach the surface? In
   one run the milestone named four visible numbers and the card decomposition
   delivered three — the fourth card had shipped a calculator nothing called,
   and only a wrap-time adjudication caught the silently-breakable promise.
6. **Inconsistency sweep** — spec contradictions, undefined shapes referenced
   by issues, label/board drift, missing CI on any repo whose PRs must pass a
   merge gate (a gate that rejects green-by-absence holds a zero-CI repo's
   PRs forever — check this BEFORE the first merge, not after).
   Classify each finding: *adjudicable* (agent rules it during the run) vs
   *architectural* (user decides now). **List candidate follow-up issues;
   file none until the user approves the list.**
7. **Held-for-human list** — spec/contract freezes (including any doc
   amendment that would edit one), anything installing or changing the
   operator's machine, external data only the operator has, gates named by the
   project's own workflow docs. **A gate the operator delegates back runs as a
   two-mind protocol**: the implementer decides with citations, and the
   reviewer independently re-decides. Two convergent minds stood in for the
   operator cleanly twice in one run; divergence escalates.
8. **Budget** — token target and the drain rule.

User approves (possibly with edits) → run starts. Scope changes mid-run
(new issues discovered, blockers) are appended to the ledger and surfaced in
the next report, not silently absorbed.

## Phase 1 — Per-issue loop

**Approach.** One agent reads the issue + cited specs + current code, posts
a concrete approach as an issue comment (files, tests, fixture, exit
assertion), flips the triage label. Returns "DESIGN QUESTIONS: none | list
with recommendations". Approach agents for sibling issues run in parallel but
must be told about each other's file surfaces.

**Go-gate** (orchestrator). Clean approach → flip to go and dispatch the
fixer. Design questions → adjudicator first. Strip any "needs human
brainstorm first"-style gating label when gating — it is spent once the
approach passed a human-delegated gate; leaving it on poisons board status
derivation (parked outranks lifecycle).

**Adjudication.** Strongest tier. Rules each question against the specs with
citations; posts a binding "## Design decisions" comment; drafts any doc
amendment as a PR, reviewed for `DOCS_PR_MATCH` (defined in the reviewer brief
template below) and **squash-merged by the orchestrator after its paired
engine PR lands** — or immediately if standalone. No held queue: holding docs
amendments for the human only added latency, and every one came back merged
unchanged. Design-changing amendments are still surfaced in the report, just
not gated — **with one exception: an amendment that edits a FROZEN spec or
contract still goes to the held-for-human list.** Code proceeds on the ruling.
A schema-shaped ruling triggers the schema-change chain (below).

**A ruling's own numbers are hypotheses to the fixer, not facts.** An
adjudicator's cited figure can still be off by measurement — in one run a
census count, a measured dimension and an exception type all moved when the fixer
checked them. The fixer verifies before building on the figure, and posts any
correction as a follow-up comment after merge rather than absorbing it
silently.

**Fixer.** TDD (red recorded, then green), in a fresh worktree
(`git -C <repo> fetch origin && git worktree add <scratch>/wt-<issue> -b
<branch> origin/main`), branch per the repo's convention, PR body carries
red→green evidence, labels flipped by the fixer at start/end. Never merges,
never pushes to a protected/main branch. Cross-repo issues: one worktree and
one PR per repo, cross-referenced; merged later as an ordered group.
**A design resting on several rulings gets a throwaway probe before the real
diff** — a minimal end-to-end skeleton, actually run. One such probe surfaced
29 failures from a contradiction across four rulings that nobody had seen on
paper, and was the cheapest stop-clause of its run. **Widening a gate is a
design act, not an implementation detail**: a necessary, narrow exemption is
still disclosed in the PR body and paired with a tripwire test that reads the
production roster (never a re-typed copy), so the next addition reds.

**Review.** Independent agent, never the implementer. Gets the issue, the
approach + rulings, the spec sections, the PR. Posts a GitHub review with an
explicit `VERDICT: APPROVED | CHANGES_REQUESTED` line (self-approval is
blocked when reviewer and author share the account — the COMMENT + verdict
line IS the record). **The `VERDICT:` line must be literally present in the
POSTED review body, not just in the agent's return to the orchestrator** —
the merge agent checks GitHub's own review text, and on one card the posted
review bodies carried no verdict line at all (the state read back as COMMENTED
regardless of what the agent's return said). The reviewer brief template below
carries this requirement so it does not depend on this paragraph being read.
Reviews verify claims, not prose: run the suite, probe the mechanism
adversarially, sabotage-test guards ("would this test catch the bug it claims
to catch?").

**Fix rounds.** Findings go back to the SAME fixer via message (resume), not
a fresh agent — rounds 1–3. Round 4–5: fresh agent, one tier up. Cap 5, then
adjudicate open findings: park with a ruling or stop. Each round ends with a
scoped re-review of the fix diff by the SAME reviewer (resume). **Exception —
the orchestrator verifies it instead of spending a review cycle:** any round
that is doc/comment text plus mechanical tests, with **zero non-comment
production lines**. What makes that safe is not the greps — it is
**re-applying a discriminating mutation yourself, on a different axis than
the fixer's.** Same-axis re-application proves almost nothing.
Non-blocking findings: take one-liners worth taking now; everything else →
ledger + close comment + approved follow-up issue.

**Merge** (orchestrator). Review clean + CI green + no open human gate →
squash-merge, delete branch, close issue with a summary comment naming what
was deferred, sync the board, mark the ledger. **Exception: `main` merged
INTO an integration branch uses `--merge`, never squash** — main's own commits
carry closing keywords, and a squash concatenates every message and re-fires
them when the branch reaches main. Run the full suite on the merged tree
before the final PR; per-branch gates do not compose (a schema bump under one
run turned a textually clean merge into four semantic reds, one a lie). Cross-repo groups merge in
dependency order (producer repo first), all-or-nothing. **Delegate the merge
mechanics to a small agent** — gate polling, conflict resolution, the
close-comment/label/board-sync bundle — because orchestrator context is for
coordination; a single trivial gate-plus-merge may stay one inline command.
**A review's docs-only wording nit on an otherwise-clean docs PR: fix it on
the docs branch yourself before merging** rather than spinning a fix round —
that worked twice in one run. **A card that straddles the wave boundary closes
in the wave that did its work, and the remainder is filed fresh** — cleaner
than an open card in a closed milestone, and the same applies to an exit that
is structurally unclosable (file its recurring successor).

**The post-merge state read is racy — do not gate on it alone.** A PR body carrying
only a bare issue reference while the *squash commit* body carries the full closing
keyword still auto-closes, but a state read immediately after the merge can return OPEN.
Asserting "the auto-close failed" from that read put a wrong sentence into a
permanent close comment. **Read the commit body, or re-read the state after a beat**,
before claiming either outcome.

**Scope rulings belong to the reviewer.** After several fix rounds the orchestrator
is the worst-placed reader of whether the diff has sprawled — it shaped the rounds
and will read coherence into it. Ask the reviewer explicitly: is this still one
change, and what should be split?

## Protocols

**Ledger.** Scratchpad markdown, written before the first dispatch: wave
plan, per-issue log lines, rulings, deferred minors, resume queue, the
pause/resume state. After a compaction or limit reset, trust the ledger and
`git log` over memory.

**Agent briefs — three run-stopping rules.** (1) Name the Monitor tool and
`run_in_background` explicitly as banned, for **every dispatched agent** —
"no monitors" alone was read as a Bash-only rule and one fixer stalled on a
Monitor. The orchestrator's own check-up timer is the sole exception; it is the
orchestrator's, and no brief may grant it. (2) Scratch filenames are card-scoped
(`pr-<issue>-<repo>.md`); two agents sharing one filename propagated one card's
PR body onto another card's PR twice, and every `gh pr edit N` is preceded by
`gh pr view N --json title,headRefName`. (3) A tool that syncs a contract into a
sibling checkout runs only on the schema card, and its **output path is a
worktree, never the shared clone**. After any schema card, check the shared
clones with `git -C <clone> status --porcelain` and **report a dirty one to the
operator — never reset it**; the uncommitted work in it may be theirs.

**Rebases after a sibling merge.** Per-branch gates do not compose over a
counted test set, so every merge forces the queued PRs to rebase and re-run.
The card's **fixer** does the rebase — the orchestrator never implements — and
publishes it with `git push --force-with-lease`, never a bare `-f`: a fix round
pushed to the same branch while the rebase was in flight must abort the push,
not vanish.

When the rebase is content-identical the orchestrator may carry the standing
review rather than commission a third one — but only on a check that can fail.
**Record `old-base` and `old-head` before the rebase**; the force-push destroys
`old-head`, so afterwards is too late. Then:

```bash
before=$(git diff "$old_base".."$old_head") || exit 1
after=$(git diff "$new_base".."$new_head")  || exit 1
[ -n "$before" ] && [ -n "$after" ] || { echo "one side produced no patch — NOT verified"; exit 1; }
[ "$before" = "$after" ] || { echo "content differs — re-review"; exit 1; }
```

Both sides must exit 0 **and** print a patch. A bad or garbage-collected SHA
makes `git diff` write to stderr and print nothing, and comparing two empty
outputs reports "identical" — a gate that licenses skipping review must never
pass by producing nothing. Merge on the verified-identical result plus the
fixer's suite line **from the rebased head**.

Queue gated fixers with a blocking `until` poll on `origin/main` so the next
card branches promptly after a merge. Bound the poll well inside the brief's
Bash timeout and have it exit non-zero on expiry, so a slow merge surfaces as a
failed step rather than a killed shell.

**Test-runner filters.** A runner's path or namespace filter may be exact-match:
summing folder-level chunks then silently drops everything nested below them —
a large slice of the suite ran but was never counted. Confirm the runner's
filter semantics before trusting a summed total; brief agents to run unfiltered
or split by test class, and to quote per-chunk totals.

**Fixer-authored conventions.** When a spec is silent a fixer will author a
convention (which side a default falls on, where an annotation anchors, how a
zero case renders). Treat each as a design act: a narrow, tightly-scoped
adjudication either ratifies, relocates or replaces it; do not block on it and
do not let it merge un-ruled. In one run two of three were ratified; one moved
to the right section.

**Cassette retries** (only where the project records live interactions and
replays them in tests). Re-recording until a take is usable and keeping the last
one is disclosed, not cherry-picked — and only when every discard was for
validity. Discarding on content the brief never pinned is a selection the
operator rules on, and the recording's provenance should carry an attempt count.
Route it to the deferred register, not to the reviewer.

**Check-up timer.** On every dispatch or resume, arm a one-shot timer for 45
minutes (`Monitor`: `sleep 2700; echo "CHECK-UP due: <agent> ..."`). Agents
die silently — weekly quota, mid-stream API errors, background-wait stalls —
and the run reads as "still working" for hours otherwise — that is how one
run's quota pause slipped by unnoticed. When it fires, verify state with cheap
read-only commands (worktree commit time, `git status`, PR existence,
transcript last-write time, running build processes) and report one line.
**If the agent is alive, report the one line and RE-ARM the timer**; a
legitimately long agent that is checked once and then never again is the exact
hole this protocol exists to close. Rescue it if it is dead. Cancel the timer
(`TaskStop`) only when the agent returns on its own. Never re-dispatch a live
agent because the timer fired.

**Rescue.** Agent killed by limits/crash: `SendMessage` to the same agent id
— it resumes from its transcript with the worktree state intact. **Verify
worktree, branch and PR state yourself first and hand those facts back in the
message** — it stops the agent re-deriving them and stops it recreating a
worktree that still exists. Include "recreate at a fresh path if it is gone".
Causes seen: watchdog kill after idling on a background job, mid-stream API
error, session quota limit. All three resumed and completed; none needed a
fresh dispatch.

**Stall nudge.** Agents stop with "waiting for the monitor/background task".
Nudge with: use a BLOCKING wait (`until <check>; do sleep 10; done`, or
`gh pr checks --watch`), then finish and return the report. Put this in every
brief preemptively.

**When the nudge fails, remove the dependency.** If the thing the agent is
waiting on **has not started** — a queued CI run, a job with no runner — a
better blocking wait stalls it again, because there is nothing to observe. Take
the gate off the agent: tell it to return the report with `CI: queued`, and own
that gate yourself. You own it anyway; merge requires CI green *and* review
clean, and the agent cannot merge.

**Idle time at parallelism 1.** While the one in-flight agent runs, pre-write
the next brief instead of waiting on it — this kept dispatch latency near zero
across a whole run. The brief is finished when the agent returns — only the
just-landed PR/branch facts get filled in before send.

**Briefing rules.** Every brief: role, ONE issue, binding comments listed by
name, repo + worktree instructions, concurrent-agent file surfaces to avoid,
the return contract (data for the orchestrator, incl. a STATUS line).

**Every brief also sets a long Bash timeout (e.g. `timeout: 600000`) and bans
backgrounding by name — "never use `run_in_background`; never arm a `Monitor`."**
"No monitors" on its own is not enough: it reads as a Bash rule, and a fixer
that took it that way still armed the Monitor tool and stalled on it. A short default Bash timeout is what
auto-backgrounds long suite runs and live CLI calls; six agents stalled that
way in one run, each costing a nudge round-trip. **This applies to ANY
dispatched agent** — wrap, demo-capture, board and post-run agents included,
not just Phase-1 fixers and reviewers. The one that proved it was a post-run
capture agent whose ad-hoc brief omitted the line and stalled identically.

**Reviewer brief template.** On top of the rules above, every reviewer brief
carries:

- *"Post a GitHub review whose body literally contains
  `VERDICT: APPROVED | CHANGES_REQUESTED`"* — in the posted body, not only in
  your return to the orchestrator.
- *"Prove each new guard would fail if the thing it guards stopped being
  true"* — vacuous assertions were found green three different ways in one run.
- *"Rule on scope: is this still one change, and what should be split?"*
- *"Quote the card's Exit clause and name what composes each deliverable"* —
  a sink approved as "correct, not user-facing" was wired into nothing; a
  feature nobody reaches is not shipped.
- *"For every comparison against a reference, confirm the reference's answer
  is derivable from the input the compared variant receives"* — a rule scored
  a drawn-only example against the spoken cassette whose value lived only in
  the withheld utterance; no model could pass, and it decided the verdict.
- For a **docs PR paired with a ruling**, add a `DOCS_PR_MATCH` section on
  top of the `VERDICT:` line, never instead of it: **check each clause of the
  docs PR against the ruling it implements and against the code that actually
  shipped, and report `DOCS_PR_MATCH: MATCH` or the list of mismatches.** The
  merge agent merges the docs PR only on `MATCH`; the code PR's gate stays the
  literal `VERDICT:` line.

**Return contracts must force quoting, not self-assessment.** An agent asked "did you
comply?" answers from intent — one returned `DEVIATIONS: none` having missed an
explicit instruction. Ask it to **quote the line** (the closing keyword, the shipped
wording, the measured number) and it answers from the file instead.

**Tell fixers an issue's factual claims are checkable, not givens.** One issue asserted
a file documented a command a certain way; it documented no such thing — the claim came
from the orchestrator's own failed invocation, generalised. The fixer read the file,
found no defect to correct, verified real behaviour and documented that instead.
**Inventing a defect to match an issue is worse than the issue being wrong.**
`gh` comments with literal backticks: always `--body-file`, and write the file
with a **quoted** heredoc (`<<'EOF'`) — `--body` runs command substitution, and
so does an *unquoted* heredoc, which is the same bug one step later.

**The standing brief lines.** Each earned its place by catching something a
brief without it missed:

1. **"Re-measure the baseline yourself; do not carry a number across."** Two
   agents in one run caught stale suite counts handed to them by the
   orchestrator. Never state a number the agent can measure.
2. **"If any part of the ruling turns out wrong, or more expensive than it
   looked, say so explicitly — do not quietly drop it."** Three agents deviated
   and reported; all three were right, including one that corrected a ruling's
   stated premise by measurement while still following the ruling.
3. **"Any sentence asserting something is impossible or cannot be tested is a
   hypothesis. Test it before you write it."** **The highest-yield line here, by a
   wide margin.** One later run produced *five* false impossibility claims in a
   single pull request — three refuted by a reviewer building the thing, and two
   caught by the author in its own drafts because it ran the sabotage instead of
   trusting the paragraph it had just written. All written honestly by strong agents.
   The author's own diagnosis generalises: *"I reasoned about what a call does
   instead of running it."*

   Carry the sharpened form into briefs as well, because it names the step all five
   slid over: **when a claim rests on another component already doing the same work,
   the load-bearing question is whether that component carries the value forward or
   asks again.** Nothing usually requires two answers to agree.

   And when a claim survives a round because the evidence fits it: **a wrong story
   that predicts the observation correctly is not falsified by that observation.**
   An exception type is evidence; a stack frame is the measurement.
4. To a **fixer building a guard**: *"the first shape to test your guard against
   is the shape your own diff introduces."* Two more, learned the same way:
   **pin it with a property over the whole set, never a count** — a fact asserting
   "22 asks" stops discriminating the moment the code makes 23, whereas one
   asserting "every ask, wherever it lands" can only be moved by placement; and
   **ask what the new guard now covers besides the thing being guarded** — a guard
   added so bad *data* fails one node had four lines of *engine* setup inside it,
   which is the same inversion the guard existed to prevent, reintroduced by the
   change implementing it.
5. To a **fixer receiving a reviewer's remedy**: *"verify it, do not copy it —
   a right finding can carry a wrong fix."*
6. To a **fixer on geometry or any position-sensitive card**: *"use an
   ASYMMETRIC fixture and a hand-typed candidate oracle from day one."*
   Fixture-blindness repeats by axis. Two geometry cards in one wave shipped
   tests green under mirror and transpose because the fixture was symmetric,
   and a gravity filter green because the ground plane was flat. The
   position-mutation review battery catches this, but the fixture requirement
   catches it a round earlier — the one card briefed this way came back with no
   finding on that axis.

**Schema-change chain** (any ruling that adds/changes a persisted field):
doc amendment PR (orchestrator-merged, paired with the engine PR — see
Adjudication above) → field + version-constant bump → regenerate
generated artifacts (schemas, contracts, pins) → companion PR in each
consuming repo, lockstep → fixtures updated via their regen tool, never by
hand → ordered group merge. Fixtures that snapshot serialized state need a
regen tool committed alongside them or every schema bump breaks them by hand.

**Serialize schema-version acts; parallel PRs collide on the constant.** In
one run two approved engine PRs both claimed the same next version in a single
afternoon, and a third followed. Merge the smaller or further-along first,
have the other rebase and re-run its own regen chain (the tools make that
cheap); the consuming-repo pin moves last. **Declare the version constant a
shared file surface in every parallel-mode brief.**

**A merged validator with no live-fixture consumer is unverified in the
pipeline.** One shipped blocking validator was inert for a day — an exact
check that its own node's read never satisfied — and was found only by the
next card's fixer reading neighbour code. When a review notes "zero live
fixtures exercise this," treat end-to-end activation as unproven: **probe the
validator through the real node at merge time**, not just at unit level.

**Clean-env rule.** Any shell script an agent writes gets verified in a
clean environment (Docker `node:XX-bookworm`, or `env -i HOME=$(mktemp -d)`),
not just the dev machine. The three bug families that only reproduce on
clean/fast runners: second-granularity timestamp collisions, `/dev/stderr`
redirects (ENXIO on Linux when stderr is a pipe), ambient git
identity/config. CI's first run on a repo WILL find this class — treat each
find as its own issue assigned to the code's owning agent, not a drive-by.
**"Deterministic" is a per-platform claim until it has been measured
elsewhere.** A solver diverged across two operating systems at the
optimal/feasible boundary inside the same deterministic budget — and a code
comment claiming "reproducible on any machine" had already been cited as
evidence by an adjudicator. The fix lands as its own correction-term file,
never as a re-baseline of frozen evidence.

**Board/label hygiene.** State labels are flipped by the stage that owns the
transition; the orchestrator runs the board-sync tool after every close. If
board status derives from labels with parked-outranks-lifecycle precedence,
spent gating labels must come off at go time.

**Reports.** One message per issue closed (what merged, what was deferred),
plus a wave summary. During quota pause: record everything, say what's
running, say what's queued; on resume, rescue first, then fill the pipe.

**Progress line.** A long run goes quiet for tens of minutes at a time, and the
user should never have to ask where it is. **After a subagent finishes a
substantial chunk** — a PR opened, a review verdict, a fix round landed, a merge
— emit exactly:

```
**<date and time> - Progress: N%**
<one line about what just happened>
```

Get the stamp from `date`, not from memory. Emit it on meaningful completions,
not on every notification or tool call. If the user asks for "just a number",
give only the number.

**The stamp must be the FINAL text of its turn — no tool call after it.** Text
followed by tool calls in the same turn is not reliably rendered: one run
emitted two stamps (17%, 24%) immediately before dispatching the next agent,
and the user saw neither — the run looked silent for four hours while reporting
diligently. Order of operations on a completion: ledger update → next dispatch →
close the turn with the stamp. If work remains after the stamp is due, end the
turn anyway and continue on the next event.

**Fix the model once, at the first report, and keep using it.** Percentages
drift upward otherwise — this skill's own run reported 76% and had to be
corrected down to 71% mid-run, because approach work on unstarted issues was
being over-credited. What worked:

- weight each issue by **expected cost**, not by count (a heavy contract issue is
  worth three of a docs issue);
- within an issue: approach 20, fixer 45, review 25, merge 10;
- **unmerged is not done.** An approved PR that cannot merge is 90%, not 100%.

A correction downward is fine and should be stated in the same line — a number
that only ever rises is not a measurement.

## Phase 2 — Wrap (in this order)

1. **Demo evidence**: spike refresh (per the project's demo skill if one
   exists), screenshots + capture log, honesty fences from the run's rulings.
   **A card ruled into the milestone after capture has started does not
   restart the capture** — the capture is still valid evidence for the cards
   already closed, and the late card runs on its own track. Name, in the wrap
   brief, which demo pages depend on which still-open card, so the eventual
   patch touches exactly those pages and nothing else. Patch the affected
   pages; keep the earlier version.
2. **Domain walkthrough review, before the demo document is assembled** (one
   walkthrough agent — not the `reviewer` role, whose brief template mandates a
   posted PR verdict there is no PR for here; dispatch it at **top standard
   (Opus-class)**): the agent takes the demo artifact and uses
   it the way the project's end user would — opens the artifact, runs the
   report, follows the flow — and writes down every place the artifact is
   *present but wrong* for that user. The evidence census answers "did each
   promised noun ship?"; the walkthrough answers "would the user accept
   this?" — they are different questions, and one run scored full marks on the
   census while the operator's own walkthrough of the same artifact found dozens
   of defects the census could not see. Findings go into the ledger's deferred
   list as candidate cards — step 5 reads them from there, not from a close
   comment, because every card is already closed by now — and the demo
   document names them as known gaps under the honesty fences. **What the walkthrough checks is project knowledge**:
   the rubric (whatever the domain's own objects and forms are) lives in the
   project's own repo — a demo skill, a docs file, a brief template — and the
   wrap brief points at it. This runbook only says *that* the review runs;
   it never carries a project's rubric.
3. **Demo document**: assembled from the capture log's own captions (never
   invented claims), delivered to the user, and — **if the run's memory says
   demos are published** — released the way that memory describes (which repo,
   which tag, the artifact as an asset, the milestone description PATCHed to
   link it). Put it somewhere durable either way: two early runs lost their
   demo documents to ephemeral scratchpads, which is why this step exists.
4. **Close the milestone** (`gh api -X PATCH .../milestones/N -f
   state=closed`) — auto-close does not exist; one run's milestone sat open
   with every card in it closed until someone thought to check.
5. **Deferred register → operator ruling → filing. Never agent → filing.**
   Present the register **pre-grouped by closability**: (a) closable in-branch
   now with no external resource — recommend folding into the card as one
   more sub-PR before the final merge; (b) needs a cloud call, eval budget, a
   UI, or data that does not exist yet — file, at most a few cards; (c) new
   ideas — file only the top few. An operator asked for exactly that split
   ("fold most, file 1–3 — controlled and closed soon") after being handed 25
   flat items. A
   register agent consolidates every deferred item out of the run's close
   comments **plus the domain walkthrough's findings from the ledger**,
   fold-checks each one against issues already open (a candidate
   that duplicates an open card is a fold, not a new card), and groups the
   survivors by kind — contract acts / engine / docs / tooling / fixture /
   decisions. The orchestrator turns that into a one-screen list with
   recommendations; **the operator rules**; only then does a filing agent
   file. The fold-check is most of the value: in one run roughly 45 raw
   candidates folded to 13 filed cards plus 9 edits to existing cards, and an
   agent filing straight off the close comments skips it entirely. An
   adjudicator's "file the follow-up" does not bypass this gate either —
   briefs route filings to the operator, always.
   **Place each filed card by the target milestone's own Measure line, not by
   "it comes next."** A contract act or a rules card does not default into the
   next themed milestone merely because that milestone is up next; an operator
   correction caught exactly that, where the next themed milestone had picked
   up cards its theme did not need. Whatever the operator defers instead of
   filing carries into the next run's Phase 0.
6. **Board-consistency sweep, ALWAYS, as the run's last board action** (one
   subagent) — **it runs after filing, so it sees the new cards**: every open
   issue has a milestone matching its wave, non-empty board fields, native
   parent links matching body Parent lines, no label contradictions; the
   wave's closed set is milestone'd/Done/label-clean; epic spans recomputed
   after the run's filings (they go stale silently). Report-don't-guess
   anything ambiguous.
7. Run summary to the user, memory update (wave-complete entry replaces any
   paused entry; the user's owed items get their own entry), ledger closed.

## Self-improvement (mandatory at Phase 2)

This skill learns from every run. At wrap, before the final summary:

1. **Write the lesson where the evidence can live.** A lesson's *rule* belongs
   here or in SKILL.md; its *evidence* — issue numbers, file names, suite
   counts, costs — belongs in a **private** lessons file in the project's own
   repo. Keep the two apart from the start; separating them afterwards is how
   a private project ends up described in a public repo.
2. **Promote a lesson into an instruction, or it will not fire.** An entry in
   an appendix only helps a reader who reads appendices. If the lesson changes
   what an agent should *do*, it goes in a protocol section, a briefing line,
   a red flag or a rationalization row.
3. **Re-test changed behavioral guidance** (one cheap baseline/with-skill
   scenario pair) before committing; pure reference additions need only a
   read-through.
4. **Commit. Do not push a shared or public repo without asking** — check
   `gh repo view --json visibility` first, and have the diff reviewed for
   project detail before it goes anywhere public.

Roadmap (pick up when a run makes one relevant):
- Per-repo install variant (the add-handoff pattern): bake the target repo's
  label vocabulary, CI check names, branch conventions into an installed
  copy so briefs skip discovery.
- Scope-time cost dashboard artifact: per-wave burn projection vs actuals,
  refreshed at wave boundaries.
- More pressure scenarios: quota-pause recovery and schema-chain compliance
  are untested disciplines — write their scenario pairs the first time this
  skill runs on a project group other than the one it came from.

### Where the evidence lives

The runs behind these rules keep their evidence — issue numbers, milestone
labels, costs, suite counts — in a private lessons file in the project's own
repo, per rule 1 above. Every lesson that changes what an agent *does* has
already been promoted into the phase step, protocol, briefing line, red flag
or rationalization row where it fires; nothing actionable is parked here.
