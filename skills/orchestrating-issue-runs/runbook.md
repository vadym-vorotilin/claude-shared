# Runbook — orchestrating issue runs

Mechanics for each phase. SKILL.md holds the rules; this holds the how.
Distilled from real multi-repo runs. Every figure below is one project group's
observation — **recalibrate on your own first run.**

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
   approaches ~25%, adjudication ~5%.
3. **Re-estimate when an approach refutes a premise you priced on.** If an
   issue was budgeted as a cross-repo schema chain and its approach proves the
   chain does not exist, the estimate is stale — being wrong in the user's
   favour is still being wrong. **Any refuted premise that touched an estimate
   gets the estimate restated in the next report.**
4. **Scope added mid-run is unestimated by construction — say so.** Issues
   added after approval have no number attached, and one of them may be the
   most expensive of the run. When the user approves a scope change, give it
   its own estimate in the same message.
5. **Inconsistency sweep** — spec contradictions, undefined shapes referenced
   by issues, label/board drift, missing CI on any repo whose PRs must pass a
   merge gate (a gate that rejects green-by-absence holds a zero-CI repo's
   PRs forever — check this BEFORE the first merge, not after).
   Classify each finding: *adjudicable* (agent rules it during the run) vs
   *architectural* (user decides now). **List candidate follow-up issues;
   file none until the user approves the list.**
6. **Held-for-human list** — spec/contract freezes, anything installing or
   changing the user's machine, external data only the user has, gates named
   by the project's own workflow docs.
7. **Budget** — token target and the drain rule.

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
amendment as a PR **held for the user**; code proceeds on the ruling. A
schema-shaped ruling triggers the schema-change chain (below).

**Fixer.** TDD (red recorded, then green), in a fresh worktree
(`git -C <repo> fetch origin && git worktree add <scratch>/wt-<issue> -b
<branch> origin/main`), branch per the repo's convention, PR body carries
red→green evidence, labels flipped by the fixer at start/end. Never merges,
never pushes to a protected/main branch. Cross-repo issues: one worktree and
one PR per repo, cross-referenced; merged later as an ordered group.

**Review.** Independent agent, never the implementer. Gets the issue, the
approach + rulings, the spec sections, the PR. Posts a GitHub review with an
explicit `VERDICT: APPROVED | CHANGES_REQUESTED` line (self-approval is
blocked when reviewer and author share the account — the COMMENT + verdict
line IS the record). Reviews verify claims, not prose: run the suite, probe
the mechanism adversarially, sabotage-test guards ("would this test catch
the bug it claims to catch?").

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
was deferred, sync the board, mark the ledger. Cross-repo groups merge in
dependency order (producer repo first), all-or-nothing.

## Protocols

**Ledger.** Scratchpad markdown, written before the first dispatch: wave
plan, per-issue log lines, rulings, deferred minors, resume queue, the
pause/resume state. After a compaction or limit reset, trust the ledger and
`git log` over memory.

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
`gh pr checks --watch`), then finish and return the report. Put this in
fixer briefs preemptively.

**When the nudge fails, remove the dependency.** If the thing the agent is
waiting on **has not started** — a queued CI run, a job with no runner — a
better blocking wait stalls it again, because there is nothing to observe. Take
the gate off the agent: tell it to return the report with `CI: queued`, and own
that gate yourself. You own it anyway; merge requires CI green *and* review
clean, and the agent cannot merge.

**Briefing rules.** Every brief: role, ONE issue, binding comments listed by
name, repo + worktree instructions, concurrent-agent file surfaces to avoid,
the return contract (data for the orchestrator, incl. a STATUS line).
`gh` comments with literal backticks: always `--body-file`, and write the file
with a **quoted** heredoc (`<<'EOF'`) — `--body` runs command substitution, and
so does an *unquoted* heredoc, which is the same bug one step later.

**Five lines that go in EVERY brief.** Each earned its place by catching
something a brief without it missed:

1. **"Re-measure the baseline yourself; do not carry a number across."** Two
   agents in one run caught stale suite counts handed to them by the
   orchestrator. Never state a number the agent can measure.
2. **"If any part of the ruling turns out wrong, or more expensive than it
   looked, say so explicitly — do not quietly drop it."** Three agents deviated
   and reported; all three were right, including one that corrected a ruling's
   stated premise by measurement while still following the ruling.
3. **"Any sentence asserting something is impossible or cannot be tested is a
   hypothesis. Test it before you write it."** Three false impossibility claims
   shipped in one run, all written honestly by strong agents.
4. To a **fixer building a guard**: *"the first shape to test your guard against
   is the shape your own diff introduces."*
5. To a **fixer receiving a reviewer's remedy**: *"verify it, do not copy it —
   a right finding can carry a wrong fix."*

And one for **every reviewer brief**: *"prove each new guard would fail if the
thing it guards stopped being true"* — vacuous assertions were found green three
different ways in one run.

**Schema-change chain** (any ruling that adds/changes a persisted field):
doc amendment PR (held for user) → field + version-constant bump → regenerate
generated artifacts (schemas, contracts, pins) → companion PR in each
consuming repo, lockstep → fixtures updated via their regen tool, never by
hand → ordered group merge. Fixtures that snapshot serialized state need a
regen tool committed alongside them or every schema bump breaks them by hand.

**Clean-env rule.** Any shell script an agent writes gets verified in a
clean environment (Docker `node:XX-bookworm`, or `env -i HOME=$(mktemp -d)`),
not just the dev machine. The three bug families that only reproduce on
clean/fast runners: second-granularity timestamp collisions, `/dev/stderr`
redirects (ENXIO on Linux when stderr is a pipe), ambient git
identity/config. CI's first run on a repo WILL find this class — treat each
find as its own issue assigned to the code's owning agent, not a drive-by.

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
