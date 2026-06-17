---
name: work-on-gh-issue
description: Implement one approved GitHub issue end-to-end via strict TDD — pick an eligible issue, branch, reproduce it with a failing test, fix to green, run the full suite, open a PR, and shepherd it through review. Use when asked to "work on issue N", "fix issue N", "pick up the next ready issue", or "work the backlog".
---

# work-on-gh-issue — implement one approved issue via TDD

You implement ONE approved issue from `{{ISSUE_REPO}}` and open one PR. The issue is
already triaged and approved (it is in the **{{ELIGIBLE_STATE}}** state); your job is
to implement it well, not to re-decide whether it should be done.

All file changes happen in the workspace: {{WORKSPACE}}

## Invocation

- `work-on-gh-issue <number>` — work that specific issue. If it is not currently in
  the **{{ELIGIBLE_STATE}}** state, say so and ask the user to confirm before
  proceeding.
- `work-on-gh-issue` (bare) — rank the eligible issues (§1), show the list, propose
  the top one, and WAIT for the user to confirm or pick another before starting.

## 1. Select the issue

{{STATE_ADAPTER}}

## 2. Claim it

Once the user confirms an issue, read its full content first (title, body, and ALL
comments — human comments OVERRIDE the body's proposed approach).
{{INTERACTIVE_GUARD}}
Then transition it **{{ELIGIBLE_STATE}} → {{IN_PROGRESS_STATE}}** (adapter "to
in-progress").

## 2a. Existing PRs on this issue (rework — preserve approvals)

Rework happens when an issue is made eligible again while PR(s) from a prior pass are
still open. Before branching, check for them in each repo a fix could live in (the
issue repo and any submodule remotes):
`gh pr list --repo <pr-repo> --state open --search "{{ISSUE_REPO}}#<n> in:body" --json number,title,headRefName,reviewDecision,labels`
(also look for branches matching `{{BRANCH_PREFIX}}<n>-*`).

If any exist, you are ADDING the outstanding delta (per the issue body + human
follow-up comments), NOT redoing the fix:
- Do NOT touch, reword, or re-push an APPROVED PR or its branch.
- Implement ONLY the outstanding work as a NEW sibling PR on a branch
  `{{BRANCH_PREFIX}}<n>-<new-slug>` (a DISTINCT slug, same `<n>-` prefix so the
  siblings group together).
- ADDITIVE ONLY: if the outstanding work would require MODIFYING an already-approved
  PR (rather than a new sibling), STOP — hard-stop (§6) with a reason beginning
  "needs-human:" explaining why.
- NOTHING-TO-DO: if nothing remains beyond what the existing PR(s) already cover, do
  NOT open a PR — hard-stop (§6) with a reason beginning "needs-human: all work
  already covered by existing PR(s) — please review/merge or clarify".

## 3. Branch

In {{WORKSPACE}}, ensure you are on an up-to-date `{{DEFAULT_BRANCH}}` with a clean
tree, then create `{{BRANCH_PREFIX}}<issue#>-<short-slug>`. Never commit to
`{{DEFAULT_BRANCH}}`.
{{SUBMODULE_BRANCH}}

## 4. Implement via strict TDD (non-negotiable)

a. REPRODUCE FIRST. Write the failing test(s) that reproduce the issue and run them
   with {{TEST_CMD}}. {{TEST_ID_CONVENTION}}The test(s) MUST genuinely FAIL against
   the unmodified workspace — that red run IS your reproduction. CAPTURE the failing
   output; you quote it in the PR.
   CANNOT REPRODUCE — HARD STOP: if the test passes on unmodified code, you cannot
   reproduce the finding (already fixed, stale, or an environment artifact). Do NOT
   implement a fix and do NOT open a PR. Move the issue to **{{BLOCKED_STATE}}**
   (adapter "to blocked") with a comment beginning "could not reproduce: ".
b. Implement the MINIMAL fix.
c. Run the same test(s) again — green. CAPTURE the output.
d. Run the FULL relevant suite via {{TEST_CMD}}. ALL green, or hard-stop (§6).

## Pre-PR self-review (before opening the PR)

After the suite is green and committed, review your branch diff with fresh,
skeptical eyes BEFORE opening the PR — this front-loads the hygiene the PR reviewer
would otherwise catch and usually collapses the review loop to a single round. For
true independence, dispatch a SEPARATE read-only review subagent over the diff if you
can; otherwise self-review. Run `git diff {{DEFAULT_BRANCH}}...HEAD` in the affected
repo and check each hunk against this checklist:

- **Tests** — async/UI tests await a real data-dependent element (not a static
  header) before asserting; any mock used to capture output is CONFIGURED (stubbed
  return / callback), not merely invoked; no positional/index selectors.
- **Correctness** — async callbacks in effects check a cancellation/still-mounted
  guard before writing state; `||` vs `??` is right where empty string must fall
  through; fire-and-forget promises have a `.catch()`; the code honors the invariant
  its own adjacent comment states.
- **DRY** — grep for an existing constant/util/mapping before adding a new one.
- **Docs** — comments/docstrings don't over-claim behavior this path doesn't
  guarantee; if you added test IDs, the index/header doc is updated.
- **Conventions** — new tests follow the suite's documented id/location convention.

For each BLOCKING finding, fix it with the SAME red→green TDD discipline (§4), re-run
the FULL suite green, then re-review. Stop once the diff is clean or after **2
rounds**, whichever comes first; carry any leftover suggestions into the PR's
`## Pre-review notes`.

## 5. Commit & open the PR

Small conventional commits (`fix:`, `test:`); keep history readable.

NEVER use a GitHub closing keyword for the issue — none of `close`/`closes`/`closed`,
`fix`/`fixes`/`fixed`, `resolve`/`resolves`/`resolved` followed by `#<n>` or
`{{ISSUE_REPO}}#<n>` — in ANY commit message OR the PR title/body. Merging to
`{{DEFAULT_BRANCH}}` would auto-close the issue and bypass this skill's state
transitions (the issue should land in **{{IN_REVIEW_STATE}}** and let the
merge/deploy process decide its final state). To reference the issue without closing
it, use a bare link or `Refs {{ISSUE_REPO}}#<n>` — no closing verb before it.

Push the branch and open a PR on the affected repo, assigning it to the repo owner so
they find it on their list — `gh pr create --assignee <owner>` (where `<owner>` is the
gh login from Attribution, i.e. `gh api user --jq .login`). PR body:
- `## Finding` — summary + a BARE link to the issue (`{{ISSUE_REPO}}#<n>`; a bare link
  does NOT close — never precede it with a closing verb)
- `## Red tests` — each new test, what it asserts, the captured RED output
- `## Green` — the change that made them pass + the captured full-suite green output
- `## Risk` — blast radius
- `## Pre-review notes` — only if the pre-PR self-review left suggestions or
  unaddressed findings after 2 rounds
- `## Deviation from approved approach` — only if you deviated

If `gh pr create --assignee` didn't take, add it after:
`gh pr edit <n> --repo <pr-repo> --add-assignee <owner>`.

**A fix may span more than one PR** (e.g. a submodule change plus a parent-repo
change). Open each as its own PR (each gets `--assignee <owner>` and the PR-phase
labels below). Only once ALL the PRs for this fix are open do you move the issue
**{{IN_PROGRESS_STATE}} → {{IN_REVIEW_STATE}}** (adapter "to in-review") and comment
each PR URL on the issue.

## PR review-phase labels

These live on the **PR**, in the affected code repo (`<pr-repo>` — may be a
submodule's own remote), and are independent of the issue's state. Apply them to
EVERY PR a fix opens (see the multi-PR note in §5). All label edits are best-effort:
tolerate a label not existing (log and continue).

{{PR_LABELS_BLOCK}}

{{COPILOT_LOOP}}

## 6. Hard stops

If you cannot reproduce the finding (§4a), the full suite will not go green, the fix
needs changes the issue did not approve, or anything is ambiguous: STOP. Push your
branch as-is (work preserved) and move the issue to **{{BLOCKED_STATE}}** with a
comment explaining why (for non-reproduction, begin with "could not reproduce: ").

- **No PR yet** (the common case — stop happened before §5): do NOT open a PR.
- **PR already open** (stop happened during the Copilot loop, so the PR carries
  `{{PR_IN_AUTO_REVIEW_LABEL}}`): the automated loop has given up and a human should
  look — swap the PR labels (best-effort): remove `{{PR_IN_AUTO_REVIEW_LABEL}}`, add
  `{{PR_READY_FOR_HUMAN_LABEL}}` on `<pr-repo>`. Leave the PR open.

## Forbidden

Merging PRs (`gh pr merge`), pushing to `{{DEFAULT_BRANCH}}`, force-pushing, editing
files outside {{WORKSPACE}}, unrelated refactoring, committing secrets.

## Attribution

When you post a comment, sign it clearly as {{ATTRIBUTION}}. Derive the exact GitHub
login with `gh api user --jq .login` — NEVER guess it or use an OS username; a wrong
@mention pings a stranger.
