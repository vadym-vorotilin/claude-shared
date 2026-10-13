# Installing and assumptions — orchestrating issue runs

Read once per project, before its first run, and whenever a run starts on a
machine or repo this skill has not run on.

## Installing into a project, with an overlay

A project keeps its overlay at
`<project>/.claude/skills/orchestrating-issue-runs/project.md` — in the
project's own skill directory, never inside the shared `claude-shared`
checkout, which is public and is where an overlay's private gates would be
published. Read it before the phase files and before Phase 0. **Where the overlay
or the repo's `CLAUDE.md` conflicts with anything here, they win** — this
skill is generic and a project knows its own gates.

The overlay is a separate file **by convention, so this one never has to be
edited to install it.** An install that edits the shared files cannot be
updated without a merge, so it rots — and a rotted overlay fails silently:
the project's own overrides stop loading while everything still looks
installed — and what stops loading could be a rule reserving merges to a
human. Give the project its own skill directory and **symlink `SKILL.md` into it** from
the shared copy. That one link is enough: the skill resolves every other file —
the phase files, `briefs/`, `reference/` and its sibling skills — through it
(SKILL.md → "Which file to read"), so an overlay cannot end up with some files
linked and others missing. Linking more is harmless. Put every local difference in `project.md`, which stays
with the project. The sibling skills (`cache-warmth`, `context-ceiling`,
`unattended-run`) need no install in the project — they are read beside the
shared copy. The ceiling hook is not installed by any symlink — run
**`/add-context-ceiling`** on the project.

**Verify the overlay actually loaded before the first dispatch** — ask the
session to quote a line that exists only in `project.md`. A machine that has
run `sync.sh` already carries this skill under the same name in
`~/.claude/skills/`, and which copy wins is not something this skill can
promise; if the project's does not, give the project directory a distinct
name and point the operator at it.

**The most dangerous thing an overlay can carry is a narrower authority than
this skill assumes.** This skill assumes the orchestrator merges. If a
project reserves merges, deploys, or any other act to a human, that is in
the overlay, and it is the first thing to check before dispatching.

## What this assumes

Check these before Phase 0; the skill will mislead you where they do not hold.

- **GitHub + `gh`**, with issues as the unit of work and PRs as the unit of
  delivery. Nothing here translates to another tracker unchanged.
- **A subagent harness that can resume an agent from its transcript.** Several
  protocols (fix rounds, rescue) assume it. If yours cannot, see Iron rule 5's
  fallback and expect fix rounds to cost full price.
- **`git worktree`**, and a scratch directory outside the repo. Snippets that
  name `origin` and `main` mean "your remote" and "your default branch" —
  substitute them where yours differ.
- **Optional per-project pieces — each belongs to the project, not to this
  skill:** a board-sync tool, a demo skill, a run memory file. Where one is
  absent, the step that mentions it says what to do instead; none is required
  for the run to work.
- **The `unattended-run` skill beside it too** — the sweep, rescue, stamps,
  budget read and the unattended stop.
- **The `context-ceiling` skill beside it too**, with its hook installed on
  the project by `/add-context-ceiling`; without the hook a fixer's ceiling is a
  brief line only.
- **The `cache-warmth` skill, installed beside this one** in the same skills
  directory (`sync.sh` puts all four in `~/.claude/skills/`). Paths written
  `../cache-warmth/…` are relative to `$S`, the directory `SKILL.md` resolves
  to; use the absolute form in a `cat` or a brief.
- **The `token-report` skill**, for every spend figure (Budget check). Without
  it, say so in the report rather than estimating.
- **Merge rights that do not need a second human approval.** Reviewer and
  author share one account here, so the verdict line *is* the record. On a repo
  with required approvals or CODEOWNERS the orchestrator's merge will fail —
  **verify branch protection and the repo's merge method at Phase 0** and put
  both in the scope doc.
- **Issues backed by citable specs.** Adjudication rules *against documents*.
  With a backlog of three-line issues and no specs, the adjudicator has nothing
  to cite: have it **recommend, and record the decision as the new spec**,
  rather than pretend to rule.
- **A production/test split you can diff.** Checks phrased as "zero non-comment
  production lines" assume you can name the production path and recognise a
  comment. Restate them in your own layout's terms rather than copying.

**Before the first unattended run:** try this on a repo where an autonomous
squash-merge to the default branch is acceptable. This skill merges and closes
issues on its own once the scope is approved.
