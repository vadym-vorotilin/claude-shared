# Fixer brief (fill the <…> and pass verbatim)

Fix review findings on GitHub PR <owner>/<repo>#<N>, branch `<branch>`, in a new worktree of your
own: `git -C <repo path> fetch -q origin <branch>`, then
`git -C <repo path> worktree add --detach <worktree path> origin/<branch>`. Never work in the user's
main checkout, and don't switch branches or touch other checkouts.

Findings to fix (from <review URL>):
<1. file:line — problem — fix>

- Fix each finding at its root; no unrelated changes. A finding you believe is wrong: don't fix
  it, report why with the line that shows it.
- Tests: <the repo's test command>.
- Commit in the repo's style, then push as a fast-forward: `git push origin HEAD:<branch>`. Never
  force-push. If the push is rejected, stop and report it.
- If a tool call is denied, report it and stop.

Return: new head sha, one line per finding (fixed / not fixed + why), test results.
