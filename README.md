# claude-shared

Shared [Claude Code](https://claude.com/claude-code) environment settings, synced
across machines via this git repo.

## What's shared

| File | Deploys to | Contents |
|------|-----------|----------|
| `claude/statusline-command.sh` | `~/.claude/statusline-command.sh` | Colored status line: `dir \| branch \| model \| ctx% \| 5h%` |
| `claude/settings.shared.json` | merged into `~/.claude/settings.json` | `model`, `effortLevel`, `enabledPlugins`, `statusLine` |
| `skills/*/` | symlinked into `~/.claude/skills/` | All shared skills (see below) |

### Shared skills

- **`/sync-claude-env`** — pull the latest shared config and apply it on this machine.
- **`/add-handoff`** — install the reusable `/handoff` session-continuity skill
  into another project, tailored to that repo. The template lives in
  `templates/handoff/SKILL.md`.

## Adding /handoff to another project

Inside Claude Code, run the **`/add-handoff`** skill, e.g. _"add /handoff to repo
~/projects/foo"_. It will:

1. Inspect the target repo (submodules, a tasks/backlog file, the test command)
   and fill the template at `templates/handoff/SKILL.md` accordingly.
2. Write `<target>/.claude/skills/handoff/SKILL.md` (default handoff doc:
   `docs/HANDOFF.md`).
3. Add a `SessionStart` hook to `<target>/.claude/settings.json` so `/handoff`
   **auto-resumes at the start of every session** in that repo (opt-out, and only
   fires once `docs/HANDOFF.md` exists).

Commit both files in the target repo so collaborators and other machines get them.

Only the **shared keys** are touched in `settings.json`. Any machine-specific
keys already present are preserved (deep, non-destructive merge), and the prior
file is backed up first.

## Set up on a new machine

```bash
git clone <this-repo-url> ~/projects/claude-shared
cd ~/projects/claude-shared
./sync.sh
```

Requires [`jq`](https://jqlang.github.io/jq/) (used to merge `settings.json`).
Restart Claude Code afterwards so the status line takes effect.

`sync.sh` also symlinks the `sync-claude-env` skill into `~/.claude/skills/`, so
from then on you can re-sync from inside Claude Code by running the
`/sync-claude-env` skill.

## Pull the latest

```bash
./sync.sh --pull          # git pull, then deploy
```

…or, inside Claude Code, run the **`/sync-claude-env`** skill.

## Push a local change

Edited your status line or core settings on one machine and want the others to
get it?

```bash
cp ~/.claude/statusline-command.sh claude/statusline-command.sh
# for settings: hand-edit claude/settings.shared.json to match the changed keys
git add -A && git commit -m "update shared claude env" && git push
```

Then run `./sync.sh --pull` (or `/sync-claude-env`) on the other machines.

## How the merge works

```
~/.claude/settings.json   (existing, local)
        *                 (jq deep merge — shared keys win)
claude/settings.shared.json
        =
~/.claude/settings.json   (shared keys applied, local-only keys kept)
```

The status line script is portable on its own — it reads `$HOME` at runtime, so
no paths are hardcoded.
