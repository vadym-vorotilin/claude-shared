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

## 3. Branch

In {{WORKSPACE}}, ensure you are on an up-to-date `main` with a clean tree, then
create `{{BRANCH_PREFIX}}<issue#>-<short-slug>`. Never commit to `main`.
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

## 5. Commit & open the PR

Small conventional commits (`fix:`, `test:`). Push the branch and open a PR on the
affected repo with this body:
- `## Finding` — summary + link to the issue (`{{ISSUE_REPO}}#<n>`)
- `## Red tests` — each new test, what it asserts, the captured RED output
- `## Green` — the change that made them pass + the captured full-suite green output
- `## Risk` — blast radius
- `## Deviation from approved approach` — only if you deviated

Then move the issue **{{IN_PROGRESS_STATE}} → {{IN_REVIEW_STATE}}** (adapter "to
in-review") and comment the PR URL on the issue.

## PR review-phase labels

These live on the **PR**, in the affected code repo (`<pr-repo>` — may be a
submodule's own remote), and are independent of the issue's state. All label edits
are best-effort: tolerate a label not existing (log and continue).

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

Merging PRs (`gh pr merge`), pushing to `main`, force-pushing, editing files outside
{{WORKSPACE}}, unrelated refactoring, committing secrets.

## Attribution

When you post a comment, sign it clearly as {{ATTRIBUTION}}. Derive the exact GitHub
login with `gh api user --jq .login` — NEVER guess it or use an OS username; a wrong
@mention pings a stranger.
