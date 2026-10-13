# Phase 2 — wrap, and the skill's self-improvement

Orchestrator-only rules. The wrap agents' instructions are `briefs/wrap.md`;
the reasoning is in `reference/full/phase2-wrap.md`.

## The wrap, in this order

1. **Demo capture** (`wrap` block, demo role). Name in the brief which pages
   depend on any still-open card. Before a page goes to the operator, read its
   claims against this run's measurements and rewrite any you cannot trace.
2. **Walkthrough** (`wrap` block, walkthrough role; top standard tier, not the
   reviewer role): point it at the project's own rubric and name every
   variable the tool chain writes to, so its environment is fully isolated.
3. **Demo document** from the capture log's captions, walkthrough findings named
   as known gaps, delivered, and released the way the run's memory says (Phase
   0's demo question). Put it somewhere durable.
4. **Close the milestone** — only the one this run owns: read it back first and
   close it only if its open count is zero.
5. **Deferred register → operator ruling → filing; never agent → filing.** A
   register agent (`wrap` block) returns the folded, grouped list; you add
   **filed-to-merged against the filing budget** and a recommendation per group
   — fold most, file few; two runs in a row above 1 means the register is
   generating work. **The operator rules**; only then does a filing agent
   file. What the operator defers carries into the next run's Phase 0.
6. **Board-consistency sweep**, always, as the run's last board action, after
   filing.
7. **Run summary**, memory update, ledger closed, and **the next session's first
   brief finished, no placeholder left**, named in the INTRO.

**Quota wind-down** (the operator calls it). Start no new card. In-flight agents
finish; each open PR gets at most one more review round, then merges or parks
green with its rebase facts on the issue. A card whose only red is a defect it
exposed files that defect as its gate, is labelled `blocked`, and parks. The
demo publishes as a **pre-release**, previews from parked PRs labelled as such;
the milestone stays open. The register becomes the next session's first act.
Then memory, the ledger's pause state, skill lessons.

## Self-improvement (mandatory at the wrap)

1. **The rule goes in this skill; the evidence stays private.** Issue numbers,
   file names, counts and costs go in a lessons file in the project's own repo.
2. **Promote a lesson into an instruction** — a phase rule, a brief block, a red
   flag — or it will not fire. A rule an agent follows goes in its `briefs/`
   block, in its voice, with the reason in `reference/why-briefs.md`.
3. **Re-test changed guidance** with a cheap scenario pair before committing.
   **Every rule added retires or merges one**; a reversed rule stays as a dated
   "retired" paragraph. The orchestrator's read budget is enforced by a test —
   a rule that does not fit replaces one that does.
4. **Commit; never push a shared or public repo without asking** — check its
   visibility first and have the diff reviewed for project detail.
5. **Measure the run against the last one** with `/token-report` over its window:
   total, sidechain share, spend above 200k context, per-agent peaks, plus
   **Exit items met / total**, **filed-to-merged** and **rulings per merged
   card**. Write them into the private lessons file next to the previous run's.
   A cost rule the numbers say did not work is reverted in the same wrap.
