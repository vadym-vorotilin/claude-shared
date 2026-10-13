**Context ceiling.** You cannot see your own context size; a hook may tell you
when you pass it. When your context passes **~150k**, stop and write a
checkpoint note — do not push on. Hard stop at **~200k**, whatever the state.
- Write the note to `CHECKPOINT.md` in your worktree **and** return it with
  `STATUS: CHECKPOINT`. Never commit it: add `CHECKPOINT.md` to
  `$(git rev-parse --git-path info/exclude)` first.
  ```
  FILES TOUCHED   path — what changed, and what is half-done
  DECISIONS       each decision and why, including options considered and dropped
  REMAINING       the concrete next step, then the rest, in order
  STATE           repo, branch, worktree path, PR number, resolved base SHA
  GOTCHAS         what surprised you: a flaky test, a slow command, a wrong claim
  ```
- **Finish instead only when the finish is bounded**: tests already green, one
  named deliverable left, no open decision. Say so in the note.
- A job that would outlast you: launch it detached and return `STATUS: running`
  with its log path, done marker and verified PID.
- Commit after every plan step (and push, where your brief allows it), so the
  note can point at a committed head.
