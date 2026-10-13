# Phase 1 — the per-issue loop and its protocols

Read in full after the scope is approved, and again by a fresh orchestrator
that takes a run over (start at "The resume packet"). Agent-facing text is in
`briefs/` and is assembled into briefs with `cat`, never read here.

**Approach.** One agent reads the issue + cited specs + current code, posts
a concrete approach as an issue comment (files, tests, fixture, exit
assertion), flips the triage label. Returns "DESIGN QUESTIONS: none | list
with recommendations". Approach agents for sibling issues run in parallel but
must be told about each other's file surfaces. When operator rulings during the
run have overtaken a card's own pass rule, the approach states the conflict,
the go-ask names it as its own question, and the milestone's Goal/Demo lines
are amended with a dated outcome at close — otherwise the closing card
certifies against text nobody still holds.

**Go-gate** (orchestrator). Clean approach → flip to go and dispatch the
fixer. Design questions → adjudicator first. Strip any "needs human
brainstorm first"-style gating label when gating — it is spent once the
approach passed a human-delegated gate; leaving it on poisons board status
derivation (parked outranks lifecycle).

**Size the ruling by the goal, and probe before you ask.** Two gates in front
of the adjudicator, both cheap:

- **Does the answer change the milestone's Exit?** If not, it does not get a
  durable design record (an ADR or equivalent). Rule it in the issue comment
  and move on. A record written for a question the Exit does not turn on costs
  a doc PR, a review, a merge and an operator read, and moves nothing anyone
  can see; a stack of them is how a run ends with every record unmerged at the
  wrap and nothing visible moved.
- **Has one probe been run?** One throwaway measurement per card before the
  operator is asked anything. Most questions that look like design questions
  are answered by running the thing once. **Probe the mechanism, at the length
  the question needs.** When an adaptive or emergent behaviour fails, measure
  what the underlying system allows before theorising about the component that
  adapts — such a probe can turn "the component hasn't improved" into "the
  system's limits don't allow it", which changes the ruling. A time or cost budget
  question gets **one full-length run**: a shortened probe's ratio does not
  extrapolate — a probe at a small fraction of the length can predict a
  slowdown the full run does not show, and a ruling built on it cuts the wrong thing.

**Rulings per merged card is a spec-health metric, and it belongs in the ledger
spend block.** Above roughly **two per merged card**, the specs are not merely
silent — they are wrong for the work, and ruling case by case is paying for the
same defect once per card. Stop and propose the spec change as **one batch**:
one amendment covering the class, one review, one operator decision. Two
consecutive milestones each far past that ratio is the shape this catches.

**Adjudication.** Strongest tier. **The brief pins everything the ruling
needs**: the exact design questions, the conflicting positions quoted from the
approach comments, the spec sections by path and anchor, and the file surfaces
involved. The adjudicator rules against those documents; it opens the repo
only to verify a specific citation, never to explore — an adjudicator left to
find its own context spends most of its turns exploring, at the highest
per-token rate in the run. One issue or one pre-declared cluster per adjudicator;
never batch unrelated issues into one agent — a batched adjudicator runs far
longer than a single one and rules no better. Rules each question against
the specs with citations; posts a binding "## Design decisions" comment;
drafts any doc amendment as a PR, reviewed for `DOCS_PR_MATCH` (the reviewer
checks each clause against the ruling and the shipped code — `briefs/reviewer.md`) and **squash-merged by the orchestrator after
its paired code PR lands** — or immediately if standalone. No held queue:
holding docs amendments for the human only adds latency, and they come back
merged unchanged. Design-changing amendments are still surfaced in the
report, just not gated — **with one exception: an amendment that edits a
FROZEN spec or contract still goes to the held-for-human list.** Code proceeds
on the ruling.
A schema-shaped ruling triggers the schema-change chain (`reference/schema-changes.md`).

**A ruling's own numbers are hypotheses to the fixer, not facts.** An
adjudicator's cited figure can still be off by measurement — a cited count, a
measured dimension or a named exception type can move when the fixer checks
it. The fixer verifies before building on the figure, and posts any
correction as a follow-up comment after merge rather than absorbing it
silently.
**So is a ruling that sets or moves a gate — the orchestrator's own
recommendation included.** Before a bar or baseline change goes to the
operator, check four things every gate silently assumes. **The scored artefact
is the one that ships**: a gate that scores a different artefact than the one
shipped (a reduced or averaged form of it) can tune in the wrong direction —
what helps the shipped one may hurt the scored one. **A bar relative to a
baseline moves whenever whatever the baseline is drawn from changes**: a
baseline measured before that change can stop meaning what the bar assumed,
and a recommendation to redefine the bar can be overtaken by the next change.
**The best of many attempts, picked on the set that gates, flatters it**:
picking the winner on the same data that judges it overstates the result by
about the margin of the pick, so the gate reads data the pick never saw. **The
harness is neutral between the things it compares**: a harness tuned to the
old variant can put every other variant in conditions it was never built for,
and the new variants look wrong because of the harness, not the variant. When a new variant fails, ask what the
harness assumes about the old one before concluding about the new one, and put
the actual runs in front of someone early.

