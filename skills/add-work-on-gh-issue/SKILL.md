---
name: add-work-on-gh-issue
description: Install the reusable /work-on-gh-issue skill into another repo, tailored to how that repo tracks issue state. Use when the user says "add /work-on-gh-issue to <repo>", "install the issue-fixer skill", or wants the TDD issue-fixer workflow available in a project.
---

# add-work-on-gh-issue — install a tailored /work-on-gh-issue skill

Installs a project-adapted copy of `/work-on-gh-issue` at
`<target>/.claude/skills/work-on-gh-issue/SKILL.md`. The skill implements one
approved GitHub issue via strict TDD and opens one PR. The source template lives in
this shared repo at `templates/work-on-gh-issue/SKILL.md`.

The one thing that varies by repo is **how issue state is tracked**:
- **labels mode** — state is GitHub issue labels.
- **project mode** — state is a GitHub Projects v2 **Status** field.

The TDD worker is identical either way; only the *state adapter* differs.

## 1. Resolve inputs

- **Target repo** — from the request, else ask. Expand `~`, make absolute. Confirm
  it is a git repo: `git -C "<target>" rev-parse --show-toplevel`.
- **Shared repo** — `SHARED="$(cat ~/.claude/claude-shared-repo 2>/dev/null || echo ~/projects/claude-shared)"`.
  Template at `$SHARED/templates/work-on-gh-issue/SKILL.md`.

## 2. Choose the mode

Ask the user: **labels** or **project**. This selects which state-adapter fill (§5)
you use and which config you gather in §3.

## 3. Inspect the target (the "adapt" step)

Run against the target and show what you find; let the user correct it:
- **Repo root:** `git -C "<target>" rev-parse --show-toplevel`.
- **Default branch** (NOT the currently checked-out branch — the user may be on a
  feature branch during install): `git -C "<target>" symbolic-ref --quiet --short refs/remotes/origin/HEAD | sed 's@^origin/@@'`, falling back to `gh repo view <owner/repo> --json defaultBranchRef --jq .defaultBranchRef.name`, else `main`. Fills `{{DEFAULT_BRANCH}}`.
- **Submodules:** `git -C "<target>" submodule status` (capture paths, if any).
- **Test command:** how the project self-checks — `run-*-tests.sh`, `package.json` `scripts.test`, a `Makefile` `test` target, a project test skill, etc. Record it, or conclude there's none (and warn: the mandatory TDD gate needs a test runner).
- **Copilot reviewer:** is `copilot-pull-request-reviewer` configured? (Ask; default the loop OFF if unknown.)

## 4. Gather config

**Mode config:**
- *labels:* issue repo (default the `origin` `owner/repo`); the four state-label
  names (defaults `go` / `in-progress` / `in-review` / `blocked`); offer to create
  any missing with the label-create block (§6); optional ordered priority labels.
- *project:* `{{PROJECT_NUMBER}}` + `{{PROJECT_OWNER}}`; the Status field name; the
  four option names; optional Priority field name + ordered option names. Resolve ids
  with `gh project field-list <number> --owner <owner> --format json` and fill
  `{{PROJECT_ID}}`, `{{STATUS_FIELD_ID}}`, `{{IN_PROGRESS_OPTION_ID}}`,
  `{{IN_REVIEW_OPTION_ID}}`, `{{BLOCKED_OPTION_ID}}`, and (if used) the Priority field
  id + ordered option ids.

**Shared config:**
- `{{ISSUE_REPO}}` = `owner/repo`.
- `{{WORKSPACE}}` = `the current checkout (the repo you run this skill in)` by
  default; or, if the user wants isolation, a configured path with a refresh note.
- `{{TEST_CMD}}` = the detected command; `{{TEST_ID_CONVENTION}}` = a sentence about
  the repo's test-ID scheme **ending with a trailing space** (it is concatenated
  directly before "The test(s) MUST…", so the trailing space keeps the spacing
  clean), or the empty string.
