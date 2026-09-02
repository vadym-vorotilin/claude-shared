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

One strongest-tier agent, **dispatched** — not the orchestrator reading in
session. Inputs: specs/ADRs/glossary, project memory, ALL open issues +
labels + board state, open PRs, CI state per repo, prior-run
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
- **The project-memory read** behind the demo-release question, which is asked
  before the doc is presented and so cannot wait for it.

Anything else — opening a spec, reading an issue body, reading a PR diff — is
the survey leaking into the orchestrator, whatever the doc it ends up holding
says.

The scope agent is not exempt from rule 9's ceiling, and it writes the handoff
note like anything else — that rule is unconditional (Handoff note, below),
and a survey that dies unrecorded is repurchased in full. What differs is the
remedy. It returns the **partial doc plus the note saying which surfaces it
covered**, and the **orchestrator** dispatches the rest — per repo, or sources
versus board state — then posts the merged doc. An agent already at its
ceiling cannot split itself, and a partial doc posted as the scope is a repo's
issues missing from the run with nothing to show it.

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

**Adjudication.** Strongest tier. **The brief pins everything the ruling
needs**: the exact design questions, the conflicting positions quoted from the
approach comments, the spec sections by path and anchor, and the file surfaces
involved. The adjudicator rules against those documents; it opens the repo
only to verify a specific citation, never to explore — an adjudicator left to
find its own context spends most of its turns exploring, at the highest
per-token rate in the run. One issue or one pre-declared cluster per adjudicator;
never batch unrelated issues into one agent — the batched ones run several
times longer than the median and rule no better. Rules each question against
the specs with citations; posts a binding "## Design decisions" comment;
drafts any doc amendment as a PR, reviewed for `DOCS_PR_MATCH` (defined in the
reviewer brief template below) and **squash-merged by the orchestrator after
its paired engine PR lands** — or immediately if standalone. No held queue:
holding docs amendments for the human only added latency, and every one came
back merged unchanged. Design-changing amendments are still surfaced in the
report, just not gated — **with one exception: an amendment that edits a
FROZEN spec or contract still goes to the held-for-human list.** Code proceeds
on the ruling.
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

**The fixer stops at the context ceiling — and something has to tell it.** No
agent can read its own context (iron rule 10), so the brief line alone gets
breached silently; in one measured run most of the agents it bound went past
it and several past the hard stop. Install `hooks/agent-ceiling.py` as a
`PreToolUse` hook (steps below) and the harness does the measuring. In the
project's `.claude/settings.json`, inside the top-level `"hooks"` object —
without that wrapper the entry is valid JSON the harness silently ignores:

```json
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "*",
        "hooks": [{ "type": "command",
          "command": "sh -c '[ -r \"$CLAUDE_PROJECT_DIR/.claude/hooks/agent-ceiling.py\" ] || exit 0; exec python3 \"$CLAUDE_PROJECT_DIR/.claude/hooks/agent-ceiling.py\"'" }] }
    ]
  }
}
```

The `[ -r ... ] || exit 0` guard is not decoration. `python3` on a file it
cannot open exits 2, and for a `PreToolUse` hook exit 2 means *block this tool
call* — with `"matcher": "*"` that is every call in the session, the main loop
included, until someone edits the settings back. A missing hook file has to
mean "no enforcement", never "no work". The operator also has to approve a
changed project hook before it runs at all; until that is accepted the hook is
inert.

It reads the agent's own transcript, blocks **once** on each threshold crossing
with the ceiling message on stderr, records the crossing, then stays out of the
way — blocking once is what makes it unmissable, blocking every call would
deadlock the agent. It exempts the main loop, and it **fails open**: it is
advisory, and a bug in it must never halt a run. (The companion guard hook, which
enforces prohibitions rather than budgets, fails **closed** — opposite rule,
opposite reason. Do not copy one policy into the other.)

