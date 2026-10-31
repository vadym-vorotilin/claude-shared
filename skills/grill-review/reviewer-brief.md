# Reviewer brief (fill the <…> and pass verbatim)

Review GitHub PR <owner>/<repo>#<N> "<title>". <One line on what the project is, if it helps.>

- Scope: <full PR | only the delta <old sha>..<new sha>; earlier rounds covered the rest at <old sha>>.
- Head: `<head sha>`. Spec: the linked issue(s) <#…> and any design or plan doc they link; the PR
  body; the repo's own instructions (CLAUDE.md, AGENTS.md, CONTRIBUTING).
- Read the code without touching any checkout. Fetch from the base repo by URL:
  ```bash
  git -C <repo path> fetch -q https://github.com/<owner>/<repo>.git <base branch>
  git -C <repo path> rev-parse FETCH_HEAD    # the base sha: note it
  git -C <repo path> fetch -q https://github.com/<owner>/<repo>.git pull/<N>/head
  git -C <repo path> rev-parse FETCH_HEAD    # must print <head sha>
  ```
  If the last line isn't `<head sha>`, the PR moved: stop and report it. From here on use literal
  shas, not shell variables, which don't survive between tool calls and fail silently when empty:
  `git -C <repo path> show <head sha>:<path>`, and `git -C <repo path> diff <base sha>...<head sha>`
  for a full PR or `git -C <repo path> diff <old sha> <head sha>` for a delta.
- <Delta round with a merge of the base branch: review only `git log --first-parent <old>..<head>`
  commits other than the merge, plus the merge's conflict resolutions (`git show --cc <merge sha>`).
  The base branch's own changes are out of scope.>
- <Public repo: this review is world-readable. No private names, paths or logs in it.>
- Verify: does it do what the issue says; is it actually wired up (registrations, config, serialized
  references, generated files); dangling references after deletions; tests cover the change; docs
  claims match the code and the git/GitHub facts (tags, merge commits, versions); committed binaries
  or generated files come from the source they claim.
- Skip pure style nits. Every finding names a concrete failure scenario and the line proving it.
- <Previous findings to confirm fixed: 1. … 2. …>  (re-review rounds only)
- <Findings left on purpose, with reasons: 1. … Don't raise these again unless the reason is wrong.>

Post ONE review: build `review.json` with `event: "COMMENT"`, `commit_id: "<head sha>"`, `body`,
and inline `comments` only on lines in the diff, in a NEW empty folder
`<scratch>/review-<repo>-<N>-r<round>/` (exists already → add `-b`). Post with
`gh api repos/<owner>/<repo>/pulls/<N>/reviews --input <that folder's absolute path>/review.json --jq '.html_url // .message'`.
Body: what the PR does, what you verified, findings most-severe first (numbered,
`file:line — problem — fix`), and as its LAST line exactly `VERDICT: SATISFIED` or
`VERDICT: CHANGES NEEDED` (cheap non-blocking fixes count as CHANGES NEEDED; findings left on purpose
don't).

If a tool call is denied, report it and stop. If your context runs long, write CHECKPOINT.md in the
folder (what's verified, what's left) and stop. Return: review URL, head sha, verdict, findings.