**Fixer.** TDD (red recorded, then green), in a fresh worktree
(`git -C <repo> fetch <remote> && git -C <repo> worktree add
<scratch>/wt-<issue> -b <branch> <remote>/<default-branch>` — `<remote>` and
`<default-branch>` are whatever this repo uses, usually `origin` and `main`),
branch per the repo's convention, PR body carries
red→green evidence, labels flipped by the fixer at start/end. Never merges,
never pushes to a protected/main branch. Cross-repo issues: one worktree and
one PR per repo, cross-referenced; merged later as an ordered group.
**A design resting on several rulings gets a throwaway probe before the real
diff** — a minimal end-to-end skeleton, actually run. Such a probe can surface
failures from a contradiction across rulings that nobody saw on paper, and is
the cheapest stop-clause available. **Widening a gate is a
design act, not an implementation detail**: a necessary, narrow exemption is
still disclosed in the PR body and paired with a tripwire test that reads the
production roster (never a re-typed copy), so the next addition reds.

**The fixer stops at the context ceiling — and something has to tell it.**
No agent can read its own context (iron rule 10), so the brief line alone gets
breached silently. The **`context-ceiling`** skill has the mechanism: install
its hook on the project with **`/add-context-ceiling`** and prove it fires
before the first dispatch (that skill's step 4); put
`../context-ceiling/brief.md` into every fixer's brief verbatim. What is the
orchestrator's own:

- **Large cards are briefed as parts from the start** (A, B, then a finisher),
  each committing and pushing after every plan step, so a checkpoint costs one
  short continuation brief and no lost work.
- **A job that outlasts the agent** returns `running`; the finisher is
  dispatched when the orchestrator's background wait sees the done marker.
- **Do not raise the hook's thresholds because the orchestrator's number went
  up** — they bind dispatched agents, whose number did not change. Set them for
  the longest reviewer you dispatch (iron rule 9).

**Review.** Independent agent, never the implementer, on the top standard tier
— the last gate before merge. It gets the issue, the approach and rulings, the
spec sections, and the PR pinned by head and base SHA; its rules are
`briefs/reviewer.md`. **The merge gate reads the `VERDICT:` line in the POSTED
review body**, never the agent's return: a posted body can carry no verdict at
all, and same-account reviews read back as COMMENTED whatever they say.

**Fix rounds.** Findings go back to the SAME fixer via message (resume), not
a fresh agent — rounds 1–3, while it is under the ceiling. Round 4–5: fresh
agent, one tier up, briefed from the fixer's checkpoint note. **A fresh agent
on an existing branch collides with the old agent's worktree**, which still
holds that branch after the old agent finishes (it is locked, and git refuses
a second checkout). Before the dispatch, either remove it —
only after confirming the old agent has finished and `git -C <path> status
--porcelain` is empty, then `git worktree remove -f -f <path>`; a non-empty
status means uncommitted work, so do not remove it — or brief the new agent to
work on `checkout -B <local> origin/<branch>` and push with
`<local>:<branch>` once it has confirmed the remote head is unchanged. Without that, the new agent
spends turns on the lock. Cap 5, then
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
was deferred, sync the board (the project's board-sync tool, if it has one;
see Board/label hygiene), mark the ledger. **Exception: `main` merged
INTO an integration branch uses `--merge`, never squash** — main's own commits
carry closing keywords, and a squash concatenates every message and re-fires
them when the branch reaches main. Run the full suite on the merged tree
before the final PR; per-branch gates do not compose (a schema bump on one
branch can turn a textually clean merge into semantic reds). Cross-repo groups merge in
dependency order (producer repo first), all-or-nothing. **Delegate the merge
mechanics to a small agent** — gate polling, conflict resolution, the
close-comment/label/board-sync bundle — because orchestrator context is for
coordination; a single trivial gate-plus-merge may stay one inline command.
**A review's docs-only wording nit on an otherwise-clean docs PR: fix it on
the docs branch yourself before merging** rather than spinning a fix round.
**A card that straddles the wave boundary closes
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
that has grown large, re-running the suite again and again, can cost more than
the implementation it repairs. When a fix round passes the cost of the
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
`git log` over memory. **Put it on disk, not on a tmpfs scratchpad** — a
ledger there can be cleared with `/tmp` between sessions. It is recoverable:
a subagent can rebuild it from the previous session's transcript by reading
the tool calls, which is the fallback, but it costs a dispatch and it only
works while the transcript is still there.

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

Queue gated fixers with an `until` poll on `origin/main` **run in the
background** (Protocols → "The orchestrator never takes a turn to wait") so the
next card is dispatched on the notification, not on a poll turn. Bound it
inside the orchestrator's cache lifetime and have it exit non-zero on expiry,
so a slow merge surfaces as a failed step rather than a killed shell.

**Test-runner filters.** A runner's path or name filter may be exact-match
rather than prefix-match: summing per-chunk totals then silently drops
whatever no filter matched — tests ran but were never counted. Confirm the
runner's filter semantics before trusting a summed total; brief agents to run
unfiltered or split by test class, and to quote per-chunk totals.

**Retried captures** (only where the project captures live external output and
replays it in tests). Re-capturing until a capture is usable and
keeping the last one is disclosed, not cherry-picked — and only when every
discard was for validity. Discarding on content the brief never pinned is a
selection the operator rules on, and the capture's provenance should carry an
attempt count. Route it to the deferred register, not to the reviewer.

**Past the soft ceiling: a handover, offered, not taken.** The numbers and the
reasoning are `context-ceiling` → "The main session". The orchestrator's part:
bring the ledger fully current — wave state, in-flight agents with worktrees
and PRs, open gates, resume queue, spend — since **the orchestrator cannot clear
its own context**, then post one handover message and stop dispatching until it
is answered. It says where the run is and what each in-flight agent waits on,
any open gate, the ledger's path, and the two options: **at a wave boundary
with nothing in flight, a fresh session** is cheapest; **mid-wave with agents
running, compact** and keep the handles, since a fresh session cannot message
the old one's agents. Give the literal instruction a fresh session needs —
*"read `<ledger path>`, verify worktree/branch/PR state with `git` and `gh`
before trusting it, then continue at `<next concrete step>`"* — and end with
the progress stamp.

**Checkpoint note.** The template, and how a continuation is briefed from it,
are in the `context-ceiling` skill. The orchestrator's part: copy each note into
the ledger on arrival, dispatch the continuation with the note **verbatim** plus
the standard brief (role, one issue, binding comments, file surfaces, return
contract), and verify its STATE lines yourself first. Treat the first wave that
uses notes as a pilot — read them, and add the heading a continuation had to
re-derive.

**Reviewers never hand off.** A split review is two partial opinions, neither
of which saw the whole change. A review too large for one agent means the diff
is too large — ask the reviewer for the scope ruling instead.

**The resume packet is what a fresh orchestrator reads before its first
dispatch, and it is bounded** — whatever it reads then is carried on every turn
after. In order, and nothing else:
1. the project's handoff file and the run's INTRO — self-sufficient, under ~4k
   tokens: mains, open PRs by number and head, what is in flight, the NEXT
   list, budgets, ceilings. If it needs a second file to be understood, the
   last wrap was lossy; fix the INTRO at your own wrap;
2. the ledger's last stamp by `tail`, never the ledger — **the ledger is
   append-only for the orchestrator**, grepped by issue when a card names one;
3. live state from the tracker as field-selecting one-liners.

Prior briefs, registers and earlier runs' ledgers are not read at start, and
phase files only when their phase applies. **The first dispatch is the leg
whose brief already exists with no placeholder left.** **Stamp the ready
point** — the context at the first dispatch — on its ledger line; past ~80k,
name the file that did it. Keep the ledger tail to 20 lines and a ledger line
to 300 characters; the detail is in the report file the line points at.

**Budget check.** Iron rule 7's number is the `unattended-run` skill's budget
read ("Budget"), taken between waves and before each fix round after the first,
and written into the ledger beside the wave line so a drain is decided on a
trend. Before the first wave, find the per-project view
(`token_audit.py --view projects`, from `token-report`) and record the command
in the INTRO — on a shared machine the machine-wide total cannot apply this
rule at all. `--view agents --top 40` shows which agents carry the cost and
how large their contexts grew: the view that says whether the ceiling holds.
The stamp's context figure is `context-size.py`'s, never the spend report's.

**The orchestrator never takes a turn to wait.** The forms — the wait table,
the 50-minute bound on background waits, the expiry rule, the heartbeat — are
the **cache-warmth** skill's main-session rules (`../cache-warmth/SKILL.md`);
read that section at the first dispatch. What is the orchestrator's own:

- **The commonest world-condition wait is the gated-fixer queue** ("Queue gated fixers",
  above): the `until` on the default branch runs in the
  background and the next card is dispatched on the notification, not on a poll.
- **The failure-shape wait is the liveness sweep below.**
- A second expiry of the same wait is a ledger line and an operator question.
- Dispatched agents keep the subagent rule (poll, do not block); their cache is
  minutes, not an hour.

**Liveness sweep.** Arm the `unattended-run` skill's sweep (§6, "The liveness
sweep") as one persistent `Monitor` at the first dispatch, attended or not —
the dead-agent problem does not depend on whether the operator is watching. Its
default `WATCH` glob, `wt-*/` under `$SCRATCH`, matches the Fixer step's
worktree naming. Add the orchestrator's own failure shape to it: **"the agent
said it opened a PR and there is none"** (`gh pr view` for a PR that should
exist by now). The shared status line shows each live agent's cache TTL; a
reading at 100% on an agent meant to be polling says the same as a `COLD` line,
sooner. A transcript idle five minutes is a brief violation for the
self-improvement pass, not a wake-up.