- `{{DEFAULT_BRANCH}}` = the repo's default branch from §3 (e.g. `main`).
- `{{BRANCH_PREFIX}}` = default `fix/`.
- `{{ATTRIBUTION}}` = a role label, default
  `an automated fixer acting on behalf of @<owner-login>`.
- `{{PRIORITY_ORDER}}` = a JSON array of priority labels/options highest→lowest, or
  `[]`.
- `{{PR_IN_AUTO_REVIEW_LABEL}}` = default `in-auto-review`;
  `{{PR_READY_FOR_HUMAN_LABEL}}` = default `ready-for-human`.
- **Interactive guard (optional):** ask for a label that marks issues too complex to
  auto-fix (need human brainstorm→plan), default none. This fills
  `{{INTERACTIVE_GUARD}}` (§6).

## 5. Fill the state adapter

Use exactly one of the two blocks below for `{{STATE_ADAPTER}}`.

### State adapter — labels mode

Substitute `{{STATE_ADAPTER}}` with the assembled section below, filling the four
state names and `{{PRIORITY_ORDER}}` (a JSON array, default `[]`). `{{ISSUE_REPO}}` is
filled by the shared-config pass.

> Notation: `{{…}}` = install-time fill (must be gone after install — the scan
> enforces it). Lowercase `<…>` (e.g. `<n>`, `<short-slug>`) = runtime placeholders
> the worker fills as it runs; they intentionally REMAIN in the installed file.

Selection: fetch eligible issues with
`gh issue list --repo {{ISSUE_REPO}} --state open --label {{ELIGIBLE_STATE}} --json number,title,labels --limit 100`
and pipe that JSON array into this ranking jq (drops `{{BLOCKED_STATE}}`, orders by
priority then age):

```bash
# Reads the gh issue-list JSON array on stdin; prints "<number>\t<title>"
# ranked by priority then age (oldest-first within a priority bucket).
jq -r --argjson prio '{{PRIORITY_ORDER}}' '
  map(select(([.labels[].name] | index("{{BLOCKED_STATE}}")) | not))
  | map(.prank = (([.labels[].name]) as $l
      | ([range(0; ($prio|length)) | . as $i | select($l | index($prio[$i]) != null)][0]) // ($prio|length)))
  | sort_by(.prank, .number)[]
  | "\(.number)\t\(.title)"'
```

Adapter operations (run as the worker reaches each milestone):
- to in-progress: `gh issue edit <n> --repo {{ISSUE_REPO}} --remove-label {{ELIGIBLE_STATE}} --add-label {{IN_PROGRESS_STATE}}`
- to in-review:   `gh issue edit <n> --repo {{ISSUE_REPO}} --remove-label {{IN_PROGRESS_STATE}} --add-label {{IN_REVIEW_STATE}}`
- to blocked:     `gh issue edit <n> --repo {{ISSUE_REPO}} --remove-label {{IN_PROGRESS_STATE}} --add-label {{BLOCKED_STATE}}`
- read content:   `gh issue view <n> --repo {{ISSUE_REPO}} --json number,title,body,comments`
- comment:        `gh issue comment <n> --repo {{ISSUE_REPO}} --body "..."`

### State adapter — project mode

Substitute `{{STATE_ADAPTER}}` with the assembled section below. All `{{…}}` are
install-time fills: `{{PROJECT_NUMBER}}`, `{{PROJECT_OWNER}}`, the resolved
`{{PROJECT_ID}}` / `{{STATUS_FIELD_ID}}` / `{{IN_PROGRESS_OPTION_ID}}` /
`{{IN_REVIEW_OPTION_ID}}` / `{{BLOCKED_OPTION_ID}}`, and `{{ISSUE_REPO}}`.
`{{PRIORITY_ORDER}}` is the JSON array of Priority option names highest→lowest,
default `[]`. Lowercase `<…>` are runtime placeholders that REMAIN.

