#!/usr/bin/env bash
#
# Sync shared Claude Code environment settings into ~/.claude on this machine.
#
# Deploys:
#   - claude/statusline-command.sh  -> ~/.claude/statusline-command.sh
#   - claude/subagent-statusline-command.sh
#                                    -> ~/.claude/subagent-statusline-command.sh
#   - claude/statusline-lib.sh      -> ~/.claude/statusline-lib.sh
#                                      (sourced by both status line scripts)
#   - claude/statusline-progress.sh -> ~/.claude/statusline-progress.sh
#   - claude/statusline-progress-hook.sh
#                                    -> ~/.claude/statusline-progress-hook.sh,
#                                      and a PostToolUse entry in settings.json
#   - claude/settings.shared.json   -> merged into ~/.claude/settings.json
#                                      (shared keys win; local-only keys preserved)
#   - skills/*/                      -> symlinked into ~/.claude/skills/
#                                      (ALL shared skills; real dirs left untouched)
#   - claude/CLAUDE.snippet.md       -> a managed block in ~/.claude/CLAUDE.md
#                                      (only the text between the markers is touched)
#   - this checkout's path           -> ~/.claude/claude-shared-repo
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

# --pull: update the checkout first, then re-run the updated script without
# --pull (so it cannot loop), so every check below is the pulled script's and
# looks at the pulled snippet.
if [ "${1:-}" = "--pull" ]; then
  shift
  log "git pull in $REPO"
  git -C "$REPO" pull --ff-only
  exec bash "$REPO/sync.sh" "$@"
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required (used to merge settings.json). Install it and re-run." >&2
  exit 1
fi

# Preflight: validate the CLAUDE.md managed-block inputs before anything is
# changed, so a bad file stops the sync before steps 1-3 deploy anything.
GLOBAL_MD="$CLAUDE_DIR/CLAUDE.md"
SNIPPET="$REPO/claude/CLAUDE.snippet.md"
START='<!-- >>> claude-shared (managed by claude-shared/sync.sh — edit the snippet, not here) >>> -->'
END='<!-- <<< claude-shared <<< -->'
# Count whole marker lines (a trailing CR is ignored). The block is replaced
# only when there is exactly one START followed later by exactly one END, and
# appended when there is neither. Anything else (orphan, duplicate, reversed or
# several pairs) is ambiguous, so fail without touching the file.
marker_state="none"
if [ -f "$GLOBAL_MD" ]; then
  marker_state="$(awk -v start="$START" -v end="$END" '
    { line = $0; sub(/\r$/, "", line) }
    line == start { ns++; if (!fs) fs = NR }
    line == end   { ne++; if (!fe) fe = NR }
    END {
      if (ns == 0 && ne == 0) print "none"
      else if (ns == 1 && ne == 1 && fs < fe) print "pair"
      else if (ns == 0) print "END marker without a START marker (" ne " END)"
      else if (ne == 0) print "START marker without an END marker (" ns " START)"
      else if (ns == 1 && ne == 1) print "END marker before the START marker"
      else print "expected exactly one START and one END marker, found " ns " START and " ne " END"
    }
  ' "$GLOBAL_MD")"
fi
if [ ! -f "$SNIPPET" ] || [ ! -r "$SNIPPET" ]; then
  echo "error: snippet $SNIPPET is missing or unreadable; ~/.claude was not changed." >&2
  exit 1
fi
case "$marker_state" in
  none|pair) ;;
  *)
    echo "error: $GLOBAL_MD has malformed claude-shared markers: $marker_state." >&2
    echo "Fix the markers by hand (one START line, then one END line), then re-run. ~/.claude was not changed." >&2
    exit 1
    ;;
esac

mkdir -p "$CLAUDE_DIR/skills"

# 1. Status line scripts -----------------------------------------------------
# The session's line, the agent panel's rows, and the helpers both source.
for f in statusline-lib.sh statusline-command.sh subagent-statusline-command.sh statusline-progress.sh statusline-progress-hook.sh; do
  log "deploy $f"
  cp "$REPO/claude/$f" "$CLAUDE_DIR/$f"
  chmod +x "$CLAUDE_DIR/$f"
done

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

