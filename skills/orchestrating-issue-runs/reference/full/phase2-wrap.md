> Full text of `phase2-wrap.md` before the terse rewrite: the reasoning and the incidents behind each rule. Not read at run time — read it when a terse rule is unclear, or before changing one.

# Phase 2 — wrap, and the skill's self-improvement

Read in full when the run's last card merges, the operator calls the quota, or
an unattended run stops.

## Phase 2 — Wrap (in this order)

1. **Demo evidence**: refresh the demo against the merged work (per the project's demo skill if one
   exists — an optional per-project piece; without one, the wrap brief spells
   out the refresh steps itself), screenshots + capture log, honesty fences from the run's rulings.
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
   *present but wrong* for that user. The evidence checklist answers "did each
   promised noun ship?"; the walkthrough answers "would the user accept
   this?" — they are different questions, and a run can score full marks on the
   checklist while a walkthrough of the same artifact finds many defects the checklist
   could not see. Findings go into the ledger's deferred
   list as candidate cards — step 5 reads them from there, not from a close
   comment, because every card is already closed by now — and the demo
   document names them as known gaps under the honesty fences. **The
   walkthrough runs on the operator's machine, so "a fresh user" means an
   isolated environment, and that means isolating every directory the tool
   chain writes to, not only HOME:** its caches, tool and data directories,
   and credential helpers too. A walkthrough that isolates HOME and the XDG
   directories can still write into the real package-manager cache on a failed first install. Name those variables in the brief. **What the walkthrough checks is project knowledge**:
   the rubric (whatever the domain's own objects and forms are) lives in the
   project's own repo — a demo skill, a docs file, a brief template — and the
   wrap brief points at it. This file only says *that* the review runs;
   it never carries a project's rubric.
3. **Demo document**: assembled from the capture log's own captions (never
   invented claims), delivered to the user, and — **if the run's memory says
   demos are published** (the memory file is optional; with none, ask the
   operator once) — released the way that memory describes (which repo,
   which tag, the artifact as an asset, the milestone description PATCHed to
   link it). Put it somewhere durable either way: ephemeral scratchpads lose
   demo documents, which is why this step exists.
4. **Close the milestone** (`gh api -X PATCH .../milestones/N -f
   state=closed`) — **only the milestone this run opened or owns; read it back
   first** (`gh api .../milestones/N`: title, open and closed counts) and close
   it only if it is the one and its open count is zero. Auto-close does not
   exist, and a milestone can sit open with every card in it closed until
   someone thinks to check.
5. **Deferred register → operator ruling → filing. Never agent → filing.**
   **First filter the register by the goal line**, before grouping: a finding
   that moves nothing on the goal is a close-comment line and is discharged
   there, not carried into the register at all. Then check the run against its
   **filing budget** (Phase 0 item 8) and state filed-to-merged in the same
   message the register goes in — the operator is ruling on the number as well
   as the items.
   Present what survives **pre-grouped by closability**: (a) closable in-branch
   now with no external resource — recommend folding into the card as one
   more sub-PR before the final merge; (b) needs a cloud call, eval budget, a
   UI, or data that does not exist yet — file, at most a few cards; (c) new
   ideas — file only the top few. An operator handed a long flat list will ask
   for exactly that split: fold most, file few, keep it controlled and closed
   soon. A
   register agent consolidates every deferred item out of the run's close
   comments **plus the domain walkthrough's findings from the ledger**,
   fold-checks each one against issues already open (a candidate
   that duplicates an open card is a fold, not a new card) **and against the
   PR bodies of the run's own merged cards** — a finding a PR already
   disclosed and disposed of is discharged, not deferred — and groups the
   survivors by kind — contract acts / code / docs / tooling / fixture /
   decisions. The orchestrator turns that into a one-screen list with
   recommendations; **the operator rules**; only then does a filing agent
   file. The fold-check is most of the value: a raw candidate list folds to
   a fraction as many filed cards plus edits to existing cards, and an
   agent filing straight off the close comments skips it entirely. An
   adjudicator's "file the follow-up" does not bypass this gate either —
   briefs route filings to the operator, always.
   **Place each filed card by the target milestone's own Measure line, not by
   "it comes next."** A contract act or a tooling card does not default into the
   next themed milestone merely because that milestone is up next — that is
   how a milestone picks up cards its theme did not need. Whatever the operator defers instead of
   filing carries into the next run's Phase 0.
