# Why the iron rules say what they say

SKILL.md states each rule in a few lines. This is the full text the rules had
before they were shortened — the reasoning and the failure each was written
against. Read it when a rule seems not to apply, or before changing one.

## Model check

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

## Iron rules, full text

1. **No dispatch of run work before scope approval.** "The user said
   unattended" is not approval of a scope they haven't seen. Present the scope
   doc, wait. The Phase 0 scope agent is the one exception, because it is what
   produces the doc being approved — nothing downstream of it moves until the
   user has.
2. **Worktree per agent, always** — including coupled tasks. Coupling is
   handled by merge order and declared file surfaces, never a shared checkout.
3. **Verdicts are data; the orchestrator merges — unless the project says
   otherwise.** Check `project.md` and `CLAUDE.md` for a human merge gate
   before the first dispatch, and put it on the held-for-human list if there is
   one; a run that merges through a gate the project reserved cannot be undone
   by noticing later. A reviewer never merges.
   An implementer never reviews its own diff. Merge = review clean + checks
   green + no open human gate.
4. **Design questions stop the issue, not the run.** A strong-model
   adjudicator rules with spec citations posted as a binding issue comment;
   docs amendments become PRs the **orchestrator squash-merges itself** —
   after the gate in rule 3, and after the paired code PR (or immediately if
   standalone) — no held queue; code proceeds on the ruling. **Exception: an amendment that edits a FROZEN spec
   or contract still goes to the held-for-human list.** Escalate to the human
   only what is hard-to-reverse AND a real trade-off the specs don't already
   decide.
