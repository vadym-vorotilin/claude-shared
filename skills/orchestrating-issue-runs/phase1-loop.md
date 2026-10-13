# Phase 1 — the per-issue loop

Orchestrator-only rules. Agent instructions are in `briefs/` and are assembled
into briefs, never read here (SKILL.md → "Briefs"). The reasoning behind each
rule is in `reference/full/phase1-loop.md`.

## The loop

**Approach.** One agent per issue (`approach` block); siblings in parallel, each
told the others' file surfaces. Clean → **Go-gate**: flip to go, strip any spent
gating label, dispatch the fixer. Design questions → adjudication first.

**Size the ruling by the goal.** A question that does not change the Exit gets
no durable design record — it is ruled in the issue comment. One probe per card
before the operator is asked anything. Track **rulings per merged card** in the
ledger: above ~2, the spec is the defect — propose one batched spec change.

**Adjudication.** Strongest tier, `adjudicator` block, one issue or one
pre-declared cluster per agent, never a batch. The specific part pins the exact
questions, the conflicting positions quoted from the approach comments, the
spec sections by path and anchor, and the file surfaces. The ruling is a
binding issue comment; code proceeds on it. A docs amendment PR is reviewed for
`DOCS_PR_MATCH` and **squash-merged by the orchestrator** after its paired code
PR (or at once if standalone) — **except an amendment to a FROZEN spec or
contract, which goes to the held-for-human list.** A schema-shaped ruling →
`reference/schema-changes.md`; a fixer-authored convention or an "infeasible"
claim → `reference/conventions.md`.

**Fixer.** `fixer` block, a fresh worktree per issue under `$SCRATCH/wt-<issue>`
(`$SCRATCH` on disk — built worktrees fill a tmpfs `/tmp`).
Brief a card the scope sized as large **as parts from the start** (A, B, then a
finisher). A job that outlasts the agent returns `running`; dispatch the
finisher when your background wait sees its done marker. The context-ceiling
hook must be installed and proven before the first fixer
(`/add-context-ceiling`); set its thresholds for the longest reviewer, never
for the orchestrator's number.

**Review.** Independent agent on the top standard tier, `reviewer` block, the
PR pinned by head and base SHA you resolved. **The merge gate is the literal
`VERDICT:` line in the POSTED review body**, never the agent's return.

**Fix rounds.** Findings go to the SAME fixer by message, rounds 1–3, while it is
under its ceiling; each round ends with a scoped re-review by the SAME reviewer.
Rounds 4–5: a fresh agent one tier up, from the checkpoint note — first remove
the old worktree (only if the old agent finished and `git status --porcelain` is
empty; then `git worktree remove -f -f`), or brief it to work on
`checkout -B <local> origin/<branch>`. **Cap 5, but the real cap is the budget**:
before each round after the first, read the spend; a round not worth its price
→ adjudicate the open findings instead. **A round costing more than the work it
repairs → stop and ask the operator.** A round that is doc/comment text plus
mechanical tests with **zero non-comment production lines**: verify it
yourself — no production diff, no fixture bytes moved, and **a discriminating
mutation you re-apply on a different axis than the fixer's**. Non-blocking
findings: one-liners now; the rest to the ledger and the close comment. After
several rounds, ask the reviewer whether it is still one change.

**Merge.** Review clean + CI green + no open human gate (and the Authority line
grants it) → a merge-mechanics agent (`merge` block) does the squash, close,
labels and board sync; a single trivial gate-plus-merge may stay one command.
Cross-repo groups merge producer first, all-or-nothing. A docs-only wording nit
on a clean docs PR: fix it on the branch yourself. A card straddling the wave
boundary closes in the wave that did its work; the remainder is filed fresh.

**Rebases after a sibling merge.** The card's fixer rebases (with
`--force-with-lease`) and returns `old-base` and `old-head`. Carry the standing
review only if `$S/tools/same-diff.sh <old-base> <old-head> <new-base>
<new-head>` exits 0, plus the fixer's suite line from the rebased head.
Otherwise re-review. Queue gated fixers on a background `until` on the default
branch and dispatch on its notification.

## Protocols

**Ledger.** On disk (not a tmpfs `/tmp`), written before the first dispatch:
wave plan, per-issue lines, rulings, deferred minors, resume queue, pause
state. **Append-only** for the orchestrator: read its tail, grep it by issue.
A line ≤ 300 characters, pointing at a report file for detail. After a
compaction or limit reset, trust the ledger and `git log` over memory.

**The resume packet** — all a fresh orchestrator reads before its first
dispatch: (1) the project's handoff file and the run's INTRO (self-sufficient,
under ~4k tokens); (2) the ledger's last stamp, by `tail`; (3) live tracker
state as field-selecting one-liners. The first dispatch is the leg whose brief
already exists with no placeholder left. Stamp the **ready point** (context at
the first dispatch) on its ledger line; past ~80k, name the file that did it.

