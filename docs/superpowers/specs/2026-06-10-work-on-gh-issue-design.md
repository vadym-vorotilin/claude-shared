# Design: `work-on-gh-issue` — a reusable, installable GitHub-issue fixer skill

**Date:** 2026-06-10
**Status:** approved (pending spec review)

## Summary

A reusable skill that takes one approved GitHub issue and implements it via strict
TDD, opening one PR. It generalizes a project-specific "Fixer" worker into a
project-agnostic skill that is **installed per repo** the same way the `/handoff`
skill is (tokenized template + an installer skill). It supports two ways a repo
tracks issue state:

- **labels mode (repo-issue):** state lives in GitHub issue **labels**.
- **project mode (project-issue):** state lives in a GitHub **Projects v2 Status
  field**.

The skill is **interactive** — the user invokes it in the foreground, and Claude
itself performs the state transitions (no headless orchestrator, no result-file →
shell handoff).

## The key factoring

The fixer splits into two parts; only one cares about labels-vs-statuses:

1. **State adapter** (mode-specific) — find eligible issues, read one issue's
   content, and move an issue between states `eligible → in-progress → in-review →
   blocked`.
2. **Worker** (mode-agnostic) — the TDD discipline. Identical whether state lives
   in labels or a Project Status field.

"Support both organizations" therefore = swap the adapter, keep the worker.

## What ships (in the `claude-shared` repo)

| Artifact | Role |
|---|---|
| `templates/work-on-gh-issue/SKILL.md` | Tokenized worker template (the `{{TOKEN}}` source), mirroring `templates/handoff/`. |
| `skills/add-work-on-gh-issue/SKILL.md` | Installer skill; auto-symlinked into `~/.claude/skills/` by `sync.sh`, so `/add-work-on-gh-issue` is available everywhere. |
| `tests/add-work-on-gh-issue.bats` | Bats coverage for the installer, mirroring `tests/add-handoff.bats`. |
| README + `/claude-shared` pointer updates | Discoverability. |

**Public-repo constraint:** `claude-shared` is public. None of these artifacts may
reference the private repo this was generalized from — no private project names,
paths, URLs, or internal conventions. Everything stays generic.

**Installed artifact:** `<target>/.claude/skills/work-on-gh-issue/SKILL.md` —
self-contained, with exactly one state-mode baked in. **No `SessionStart` hook**
(unlike handoff: this is on-demand, not auto-resume).

## Installed skill behavior

- **`/work-on-gh-issue 42`** → work issue #42 (warn if it is not currently in the
  eligible state).
- **`/work-on-gh-issue`** (bare) → list eligible issues, propose the top one,
  confirm with the user before starting.

### Selection order (bare invocation)

Among issues in the eligible state and **not** blocked:

1. **By priority first, if the repo is prioritized** — highest priority first.
   - *labels mode:* an optional, ordered list of priority labels (highest→lowest),
     configured at install (e.g. `p0, p1, p2`). Issues bucket by their highest
     matching priority label; unlabeled issues sort last.
   - *project mode:* an optional Priority field; options ordered highest→lowest as
     configured at install. Items with no priority sort last.
   - If no priority config exists, this step is skipped.
2. **Then oldest first** (ascending issue number) within a priority bucket.

The skill shows the ranked eligible list, proposes the top entry, and waits for
confirmation (or a different pick) before starting.

### Worker flow (mode-agnostic)

```
pick → [issue: eligible → in-progress]
     → branch off up-to-date main ({{BRANCH_PREFIX}}<issue#>-<slug>)
     → reproduce RED  (hard-stop if it can't reproduce → blocked)
     → minimal fix → GREEN → full suite ({{TEST_CMD}})
     → push branch + open PR → [issue: in-progress → in-review]
     → {{Copilot loop enabled?}}
          yes → [PR: +in-auto-review] → review loop (≤3 rounds)
              → [PR: -in-auto-review, +ready-for-human]
          no  → [PR: +ready-for-human]
     → done
any hard stop → push branch, NO PR, [issue: → blocked] + explanatory comment
```