**What it assumes — verify these, or it is a silent no-op.** The hook decides
"this is a dispatched agent" from a `subagents/` segment in the transcript path,
the layout the CLI has written since 2.1. Where that directory is named
differently the test never matches, the hook returns 0 on every call, and
nothing enforces the ceiling — a gate that always passes, which is worse than no
gate, because you will trust it. It needs the transcript's own directory to be
writable, too — it records each crossing in a dot-file beside the transcript,
and where it cannot write one it stays silent rather than block again, which
means no enforcement at all. It also needs `python3` 3.9 or newer on `PATH`
(it calls `str.removesuffix`), and the snippet above loads the file from
`.claude/hooks/`, so install it there — shipping it beside the skill installs
nothing. **Symlink it, do not copy it**: a copy stops taking fixes, and unlike a
stale overlay a stale hook still looks like it is working. From the project
root:

```bash
mkdir -p .claude/hooks
ln -sfn "$HOME/.claude/skills/orchestrating-issue-runs/hooks/agent-ceiling.py" \
        .claude/hooks/agent-ceiling.py
test -r .claude/hooks/agent-ceiling.py \
  || echo "target missing — fix the path before adding the settings entry"
```

That `test -r` is the point of the third line: `ln -s` creates a link to a
target that is not there without complaint, and a skill installed anywhere but
`~/.claude/skills/` leaves you with exactly that. `-fn` also makes a re-run
idempotent instead of erroring on the existing link. If you later move or
uninstall the skill, remove the settings entry first.

**It cannot tell a reviewer from a fixer.** Iron rule 9 exempts reviewers from
the ceiling — a verdict does not split — but the hook binds every dispatched
agent, and its thresholds come from the CLI's own environment, so they cannot be
raised for one agent mid-run. Set the thresholds high enough for the longest
reviewer you dispatch and let the reviewer's turn budget bound it instead;
otherwise a long review is told to hand off mid-verdict, which rule 9 forbids.

Prove it fires before you let it bound a run: **export `AGENT_CEILING_SOFT=1`
before starting the CLI** — the hook inherits that environment, so a value set
mid-session never reaches it — then dispatch a throwaway agent. Its first tool
call should come back blocked with the ceiling message. If it does not, the
ceiling is unenforced here and the brief line is all you have — which is reason
to keep that line in every brief regardless, since it is also what makes the
resulting handoff note well-formed.

Every brief still carries it: *when your context passes ~150k, stop and write
the handoff note (below).* An agent re-reads its whole context on every turn,
so a long fixer's last turns are its most expensive ones while a continuation
starts near a fifth of that size.
Mid-card is a fine place to stop: the note, the branch and the worktree carry
the state.

**The ceiling is a checkpoint, not a guillotine.** Writing the note is
unconditional — it is cheap, and it is what survives if the agent dies.
Returning is not:

- **More than a few turns of work left, or any design question still open →
  return the note.** This is the case the ceiling exists for: the agent that
  would otherwise run to several hundred k re-deriving its own history.
- **A bounded finish → finish it, and say so in the note.** Handing off three
  turns from done buys nothing — the continuation pays a fresh cache write and
  a re-orientation to save those turns — and it risks the one thing a note
  cannot carry: what the agent tried and rejected. "Bounded" is evidence, not a
  feeling: the suite is already green, one named deliverable remains (the PR
  body, a last assertion, a rename), and no decision is open. Hard stop at
  ~200k: past that, return the note whatever the state.

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
to catch?"). **The brief pins the diff and the base**: PR number, resolved head
and base SHAs, the file list — review *that diff*, and open anything outside it
only to check a specific claim you are making. A reviewer left to explore
arrives at the same verdict having read several times the context, and unlike a
fixer it cannot be handed off to cap that (below). Keep reviewers on the top
standard tier: this is the last gate before merge, and the saving from
downgrading it is small next to what it catches.

**Fix rounds.** Findings go back to the SAME fixer via message (resume), not
a fresh agent — rounds 1–3, while it is under the ceiling. Round 4–5: fresh
agent, one tier up, briefed from the fixer's handoff note. Cap 5, then
adjudicate open findings: park with a ruling or stop. **The real cap is the
budget, not the count**: before each round after the first, check the run's
spend (Budget check, below) against what the round is worth. A late round on a
resumed agent costs a multiple of round 1 for a same-sized fix, because the
resumed agent carries every earlier round in the context it re-reads each turn.
When the round is not worth its price, adjudicate the open findings instead.
Each round ends with a scoped re-review of the fix diff by the SAME reviewer
(resume). **Exception — the orchestrator verifies it instead of spending a
review cycle:** any round
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

