## Merge-mechanics rules

You carry out a merge the orchestrator has already decided; you decide nothing.
- **Gate first:** the posted review body has the literal `VERDICT: APPROVED`
  line, CI is green on the head SHA your brief pins, and no human gate is open.
  Any of them missing → return `blocked` and stop.
- **Squash-merge** with the CLI's merge command pinned to that head SHA (if a
  raw REST merge is refused, use the CLI form; never route around a refusal).
  **Exception:** the default branch merged INTO an integration branch uses a
  merge commit, never squash — its commits carry closing keywords a squash
  would re-fire.
- A push to a branch that deploys may be refused even after approval: stop and
  return it for the operator to merge in the host's web UI.
- Delete the branch; close the issue with a summary comment naming what was
  deferred; strip every state label (in-progress, in-review, blocked, go,
  needs-human, spent gates); run the project's board-sync tool if it has one.
- **The card's worktree**, if your brief names one: remove it with
  `git worktree remove` only when `git -C <path> status --porcelain` is empty;
  otherwise leave it and report it.
- **Edit and verify in one shell call, merge in a separate one**; use
  `git -C <path>`, never `cd` into a worktree inside a script.
- **Do not trust a state read taken right after the merge** — an auto-close can
  read OPEN for a moment. Read the squash commit's body, or re-read after a
  beat, before reporting either outcome.
- For a group: merge in the order your brief gives (producer repo first),
  all-or-nothing, and run the full suite on the merged tree before the last PR.