Two label namespaces are in play and must not be confused:

- **Issue-state labels/statuses** (`eligible / in-progress / in-review / blocked`)
  live on the *issue* and are driven by the state adapter (§ State adapter).
- **PR-phase labels** (`in-auto-review`, `ready-for-human`) live on the **PR**, in
  the affected code repo (which may be a submodule with its own remote). They mark
  the PR's review phase: `in-auto-review` while the Copilot loop runs, swapped to
  `ready-for-human` once it converges (or after 3 rounds), or set to
  `ready-for-human` directly when the Copilot loop is disabled. Applied via
  `gh pr edit <n> --repo <pr-repo> --add-label/--remove-label`. These are
  cross-cutting — they apply in both labels mode and project mode.

Carried over from the original worker prompt, generalized:

- **Scope discipline** — implement exactly what the issue (as amended by human
  comments) describes; document any deviation in the PR body.
- **Strict TDD reproduction gate (mandatory)** — write a failing test that
  reproduces the finding; it MUST be red against unmodified code (that red run is
  the reproduction). Cannot reproduce → hard stop, mark blocked with reason
  beginning "could not reproduce: ". Then minimal fix → green → full suite.
- **Conventional commits**; readable history.
- **PR body** sections: `## Finding` (links the issue), `## Red tests`,
  `## Green`, `## Risk`, `## Deviation from approved approach` (only if deviated).
- **Forbidden:** merging PRs, pushing to `main`, force-pushing, editing files
  outside the workspace, unrelated refactoring, committing secrets.
- **Attribution:** when the skill posts comments, sign clearly as an automated
  fixer on behalf of the posting account. Derive the exact GitHub login with
  `gh api user --jq .login` — never guess or use an OS username.

## The one mode-specific piece — the State adapter

The installer fills exactly one `{{STATE_ADAPTER}}` block; the worker is identical
either way.

- **labels mode:**
  - eligibility: `gh issue list --repo <repo> --state open --label <eligible>
    --json number,title,labels,...` minus those carrying the blocked label.
  - transition: `gh issue edit --add-label/--remove-label`.
  - content: `gh issue view <n> --json number,title,body,comments`.
  - comments: `gh issue comment`.
- **project mode:**
  - eligibility: list project items whose **Status** field == the eligible option
    (via `gh project item-list` / GraphQL), minus the blocked option.
  - transition: set the Status field via GraphQL `updateProjectV2ItemFieldValue`
    (or `gh project item-edit`).
  - content: `gh issue view` on the item's linked issue.
  - comments: `gh issue comment` on the linked issue.
  - The installer resolves the project's **Status field id + option ids** (and the
    optional Priority field id + option ids) up front via `gh project field-list`
    and bakes them into the installed skill.

## Tokens (filled at install)

**Shared:**

- `{{ISSUE_REPO}}` — `owner/repo` for the issues.
- `{{WORKSPACE}}` — default: current checkout (verify clean tree on up-to-date
  `main`, then branch). Optional: a configured workspace path + a hard-reset
  refresh block for users who want isolation.
- `{{TEST_CMD}}` — the full-suite command(s); optional `{{TEST_ID_CONVENTION}}`
  describing the repo's test-ID scheme, if any.
- `{{BRANCH_PREFIX}}` — default `fix/`.
- `{{ATTRIBUTION}}` — role label for signed comments + the owner-handle derivation
  rule.
- `{{COPILOT_LOOP}}` — the whole review-loop section, included or removed.
- `{{PR_IN_AUTO_REVIEW_LABEL}}` — PR label applied while the Copilot loop runs
  (default `in-auto-review`). Only present when the loop is enabled.
- `{{PR_READY_FOR_HUMAN_LABEL}}` — PR label marking the PR ready for human review
  (default `ready-for-human`).