**Rework that outgrows the work is a signal, not a phase.** The round cap is a
backstop against a loop, and it does not catch the expensive case: cost lives
in what one round does, not in how many there are. A single round on a fixer
that has grown large, re-running the suite dozens of times, can cost more than
the implementation it repairs — in one measured run, on the worst card the fix
round outspent the build it was fixing. When a fix round passes the cost of the
work it repairs, the card was mis-specified or the review was wrong; **stop and
put it to the operator** rather than grinding out another round. This needs no
new instrument: the ledger already records what each agent cost.

**Scope rulings belong to the reviewer.** After several fix rounds the orchestrator
is the worst-placed reader of whether the diff has sprawled — it shaped the rounds
and will read coherence into it. Ask the reviewer explicitly: is this still one
change, and what should be split?

## Protocols

**Ledger.** Scratchpad markdown, written before the first dispatch: wave
plan, per-issue log lines, rulings, deferred minors, resume queue, the
pause/resume state. After a compaction or limit reset, trust the ledger and
`git log` over memory. **Put it on disk, not on a tmpfs scratchpad** — one
run's ledger was cleared with `/tmp` between sessions. That one was recovered:
a subagent rebuilt it from the previous session's transcript by reading the
tool calls, which is the fallback, but it costs a dispatch and it only works
while the transcript is still there.

**Agent briefs — three run-stopping rules.** (1) Name the Monitor tool and
*unpolled* `run_in_background` explicitly as banned, for **every dispatched
agent** — "no monitors" alone was read as a Bash-only rule and one fixer
stalled on a Monitor. Detached-and-polled work is the permitted form (Poll, do
not block, below). The orchestrator's own liveness sweep is the only Monitor
any agent may rely on; it is the orchestrator's, and no brief may grant it.
(2) Scratch filenames are card-scoped
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

