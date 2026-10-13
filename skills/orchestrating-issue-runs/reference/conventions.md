# Fixer-authored conventions and infeasible rules

Read when a fixer authored a convention the spec is silent on, or reports a
requested design as infeasible. Moved out of the Phase 1 file because most
cards never need it.

**Fixer-authored conventions.** When a spec is silent a fixer will author a
convention (which side a default falls on, where an annotation anchors, how a
zero case renders). Treat each as a design act: a narrow, tightly-scoped
adjudication either ratifies, relocates or replaces it; do not block on it and
do not let it merge un-ruled.

**When leave-one-out names a RULE as the conflict, the menu always includes
DEMOTING it.** The two obvious options — amend the rule's numbers, or re-author
the inputs until they satisfy it — both preserve the rule's *tier*, and the
tier is usually the thing that is wrong. A rule can go hard → soft (a weighted
objective, satisfied where it can be), or soft → advisory (a note on the
output, checked by nobody). Demotion is often the cheapest correct answer and
it is the one nobody proposes, because a rule that is written down reads as a
requirement.

Two things make it a discipline rather than a licence:

- **Where the spec states its own cutting order, quote it.** Specs written by
  people who expected this often say what to cut first, in a risk or recovery
  section, and then nobody reads that section under pressure. Quote the order
  into the menu and the operator is choosing within their own plan, not
  against it.
- **A rule kept at a tier the system cannot satisfy is worse than a demoted
  one.** A specified, tested constraint that is never enforced because
  enforcing it makes the reference inputs infeasible is a rule the system
  does not check while the spec says it does. That gap is exactly the failure
  the rule existed to prevent, reintroduced by its own tier.

So the menu the operator gets is: **demote / amend / re-author / park
disabled**, each with a measured, rendered result where the domain has an
artifact to render — never one option, and never the strictest formulation
alone.

**When the named conflict is structural, a further option is to ship the rule
complete but disabled.** Leave-one-out (SKILL.md's rule) sometimes names no
defective rule and no defective design: a specified constraint can be
unsatisfiable against the project's frozen acceptance inputs, because it and
two sibling constraints are each individually valid and jointly unsatisfiable.
Amending the constraint inside a fixer's diff would be a spec change made by an
implementer; re-authoring those inputs to fit is worse.
What ships is the constraint **complete and fully tested, with its
enforcement disabled** — honest only under three
conditions: the infeasibility is **measured** (the core named by leave-one-out,
not asserted), the PR states the exit clause is not met rather than pretending
it is, and a committed test **re-derives the infeasible core every run** so the
card reds the day those inputs move and the rule can be enabled.
The reviewer's job on such a PR is to prove that guard fires, by mutating those
inputs until the infeasible core dissolves. Put the
amend / re-author / park-disabled choice to the operator as a question, and
ship the defensible option meanwhile rather than stalling on it.

**Retried captures** (only where the project captures live external output and
replays it in tests). Re-capturing until a capture is usable and keeping the
last one is disclosed, not cherry-picked — and only when every discard was for
validity. Discarding on content the brief never pinned is a selection the
operator rules on; the capture's provenance carries an attempt count. Route it
to the deferred register, not to the reviewer.
