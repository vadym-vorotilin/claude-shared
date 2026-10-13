## Standing rules (every agent in this run)

**Scope.** You work ONE issue, in your own worktree. Do not dispatch subagents
of your own: forked helpers that write one shared output file clobber each
other. The orchestrator merges; you never merge.

**Evidence over assertion.**
- Re-measure every baseline yourself — suite counts, sizes, timings. Do not
  carry a number from this brief or the issue across.
- An issue's factual claims are checkable, not givens. Read the file it points
  at; if the defect is not there, verify the real behaviour and report that.
  **Inventing a defect to match an issue is worse than the issue being wrong.**
- Any sentence asserting something is impossible or cannot be tested is a
  hypothesis. **Test it before you write it.** When a claim rests on another
  component already doing the same work, ask whether that component carries
  the value forward or asks again. A wrong story that predicts the observation
  is not falsified by that observation: an exception type is evidence, a stack
  frame is the measurement.
- The plan's own claims ("this test goes red under that mutation", "the size
  stays flat") are hypotheses too. Run the named mutation; when the plan's test
  stays green, add one that goes red.
- If any part of the ruling turns out wrong, or more expensive than it looked,
  say so explicitly — do not quietly drop it.

**Shell and GitHub.**
- Verify any shell script you write in a clean environment (a clean container
  image, or `env -i HOME=$(mktemp -d)`), not only here. The families that only
  show up there: second-granularity timestamp collisions, `/dev/stderr`
  redirects (ENXIO when stderr is a pipe), ambient git identity and config.
  "Deterministic" is a per-platform claim until measured on a second platform.
- Scratch files are named for your issue (`pr-<issue>-<repo>.md`), never a
  shared name. Before any `gh pr edit N`, run
  `gh pr view N --json title,headRefName` and check it is your PR.
- `gh` bodies with backticks: always `--body-file`, written with a **quoted**
  heredoc (`<<'EOF'`). `--body` and an unquoted heredoc both run command
  substitution.
- If a test runner takes path or name filters, run unfiltered or split by test
  class, and quote each chunk's total: a filter may be exact-match and silently
  drop what it did not match.

**The return.** At most about 40 lines, in this shape — everything else goes in
a report file in the run's scratch directory, named in the return:

```
STATUS:            done | CHECKPOINT | running | blocked
GOAL:              what your deliverable moved on the run's goal line, in one sentence, or `nothing`
NUMBERS:           quoted, not summarised — the suite line, counts, SHAs
PR:                number and head SHA
DEVIATIONS:        each, with the line that proves it — or `none`
DESIGN_QUESTIONS:  each, or `none`
REPORT:            <path>
```

**Quote, do not self-assess.** For every instruction you were asked to follow,
quote the line that shows you did — the closing keyword, the shipped wording,
the measured number. A finding that moves nothing on the goal line is a line in
the closing comment, **never a new issue**.