**When the named conflict is structural, the third option is to ship the rule
issued but not posted.** Leave-one-out (SKILL.md's rule) sometimes names no
defective rule and no defective design: on one card a specified constraint was
unsatisfiable against the project's frozen acceptance inputs, because it and two
sibling constraints were each individually valid and jointly unsatisfiable.
Amending the constraint inside a fixer's diff would have been a spec change
made by an implementer; re-authoring those inputs to fit was worse.
What shipped was the constraint **complete and fully tested, with its
registration disabled** — honest only under three
conditions: the infeasibility is **measured** (the core named by leave-one-out,
not asserted), the PR states the exit clause is not met rather than pretending
it is, and a committed test **re-derives the infeasible core every run** so the
card reds the day those inputs move and the rule becomes postable.
The reviewer's job on such a PR is to prove that guard fires — this one did,
by mutating those inputs until the infeasible core dissolved. Put the
amend / re-author / park-unposted choice to the operator as a question, and
ship the defensible option meanwhile rather than stalling on it.

**Recorded-interaction retries** (only where the project records live
interactions and replays them in tests). Re-recording until a take is usable and
keeping the last one is disclosed, not cherry-picked — and only when every
discard was for validity. Discarding on content the brief never pinned is a
selection the operator rules on, and the recording's provenance should carry an
attempt count. Route it to the deferred register, not to the reviewer.

**The orchestrator cannot see its own context either**, so "approaching the
ceiling" is judged by run milestones rather than tokens: it offers the handover
below at each wave boundary from the second on, and the operator decides.
`--view agents` will not answer this one — that view is built from subagent
rows and excludes the orchestrator by construction.

**The ledger is the orchestrator's own handoff note.** The orchestrator is
subject to the context ceiling like everything it dispatches. As its own
context approaches it, bring the ledger fully current — wave state, in-flight
agents with their worktrees and PRs, open gates, resume queue, spend so far —
and tell the user that a fresh orchestrator session can take the run over from
the ledger file, because **the orchestrator cannot clear its own context**.

**Where to hand over matters more than whether.** Agent handles are
session-scoped: a fresh session can read the ledger, the worktrees and the PRs,
but it cannot `SendMessage` the previous session's agents. Both options exist
at every point; what changes is which one is cheap:

- **At a wave boundary, nothing in flight** — a fresh session is cheapest and
  loses nothing. Compaction is still perfectly valid here if the user prefers
  to stay put; it just keeps carrying more context than a fresh start would.
- **Mid-wave, agents running** — compact and keep the handles. A compacted
  orchestrator carries more than a fresh one, but losing the rescue path for
  several running agents costs more than the context does.

**The choice is the user's; the orchestrator's job is to make it informed.**
Post one handover message and then stop dispatching until it is answered:
where the run is (wave, issues closed, what is in flight and what each agent is
waiting on), any open gate, the ledger's path, the two options above with the
trade-off in one line each, and the literal instruction a fresh session needs —
*"read `<ledger path>`, verify worktree/branch/PR state with `git` and `gh`
before trusting it, then continue at `<next concrete step>`"*. Say plainly that
in-flight agents cannot be messaged from a new session, so if any are running,
either wait for them or accept recovering their work from the worktree and PR.
End the message with the progress stamp, as always.

**Handoff note.** The unit that lets an agent stop without losing work: written
when it hits the ceiling, and written **before a deliberate park** rather than
leaving a large-context agent to thaw at full size later. Five headings:

```
FILES TOUCHED   path — what changed, and what is half-done
DECISIONS       each decision and why, including options considered and dropped
REMAINING       the concrete next step, then the rest, in order
STATE           repo, branch, worktree path, PR number, resolved base SHA
GOTCHAS         what surprised you: a flaky test, a slow suite, a wrong claim
                in the issue
```

The agent writes the note into its worktree (or the orchestrator copies it into
the ledger on arrival) as well as returning it — a note that exists only in a
returned message dies with an agent that never returns.

The orchestrator dispatches the continuation with that note **verbatim**, plus
the standard brief (role, one issue, binding comments, file surfaces, return
contract). Do not summarise the note — summarising is where handoffs lose the
one detail the next agent needed. Verify the STATE lines yourself before
sending: worktree present, branch pushed, PR open, SHA resolvable.

**Reviewers never hand off.** A review is one coherent whole-diff verdict; a
split review is two partial opinions, neither of which saw the whole change. If
a review is genuinely too large for one agent, the diff is too large — ask the
reviewer for the scope ruling instead.

A lossy note makes the continuation redo work, which no token count shows.
Treat the first wave that uses one as a pilot: read the note before dispatching
the continuation, and if the continuation had to re-derive something, add the
missing heading to this template.

**Budget check.** Iron rule 7 needs a number, not a feeling:

```bash
python3 ~/.claude/skills/token-report/token_audit.py --since <run-start> --json \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["usd"])'
```

Consult it between waves and before each fix round after the first, and record
the figure in the ledger next to the wave line so the drain decision is made
against a trend rather than one reading. `--view agents --top 40` shows which
agents carry the cost and how large their contexts grew — that is the view that
says whether the ceiling is being respected. (Needs the `token-report` skill
installed; without it, say so in the report rather than estimating. A zero
reading is a claim to check, not a result: the same `$0.00` comes from a
mistyped window and from a mistyped `--root`, and the JSON's `root_missing`
flag is what separates them.)

**Liveness sweep.** Agents die silently — weekly quota, mid-stream API errors,
background-wait stalls — and the run reads as "still working" for hours
otherwise; that is how one run's quota pause slipped by unnoticed. Detect it
**outside the orchestrator's context**: one sweep for the whole run, not a
timer per agent. A per-agent timer pays a full orchestrator context read on
every firing, for every agent, just to learn "still alive", and still finds a
stall up to its interval late.

Arm one persistent `Monitor` at the first dispatch that polls the cheap signals
for every in-flight agent and **prints nothing while they look healthy**, so
the orchestrator is woken only when one looks dead:

```bash
: "${SCRATCH:?set SCRATCH to the scratch directory for this run}"  # no silent no-op
shopt -s nullglob
STALE_MIN=15
GRACE=3                      # passes to allow before the first worktree exists
armed=0; empty=0
while true; do
  wts=("$SCRATCH"/wt-*/)
  if [ ${#wts[@]} -eq 0 ]; then
    empty=$((empty + 1))
    # Speak once the sweep has ever seen a worktree (they vanished), or once
    # the grace period is up (it was armed on the wrong path) — then STOP.
    # Never go quiet, and never natter: a sweep watching nothing has nothing
    # to watch, and a line every two minutes is the per-agent timer again.
    if [ $armed -eq 1 ] || [ $empty -gt $GRACE ]; then
      echo "SWEEP DOWN: no worktrees under $SCRATCH — not watching anything"
      exit 1
    fi
    sleep 120; continue
  fi
  armed=1; empty=0
  for wt in "${wts[@]}"; do
    if find "$wt" -name .git -prune -o -newermt "-${STALE_MIN} minutes" \
         -print -quit 2>/dev/null | grep -q .; then
      continue                      # something changed recently: healthy
    fi
    echo "STALL: $(basename "$wt") — nothing written for ${STALE_MIN}m"
  done
  sleep 120
done
```

Adapt the signals to the run — worktree mtimes as above, the agent transcript's
mtime, `gh pr view` for a PR that should exist by now. (`.git` is pruned on
purpose: index churn from a stuck command is not progress, and leaving it in
made the sweep report a hung agent as healthy the first time this was tested.)

Two properties make it a gate rather than decoration: it is **silent while
healthy** (otherwise it is the per-agent timer again, wearing a loop), and it
**speaks on every failure shape you would act on**, including "the agent said
it opened a PR and there is none".

The empty glob is one of those failure shapes, and it is the one a sweep gets
wrong by default. Arming at first dispatch is normal — the fixer has usually
not created its worktree yet — so the loop tolerates an empty `$SCRATCH` for a
few passes and then says so, and it says so **immediately** once it has seen a
worktree and they later vanish (pruned, moved, renamed mid-run). Without that
second case the sweep watches nothing and reports nothing for the rest of the
run: a gate that silently always passes is worse than no gate.

It says it **once and exits**, and that is the other half of the rule. A sweep
that repeats "I am watching nothing" every two minutes wakes the orchestrator
into a full context read for a fact it already has — the exact cost that killed
the per-agent timer two paragraphs up. Speaking once and dying is louder and
cheaper than a running commentary, and it cannot be tuned out.

So `SWEEP DOWN` is an action, not a notification: fix what it names — usually
`$SCRATCH` pointing at the wrong path, or worktrees pruned while the run was
still live — verify the in-flight agents by hand once, and **arm a new sweep**.
Until you do, nothing is watching, and the run's silence means nothing.
Confirm at arm time that it names live worktrees rather than assuming the
silence is health.

On a `STALL` line, verify with cheap read-only commands (worktree commit time,
`git status`, PR existence, transcript last-write time, running build
processes) and rescue it if it is genuinely dead. **Never re-dispatch a live
agent because the sweep fired** — a long agent is not a dead one, and the sweep
is a hint, not a verdict. `TaskStop` it when the run ends.

**Warm-ping only for a genuine park.** When the run is deliberately paused —
quota drain, waiting on an operator gate — arm a timer that wakes the
orchestrator before its own cache goes cold. That is what "a pause needs an
armed timer or monitor" is for: parks, not dispatches.

**Rescue.** Agent killed by limits/crash: `SendMessage` to the same agent id
— it resumes from its transcript with the worktree state intact. **Verify
worktree, branch and PR state yourself first and hand those facts back in the
message** — it stops the agent re-deriving them and stops it recreating a
worktree that still exists. Include "recreate at a fresh path if it is gone".
Causes seen: watchdog kill after idling on a background job, mid-stream API
error, session quota limit. All three resumed and completed; none needed a
fresh dispatch.

**Resume under the ceiling; continue above it.** A resume restores the agent's
whole context and re-reads it every turn afterwards. If the dead agent was
already past ~150k — or has been cold for more than a few minutes carrying a
large context — dispatch a **continuation** instead, from its last handoff note,
or failing that from the ledger plus the worktree, branch and PR facts you
verified. Both paths pay one full cache write at that moment; only one of them
keeps paying for the bloat afterwards.

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
*unpolled* backgrounding by name — "never fire `run_in_background` and then
wait on it blind; never arm a `Monitor`. If a command will outlast your cache,
run it detached and poll it on a short cadence (Poll, do not block, below)."**
"No monitors" on its own is not enough: it reads as a Bash rule, and a fixer
that took it that way still armed the Monitor tool and stalled on it. **Ban
dispatching subagents in the same breath**: nothing said an agent could not
fork, and a triage agent forked four helpers that wrote one shared output file
and clobbered each other. A short default Bash timeout is what
auto-backgrounds long suite runs and live CLI calls; six agents stalled that
way in one run, each costing a nudge round-trip.

**But a blocking wait has its own price, and it is the larger one.** A
subagent's prompt cache is short-lived — far shorter than the orchestrator's —
and a command that blocks for longer than that lifetime expires the agent's
whole cache, so the next turn rewrites the entire context at the cache-write
rate rather than reading it. Measured over one run, that single mechanism was
the largest line item in the whole bill.

**It is the waiting, not the test suite.** The suite is the commonest instance
and not the majority of the cost: in the same measurement, builds, worktree
checkouts on a large repo, and other ordinary multi-minute commands together
cost more than the full suite did. So do not read this as advice about testing
and conclude it misses you because your suite is fast. Any command that outlasts
the cache costs the same rewrite, whatever it was doing, and the agents in that
run were already disciplined about test scope — they ran more than twice as many
targeted tests as full ones, and still paid it.

That also rules out the fix that first suggests itself. **Verifying less is not
the answer**, and neither is moving the slow command into a second agent: the
first agent still has to wait for the result, and waiting is the thing that
costs. An agent that kept taking turns across a long run paid none of it, which
is what makes this a briefing choice rather than a fact of life.

So the rule is **poll, do not block**: anything expected to outlast the cache
runs detached and is polled on a short cadence, and anything shorter blocks as
before. A poll turn costs one cache read; a blocked wait costs a full rewrite,
which is more than an order of magnitude dearer at the context a fixer reaches
mid-run. Polling also detects the stall the ban was written to prevent — a
poll that stops coming back is a stall, visible in minutes rather than at the
next nudge — so this does not reopen the hole. What stays banned is
**unpolled** backgrounding: firing a long job and then waiting on it blind.
**That ban applies to ANY dispatched agent** — wrap, demo-capture, board and
post-run agents included,
not just Phase-1 fixers and reviewers. The one that proved it was a post-run
capture agent whose ad-hoc brief omitted the line and stalled identically.

**Reviewer brief template.** On top of the rules above, every reviewer brief
carries:

- *"Post a GitHub review whose body literally contains
  `VERDICT: APPROVED | CHANGES_REQUESTED`"* — in the posted body, not only in
  your return to the orchestrator.
- *"Prove each new guard would fail if the thing it guards stopped being
  true"* — vacuous assertions were found green three different ways in one run.
- *"Review PR #N at head `<sha>`, base `<sha>` — these files. Open anything
  outside the diff only to verify a specific claim you are making."* Resolve
  the SHAs yourself and pin them; a shared clone moves under concurrent agents.
- *"Rule on scope: is this still one change, and what should be split?"*
- *"Quote the card's Exit clause and name what composes each deliverable"* —
  a sink approved as "correct, not user-facing" was wired into nothing; a
  feature nobody reaches is not shipped.
- *"For every comparison against a reference, confirm the reference's answer
  is derivable from the input the compared variant receives"* — a rule scored
  one variant's example against a reference recording whose value lived only
  in the withheld input; no model could pass, and it decided the verdict.
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
6. To a **fixer on any position- or orientation-sensitive card**: *"use an
   ASYMMETRIC fixture and a hand-typed candidate oracle from day one."*
   Fixture-blindness repeats by axis. Two such cards in one wave shipped tests
   green under mirror and transpose because the fixture was symmetric, and a
   third passed a directional filter because the fixture had no variation on
   the axis it filtered. The position-mutation review battery catches this, but
   the fixture requirement catches it a round earlier — the one card briefed
   this way came back with no finding on that axis.

   **A rule about a relation between two objects needs a mutation that moves
   only one of them.** Whole-thing transforms — mirror, transpose, shift,
   rotate — move both, and on two separate cards every one of them left the
   suite green while the rule under test was broken. Only a mutation that
   moves one of the two objects and leaves the other where it is discriminates
   a working rule from a broken one; no whole-thing transform can.
7. To **any long-running agent**: *"when your context passes ~150k, stop and
   write the handoff note; do not push on."* The one line that bounds an
   agent's cost, because cost grows with context × turns and not with how much
   the agent says. Pair it with the note template (Handoff note, above) so the
   agent does not have to ask what a handoff note is. Reviewers get the
   opposite line: one verdict on the whole diff, never split.

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

**Then merge in ASCENDING version order and let the fixers correct themselves.**
Three held versions against a `main` that moved four times is one reorder per
merge if the orchestrator owns the numbering, and every reorder is a round trip
to a fixer. What worked instead: merge lowest-claimed-version first so the
constant only ever rises, and give every fixer the standing line **"re-read the
constant on `main` immediately before you push, and take the next free number
above it only if yours has been passed."** Gaps are usually harmless — check
what the version tests actually assert (one suite asserted only a monotonicity
bound, so a skipped version or two cost nothing), and renumbering a built PR
down to close a gap re-touches generated fixtures and merged doc text for
cosmetics.

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
elsewhere.** A numeric computation diverged across two operating systems at
its own accept/reject boundary inside the same deterministic budget — and a code
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

**Run `date` for every single stamp, in the turn that emits it.** Not from
memory, and above all not by adding the elapsed work to the last stamp — that
is how one run's stamps ended up **77 minutes ahead** of the clock before the
operator caught it, which also made every time in its ledger a label of unknown
accuracy. This is a per-stamp instruction, not a per-ledger one; it was already
written once as the latter and was read as advice. Emit it on meaningful
completions, not on every notification or tool call. If the user asks for "just a number",
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
   that duplicates an open card is a fold, not a new card) **and against the
   PR bodies of the run's own merged cards** — a finding a PR already
   disclosed and disposed of is discharged, not deferred; one filing agent
   correctly declined four such sets on that ground — and groups the
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

