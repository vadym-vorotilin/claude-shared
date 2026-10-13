# Schema changes

Read when a card adds or changes a persisted field, a version constant or an
agent-facing record. Moved out of the Phase 1 file because most cards never
need it.

**Schema-change chain** (any ruling that adds/changes a persisted field):
doc amendment PR (orchestrator-merged, paired with the code PR — see
`phase1-loop.md` → Adjudication) → field + version-constant bump → regenerate
generated artifacts (schemas, contracts, pins) → companion PR in each
consuming repo, lockstep → fixtures updated via their regen tool, never by
hand → ordered group merge. Fixtures that snapshot serialized state need a
regen tool committed alongside them or every schema bump breaks them by hand.

**A schema act on an AGENT-FACING record is a prompt change, and it is briefed
as one.** Where a project has records a model reads or writes — a structured
output schema, a tool result the model sees, a captured exchange replayed in
tests — the schema *is* part of the prompt. Two consequences the ordinary chain
does not cover:

- **A field advertised in a model's output schema invites the model to fill
  it.** A field the model is supposed to leave empty does not belong in the
  schema at all; documenting "leave this null" alongside it does not undo the
  invitation, and the model's compliance then varies by tier and by phrasing.
  Remove the field, or accept that it will be populated.
- **Bump such a schema and the captures go stale in a way tests may not
  show.** The re-capture is part of the same card, briefed together with the
  schema change and with the prompt wording it implies — not a follow-up. If
  the project pins freshness by a hash, check that the hash actually moves when
  the pinned input changes: a pin that does not move on an edit pins nothing.

**Serialize schema-version acts; parallel PRs collide on the constant.** Two
approved PRs can both claim the same next version, and a third can follow.
Merge the smaller or further-along first,
have the other rebase and re-run its own regen chain (the tools make that
cheap); the consuming-repo pin moves last. **Declare the version constant a
shared file surface in every parallel-mode brief.**

**Then merge in ASCENDING version order and let the fixers correct themselves.**
Several held versions against a default branch that keeps moving is one
reorder per merge if the orchestrator owns the numbering, and every reorder is
a round trip to a fixer. Instead: merge lowest-claimed-version first so the
constant only ever rises, and give every fixer the standing line **"re-read the
constant on the default branch immediately before you push, and take the next
free number above it only if yours has been passed."** Gaps are usually
harmless — check what the version tests actually assert (a suite may assert
only a monotonicity bound, in which case a skipped version costs nothing), and
renumbering a built PR
down to close a gap re-touches generated fixtures and merged doc text for
cosmetics.

**A merged validator with no live-fixture consumer is unverified in the
pipeline.** A blocking validator can ship inert — an exact check that its own
stage's input never satisfies — and be found only by a later card's fixer
reading neighbour code. When a review notes "zero live fixtures exercise
this," treat end-to-end activation as unproven: **probe the validator through
the real pipeline stage at merge time**, not just at unit level.