**Heartbeat:** the `cache-warmth` heartbeat, armed in the same turn as the
first dispatch and re-armed until the wrap. When it fires, the check is the
agents' output-file mtimes and `pgrep`, never a transcript read.

**Unattended mode.** The `unattended-run` skill holds the contract, when to
stop and the stop sequence. The orchestrator's specifics:
- **Still gated:** scope approval (iron rule 1), the scope doc's **Authority**
  line, and every human gate in the overlay. An act the Authority line does not
  grant is reserved — park the card, do not do it.
- **What continues:** every card whose next step is the orchestrator's or an
  agent's. A design question goes to the adjudicator (iron rule 4). An
  operator-only question parks that card (label `needs-human`, a ledger line,
  an item on the held list).
- **Stop conditions** add the orchestrator's: every remaining card, gate or wrap
  step needs the operator — a human gate, a release, a deferred-register
  ruling, a held amendment. The context ceiling is the orchestrator's soft one
  (overlay, or 200k).
- **The stop** writes the ledger's RESUME PACKET and runs the project's handoff
  wrap (`/handoff wrap`, or its handoff doc); the ledger is pushed only if the
  overlay or the operator granted pushing.

**Rescue, stall nudge, removing the dependency** — the `unattended-run`
skill's helper rules (§6), attended or not: resume a dead agent with
`SendMessage` after verifying its worktree, branch and PR yourself; continue
from its checkpoint note above the ceiling (`context-ceiling`); resume the
orchestrator's own crashed session rather than starting fresh, since only it can
message its agents. When the agent waits on something that has not started — a
queued CI run — have it return with `CI: queued` and own that gate: you own it
anyway, since merge needs CI green *and* review clean, and the agent cannot
merge.

