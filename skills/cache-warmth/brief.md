**Waiting (cache rule).** Your prompt cache expires after about five minutes
idle, and the next turn then rewrites your whole context at about ten times the
cost of a cache read. So:
- Run any command you expect to take longer than about three minutes
  **detached**, and poll it with a bounded wait per call:
  `timeout 170 bash -c 'until grep -qE "<done marker>" <log>; do sleep 15; done'; tail -3 <log>`
- **The bound is a maximum, not an example: every poll call returns within
  about three minutes**, whatever the command is expected to take. Claude Code
  moves a subagent's foreground Bash call to the background after 180 seconds,
  whatever its `timeout`, and the poll's output is then lost.
- This is a cache rule, not a timeout rule: it applies to builds, checkouts,
  renders, browser sessions and recordings exactly as much as to tests.
- Never fire `run_in_background` and then wait on it blind, and never arm the
  `Monitor` tool.
- Use a long Bash timeout (`timeout: 600000`) as a ceiling for a runaway
  command, never as a poll cadence.
