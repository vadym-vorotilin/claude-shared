#!/usr/bin/env bash
#
# Sync shared Claude Code environment settings into ~/.claude on this machine.
#
# Deploys:
#   - claude/statusline-command.sh  -> ~/.claude/statusline-command.sh
#   - claude/settings.shared.json   -> merged into ~/.claude/settings.json
#                                      (shared keys win; local-only keys preserved)
#   - skills/sync-claude-env        -> symlinked into ~/.claude/skills/
#
# Idempotent: safe to re-run. Existing settings.json is backed up before merge.
#
# Usage:
#   ./sync.sh            # deploy from the current checkout
#   ./sync.sh --pull     # git pull first, then deploy
#
set -euo pipefail

# Resolve this script's directory (the repo root), following symlinks.
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE"
done
REPO="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"

CLAUDE_DIR="$HOME/.claude"

log() { printf '  \033[36m›\033[0m %s\n' "$1"; }

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required (used to merge settings.json). Install it and re-run." >&2
  exit 1
fi

if [ "${1:-}" = "--pull" ]; then
  log "git pull in $REPO"
  git -C "$REPO" pull --ff-only
fi

mkdir -p "$CLAUDE_DIR/skills"

# 1. Statusline script ------------------------------------------------------
log "deploy statusline-command.sh"
cp "$REPO/claude/statusline-command.sh" "$CLAUDE_DIR/statusline-command.sh"
chmod +x "$CLAUDE_DIR/statusline-command.sh"

# 2. settings.json (merge) --------------------------------------------------
SHARED="$REPO/claude/settings.shared.json"
TARGET="$CLAUDE_DIR/settings.json"
if [ -f "$TARGET" ]; then
  log "merge shared keys into existing settings.json"
  cp "$TARGET" "$TARGET.bak.$(date +%Y%m%d%H%M%S)"
  # Deep merge: existing first, shared second -> shared keys override,
  # local-only keys are preserved (recursive object merge via '*').
  tmp="$(mktemp)"
  jq -s '.[0] * .[1]' "$TARGET" "$SHARED" > "$tmp"
  mv "$tmp" "$TARGET"
else
  log "create settings.json from shared template"
  cp "$SHARED" "$TARGET"
fi

# 3. Install the re-sync skill ---------------------------------------------
log "install sync-claude-env skill"
SKILL_LINK="$CLAUDE_DIR/skills/sync-claude-env"
rm -rf "$SKILL_LINK"
ln -s "$REPO/skills/sync-claude-env" "$SKILL_LINK"

# 4. Record repo location so the skill can find it later --------------------
printf '%s\n' "$REPO" > "$CLAUDE_DIR/claude-shared-repo"

echo
echo "✓ Synced. Restart Claude Code (or open a new session) to pick up the statusline."
echo "  Re-sync anytime with the /sync-claude-env skill, or: $REPO/sync.sh --pull"
