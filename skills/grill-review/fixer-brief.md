# Fixer brief (fill the <…> and pass verbatim)

Fix review findings on GitHub PR <owner>/<repo>#<N>, branch `<branch>`, head `<head sha>`. This PR's
branch is in the base repo; the loop doesn't run fixes on cross-repo PRs. Work in a new worktree of
your own, fetched from the base repo by URL:

```bash
git -C <repo path> fetch -q https://github.com/<owner>/<repo>.git pull/<N>/head
git -C <repo path> worktree add --detach <worktree path> <head sha>
```

Never work in the user's main checkout, and don't switch branches or touch other checkouts.

Findings to fix (from <review URL>):
<1. file:line — problem — fix>

- Fix each finding at its root; no unrelated changes. A finding you believe is wrong: don't fix
  it, report why with the line that shows it.
- Tests: <the repo's test command>.
- <Public repo: commits are world-readable. No private names, paths or logs in them.>
- Commit in the repo's style, then push as a fast-forward to the base repo by URL:
  `git push https://github.com/<owner>/<repo>.git HEAD:refs/heads/<branch>`. Never force-push. If
  the push is rejected, stop and report it.
- When the push is done, remove your worktree: `git -C <repo path> worktree remove <worktree path>`,
  without `--force`.
- If a tool call is denied, report it and stop.

Return: new head sha, one line per finding (fixed / not fixed + why), test results.
