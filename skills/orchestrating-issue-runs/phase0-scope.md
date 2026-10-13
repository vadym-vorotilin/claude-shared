# Phase 0 — goal, then scope

Read in full at run start, before the scope dispatch. Every figure here is a
starting parameter, not a promise — recalibrate on your own first run.

### The goal line comes first, and it is one sentence

Before the scope agent is dispatched, write the run's **goal line**: the
observable outcome this run must produce, testable by looking at the artifact —
a report that shows something it does not show today, a screen that loads, a
recording somebody can watch — not by looking at the board. Agree it with
the operator in the same message that asks for scope approval, and put it at
the top of the ledger.

Iron rule 11 says why this is a rule and not advice: without it the unit of
work is the card, and a backlog will always supply more cards than a goal
needs. The failure it prevents has a shape — a run that closes cards
diligently, files more than it closes, and ends with nothing visible having
moved.

**The goal line then binds four things**, and each of them is a step below, not
a sentiment:

1. the scope agent derives the **minimum** card set that closes it and names
   the rest **out of the wave, by name** (item 1);
2. every brief carries the goal line, and the return contract asks what the
   deliverable moved on it (Briefing rules);
3. the progress stamp reports **Exit items met / total first**, card cost
   second (Progress line);
4. rulings are sized by it — no durable design record for a question that does
   not change the Exit, one probe per card before the operator is asked
   anything (Adjudication).

**An Exit item is measured, and the measurement is reproducible:** it needs an
offline reproduction path before review, and if that path is keyed on a live
data set it needs a pinned snapshot or a tolerant mode, or it breaks when the data changes. **Where the claim is determinism, pin the
expected value from an earlier, independent run and assert it** — a check that
only compares a run with itself cannot see drift. A rerun that matches pins set by earlier independent runs is
evidence of reproducibility; one that matches only itself is assertion. **A measured build output
(size, count, hash of an artefact) comes from a clean build**: an incremental build can hand back an artefact from before the change,
so a size recorded from one is stale.
Clean the target first, and name the clean in the recorded command.

### Is this run the right run at all? — the lineage check

A follow-on milestone is the case where the goal line is most likely to be
missing and least likely to be missed. **Before dispatching the scope agent,
quote the previous milestone's own wrap verdict** — what it said it had and had
not achieved — and compute the **lineage share**: what fraction of this
milestone's cards descend from cards in its predecessor (a `Refs`/parent trail,
or the same defect re-cut under a new number).

**Above roughly half, stop and put the direction question to the operator
before any dispatch.** A milestone that is mostly its predecessor's leftovers
is not a backlog; it is evidence that the predecessor did not close its
question, and running it again re-cuts the same defects at the same price. A
chain of follow-ons can run several milestones deep with no new requirement
entering after the first, and nothing visible moving across all of them. The
cheap tell is available at the start of each: the lineage share is near
total.

The operator's answer is a direction ruling, not a scope edit: continue, change
the acceptance standard, or go somewhere else. Only then is the scope agent
worth its cost.

### Scope

One strongest-tier agent, **dispatched** — not the orchestrator reading in
session. Inputs: the goal line, specs/ADRs/glossary, project memory, ALL open
issues + labels + board state, open PRs, CI state per repo, prior-run
ledgers/deferred-minors.

**The survey is rented context; the scope doc is what the run keeps.** The
agent reads the sources and returns the doc; the orchestrator runs the receipt
check below and posts it. An orchestrator that reads the sources itself buys
the same doc and then re-reads the whole survey on every remaining turn of the
run — the surest way to spend most of its ceiling (iron rule 9) before the
first dispatch.

**Check it by tool calls, not by a token target.** The orchestrator has no way
to read its own context size from inside a run, so a number here is a gate that
always passes; its own tool calls it can see. Phase 0 is dispatch, receive,
check, post — plus exactly these three:

- **Resolving a citation.** That issue #N exists and is open, that a cited spec
  section exists, that a PR is real. Resolving a citation is not reading the
  source: `gh issue view N --json title,state` is a line, `gh issue view N` is
  the body. The first is the receipt check; the second is the leak.
- **Branch protection and the merge method** per repo (What this assumes,
  above) — one `gh api` call each, and the result goes in the doc.
- **The project-memory read** (if the project keeps one) behind the
  demo-release question, which is asked before the doc is presented and so
  cannot wait for it.

Anything else — opening a spec, reading an issue body, reading a PR diff — is
the survey leaking into the orchestrator, whatever the doc it ends up holding
says.

The scope agent is not exempt from rule 9's ceiling, and it writes the checkpoint
note like anything else — that rule is unconditional (`context-ceiling` skill),
and a survey that dies unrecorded is repurchased in full. What differs is the
remedy. It returns the **partial doc plus the note saying which surfaces it
covered**, and the **orchestrator** dispatches the rest — per repo, or sources
versus board state — then posts the merged doc. An agent already at its
ceiling cannot split itself, and a partial doc posted as the scope is a repo's
issues missing from the run with nothing to show it.

**If this run's wrap will produce a demo artifact, ask once — before
presenting the scope doc — whether to publish it as a release**, and SAVE the
answer to project memory so later runs read it instead of re-asking. Re-ask
only if memory holds no answer. (Project memory is optional and the project's
own; where there is none, record the answer in the ledger and the INTRO, and
ask again each run.) The run's memory is also what says *how* demos
are published: which repo, which tag scheme, whether the milestone description
links the asset — with no memory, ask the operator for those three facts once
and write them into the ledger. **Build a demo page self-contained** — images inline as data
URIs, no sibling files: sandboxed page hosts block sibling-file loads (a page can render with every figure missing), and one
self-contained file is also what attaches cleanly as a release asset.
**Before a demo page goes to the operator, the orchestrator reads its claims
against this run's measurements** and rewrites any it cannot trace — "X is
unchanged" is the usual one, carried from an earlier run by an agent that never
re-ran X. A page can state a reference result is unchanged when it was never re-run;
rewrite it to what was measured ("inputs untouched, not re-run") before publishing.