## Briefs

**A brief is assembled, not written whole.** The agent-facing rules live in
`briefs/` and the two sibling skills, in the agent's own voice; the orchestrator
writes only the issue-specific part and joins them with the `brief` function
below — **it never reads
those files into its own context.** `$S` is the directory `SKILL.md`
resolves to (SKILL.md → "Which file to read"):

```bash
S="$(dirname "$(readlink -f <path to SKILL.md>)")"   # SKILL.md → "Which file to read"
: "${SCRATCH:?set SCRATCH to the run's scratch directory, the one the ledger lives in}"
brief() { # brief <out> <block>... — fails loudly on a missing block, never writes a partial brief
  local out="$1"; shift
  for f in "$@"; do [ -r "$f" ] || { echo "brief: missing block $f" >&2; return 1; }; done
  for f in "$@"; do cat "$f"; echo; done > "$out"
}
brief "$SCRATCH/brief-<issue>-fixer.md" \
  "$S/briefs/common.md" "$S/briefs/issue.md" "$S/../cache-warmth/brief.md" \
  "$S/../context-ceiling/brief.md" "$S/briefs/fixer.md" "$SCRATCH/spec-<issue>-fixer.md" \
  || echo "STOP: fix the brief before dispatching"
```

| Role | Blocks, in order (`briefs/common.md` and `cache-warmth/brief.md` always) |
|---|---|
| fixer, continuation, combined approach+fix | `briefs/issue.md`, `context-ceiling/brief.md`, `briefs/fixer.md` |
| reviewer | `briefs/issue.md`, `briefs/reviewer.md` — never the ceiling block: a verdict does not split |
| approach, adjudicator | `briefs/issue.md`; `context-ceiling/brief.md` when the leg can run long |
| scope, capture, wrap, merge mechanics | no per-issue block — the specific part states the task and its return fields; `context-ceiling/brief.md` when the leg can run long |