**Quota wind-down (the operator calls it; Phase 2 in miniature).** Start no
new card. Let in-flight agents finish; each open PR gets at most one review
round, then either merges (orchestrator gate on the merge SHA) or parks
green with its rebase facts written on the issue (which base it was cut
from, which numbers moved under measurement). A card whose only red is a
defect it *exposed* files that defect as its gate, is labelled `blocked`, and
parks. The demo publishes as a **pre-release** (`w0N-demo-prelim`): sheets
from `main`, plus previews rendered from parked PRs in a labelled section
that says why they are not merged; the milestone stays open. The deferred
register → ruling → filing becomes the next session's first act, not a spend
now. Then memory, ledger pause state, skill lessons.

**Mechanics that bit (keep):** take every ledger time from `date`; edit a
branch and verify in one shell call, merge in a **separate** call, and never
`cd` into a worktree inside a script (`git -C` only) — `set -e` did not abort
a failed anchor edit and the PR merged without it; a tmpfs `/tmp` fills with
four built worktrees (Bash then returns exit 1 with no output) — worktrees go
on disk under `~/.claude/jobs/<run>/tmp`.

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
5. **Measure the run and compare it to the last one.** `/token-report` over the
   run's window (`--since <start> --until <end>`, then `--view agents --top
   40`): total, the sidechain share, how much of the spend happened above 200k
   context, and the per-agent context peaks. Write those into the private
   lessons file next to the previous run's, and compare. This is what tells you
   whether a cost rule — the context ceiling, a tier change, the liveness sweep
   — did what it was adopted to do. A rule adopted from a model and never
   re-measured is a habit, not a lesson; if the numbers say it did not work,
   revert it here in the same wrap.

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