Selection: fetch items with
`gh project item-list {{PROJECT_NUMBER}} --owner {{PROJECT_OWNER}} --format json --limit 100`
and pipe into this ranking jq (keeps Status == `{{ELIGIBLE_STATE}}`, drops
`{{BLOCKED_STATE}}`, orders by priority then issue number):

```bash
# Reads `gh project item-list --format json` on stdin; prints "<number>\t<title>".
jq -r --argjson prio '{{PRIORITY_ORDER}}' '
  .items
  | map(select(.status == "{{ELIGIBLE_STATE}}" and .status != "{{BLOCKED_STATE}}"))
  | map(.prank = ((.priority // "") as $p | ($prio | index($p)) // ($prio|length)))
  | sort_by(.prank, .content.number)[]
  | "\(.content.number)\t\(.title)"'
```

Adapter operations (set Status via GraphQL; read/comment on the linked issue). Get an
item's `<itemId>` by matching `.content.number` in the `item-list` JSON. Pick `<o>`
from `{{IN_PROGRESS_OPTION_ID}}` / `{{IN_REVIEW_OPTION_ID}}` / `{{BLOCKED_OPTION_ID}}`
for the target state:
- set status: `gh api graphql -f query='mutation($p:ID!,$i:ID!,$f:ID!,$o:String!){updateProjectV2ItemFieldValue(input:{projectId:$p,itemId:$i,fieldId:$f,value:{singleSelectOptionId:$o}}){projectV2Item{id}}}' -f p={{PROJECT_ID}} -f i=<itemId> -f f={{STATUS_FIELD_ID}} -f o=<o>`
- read content: `gh issue view <n> --repo {{ISSUE_REPO}} --json number,title,body,comments`
- comment:      `gh issue comment <n> --repo {{ISSUE_REPO}} --body "..."`

## 6. Fill the cross-cutting blocks

**`{{SUBMODULE_BRANCH}}`** — if the repo has submodules, fill with: ` Identify the
affected repo (a submodule or the parent). Submodules start in detached HEAD at the
parent's pinned commit — run \`git checkout main && git pull\` INSIDE the submodule
before branching, work and push ONLY in the submodule, and do NOT bump the parent
pointer (the human does that at merge time). For a PARENT-repo fix, stage ONLY the
files you changed by explicit path (never \`git add -A\` / \`git add .\`) — the
submodules sit at moved commits, so a blanket add would sweep a submodule-pointer bump
into your PR.` — else empty string.

**`{{INTERACTIVE_GUARD}}`** — if an interactive-guard label was configured, fill with
(substituting the label name): `\n- INTERACTIVE GUARD: if the issue carries the
\`<label>\` label, it is too complex to fix in this focused TDD flow — it needs
brainstorming and a plan first. Do NOT proceed to reproduce/fix. Tell the user and
offer to switch to the brainstorming skill (then writing-plans) instead; leave the
issue in **{{ELIGIBLE_STATE}}**.\n` — else empty string.

**`{{COPILOT_LOOP}}`** — if the Copilot loop is enabled, fill with a `## Copilot
review loop` section. The pre-PR self-review (worker §"Pre-PR self-review")
front-loads the hygiene Copilot used to catch, so wave 1 is usually clean and a 3rd
wave reliably finds nothing — cap at 2. Key discipline (a real bug came from getting
this wrong):
- WAIT by ACTIVELY POLLING IN-SESSION — a blocking loop you run right now: repeat up
  to ~20 times: `sleep 30`, then `gh pr view <n> --repo <pr-repo> --json reviews`;
  break as soon as a Copilot review with `submittedAt` newer than the head commit
  appears. If ~10 min elapse with no new review, note the timeout in a PR comment and
  exit the loop (treat as "done"). NEVER end your turn to "wait for a notification" —
  if you stop, the loop is abandoned and the PR is left unfinished.
