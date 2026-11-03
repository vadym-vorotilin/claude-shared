---
name: grill-review
description: Review a GitHub pull request, fix the findings, and re-review until a fresh reviewer agent is satisfied with the current head. Use only when the user asks for this loop by name ("grill-review PR N") or asks to "review and fix until satisfied". For one review with no fixes, use /review-pr. Posts reviews and pushes fixes to the PR, so read "What this assumes" first.
---

# Grill review — review, fix, re-review until satisfied

A PR is ready for a human merge only when a reviewer agent's **last** review ends with
`VERDICT: SATISFIED` on the PR's **current head**. Any commit after that review (a README tweak, a
regenerated file, a merge of the base branch) needs another round on the delta.

`/review-pr` is one careful review that waits for your go-ahead before it posts. This skill is the
loop: it posts each round and pushes the fixes itself. The go-ahead is the user asking for this
loop on this PR. If the user did not, ask before the first post.

## What this assumes

- `gh` installed and authenticated, with a token that can **write** reviews and push to the PR's
  branch, and git set up to use it for HTTPS (`gh auth setup-git`).
- A **GitHub-hosted** PR, and a harness that can dispatch subagents. A review you write yourself
  doesn't count: the reviewer has to be an agent that did not write the code.
- A local clone of the repo. Any remote layout works, because everything is fetched from the base
  repo by URL, not from `origin`.
- A scratch folder outside the repo, for review files. `<scratch>` below means that folder.
- **Cross-repo PRs (forks) get one review and no fixes.** Run steps 1 and 2, report the findings,
  and stop: the loop never pushes to a fork, and a branch of the same name in the base repo is a
  different branch.
- **Scope of the go-ahead, all on this PR only:** `COMMENT` reviews, fast-forward pushes to its
  branch, and a comment or body edit that records a finding left on purpose. Merging only if the
  user said "merge when ready" for this PR. No force-push and no other branch. If the repo's own
  instructions forbid agents to push, ask first.
- **Reviews and commits are as visible as the PR.** On a public repo, keep private names, logs and
  paths out of what you post and commit. Say so in the briefs when it applies.

## The loop

1. Record the facts: `gh pr view N -R <owner>/<repo> --json
   state,headRefOid,headRefName,baseRefName,isCrossRepository`. If `state` isn't `OPEN`, stop and
   say so. For a delta round, check the last reviewed sha is still an ancestor (`git merge-base --is-ancestor <old> <head>`). If it isn't (a
   force-push), or git can't find the sha, review the whole PR again.
2. Dispatch a **reviewer** agent, on the strongest model you have, with `reviewer-brief.md` filled
   in. One review per round, and a fresh agent each round.
3. Read its numbered findings. No findings means step 6. Otherwise every finding is fixed **in this
   PR**, blocking or not, when the fix is cheap.
   - A finding that needs the user's call, or isn't cheap to fix, ends the loop: stop and ask, with
     the findings listed.
   - A finding that needs another repo's merged code, or that you can show is wrong with the line
     that proves it, is left. Record it and why in a PR comment, and list it in the next reviewer's
     brief.
4. Fix: small text or code fixes yourself, in a worktree as `fixer-brief.md` describes, never in the
   user's checkout; bigger ones through a **fixer** agent with that brief. Run the repo's tests for
   code changes. Push a fast-forward commit, never a force-push.
5. Run a fresh reviewer round on the delta (`<reviewed sha>..<new head>`), or on the same head if the
   only change is a finding left on purpose. Back to 3.
6. Finish when the verdict below passes and the checks below are done. If the verdict doesn't pass
   (the head moved, or no review landed), go back to step 1. After **4 rounds** without finishing
   (counted since the last `SATISFIED`), stop and ask the user, with the open findings listed.

**The verdict.** Read it from GitHub, not from the agent's reply. Re-read the head first, because it
may have moved. Only reviews by the login that runs this loop count toward the verdict. The last
counted review must have `commit_id` equal to the current head and a body whose last line is exactly
`VERDICT: SATISFIED`. Report anyone else's reviews, including a bot's, and ask before merging if any
author's latest review other than a `COMMENTED` one is `CHANGES_REQUESTED`, unless it was dismissed.
A later comment doesn't withdraw a change request.

```bash
gh pr view N -R <owner>/<repo> --json headRefOid --jq .headRefOid
login="$(gh api user --jq .login)"
gh api --paginate repos/<owner>/<repo>/pulls/N/reviews \
  --jq ".[] | select(.user.login == \"$login\") | {commit_id, submitted_at, body}"
gh api --paginate repos/<owner>/<repo>/pulls/N/reviews \
  --jq ".[] | select(.user.login != \"$login\") | {author: .user.login, state, commit_id, submitted_at}"
```

**The checks.** Poll them in a bounded loop, not with `--watch`, which has no timeout. This one takes
at most 30 minutes, so run it as a background command if your harness limits foreground ones. `gh`
exits 8 while checks are pending.

```bash
for _ in $(seq 1 60); do
  out="$(gh pr checks N -R <owner>/<repo> 2>&1)"; rc=$?
  [ "$rc" -eq 8 ] || break
  sleep 30
done
printf '%s\nexit %s\n' "$out" "$rc"
```

- Exit 0: the checks are done.
- Exit 8: still pending after 30 minutes. Report that and stop.
- Any other exit, read the output. A failed check is a finding: back to step 4.
- "No checks reported" straight after a push may mean CI hasn't started, so run it again after a
  minute. If that repeats, the repo has no CI. The loop can finish, but say in your report that no CI
  ran, so nobody reads it as a pass.

Merging is the user's call unless they said "merge when ready" for this PR, which means merge after
`SATISFIED` on the head, not before. The user being in a hurry, or "it's reviewed already", never
skips a round: say what changed since the review and that the delta round is running.

**Delta that contains a merge of the base branch:** the reviewer reviews only this PR's own changes
and the conflict resolutions, not the base branch's PRs, which had their own review. Give it the
scope in the brief: `git log --first-parent <old>..<head>` lists the PR's own commits, and
`git show --cc <merge sha>` shows how conflicts were resolved.

## Posting rules

| Rule | Why |
|---|---|
| A **new, empty scratch folder per round** for the body and JSON: `<scratch>/review-<repo>-<N>-r<round>`, with a `-b`, `-c` suffix on a retry; never reuse one | An agent can pick up an earlier round's `review.json`, and GitHub answers 422 with nothing posted |
| Post with `gh api repos/<owner>/<repo>/pulls/N/reviews --input <absolute path>/review.json` (`event`, `commit_id`, `body`, optional `comments[]`) | A file is checkable before the post, and a relative path can post a stale one. Long bodies and array fields go wrong through `-f` flags in some `gh` versions |
| `event=COMMENT` | GitHub forbids APPROVE and REQUEST_CHANGES on your own PR, and the verdict line carries the result |
| `commit_id` = the head recorded in step 1 | A review on an old sha anchors comments to the wrong lines |
| Body's last line exactly `VERDICT: SATISFIED` or `VERDICT: CHANGES NEEDED` | The loop keys on it |
| A reviewer near its context limit writes `CHECKPOINT.md` in its folder and stops; a fresh agent finishes from it | A very large PR can exhaust a single reviewer |

## Red flags

- "The change since the satisfied review is only a README / a regenerated file / a merge" → still a
  delta round.
- "Fine as a follow-up" for a cheap finding → fold it in now.
- A reviewer claim you can't reproduce → ask it for the line that proves it; don't fix blind.
