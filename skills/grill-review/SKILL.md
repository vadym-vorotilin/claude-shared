---
name: grill-review
description: Review a GitHub pull request, fix the findings, and re-review until a fresh reviewer agent is satisfied with the current head. Use when a PR needs review before merge, when asked to "review and fix until satisfied" or "grill-review PR N", or after pushing new commits to a PR that was already reviewed. Posts reviews and pushes fixes to the PR, so read "What this assumes" first.
---

# Grill review — review, fix, re-review until satisfied

A PR is ready for a human merge only when a reviewer agent's **last** review ends with
`VERDICT: SATISFIED` on the PR's **current head**. Any commit after that review (a README tweak, a
regenerated file, a merge of the base branch) needs another round on the delta.

`/review-pr` is one careful review that waits for your go-ahead before it posts. This skill is the
loop: it posts each round and pushes the fixes itself, and asking for it is the go-ahead.

## What this assumes

- `gh` installed and authenticated, with a token that can **write** reviews and push to the PR's
  branch. On a fork PR you can't push to, list the findings and stop after the first review.
- A **GitHub-hosted** PR, and a harness that can dispatch subagents. A review you write yourself
  doesn't count: the reviewer has to be an agent that did not write the code.
- **Scope of the go-ahead:** posting `COMMENT` reviews on this PR and fast-forward pushes to its
  branch. Nothing else: no merge, no force-push, no other branch. If the repo's own instructions
  forbid agents to push, ask first.
- **Reviews are as visible as the PR.** On a public repo, whatever a round posts is public, so keep
  private names, logs and paths out of the review body. Say so in the brief when it applies.

## The loop

1. Record the head: `gh pr view N -R <owner>/<repo> --json headRefOid`. For a delta round, check
   the last reviewed sha is still an ancestor (`git merge-base --is-ancestor <old> <head>`); if it
   isn't (a force-push), review the whole PR again.
2. Dispatch a **reviewer** agent, on the strongest model you have, with `reviewer-brief.md` filled
   in. One review per round, and a fresh agent each round.
3. Read its numbered findings. Every finding is fixed **in this PR**, blocking or not, when the fix
   is cheap. Leave one only if it needs another repo's merged code or the user's call, and state
   the reason in the PR.
4. Fix: small text or code fixes yourself; bigger ones through a **fixer** agent with
   `fixer-brief.md`. Run the repo's tests for code changes. Push a fast-forward commit, never a
   force-push.
5. Re-review the delta (`<reviewed sha>..<new head>`) with a fresh reviewer round. Back to 3.
6. Stop on the two checks below. After **4 rounds** without them (counted since the last
   `SATISFIED`), stop and ask the user, with the open findings listed.

**The verdict.** Read it from GitHub, not from the agent's reply: the last review on the PR must
have `commit_id` equal to the current head and a body whose last line is exactly
`VERDICT: SATISFIED`.

```bash
gh api --paginate repos/<owner>/<repo>/pulls/N/reviews --jq '.[] | {commit_id, submitted_at, body}'
```

**The checks.** `gh pr checks N` must be green. A repo without CI answers "no checks reported":
that isn't a failure, but it is not a pass either, so say in your report that no CI ran.

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
| Post with `gh api repos/<owner>/<repo>/pulls/N/reviews --input review.json` (`event`, `commit_id`, `body`, optional `comments[]`) | The `-f 'comments[][path]=…'` form groups array fields wrong, which is also a 422 |
| `event=COMMENT` | GitHub forbids APPROVE and REQUEST_CHANGES on your own PR, and the verdict line carries the result |
| `commit_id` = the head recorded in step 1 | A review on an old sha anchors comments to the wrong lines |
| Body's last line exactly `VERDICT: SATISFIED` or `VERDICT: CHANGES NEEDED` | The loop keys on it |
| A reviewer near its context limit writes `CHECKPOINT.md` in its folder and stops; a fresh agent finishes from it | A very large PR can exhaust a single reviewer |

## Red flags

- "The change since the satisfied review is only a README / a regenerated file / a merge" → still a
  delta round.
- "Fine as a follow-up" for a cheap finding → fold it in now.
- A reviewer claim you can't reproduce → ask it for the line that proves it; don't fix blind.
