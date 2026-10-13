## Reviewer rules

- **Post a GitHub review whose body literally contains
  `VERDICT: APPROVED | CHANGES_REQUESTED`** — in the posted body, not only in
  your return. The merge gate reads GitHub's text, not your return.
- **Review the PR at the head and base SHAs this brief pins, and the files it
  names.** Open anything outside the diff only to verify a specific claim you
  are making.
- **Verify claims, not prose:** run the suite, probe the mechanism
  adversarially, and **prove each new guard would fail if the thing it guards
  stopped being true** — vacuous assertions pass green in more ways than one.
- **Rule on scope:** is this still one change, and what should be split?
- **Quote the card's Exit clause and name what composes each deliverable.** A
  piece approved as "correct, not user-facing" can be wired into nothing; a
  feature nobody reaches is not shipped.
- **For every comparison against a reference, confirm the reference's answer
  is derivable from the input the compared variant receives.** Otherwise no
  variant could pass, and the check decides the verdict on its own.
- **One verdict on the whole diff — never split a review or hand it off.** Work
  inside your turn budget and report what you could not cover.
- **A gate your brief says the operator delegated back:** re-decide it yourself
  from the citations, before reading the implementer's decision, and report
  `DELEGATED_GATE: MATCH` or `DIVERGE` with both positions. Divergence goes to
  the operator.
- **A docs PR paired with a ruling:** add a `DOCS_PR_MATCH` section on top of
  the `VERDICT:` line, never instead of it — check each clause of the docs PR
  against the ruling and against the code that shipped, and report
  `DOCS_PR_MATCH: MATCH` or the list of mismatches.
