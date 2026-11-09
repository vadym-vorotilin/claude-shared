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

For a command you expect to run more than a few minutes and that prints a
percentage (a test suite, a build, a backup), wrap it so its progress shows in the
status line: `bash ~/.claude/statusline-progress.sh run "<name>" -- <command>`.
Output and exit code are the command's; stderr is merged into stdout.
<!-- <<< claude-shared <<< -->
