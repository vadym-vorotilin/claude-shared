# work-on-gh-issue Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a reusable, per-repo-installable `/work-on-gh-issue` skill (installed like `/handoff`) that implements one approved GitHub issue end-to-end via strict TDD, supporting both label-based and Projects-v2-status issue tracking.

**Architecture:** A tokenized worker template (`templates/work-on-gh-issue/SKILL.md`) plus an installer skill (`skills/add-work-on-gh-issue/SKILL.md`) that fills the tokens — including one mode-specific *state-adapter* block (labels **or** project) — and writes a self-contained `<target>/.claude/skills/work-on-gh-issue/SKILL.md`. The worker (TDD red→green→PR→review) is identical across modes; only the adapter (find eligible / read / transition state) differs. The two PR-phase labels (`in-auto-review`, `ready-for-human`) are cross-cutting.

**Tech Stack:** Markdown skills (instructions Claude follows), `gh` CLI + `jq` at runtime, bats (containerized) for tests over the executable fenced blocks. Spec: `docs/superpowers/specs/2026-06-10-work-on-gh-issue-design.md`.

**Constraint:** `claude-shared` is **public** — no reference to any private source repo. Do not push without the user's approval.

---

## File Structure

- Create `templates/work-on-gh-issue/SKILL.md` — tokenized worker. Sections: invocation, selection, `{{STATE_ADAPTER}}`, TDD worker, `{{COPILOT_LOOP}}`, PR-label block, hard stops, forbidden, attribution. Contains two **separately fenced** executable blocks the tests target: the labels-mode **ranking jq** (reads issue JSON on stdin) and nothing else runtime-coupled.
- Create `skills/add-work-on-gh-issue/SKILL.md` — installer. Sections: resolve inputs, choose mode, inspect repo, mode config (labels/project), shared config, **token table**, the **state-adapter fills** (labels + project), the **placeholder-scan** fenced block, write, report.
- Create `tests/work-on-gh-issue.bats` — extracts and runs the ranking jq and the placeholder scan; plus static lint (token coverage, scan covers `{{`+`<`, no "delete the line" on shared-content tokens) for the new pair.
- Modify `README.md` — add a one-line pointer to the new installable skill.
- Modify `skills/claude-shared/SKILL.md` — mention `/add-work-on-gh-issue` alongside `/add-handoff` **only if** it enumerates installable skills (check first; otherwise skip).

No change to `sync.sh` (it already globs `skills/*/`) or `tests/Dockerfile` (tests use only jq/grep/git).

---

## Task 1: Scaffold both skill files (minimal valid frontmatter) + test file existence guard

**Files:**
- Create: `templates/work-on-gh-issue/SKILL.md`
- Create: `skills/add-work-on-gh-issue/SKILL.md`
- Test: `tests/work-on-gh-issue.bats`

- [ ] **Step 1: Write the failing test**

Create `tests/work-on-gh-issue.bats` with:

```bash
#!/usr/bin/env bats
#
# work-on-gh-issue: exercises the executable fenced blocks in the template +
# installer (ranking jq, placeholder scan) and lints the token contract.
# The test image has bash/bats/jq/git/gawk only — NO gh, NO node. Tests must
# never invoke gh.

load 'helpers/setup'
load 'helpers/extract'

setup()    { common_setup; }
teardown() { common_teardown; }

TEMPLATE() { echo "$REPO/templates/work-on-gh-issue/SKILL.md"; }
ADDER()    { echo "$REPO/skills/add-work-on-gh-issue/SKILL.md"; }

# ------------------------------------------------------------- SCAFFOLD ----

@test "template and installer exist with a name frontmatter field" {
  assert_file_exists "$(TEMPLATE)"
  assert_file_exists "$(ADDER)"
  assert_contains "$(head -5 "$(TEMPLATE)")" "name: work-on-gh-issue"
  assert_contains "$(head -5 "$(ADDER)")" "name: add-work-on-gh-issue"
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `tests/run.sh` (or, faster while iterating, the single file inside the container).
Expected: FAIL — `missing file: .../templates/work-on-gh-issue/SKILL.md`.

- [ ] **Step 3: Create the two files with minimal frontmatter**

`templates/work-on-gh-issue/SKILL.md`:

```markdown
---
name: work-on-gh-issue
description: placeholder — filled in Task 2
---
```

`skills/add-work-on-gh-issue/SKILL.md`:

```markdown
---
name: add-work-on-gh-issue
description: placeholder — filled in Task 4
---
```

- [ ] **Step 4: Run test to verify it passes**

Run: `tests/run.sh`
Expected: the scaffold test PASSES.

- [ ] **Step 5: Commit**

```bash
git add templates/work-on-gh-issue/SKILL.md skills/add-work-on-gh-issue/SKILL.md tests/work-on-gh-issue.bats
git commit -m "scaffold work-on-gh-issue template + installer + test file"
```

---

## Task 2: Worker template body (mode-agnostic) — TESTED via structure lint

The worker is identical across modes. We pin its required sections + tokens with a
static lint (no `gh`/`node` needed), then write the body. The ranking jq is added and
tested in Task 3, where it lives — inside the installer's labels adapter.

**Files:**
- Modify: `templates/work-on-gh-issue/SKILL.md`
- Test: `tests/work-on-gh-issue.bats`

- [ ] **Step 1: Write the failing structure-lint test**

Append to `tests/work-on-gh-issue.bats`:

```bash
# --------------------------------------------------------- WORKER SHAPE ----