5. **Ledger before first dispatch** (`$RUN/ledger.md`: waves, per-issue state,
   rulings, deferred minors, resume queue). Survives compaction and limits.
   Dead agents are **resumed from their transcripts** — while they are still
   under the context ceiling (rule 9). Above it, or with a cold cache, **continue
   from its checkpoint note instead** (`context-ceiling` → "Resume under the
   ceiling; continue above it"). If the agent
   id is genuinely unrecoverable, dispatch with the ledger's state summary plus
   the worktree, branch and PR facts you verified yourself.
6. **Nothing deferred silently — and not everything deferred becomes a card.**
   Every non-blocking finding gets a ledger entry and a close-comment mention.
   A **follow-up issue** on top of that only when the finding moves the run's
   goal line (rule 11), and only after the user approved creating it, per scope
   rules. "Nothing deferred silently" is easily read as "everything deferred is
   filed", and the register then manufactures work: a run can file more cards
   than it merges, every one a real finding and none of them on the goal.
   **Set a filing budget in the scope doc and report filed-to-merged in the
   wrap.** Two runs above 1 means the mechanism is producing the backlog.
7. **Budget = graceful drain.** At the token target: start nothing new, let
   in-flight rounds finish, report, pause. **Measure it, don't estimate it** —
   `/token-report`'s `--json` total between waves and before each fix round
   (phase1-loop.md → Budget check). A budget rule with no instrument is a wish.
8. **Report progress after every substantial agent completion** — a stamped
   `**<date and time> - Progress: Exit <met>/<total> · N%**` line plus one line
   of what happened. **The time comes from `date` in that same turn, never
   from reckoning** — an estimated stamp drifts from the clock, and a stamp the
   reader cannot trust is worse than none. **Exit items first, card cost second**: the percentage
   measures spend consumed, and a run can consume most of its cards without
   moving a single Exit item. Weight the percentage by expected issue cost,
   never by count; unmerged is not done. Read `context-size.py` (`context-ceiling` skill) in
   the same turn and record its `current` in the ledger — that is the orchestrator's
   own context instrument (rule 9). See phase1-loop.md → Reporting.
9. **Context is a budget, and the orchestrator's is not the fixer's** — the
   **`context-ceiling`** skill holds the rule, the instruments and the
   checkpoint note. Its numbers, as this run uses them:
   - **Fixers and other long-running dispatched agents stop at ~150k, write a
     checkpoint note, and return it** (hard stop ~200k), enforced by the hook
     `/add-context-ceiling` installs; the orchestrator dispatches a
     continuation from that note.
   - **The orchestrator's ceiling is soft 200k / hard 500k**, read with
     `context-size.py` **at each progress stamp** into the ledger. Past the soft
     one it does not stop — it **offers the operator a handover at the next
     natural boundary**: a merge, a wave end, a ruling.
   - **Reviewers are exempt from the ceiling but not from a budget** — a verdict
     does not split; a reviewer gets a **turn budget** and reports what it could
     not cover. Its length is a larger lever on cost than its tier, so keep
     reviewers on the stronger tier and bound their length — save on length,
     not on tier.

10. **A threshold ships with the instrument that reads it.** No agent can see
    its own context size: the harness does not report it and `/context` belongs
    to the operator, so "stop at N tokens" is a rule its subject cannot obey and
    it will be breached silently, and by a wide margin. Every threshold in a
    brief must therefore come with a way to read the quantity, or be restated as
    something the agent can already see: a turn count, a wave boundary, a
    deliverable.
    Where no instrument exists, build one — a `PreToolUse` hook receives the
    transcript path, so it can measure the agent and inject the warning, which
    turns instruction into enforcement. **A threshold with no instrument is
    decoration, and worse than none: it reads as a control that is working.**
    An agent measured past **twice** its stated ceiling is an instrument that
    did not bind — fix it before the next dispatch.
11. **The run has one goal line, and it is written before Phase 0.** One
    sentence naming the observable outcome — a report that opens, a screen
    that loads, a recording someone can watch — testable by looking at the
    artifact, not at the board. Everything downstream keys on it:
    - the **scope agent derives the minimum card set that closes it** and names
      everything else as out of the wave, by name, in the doc;
    - **every brief carries the goal line**, and the return contract asks what
      the deliverable moved on it;
    - the **progress stamp reports Exit items met / total FIRST**, card cost
      second (phase1-loop.md → Progress line);
    - **rulings are sized by the goal.** A question that does not change the
      Exit does not get a durable design record; one probe is run per card
      before the operator is asked anything. Above roughly two rulings per
      merged card, the spec is the defect — propose the change as one batch.

    Without it the unit of work is the card, and a backlog will always supply
    more cards than a goal needs. A run that ends with the Exit unmoved and the
    cards closed has diverged, however well the loop ran.

## Phase 1 passages, full text before they were shortened

**Review.** Independent agent, never the implementer. Gets the issue, the
approach + rulings, the spec sections, the PR. Posts a GitHub review with an
explicit `VERDICT: APPROVED | CHANGES_REQUESTED` line (self-approval is
blocked when reviewer and author share the account — the COMMENT + verdict
line IS the record). **The `VERDICT:` line must be literally present in the
POSTED review body, not just in the agent's return to the orchestrator** —
the merge agent checks GitHub's own review text, and a posted review body can
carry no verdict line at all (the state reads back as COMMENTED regardless of
what the agent's return said). `briefs/reviewer.md`
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

**The orchestrator's ceiling is not the fixer's: soft 200k, hard 500k.** Why
the numbers differ, and how to read the orchestrator's, is in the
`context-ceiling` skill ("The main session"). Read `context-size.py` at each
progress stamp and write its `current` beside the stamp in the ledger; the run
milestones alone ("second wave boundary") say nothing about which side of 200k
or 500k you are on.

**The ledger is the orchestrator's own handover record.** When the instrument says
the soft ceiling is behind you, bring the ledger fully current — wave state,
in-flight agents with their worktrees and PRs, open gates, resume queue, spend
so far — and tell the user that a fresh orchestrator session can take the run
over from the ledger file, because **the orchestrator cannot clear its own
context**.

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

**Reviewers never hand off.** A review is one coherent whole-diff verdict; a
split review is two partial opinions, neither of which saw the whole change. If
a review is genuinely too large for one agent, the diff is too large — ask the
reviewer for the scope ruling instead.

**The resume packet is what a fresh orchestrator reads before its first
dispatch, and it is bounded.** What a fresh orchestrator reads before its first dispatch is carried on every
turn that follows, so it reads little: the system prompt and instructions are a
large fixed base, and the overlay, a phase file read when it is not needed, ledger greps and
directory listings only add to it. Cost per unit of
work goes as (base + cap) / (cap − base): with a large base a handover at the soft ceiling is
dearer per unit of work than running to the hard one, which is why long
sessions felt right; with a small base both are cheap. So the packet, in order and nothing else:
(1) the project's handoff file and the run's INTRO — self-sufficient, under
~4k tokens: mains, open PRs by number and head, what is in flight, the NEXT
list, budgets, ceilings; if it needs a second file to be understood, the last
wrap was lossy and the fix is the INTRO, at your own wrap; (2) the ledger's
last stamp by `tail`, never the ledger — **the ledger is append-only for the
orchestrator**, grepped by issue when a card names one; (3) live state from
the tracker as field-selecting one-liners. The overlay is loaded by the skill;
the phase files are read only when their phase applies (SKILL.md → "Which file to read"); prior briefs, registers and earlier runs'
ledgers are not read at start. **The first dispatch is the leg whose brief
already exists with no placeholder left** — a brief that still needs writing
is written after that dispatch, not before it, so a finished brief never waits
behind one being built. **Stamp
the ready point** — the context at the first dispatch — on that dispatch's
ledger line; past ~80k, name the file that did it. Turn 1 alone is already the stable prefix plus the INTRO, the
memory index, the instructions file and the skill listing, so the ready point
is never zero; a ready point well past that floor means work was done before
the first dispatch. Keep the ledger tail to 20 lines and a ledger line to 300 characters — the
detail is in the report file the line points at, and a long line costs on every turn.

**Budget check.** Iron rule 7 needs a number, not a feeling: the
`unattended-run` skill's budget read (§5), which refuses to report `$0` from a
mistyped window or root.

Before the first wave, find the instrument's per-project view
(`token_audit.py --view projects`, from the `token-report` skill) and record the
command in the INTRO; a run on a shared machine that reads only the
machine-wide total cannot apply this rule at all.

**The orchestrator's own context has a second instrument, and it is the one
the stamp needs.** The spend read measures spend, not context size. Read
`$S/../context-ceiling/tools/context-size.py` (exit 0 / 1 / 2 for under-soft /
past-soft / past-hard; `--json` for the ledger) and write its `current` into the
ledger beside every progress stamp. Never estimate it.

Consult the spend report (`token_audit.py` from the `token-report` skill)
between waves and before each fix round after the
first, and record its figure in the ledger next to the wave line so the drain
decision is made against a trend rather than one reading. The progress stamp's
context figure comes from `context-size.py`, not from the spend report (Iron
rule 9). `token_audit.py --view agents --top 40` shows which agents carry the
cost and how large their contexts grew — that is the view that says whether
the ceiling is being respected.

**An agent measured past twice its ceiling is an instrument failure, and it is
fixed before the next dispatch** — not a ledger note. The checks, in order, are
in the `context-ceiling` skill.

**Heartbeat: from the first dispatch until the wrap.** Arm the cache-warmth
skill's 50-minute heartbeat **in the same turn as the first dispatch**. When it
fires, re-arm it, then run the liveness check — the agents' output-file mtimes
and `pgrep` on their processes, never a transcript read — and reply with one
line if nothing moved. Keep it through every park at an operator gate or a
quota drain. Stop re-arming it only at the wrap (see "Unattended mode → the
stop"), and say in the final message that it is off.