**Waiting.** Never take a turn to wait: no `sleep`, `until`, `--watch` or
task-output call in your own turn.
- an agent → its completion notification;
- a condition (a merge, a check, the default branch moving) → background
  `timeout 3000 bash -c 'until <check>; do sleep 30; done'`, exiting non-zero on
  expiry; on expiry, one field-selecting read of the cause and re-arm once; a
  second expiry is a ledger line and an operator question;
- **heartbeat**, armed in the same turn as the first dispatch: background
  `sleep 3000; echo HEARTBEAT`. When it fires, re-arm it first, then check the
  agents' output-file mtimes and `pgrep` — never a transcript — and reply in one
  line if nothing moved. Stop re-arming it only at the wrap.

**Liveness sweep.** At the first dispatch, arm `$S/../unattended-run/tools/sweep.sh`
as **one** persistent `Monitor`, with `SCRATCH` set. On `STALL`, verify with
cheap reads (commit time, `git status`, PR, processes) before acting; a long
agent is not a dead one. On `SWEEP DOWN`, fix what it names and re-arm.

**Rescue.** A dead agent under its ceiling: resume it by `SendMessage`, after
verifying its worktree, branch and PR yourself and handing those facts back.
Above ~150k, or cold with a large context: dispatch a continuation from its
checkpoint note **verbatim**, plus the standard brief. If your own session
crashes, resume that same session — only it can message its agents. **An agent
stalled on something that has not started** (a queued CI run): have it return
with `CI: queued` and own that gate yourself.

**Past your soft ceiling (200k, read with `context-size.py`).** Bring the ledger
fully current, post one handover message and **start no new work** until it is
answered: where the run is, what each in-flight agent waits on, open gates, the
ledger's path, and the choice — a **fresh session** at a wave boundary with
nothing in flight, **compaction** mid-wave (a fresh session cannot message the
old one's agents) — with the literal instruction a fresh session needs. Hard
500k is a stop.

**Budget check.** The spend read (`unattended-run` → "Budget"), between waves
and before each fix round after the first, written into the ledger beside the
wave line. Record the per-project view command (`token_audit.py --view
projects`) in the INTRO before the first wave.

**Unattended mode.** Follow the `unattended-run` skill's "When to stop" and "The
stop" (read them when the operator says "unattended"). Its authority is the
scope's Authority line plus the overlay's gates; an operator-only question parks
that card (`needs-human`, a ledger line, the held list); a design question goes
to the adjudicator. The stop also writes the ledger's RESUME PACKET and runs the
project's handoff wrap; the ledger is pushed only if pushing was granted.

## Briefs

**The specific part** you write (`$SCRATCH/spec-<issue>-<role>.md`): **the
goal line**, the role, ONE issue, binding comments by name, repo and worktree
instructions, the file surfaces to avoid — in parallel mode **the version
constant is one** — and any return fields to add. A reviewer's adds the PR and
the SHAs you resolved, the files, and a turn budget. Never state a number the
agent can measure.
- **Check each return for the bans' trace.** After a card that ran a
  contract-sync tool, check the shared clones with `git -C <clone> status
  --porcelain`; **report a dirty one to the operator, never reset it.**
- **Read little yourself:** a return, a grep of its report, a field-selecting
  one-liner, a file under ~200 lines. A raw tracker view, transcript, diff or
  image goes to a **reader leg** at the cheapest tier returning at most ten
  lines. Before briefing a fix for something *missing* from an output, read
  that one line in full.
- **A return takes two turns**: (1) read it, grep the report for any named
  question, and run the state check the next dispatch depends on; (2) the ledger
  line, the handoff-file edit and the next dispatch, as parallel calls.
- An agent that cannot say what its deliverable moved on the goal line built
  something adjacent: raise scope before the review.
- While one agent runs, write the next specific part.

## Reporting

**Labels and board.** The stage that owns a transition flips its label; the
close step strips every state label (a keyword close skips the stage that
would). Run the project's board-sync tool after every close, if it has one.

**Reports.** One message per issue closed (what merged, what was deferred),
plus a wave summary.

**Progress line**, after each substantial completion (a PR opened, a verdict, a
fix round landed, a merge):

```
**<date and time> - Progress: Exit <met>/<total> · N%**
<one line about what just happened>
```

- The time comes from `date`, run in that same turn. Never reckon it.
- Order: spend read → ledger line (with `context-size.py`'s `current`) → next
  dispatch → **the stamp last; no tool call after it.**
- Exit items come from the milestone's Exit/Measure/Demo line, counted once at
  Phase 0 (no Exit line: the goal line is the one item).
- The percentage is weighted by expected issue cost, fixed at the first report:
  approach 20, fixer 45, review 25, merge 10; an approved PR that cannot merge is
  90%. A correction downward is stated in the line.