@test "worker template has the required sections and tokens" {
  body="$(cat "$(TEMPLATE)")"
  for needle in \
    "## 1. Select the issue" \
    "{{STATE_ADAPTER}}" \
    "## 4. Implement via strict TDD" \
    "CANNOT REPRODUCE" \
    "{{TEST_CMD}}" \
    "## 6. Hard stops" \
    "## Forbidden" \
    "{{PR_LABELS_BLOCK}}" \
    "{{COPILOT_LOOP}}" \
    "{{ATTRIBUTION}}"; do
    assert_contains "$body" "$needle"
  done
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `tests/run.sh`
Expected: FAIL — the template is still the Task 1 placeholder, so none of the needles are present.

- [ ] **Step 3: Write the worker template body**

Replace the entire contents of `templates/work-on-gh-issue/SKILL.md` with:

````markdown
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

Merging PRs (`gh pr merge`), pushing to `{{DEFAULT_BRANCH}}`, force-pushing, editing
files outside {{WORKSPACE}}, unrelated refactoring, committing secrets.

## Attribution

When you post a comment, sign it clearly as {{ATTRIBUTION}}. Derive the exact GitHub
login with `gh api user --jq .login` — NEVER guess it or use an OS username; a wrong
@mention pings a stranger.
````

- [ ] **Step 4: Run the structure-lint test — green**

Run: `tests/run.sh`
Expected: "worker template has the required sections and tokens" PASSES.

- [ ] **Step 5: Commit**

```bash
git add templates/work-on-gh-issue/SKILL.md tests/work-on-gh-issue.bats
git commit -m "feat: work-on-gh-issue mode-agnostic worker template"
```

---

## Task 3: State-adapter fills in the installer (labels + project) — ranking TESTED

The installer holds the canonical text it substitutes for `{{STATE_ADAPTER}}`. The
labels-mode **ranking jq** is the testable seam: it lives here as a standalone
top-level `bash` block (NOT nested inside another fence), reading the issue JSON on
stdin, so the test can pipe a fixture without invoking `gh`. The worker prose already
references the named adapter operations ("to in-progress", "to in-review", "to
blocked").

**Files:**
- Modify: `skills/add-work-on-gh-issue/SKILL.md`
- Test: `tests/work-on-gh-issue.bats`

- [ ] **Step 1: Write the failing ranking test (targets the installer)**

Append to `tests/work-on-gh-issue.bats`:

```bash
# -------------------------------------------------------------- RANKING ----

# Extract the canonical ranking jq from the installer's labels adapter and fill its
# two tokens to concrete values, the way the installer would (sed-on-extract, like
# add-handoff.bats does with <target>). extract_code_block keys on a substring that
# must appear BEFORE the ```bash fence, so we key on the prose phrase that introduces
# it. The block reads the issue JSON on stdin.
rank_cmd() { # priority_json
  extract_code_block "$(ADDER)" "into this ranking jq" bash \
    | sed -e "s/{{PRIORITY_ORDER}}/$1/g" -e "s/{{BLOCKED_STATE}}/blocked/g"
}

@test "ranking drops blocked and orders by priority then issue number" {
  fixture='[{"number":5,"title":"A","labels":[{"name":"go"},{"name":"p1"}]},
            {"number":3,"title":"B","labels":[{"name":"go"},{"name":"p0"}]},
            {"number":9,"title":"C","labels":[{"name":"go"}]},
            {"number":2,"title":"D","labels":[{"name":"go"},{"name":"blocked"}]},
            {"number":7,"title":"E","labels":[{"name":"go"},{"name":"p0"}]}]'
  out="$(printf '%s' "$fixture" | bash -c "$(rank_cmd '["p0","p1","p2"]')")"
  # #2 blocked -> dropped. p0: 3,7 (by number); p1: 5; unranked: 9.
  assert_equal "$(printf '%s' "$out" | cut -f1 | tr '\n' ' ')" "3 7 5 9 "
}

@test "ranking with empty priority list is pure oldest-first" {
  fixture='[{"number":5,"title":"A","labels":[{"name":"go"}]},
            {"number":3,"title":"B","labels":[{"name":"go"}]}]'
  out="$(printf '%s' "$fixture" | bash -c "$(rank_cmd '[]')")"
  assert_equal "$(printf '%s' "$out" | cut -f1 | tr '\n' ' ')" "3 5 "
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `tests/run.sh`
Expected: FAIL — no "ranked by priority then age" block in the installer yet, so
`rank_cmd` is empty and the assertion mismatches.

- [ ] **Step 3: Add the labels-mode adapter section to the installer**

Append to `skills/add-work-on-gh-issue/SKILL.md`. Present the canonical ranking jq as
a **standalone top-level** `bash` block. The test extracts it by keying on the prose
phrase "into this ranking jq" that appears (in the selection sentence) BEFORE the
```bash fence, with no other ```bash between them — keep that phrase intact. Note the
deliberate non-nesting: the `gh issue list` fetch is described in prose, NOT in the
same fence as the jq.

````markdown
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
````

- [ ] **Step 4: Run the ranking tests — green**

Run: `tests/run.sh`
Expected: both ranking tests PASS (`3 7 5 9 ` and `3 5 `).

- [ ] **Step 5: Add the project-mode adapter section to the installer**

Append the project-v2 equivalent. Same non-nesting rule. The installer resolves
field/option ids at install (Task 4) and bakes them in.

````markdown
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
````

- [ ] **Step 6: Commit**

```bash
git add skills/add-work-on-gh-issue/SKILL.md tests/work-on-gh-issue.bats
git commit -m "feat: labels + project state-adapter fills, tested ranking jq"
```

---

## Task 4: Installer flow, token table, PR-label + Copilot fills, placeholder scan (TESTED)

**Files:**
- Modify: `skills/add-work-on-gh-issue/SKILL.md`
- Test: `tests/work-on-gh-issue.bats`

- [ ] **Step 1: Write the placeholder-scan failing test**

Append to `tests/work-on-gh-issue.bats`:

```bash
# ------------------------------------------------------- PLACEHOLDER SCAN ----

scan_cmd() { extract_code_block "$(ADDER)" "FAIL if any placeholder survived" bash; }

@test "placeholder scan flags a leftover {{TOKEN}}" {
  d="$TEST_TMP/out"; mkdir -p "$d"
  printf 'ok line\n{{LEFTOVER}}\n' > "$d/SKILL.md"
  run bash -c "DEST='$d'; $(scan_cmd)"
  assert_equal "$status" 1
  assert_contains "$output" "leftover placeholder"
}

@test "placeholder scan leaves legitimate <runtime> placeholders alone" {
  d="$TEST_TMP/out"; mkdir -p "$d"
  # The installed worker keeps lowercase <n>, <short-slug>, <pr-repo> etc.
  printf 'gh issue edit <n> --add-label foo; branch fix/<short-slug>\n' > "$d/SKILL.md"
  run bash -c "DEST='$d'; $(scan_cmd)"
  assert_equal "$status" 0
}

@test "placeholder scan passes a fully-filled file" {
  d="$TEST_TMP/out"; mkdir -p "$d"
  printf 'fully filled, no tokens here\n' > "$d/SKILL.md"
  run bash -c "DEST='$d'; $(scan_cmd)"
  assert_equal "$status" 0
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `tests/run.sh`
Expected: FAIL — no "FAIL if any placeholder survived" block exists yet (`scan_cmd` empty).

- [ ] **Step 3: Write the installer body**

After Task 3 the installer file holds frontmatter + the two "### State adapter — …"
sections. Insert the flow sections below so the file reads top-to-bottom: frontmatter
→ §1–§4 → §5 (with the two existing adapter sections moved to sit directly under the
§5 marker) → §6–§8. Do NOT delete the adapter sections. Update the frontmatter
description to the one shown here. Result:

````markdown
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
- **Default branch** (NOT the currently checked-out branch): `git -C "<target>" symbolic-ref --quiet --short refs/remotes/origin/HEAD | sed 's@^origin/@@'`, falling back to `gh repo view <owner/repo> --json defaultBranchRef --jq .defaultBranchRef.name`, else `main`. Fills `{{DEFAULT_BRANCH}}`.
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
  the repo's test-ID scheme **ending with a trailing space** (concatenated directly
  before "The test(s) MUST…"), or the empty string.
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

<!-- the two "### State adapter — labels mode" / "### State adapter — project mode"
sections from Task 3 live here -->

## 6. Fill the cross-cutting blocks

**`{{SUBMODULE_BRANCH}}`** — if the repo has submodules, fill with: ` Identify the
affected repo (a submodule or the parent). Submodules start in detached HEAD at the
parent's pinned commit — run \`git checkout main && git pull\` INSIDE the submodule
before branching, work and push ONLY in the submodule, and do NOT bump the parent
pointer.` — else empty string.

**`{{INTERACTIVE_GUARD}}`** — if an interactive-guard label was configured, fill with
(substituting the label name): `\n- INTERACTIVE GUARD: if the issue carries the
\`<label>\` label, it is too complex to fix in this focused TDD flow — it needs
brainstorming and a plan first. Do NOT proceed to reproduce/fix. Tell the user and
offer to switch to the brainstorming skill (then writing-plans) instead; leave the
issue in **{{ELIGIBLE_STATE}}**.\n` — else empty string.

**`{{COPILOT_LOOP}}`** — if the Copilot loop is enabled, fill with a `## Copilot
review loop` section. Key discipline (a real bug came from getting this wrong):
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
- Repeat, ≤3 rounds. STOP on no actionable comments, after 3 rounds, OR on the poll
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

After substituting, run the placeholder scan below — it must **FAIL if any
placeholder survived** — and fix anything it flags. (The `scan_cmd` test keys
`extract_code_block` on the phrase "FAIL if any placeholder survived", so that phrase
must sit in this prose line BEFORE the ```bash fence, not inside it.)

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
````

Ensure the two "### State adapter — …" sections from Task 3 sit under the §5 marker
(move them there if needed); they are the body of §5.

- [ ] **Step 4: Run the scan tests — green**

Run: `tests/run.sh`
Expected: both placeholder-scan tests PASS.

- [ ] **Step 5: Commit**

```bash
git add skills/add-work-on-gh-issue/SKILL.md tests/work-on-gh-issue.bats
git commit -m "feat: installer flow, fills, and tested placeholder scan"
```

---

## Task 5: Static lint for the new template/installer pair (TESTED)

Mirror the guards `lint.bats` applies to handoff, scoped to the new pair.

**Files:**
- Test: `tests/work-on-gh-issue.bats`

- [ ] **Step 1: Write the lint tests**

Append to `tests/work-on-gh-issue.bats`:

```bash
# ----------------------------------------------------------------- LINT ----

template_tokens() { grep -oE '\{\{[A-Z_]+\}\}' "$(TEMPLATE)" | sort -u; }

@test "every {{TOKEN}} in the template has a fill rule in the installer" {
  for tok in $(template_tokens); do
    grep -qF "$tok" "$(ADDER)" || fail "template token $tok has no rule in installer"
  done
}

@test "placeholder scan targets {{ }} install tokens, not <runtime> placeholders" {
  pat="$(grep -nE "grep -RnE" "$(ADDER)" | head -1)"
  # The scan matches {{UPPER_SNAKE}} tokens (braces are backslash-escaped for grep -E,
  # so check for the uppercase-token character class, which is unambiguous).
  assert_contains "$pat" '[A-Z_]'
  # It must NOT scan for lowercase <...>, which legitimately survive in the worker.
  refute_contains "$pat" '<[a-z]'
}

@test "worker forbids merging and main-pushing" {
  body="$(cat "$(TEMPLATE)")"
  assert_contains "$body" "## Forbidden"
  assert_contains "$body" "gh pr merge"
}
```

- [ ] **Step 2: Run — expect green (or a real gap)**

Run: `tests/run.sh`
Expected: PASS. If "every {{TOKEN}}…" fails, the named token in the template lacks a
literal occurrence in the installer — add its rule rather than weakening the test.

- [ ] **Step 3: Commit**

```bash
git add tests/work-on-gh-issue.bats
git commit -m "test: lint the work-on-gh-issue token contract"
```

---

## Task 6: Discoverability — README pointer + claude-shared mention

**Files:**
- Modify: `README.md`
- Modify: `skills/claude-shared/SKILL.md` (only if it lists installable skills)

- [ ] **Step 1: Read the current README skill listing**

Run: `grep -n "add-handoff\|/handoff\|installable\|skills/" README.md`
Find where `add-handoff` / `/handoff` is described.

- [ ] **Step 2: Add a parallel pointer for the new skill**

Next to the handoff entry, add a sentence: that `/add-work-on-gh-issue` installs a
per-repo `/work-on-gh-issue` skill which implements one approved GitHub issue via
strict TDD and opens a PR, supporting label- or Projects-status-based tracking. Match
the README's existing wording/format for the handoff entry (do not restructure).

- [ ] **Step 3: Mention it in the claude-shared entry skill, if applicable**

Run: `grep -n "add-handoff\|handoff" skills/claude-shared/SKILL.md`
If that skill enumerates installable skills, add `/add-work-on-gh-issue` alongside
`/add-handoff` in the same list/sentence. If it does not enumerate them, skip this
step (no change).

- [ ] **Step 4: Commit**

```bash
git add README.md skills/claude-shared/SKILL.md
git commit -m "docs: point to the work-on-gh-issue installable skill"
```

---

## Task 7: Full suite green + final review

**Files:** none (verification).

- [ ] **Step 1: Run the whole containerized suite**

Run: `tests/run.sh`
Expected: `✓ all N tests passed` — including the pre-existing handoff/sync/statusline/lint tests (none should regress) and the new `work-on-gh-issue` tests.

- [ ] **Step 2: Manual placeholder audit of both new files**

Run: `grep -nE '\{\{[A-Z_]+\}\}' templates/work-on-gh-issue/SKILL.md` (expected: tokens — these are intentional in the *template*).
Run: `grep -nE '\bTODO\b|\bTBD\b' templates/work-on-gh-issue/SKILL.md skills/add-work-on-gh-issue/SKILL.md` (expected: no matches).
Confirm the installer references every template token (the lint test already asserts this).

- [ ] **Step 3: Confirm no private-repo references (public-repo guard)**

Run: `grep -rinE 'prvl|qa-agent|qa-fixer' templates/work-on-gh-issue skills/add-work-on-gh-issue tests/work-on-gh-issue.bats docs/superpowers/specs/2026-06-10-work-on-gh-issue-design.md docs/superpowers/plans/2026-06-10-work-on-gh-issue.md`
Expected: **no matches**. Fix any that appear.

- [ ] **Step 4: Final commit if the audit changed anything**

```bash
git add -A
git commit -m "chore: final audit fixes for work-on-gh-issue" || echo "nothing to commit"
```

Do NOT push — the user reviews and pushes.

---

## Self-Review notes (filled by the plan author)

- **Spec coverage:** worker shape + invocation (T2 structure-lint), selection +
  priority-then-age ranking (T3 labels-ranking unit-tested; project ranking authored,
  not unit-tested — noted below), labels mode (T3), project mode (T3), mandatory TDD
  gate + hard stops + forbidden + attribution (T2 worker prose), PR-phase labels
  `in-auto-review`/`ready-for-human` incl. submodule pr-repo (T4 `{{PR_LABELS_BLOCK}}`
  + label-create), Copilot loop toggle (T4 `{{COPILOT_LOOP}}`), workspace configurable
  (T4 `{{WORKSPACE}}`), submodule awareness (T4 `{{SUBMODULE_BRANCH}}`), installer flow
  + placeholder scan (T4 tested), sync auto-pickup (no change needed), discoverability
  (T6), public-repo guard (T7). All spec sections map to a task.
- **Token consistency:** template body tokens (`{{ISSUE_REPO}}`, `{{ELIGIBLE_STATE}}`,
  `{{IN_PROGRESS_STATE}}`, `{{IN_REVIEW_STATE}}`, `{{BLOCKED_STATE}}`,
  `{{STATE_ADAPTER}}`, `{{WORKSPACE}}`, `{{TEST_CMD}}`, `{{TEST_ID_CONVENTION}}`,
  `{{BRANCH_PREFIX}}`, `{{SUBMODULE_BRANCH}}`, `{{PR_LABELS_BLOCK}}`,
  `{{COPILOT_LOOP}}`, `{{ATTRIBUTION}}`, `{{INTERACTIVE_GUARD}}`,
  `{{PR_IN_AUTO_REVIEW_LABEL}}`, `{{PR_READY_FOR_HUMAN_LABEL}}`) each get a fill rule
  in the installer, enforced by the T5 token-coverage lint. Installer-introduced tokens
  (`{{PRIORITY_ORDER}}`, `{{PR_IN_AUTO_REVIEW_LABEL}}`, `{{PR_READY_FOR_HUMAN_LABEL}}`,
  and the project ids `{{PROJECT_NUMBER}}`/`{{PROJECT_OWNER}}`/`{{PROJECT_ID}}`/
  `{{STATUS_FIELD_ID}}`/`{{*_OPTION_ID}}`) live only in the fills and are caught by the
  install-time placeholder scan if left unfilled.
- **Placeholder convention:** install-time fills use `{{UPPER_SNAKE}}` ONLY; the scan
  greps for those alone. Lowercase `<runtime>` placeholders (`<n>`, `<short-slug>`,
  `<pr-repo>`, `<itemId>`, `<o>`) intentionally survive in the installed worker — the
  T4 "leaves legitimate <runtime> placeholders alone" test guards this, and the T5
  lint asserts the scan pattern excludes `<[a-z]`.
- **No node / no gh in tests:** the tested seams are the labels ranking jq and the
  scan grep, fed inline JSON / temp files. No test invokes `gh`; the test image has
  only bash/bats/jq/git/gawk.
```
