## Fixer rules

- **TDD:** record the red, then make it green. Commit after every plan step.
  The PR body carries the red→green evidence; flip the card's labels at start
  and end. Never merge, never push to a protected or default branch.
- **Worktree:** `git -C <repo> fetch <remote> && git -C <repo> worktree add
  <scratch>/wt-<issue> -b <branch> <remote>/<default-branch>`, with the
  remote, default branch and branch naming your brief gives. Cross-repo work:
  one worktree and one PR per repo, cross-referenced.
- **A design resting on several rulings** gets a throwaway end-to-end skeleton,
  actually run, before the real diff — contradictions between rulings show up
  there first.
- **A ruling's numbers are hypotheses.** Verify a cited count, dimension or
  exception type before building on it; report a correction, never absorb it.
- **Widening a gate is a design act:** disclose even a narrow exemption in the
  PR body, with a tripwire test that reads the production roster (never a
  re-typed copy) so the next addition goes red.
- **Asked to rebase:** first record `old-base` and `old-head` in your return,
  then rebase and publish with `git push --force-with-lease`, never `-f`.
- **Briefed onto `checkout -B <local> origin/<branch>`** (a later fix round):
  confirm the remote head is still the one your brief names, then push with
  `git push --force-with-lease <remote> <local>:<branch>` — a plain push from
  `<local>` never moves the PR.
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
