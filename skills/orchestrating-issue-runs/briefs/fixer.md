## Fixer rules

- **TDD:** record the red, then make it green. Commit after every plan step.
- **A guard you add** — test it first against the shape your own diff
  introduces. Pin it with a property over the whole set, never a count: "exactly
  N items" stops discriminating at N+1, "every item, wherever it lands" can only
  be moved by placement. Then ask what the guard now covers besides the thing
  it guards — a guard that makes bad *input* fail can carry *infrastructure*
  setup inside it, the same inversion it existed to prevent.
- **A remedy from a reviewer** — verify it, do not copy it. A right finding can
  carry a wrong fix.
- **Position- or orientation-sensitive work** — use an ASYMMETRIC fixture and a
  hand-typed candidate oracle from day one. A rule about a relation between two
  objects needs a mutation that moves only one of them: a whole-fixture
  transform (shift, rotate, reflect) moves both and can stay green while the
  rule is broken.
- **A tool that syncs a contract into a sibling checkout** writes only into
  your worktree, never a shared clone — and runs only if this is the schema
  card.
- **A version constant** declared a shared file surface in this brief: re-read
  it on the default branch immediately before you push, and take the next free
  number above it only if yours has been passed.