# The progress hook, added to the user's PostToolUse hooks rather than merged
# with '*', which would replace that array and drop hooks already there.
# Added once: an entry that already runs this command is left as it is.
HOOK_CMD='bash ~/.claude/statusline-progress-hook.sh'
log "ensure the progress hook in settings.json"
tmp="$(mktemp)"
if jq --arg cmd "$HOOK_CMD" '
    .hooks.PostToolUse = ((.hooks.PostToolUse // [])
      | if any(.[]; any(.hooks[]?; .command == $cmd)) then .
        else . + [{matcher: "Bash", hooks: [{type: "command", command: $cmd}]}] end)
  ' "$TARGET" > "$tmp"; then
  mv "$tmp" "$TARGET"
else
  rm -f "$tmp"
  log "warning: could not add the progress hook to $TARGET; background jobs will not show"
fi

# 3. Install all shared skills (symlinked) ----------------------------------
for skill_dir in "$REPO"/skills/*/; do
  [ -d "$skill_dir" ] || continue
  name="$(basename "$skill_dir")"
  link="$CLAUDE_DIR/skills/$name"
  # Only ever replace our own symlink (or a missing path). If a real file or
  # directory lives here, it's the user's — leave it untouched.
  if [ -e "$link" ] && [ ! -L "$link" ]; then
    log "skip $name: $link is a real path, not a symlink — leaving it untouched"
    continue
  fi
  log "install $name skill"
  rm -f "$link"
  ln -s "${skill_dir%/}" "$link"
done

# 4. Ensure the /claude-shared pointer in global ~/.claude/CLAUDE.md ---------
# Idempotent managed block delimited by HTML-comment markers; never touches
# any other content in the file.
log "ensure /claude-shared pointer in ~/.claude/CLAUDE.md"
# (the markers and snippet were validated before step 1)
case "$marker_state" in
  none)
    # Append (with a separating blank line if the file already has content).
    [ -s "$GLOBAL_MD" ] && printf '\n' >> "$GLOBAL_MD"
    cat "$SNIPPET" >> "$GLOBAL_MD"
    ;;
  pair)
    # Replace the existing managed block with the current snippet.
    # Write atomically: build the new file next to the real one (a symlinked
    # CLAUDE.md is resolved first, so the link itself is left alone), copy the
    # mode onto the temp file, then rename it over the original. Any failure
    # leaves CLAUDE.md as it was.
    REAL="$GLOBAL_MD"
    while [ -h "$REAL" ]; do
      d="$(cd -P "$(dirname "$REAL")" >/dev/null 2>&1 && pwd)"
      REAL="$(readlink "$REAL")"
      case "$REAL" in /*) ;; *) REAL="$d/$REAL" ;; esac
    done
    if ! cp -p "$REAL" "$REAL.tmp"; then
      rm -f "$REAL.tmp"
      echo "error: could not write $REAL.tmp; $REAL was left unchanged." >&2
      exit 1
    fi
    if ! awk -v start="$START" -v end="$END" -v snip="$SNIPPET" '
      function emit(   l, r){
        while ((r = (getline l < snip)) > 0) print l
        if (r < 0) { bad = 1; exit 1 }
        close(snip)
      }
      { line = $0; sub(/\r$/, "", line) }
      line == start { emit(); skip = 1; next }
      skip && line == end { skip = 0; next }
      skip { next }
      { print }
      END { if (bad) exit 1 }
    ' "$REAL" > "$REAL.tmp"; then
      rm -f "$REAL.tmp"
      echo "error: could not rewrite $REAL; it was left unchanged." >&2
      exit 1
    fi
    if ! mv "$REAL.tmp" "$REAL"; then
      rm -f "$REAL.tmp"
      echo "error: could not replace $REAL; it was left unchanged." >&2
      exit 1
    fi
    ;;
esac

# 5. Record repo location so the skill can find it later --------------------
printf '%s\n' "$REPO" > "$CLAUDE_DIR/claude-shared-repo"

echo
echo "✓ Synced. Restart Claude Code (or open a new session) to pick up the statusline."
echo "  Re-sync anytime with the /sync-claude-env skill, or: $REPO/sync.sh --pull"
