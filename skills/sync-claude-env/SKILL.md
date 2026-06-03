---
name: sync-claude-env
description: Sync shared Claude Code environment settings (statusline + core settings.json keys) from the claude-shared git repo into ~/.claude on this machine. Use when the user wants to pull the latest shared Claude config, apply env settings on a new machine, or push local changes to the shared repo.
---

# Sync Claude environment settings

This skill keeps Claude Code's environment settings in step across the user's
machines via the `claude-shared` git repo. It deploys a colored statusline and
a set of core `settings.json` keys (`model`, `effortLevel`, `enabledPlugins`,
`statusLine`), merging them non-destructively into the local `~/.claude`.

## Locate the repo

The repo path is recorded at `~/.claude/claude-shared-repo`. Read it:

```bash
REPO="$(cat ~/.claude/claude-shared-repo 2>/dev/null || echo ~/projects/claude-shared)"
```

If that file does not exist and the default path is missing, ask the user where
they cloned `claude-shared`.

## Pull the latest and apply (the common case)

Run the repo's installer with `--pull`. It does `git pull --ff-only`, then
deploys the statusline script and merges the shared `settings.json` keys
(local-only keys are preserved; the prior `settings.json` is backed up first):

```bash
"$REPO/sync.sh" --pull
```

Then tell the user to restart Claude Code (or open a new session) for the
statusline to take effect.

## Push local changes to the shared repo

If the user has tweaked their statusline or core settings locally and wants the
other machines to get it:

1. Copy the live files back into the repo:
   ```bash
   cp ~/.claude/statusline-command.sh "$REPO/claude/statusline-command.sh"
   ```
   For `settings.json`, only the shared keys belong in
   `$REPO/claude/settings.shared.json` — update that file by hand (or with `jq`)
   to reflect the changed values; do **not** copy the whole local
   `settings.json`, which may contain machine-specific keys.
2. Show the user the diff, then commit and push:
   ```bash
   git -C "$REPO" add -A && git -C "$REPO" commit -m "update shared claude env" && git -C "$REPO" push
   ```

## First-time setup on a new machine

If `~/.claude/claude-shared-repo` does not exist yet, the repo was just cloned
and never synced. Run the installer once (no `--pull` needed):

```bash
"$REPO/sync.sh"
```

This deploys everything and symlinks this skill into `~/.claude/skills/` so
`/sync-claude-env` is available going forward.

## Notes

- The installer requires `jq` (used for the settings merge). If it's missing,
  it exits with a clear message — install `jq` and re-run.
- The merge is deep and non-destructive: shared keys override their local
  counterparts, but any keys that exist only locally are kept.
- A timestamped backup of `settings.json` is written before each merge.
