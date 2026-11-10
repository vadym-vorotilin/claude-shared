<!-- >>> claude-shared (managed by claude-shared/sync.sh — edit the snippet, not here) >>> -->
## Shared Claude setup

Run the **`/claude-shared`** skill to manage this machine's shared Claude
environment — the colored status line, core settings, and installing the
`/handoff` skill into your repos. It detects what's already set up and asks what
you want.

On a freshly cloned machine, run `sync.sh` from your `claude-shared` checkout
(conventionally `~/projects/claude-shared/sync.sh`; adjust if you cloned it
elsewhere) once first. It deploys everything, installs the shared skills, and
records the checkout path in `~/.claude/claude-shared-repo` so the skills find it.

## Processes: never signal outside what you started

Everything you run is this user to the kernel, so a stray `kill -- -1` kills
the desktop session and every other Claude session on the machine.

- Signal only specific pids or process groups you started and checked (a
  group must be a number above 1). Never `kill -1`, `pkill -u`, `killall -u`,
  `loginctl terminate-*`, or anything that ends the login session. A
  PreToolUse hook (`~/.claude/kill-guard-hook.sh`) blocks the literal forms.
- Run code that sends signals to groups or pids it reads from files or
  computes, such as tests of a job runner or process supervisor, their
  teardowns, or `stop`/cleanup scripts under test, under
  `~/.claude/bin/pidjail <command>`. Inside it, `-1` and every group reach only
  the jail. Example: `~/.claude/bin/pidjail bats tests/`. If it prints
  `pidjail: refused:` (no namespaces here), stop and ask; don't run the
  command unjailed.
<!-- <<< claude-shared <<< -->
