# claude-shared

Shared [Claude Code](https://claude.com/claude-code) environment settings, synced
across machines via this git repo.

## What's shared

| File | Deploys to | Contents |
|------|-----------|----------|
| `claude/statusline-command.sh` | `~/.claude/statusline-command.sh` | Colored status line: `dir \| branch \| model \| ctx% \| 5h%` |
| `claude/settings.shared.json` | merged into `~/.claude/settings.json` | `model`, `effortLevel`, `enabledPlugins`, `statusLine` |
| `skills/sync-claude-env/` | symlinked into `~/.claude/skills/` | The `/sync-claude-env` re-sync skill |

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
