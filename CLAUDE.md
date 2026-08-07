# claude-shared — instructions for Claude

## This repository is PUBLIC

`github.com/vadym-vorotilin/claude-shared` is public, and it has at least one
fork. Anything committed here is world-readable and effectively permanent —
a later commit does not un-publish it, and a history rewrite does not reach a
fork.

## Never push without asking

**Commit freely. Never push.** Pushing is the user's decision, every time,
including for a one-line typo fix.

Before any push to a repo you did not start the session in, run
`gh repo view --json visibility` and say what it returns.

## Never commit here

- Project or client names, codenames, or repo names
- Issue or PR numbers from a private tracker
- Commit SHAs from a private repo
- Test-suite counts, board sizes, token spend, API costs, timelines
- Domain vocabulary specific enough to identify a project or its industry
- Evaluation results comparing vendors, models or suppliers
- File names, namespaces or assembly names from a private codebase
- Absolute paths, usernames, internal URLs

**A project is identifiable by shape, not only by name.** A library named in an
example, a distinctive architecture, or an unusual constraint gives it away
with the codename stripped. When writing a lesson from real work, keep the
*rule* here and leave the *evidence* in the project's own private repo.

## Examples must be fictional

Calibration examples, sample briefs and illustrative output use invented
projects. Never paste real output from a working session, however useful it
looks as an example.

## Skills here are used by strangers

- No instruction may destroy work if followed literally on an unfamiliar repo.
  Anything touching `git branch -D`, force-push, `pkill`, or merge needs an
  explicit scope limit, a dry-run, or `--force-with-lease`.
- No check may be a no-op outside this setup. A gate that silently always
  passes is worse than no gate, especially where it licenses skipping review.
- State what a skill assumes — toolchain, tracker, permissions — rather than
  letting a reader discover it by failure.