- ADDRESS every comment with the SAME red→green TDD → reply signed per Attribution and
  resolve the thread. REST cannot resolve threads; use GraphQL — get the thread id
  from `gh api graphql -f query='{repository(owner:"<owner>",name:"<repo>"){pullRequest(number:<n>){reviewThreads(first:50){nodes{id isResolved comments(first:1){nodes{body}}}}}}}'`
  then `gh api graphql -f query='mutation($t:ID!){resolveReviewThread(input:{threadId:$t}){thread{id}}}' -f t=<thread-id>`.
- RE-REQUEST review (a push does NOT auto-trigger it): `gh api --method POST
  repos/<owner>/<repo>/pulls/<n>/requested_reviewers -f
  'reviewers[]=copilot-pull-request-reviewer[bot]'` (the `[bot]` suffix is required).
  Throughout this loop, `<owner>`/`<repo>` are the two halves of `<pr-repo>`.
- Repeat, ≤2 rounds. STOP on no actionable comments, after 2 rounds, OR on the poll
  timeout; note any still-open point for the human. On exit, do the
  `{{PR_LABELS_BLOCK}}` "loop exit" swap.
— else empty string.

**`{{PR_LABELS_BLOCK}}`** — fill with (all edits best-effort, tolerate a missing
label):
- **loop enabled:** `Immediately after \`gh pr create\` succeeds, mark the PR in the
  automated loop: \`gh pr edit <n> --repo <pr-repo> --add-label {{PR_IN_AUTO_REVIEW_LABEL}}\`.
  On Copilot-loop exit (no actionable comments, 3 rounds, or poll timeout) — and also
  on any hard stop that happens while the PR is already open (§6) — swap it:
  \`gh pr edit <n> --repo <pr-repo> --remove-label {{PR_IN_AUTO_REVIEW_LABEL}} --add-label {{PR_READY_FOR_HUMAN_LABEL}}\`.`
- **loop disabled:** `Immediately after \`gh pr create\` succeeds, mark it ready for
  human review: \`gh pr edit <n> --repo <pr-repo> --add-label {{PR_READY_FOR_HUMAN_LABEL}}\`.`

Offer to create the PR-phase labels (`{{PR_READY_FOR_HUMAN_LABEL}}` always;
`{{PR_IN_AUTO_REVIEW_LABEL}}` only if the loop is enabled) on the PR repo(s) with the
label-create block below.

### Label-create helper (idempotent; per repo)

```bash
# Create a label if absent (gh exits non-zero if it already exists — ignore that).
for lbl in "$@"; do
  gh label create "$lbl" --repo "$LABEL_REPO" >/dev/null 2>&1 || true
done
```

## 7. Write it

```bash
mkdir -p "<target>/.claude/skills/work-on-gh-issue"
```
Write the filled template to `<target>/.claude/skills/work-on-gh-issue/SKILL.md`.

After substituting, run the placeholder scan below — it must **FAIL if any placeholder survived** — and fix anything it flags:

```bash
# Only install-time tokens use the {{UPPER_SNAKE}} form, so that is all we scan for.
# Lowercase <runtime> placeholders (e.g. <n>, <short-slug>, <pr-repo>) are INTENTIONAL
# in the installed worker — do NOT flag them.
if grep -RnE '\{\{[A-Z_]+\}\}' "$DEST"; then
  echo "leftover placeholder(s) above — fix before finishing"; exit 1
fi
```
(`DEST` = the directory you wrote the SKILL.md into.)

## 8. Report

Tell the user: where it was written; the mode + config summary (state names,
priority, test cmd, workspace, Copilot loop on/off, PR labels); that
`/work-on-gh-issue` is available after restarting Claude Code there; that `gh` must be
authenticated (project mode also needs the `project` scope); and to **commit**
`.claude/skills/work-on-gh-issue/SKILL.md`. No `SessionStart` hook is added — this
skill is on-demand.
