**Waiting (cache rule).** Your prompt cache expires after about five minutes
idle, and the next turn then rewrites your whole context at about ten times the
cost of a cache read. So:
- Run any command that may not finish within 170 seconds
  **detached**, and poll it with a bounded wait per call:
  `timeout 170 bash -c 'until grep -qE "<done marker>" <log>; do sleep 15; done'; tail -3 <log>`
- **The bound is a maximum, not an example: every poll call returns in under
  three minutes (`timeout 170` at most)**, whatever the command is expected to
  take. Claude Code may move a subagent's foreground Bash call to the background
  after 180 seconds, whatever its `timeout`, leaving you a blind wait.
- This is a cache rule, not a timeout rule: it applies to builds, checkouts,
  renders, browser sessions and recordings exactly as much as to tests.
- Never fire `run_in_background` and then wait on it blind, and never arm the
  `Monitor` tool.
- Use a long Bash timeout (`timeout: 600000`) as a ceiling for a runaway
  command, never as a poll cadence. It cannot keep a call in the foreground past
  180 seconds, so anything longer runs detached.