- `{{SUBMODULE_*}}` — detected and filled exactly as `add-handoff` does (branch
  inside the affected submodule, don't bump the parent pointer, etc.).
- `{{ELIGIBLE_STATE}}`, `{{IN_PROGRESS_STATE}}`, `{{IN_REVIEW_STATE}}`,
  `{{BLOCKED_STATE}}` — the four state names/options.
- `{{PRIORITY_ORDER}}` — optional ordered priority labels/options (empty → step 1
  of selection is skipped).

**Mode block:** `{{STATE_ADAPTER}}` ← one of the two adapters above.

After substitution the installer **scans for any leftover `{{…}}` or `<…>`
placeholder** — there must be none (same guard as `add-handoff`).

## Installer flow (`/add-work-on-gh-issue`)

1. Resolve target repo (arg or ask); expand `~`; make absolute; confirm it is a
   git repo.
2. **Ask mode:** labels or project.
3. **Inspect** the target and show what was detected (let the user correct):
   submodules, test command(s), default branch.
4. **Mode config:**
   - *labels:* issue repo (default the `origin` `owner/repo`); the four state-label
     names (defaults `go / in-progress / in-review / blocked`); offer to
     `gh label create` any missing; optional ordered priority labels.
   - *project:* project number + owner; Status field name; the four option names;
     optional Priority field + ordered options. Resolve all field/option ids via
     `gh project field-list`.
5. **Other config:** branch prefix; attribution role label; Copilot loop
   (auto-detect `copilot-pull-request-reviewer`; default off if absent); workspace
   (current checkout vs configured path).
6. **PR-phase labels:** `ready-for-human` (always) and `in-auto-review` (only if
   the Copilot loop is enabled), with overridable defaults. Offer to
   `gh label create` them on the PR repo(s) — i.e. the affected code repo(s),
   which may be submodule remotes rather than the issue repo.
7. Fill template tokens incl. the chosen adapter; run the placeholder scan.
8. Write `<target>/.claude/skills/work-on-gh-issue/SKILL.md`.
9. **Report:** path written; mode + config summary; "restart Claude Code there to
   pick it up"; remind to **commit** the skill file. Note `gh` must be
   authenticated (project mode also needs the `project` scope).

## Prerequisites (target repo / host)

- `gh` (authenticated; `project` scope for project mode), `git`, and the repo's
  test runner on PATH.
- Branch protection on `main` recommended before unattended use (the forbidden-list
  is guidance, not a hard boundary).

## Upstream reconciliation (2026-06-10)

Folded in from the source project's latest Fixer revision (the behavior is now
battle-tested there):

- **PR label timing & best-effort:** add `in-auto-review` *immediately after* the PR
  is created; swap to `ready-for-human` on Copilot-loop exit — including on **poll
  timeout** and on a **hard stop that occurs after the PR is already open** (don't
  leave it stuck in `in-auto-review`). All PR-label edits tolerate a missing label.
- **Active in-session Copilot polling:** the loop must block-and-poll
  (`sleep 30` × ~20, ~10-min timeout) and must **never end the turn to "wait for a
  notification"** — doing so abandons the loop and leaves the PR unfinished.
- **Interactive guard (optional):** an optional configured label marks issues too
  complex for the focused TDD flow (they need brainstorm→plan). When present, the
  skill routes to brainstorming instead of reproducing/fixing, leaving the issue
  eligible. Off by default.

The new upstream `integrate.sh` / re-review stages are post-merge integration and
remain out of scope (below).

## Out of scope

Only the per-issue fixer is ported. The originating QA pipeline's other parts —
the reviewer/verifier, the human-filed-issue sweep, browser capture, the
auto-merge sweep, fix-evaluation, and any headless/scheduled orchestration — are
**not** included.

## Open questions

None blocking. Possible fast-follows: a headless batch orchestrator (the
"autonomous orchestrator" option, deferred), and a non-GitHub backend (e.g. GitLab)
behind the same adapter seam.