Produce the scope doc (posted as a message, not a file the user must open):

1. **Waves — the minimum set that closes the goal line, and what it leaves
   out.** Dependency-ordered issue groups; what parallelizes, what serializes,
   and why (file surfaces, contract dependencies). Then, in the same item, the
   **out-of-wave list**: every open card in the milestone that this plan does
   not include, **named**, one clause each for why it does not move the goal.
   An unnamed card reads as in scope to every later reader, including the
   orchestrator at the wrap. This item is the difference between a wave plan
   and a to-do list of everything that exists.
2. **Per-issue**: model tier, risk class, expected human gates, rough token
   cost. **Estimate the agent's cumulative total including its fix and
   re-review rounds** — that is what you actually buy, and a per-dispatch
   figure will read well under the true cost. A review round costs a
   fraction of the original fixer, because resume keeps the context. **Take your
   own numbers from your first run; a band from someone else's stack will not
   transfer.**
   As a shape rather than a size: fixers are the largest line, reviewers and
   approaches each a fraction of it, adjudication the smallest. **A card
   carrying both an adjudication and a contract act (schema/version-constant
   change, cross-repo pin) costs well above its plain implementation
   estimate** — a multiple, not a margin. Treat that multiplier the way you
   treat the split above: a shape to confirm against your own first run, not a
   band to import. **Count seams, not bullets.** A card that lands a new
   transport, a repo-wide guard, or a routing/identity function is a
   milestone-sized card however few bullets it has: each such seam tends to take
   several review rounds, and the card lands at a multiple of its bullet-count
   estimate.
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
   visible, and does that card's exit assertion actually reach the surface? A
   milestone can name several visible numbers while the decomposition delivers
   fewer — a card can ship a helper nothing calls, and the promise stays
   silently breakable until a wrap-time adjudication catches it.
6. **Inconsistency sweep** — spec contradictions, undefined shapes referenced
   by issues, label/board drift, missing CI on any repo whose PRs must pass a
   merge gate (a gate that rejects green-by-absence holds a zero-CI repo's
   PRs forever — check this BEFORE the first merge, not after).
   Classify each finding: *adjudicable* (agent rules it during the run) vs
   *architectural* (user decides now). **List candidate follow-up issues;
   file none until the user approves the list.**
7. **Held-for-human list** — spec/contract freezes (including any doc
   amendment that would edit one), anything installing or changing the
   operator's machine, external data only the operator has, **publishing
   evidence captured from the operator's machine** (screenshots, logs,
   recordings — into the repo, a release or an issue), gates named by the
   project's own workflow docs. The capture item holds even when a plan's file
   surface lists the file: a plan that says "commit the screenshot" was written
   before anyone looked at it, and an operator may rule such a capture internal the moment it is shown. Show it, keep it outside the repo, and record
   "seen by the operator" in its place. **A gate the operator delegates back runs as a
   two-mind protocol**: the implementer decides with citations, and the
   reviewer independently re-decides. Two convergent minds can stand in for the
   operator; divergence escalates.
8. **Budget** — token target and the drain rule, plus a **hard filing budget**:
   the maximum number of new cards this run may file, chosen against the goal
   line and stated as a number. Iron rule 6 explains why it is needed; the
   number is what makes it enforceable. Report **filed-to-merged** against it
   in the wrap, and treat two consecutive runs above 1 as the register
   generating work rather than the backlog growing.

**Return the doc, not the evidence — and cap it structurally.** A size target
is graded by the agent that wrote the doc, which always finds its own doc
reasonable; the cap that holds is a prohibition. **The doc quotes no source
material.** Findings carry citations — issue number, spec section, PR,
`file:line` — never the text they were found in: no pasted issue bodies, no
spec excerpts, no diff hunks, no CI logs.

**One exemption, and it is narrow.** A finding routed to a human decision —
the inconsistency sweep (6) and the held-for-human list (7) — quotes **one
line per clause the decision turns on**. Nobody can rule that two specs
conflict from two section numbers without opening both, which is the thing
posting the doc as a message exists to avoid. Bulk evidence stays banned and
the gate stays binary: a one-line quote inside a finding is not a pasted issue
body, and no one has to judge which it is.

**Receipt check.** Two passes over the returned doc, both cheap, neither
self-graded. It **quotes nothing** outside that exemption, and its
**citations resolve** — every issue number exists and is open, every cited
spec section is there, every referenced PR is real. This is now the whole of
what stands between a hallucinated issue number and a wave dispatched against
it: the orchestrator can no longer catch one by recognising it, because it has
not read the issues. Anything that fails either pass goes back to the scope
agent before the doc is posted, not after.

Size then follows, and scales with the run rather than being a constant that
is wrong for the next repo: the eight items above, a few lines per issue. A
doc still running long under that constraint is telling you the wave
decomposition is wrong, not that the format is too tight. And a doc arriving
at the size of its sources has moved the survey into the orchestrator's
message history rather than left it behind, where it is carried and re-read
exactly as it would have been.

User approves (possibly with edits) → run starts. Scope changes mid-run
(new issues discovered, blockers) are appended to the ledger and surfaced in
the next report, not silently absorbed.