**The specific part** (`spec-<issue>-<role>.md`) carries: **the run's goal
line**, the role, ONE issue, binding comments listed by name, repo and worktree
instructions, the concurrent agents' file surfaces to avoid — in parallel mode
**the version constant is one** — and anything the return must add. A
reviewer's adds the PR number, the **head and base SHAs you resolved yourself**
(a shared clone moves under concurrent agents), the files, and a turn budget.
Never state a number the agent can measure. Dispatch with a prompt that says
only: *"Your brief is `<B>`. Read it in full before anything else; it is your
complete brief."*

**A ban goes in every brief it binds, not only in a preamble the brief points
at** — assembly is what makes that cheap, since the shared blocks arrive in each
brief verbatim. Still check the bans' trace after each return: the post-merge
check (the command's own list is empty) is what makes a missed ban harmless.
The liveness sweep is the orchestrator's; no brief may grant an agent the
`Monitor` tool. After a card that ran a contract-sync tool, check the shared
clones with `git -C <clone> status --porcelain` and **report a dirty one to the
operator — never reset it**; the uncommitted work may be theirs.

**Idle time at parallelism 1.** While the one in-flight agent runs, write the
next specific part instead of waiting. Only the just-landed PR and branch facts
get filled in when the agent returns.

**What the orchestrator reads itself is small.** A return (the shape is in
`briefs/common.md`: at most ~40 lines plus a report path), a grep of a report
for a named question, a field-selecting tracker one-liner, a file of at most
~200 lines. A raw tracker view, a transcript, a diff or an image is read by a
**reader leg** at the cheapest tier that returns at most ten lines — the
verdict and the one fact the decision needs; an image the orchestrator opens
itself stays in its context on every later turn. **Small is for scanning, not
for concluding an absence:** a truncated line can drop exactly the token being
looked for, so before briefing a fix for something *missing* from an output,
read that one line in full.

**A return is handled in two turns.** Turn one: read the return and, if it
names a question, grep the report for it — plus the state check the next
dispatch depends on. Turn two: the ledger line, the handoff-file edit and the
next dispatch (or the merge line), as parallel tool calls. Done serially it is
four full-context turns.

**The `GOAL:` line is how scope drift shows up early.** An agent that cannot
say what its deliverable moved on the goal line has usually built something
correct and adjacent — a scope conversation to have before the review, not
after the merge. A finding that moves nothing is a close-comment line, never a
card (iron rule 6).

**Changing a brief block.** A new standing line goes into the right `briefs/`
file in the agent's voice, with the run that earned it recorded in
`reference/why-briefs.md`. Why each existing line is there is in that file.

## Reporting

**Board/label hygiene.** State labels are flipped by the stage that owns the
transition; the orchestrator runs the project's board-sync tool (an optional,
per-project piece — without one, set the board fields with `gh project
item-edit` or leave the drift to the Phase 2 board-consistency sweep) after
every close. If
board status derives from labels with parked-outranks-lifecycle precedence,
spent gating labels must come off at go time. **A keyword close (`Closes #N`
on the push to the default branch) skips the stage that would flip labels**, so
the close step strips every state label itself — in-progress, in-review,
blocked, go, needs-human, spent gate labels. A wrap sweep finds closed cards still carrying them.

**Reports.** One message per issue closed (what merged, what was deferred),
plus a wave summary. During quota pause: record everything, say what's
running, say what's queued; on resume, rescue first, then fill the pipe.

**Progress line.** The stamp's rules — its form, `date` in the same turn, the
stamp as the final text of its turn, goal items before percentage — are the
`unattended-run` skill's (§4), and hold attended or not. The orchestrator's
version of it:

```
**<date and time> - Progress: Exit <met>/<total> · N%**
<one line about what just happened>
```

- **Emit it after a subagent finishes a substantial chunk** — a PR opened, a
  review verdict, a fix round landed, a merge — not on every notification.
- **The Exit items come from the milestone's own Exit / Measure / Demo line**,
  counted once at Phase 0; with no Exit line, the goal line (iron rule 11) is
  the single item.
- **Order on a completion:** spend read (Budget check) → ledger update, figure
  included → next dispatch → the stamp, closing the turn.
- **The weighting**, fixed at the first report: each issue by expected cost,
  not by count; within an issue, approach 20, fixer 45, review 25, merge 10;
  an approved PR that cannot merge is 90%, not 100%.
