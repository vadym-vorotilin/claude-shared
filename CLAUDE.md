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

## The kill guard

`claude/kill-guard-hook.sh` (a PreToolUse hook on Bash) and `claude/pidjail`
keep an agent from signalling every process the user owns. README, "The kill
guard", describes them for users.

- **The hook is probably live in your own session.** It blocks any Bash
  command whose text matches what it guards against, even an `echo`, a commit
  message or a grep pattern. So write such text with the file tools and commit
  with `git commit -F <file>`; in a grep pattern, write `p[k]ill`.
- **A change to what the hook blocks or allows goes in four places**, kept in
  step:
  - the code;
  - its header comment;
  - README, "The kill guard";
  - a `blocked` or `allowed` line in `tests/kill-guard.bats`.
- **pkill and killall have separate option tables** (procps-ng pkill, psmisc
  killall). Check the man page of the tool you change: an option that takes a
  value but is missing from the table makes the hook read that value as a
  process name, and then it lets a broad selector through.
- **Test any broad signal only inside `pidjail`**, after checking you are
  inside it, as the existing jail tests do: PID 1 is not the host's init, and
  the command is PID 2. Never try a blocked form on the host to see whether it
  really kills.
- **The pidjail tests skip in the Docker suite**, because the container has no
  namespaces. After a change to `pidjail`, run them on a Linux host with
  `REPO_ROOT="$PWD" bats tests/kill-guard.bats`. Use `pgrep -fx` with a unique
  sleep length, never `pkill -f` or `pgrep -f` with a pattern that also appears
  in your own command line: it matches your own shell.
- **The rule agents get** lives in `claude/CLAUDE.snippet.md`, which `sync.sh`
  writes to `~/.claude/CLAUDE.md`. It and the README must say the same.