6. **Board-consistency sweep, ALWAYS, as the run's last board action** (one
   subagent) — **it runs after filing, so it sees the new cards**: every open
   issue has a milestone matching its wave, non-empty board fields, native
   parent links matching body Parent lines, no label contradictions; the
   wave's closed set is milestone'd/Done/label-clean; epic spans recomputed
   after the run's filings (they go stale silently). Report-don't-guess
   anything ambiguous.
7. Run summary to the user, memory update (wave-complete entry replaces any
   paused entry; the user's owed items get their own entry), ledger closed,
   **and the next session's first brief finished — no placeholder left — named
   as the INTRO's first dispatch.** The next session's turn after its packet
   is then a dispatch, not a Write: a session that has to write its first
   brief spends turns on it before dispatching.

**Quota wind-down (the operator calls it; Phase 2 in miniature).** Start no
new card. Let in-flight agents finish; each open PR gets at most one review
round, then either merges (orchestrator gate on the merge SHA) or parks
green with its rebase facts written on the issue (which base it was cut
from, which numbers moved under measurement). A card whose only red is a
defect it *exposed* files that defect as its gate, is labelled `blocked`, and
parks. The demo publishes as a **pre-release** (`<wave>-demo-prelim`): the demo
pages from the default branch, plus previews rendered from parked PRs in a labelled section
that says why they are not merged; the milestone stays open. The deferred
register → ruling → filing becomes the next session's first act, not a spend
now. Then memory, ledger pause state, skill lessons.

**Mechanics that bit (keep):** take every time you write — ledger line **and chat progress stamp**, and its date — from `date` in the same turn (a typed date or time drifts, across midnight included, and keeps drifting after a correction); a brief's poll call must state its own timeout explicitly (a harness default of two minutes auto-backgrounds a longer poll and the agent loses the wait); a permission classifier may deny a raw REST merge call while the CLI's own merge command with a pinned head SHA goes through — both are sanctioned, keep the second as the fallback; a classifier may also deny a push to a branch that deploys (production) even after the operator approved the merge in chat — do not retry or route around it, hand the operator the merge to make in the host's web UI; edit a
branch and verify in one shell call, merge in a **separate** call, and never
`cd` into a worktree inside a script (`git -C` only) — `set -e` can fail to
abort a failed anchor edit and the PR then merges without it; a tmpfs `/tmp`
fills with a few built worktrees (Bash then returns exit 1 with no output) —
worktrees go on disk, in a scratch directory outside `/tmp`.

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
   3a. **PRUNE: add a rule, retire or merge a rule.** This step only ever added,
   and a skill that only adds becomes a document nobody finishes — the red-flag
   list kept growing until nobody noticed that a list that long is not a
   checklist. So every pass that adds a rule either **retires** one the run
   proved wrong or subsumed, or **merges** the new one into an existing rule
   that was being read too narrowly. Prefer merging: a new rule beside an old
   one that says almost the same thing is how both get skimmed. Retiring is not
   deleting — a rule the project reversed is kept as a dated "retired"
   paragraph wherever it lived, because a reversal that leaves no trace reads
   later as a rule nobody ever meant.
   **Long enumerations move to `reference/` files beside the skill**, with a
   one-line pointer and the ten most load-bearing rows left inline. The full set
   stays readable and nothing is lost; what changes is that SKILL.md stays the
   size of a thing an agent actually reads before dispatching. Keep the counts
   in the pointer honest — they are the only signal that the reference file was
   updated too.
4. **Commit. Do not push a shared or public repo without asking** — check
   `gh repo view --json visibility` first, and have the diff reviewed for
   project detail before it goes anywhere public.
5. **Measure the run and compare it to the last one.** `/token-report` over the
   run's window (`--since <start> --until <end>`, then `--view agents --top
   40`): total, the sidechain share, how much of the spend happened above 200k
   context, and the per-agent context peaks. Alongside them, three ratios that
   say whether the run was *converging* rather than merely busy, and that go in
   the ledger's spend block as well as the wrap report:
   **Exit items met / total** · **filed-to-merged** (two runs above 1 = the
   register is generating work, iron rule 6) · **rulings per merged card**
   (above ~2 = the spec is the defect; batch the change, `phase1-loop.md` → Adjudication).
   A run can be green on cost and failing on all three.
   Write those into the private lessons file next to the previous run's, and
   compare. This is what tells you
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
