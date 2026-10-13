#!/usr/bin/env bash
# sweep.sh — the unattended-run liveness sweep (SKILL.md → "The liveness sweep").
# Run it as ONE persistent Monitor. Env: SCRATCH (required), WATCH, STALE_MIN, INTERVAL.
# Prints nothing while healthy; "STALL: <dir>" once per stall; "SWEEP DOWN" and exit 1
# when there is nothing to watch.
: "${SCRATCH:?set SCRATCH to the directory holding the helper worktrees}"  # no silent no-op
# Assumes: each helper works in a directory matching $WATCH (default: $SCRATCH/wt-*/)
# and GNU find (-newermt with a relative date; on BSD/macOS use -mmin -$STALE_MIN).
shopt -s nullglob
WATCH="${WATCH:-wt-*/}"      # glob, relative to $SCRATCH
STALE_MIN="${STALE_MIN:-30}" # 15 fires on healthy test runs; see below
INTERVAL="${INTERVAL:-120}"  # seconds between passes
GRACE=3                      # passes to allow before the first directory exists
said=""                      # directories already reported, so each STALL is said once
armed=0; empty=0
while true; do
  dirs=()
  for d in "$SCRATCH"/$WATCH; do [ -d "$d" ] && dirs+=("$d"); done   # a literal WATCH can name a missing dir
  if [ ${#dirs[@]} -eq 0 ]; then
    empty=$((empty + 1))
    # Speak once the sweep has ever seen a directory (they vanished), or once
    # the grace period is up (it was armed on the wrong path) — then STOP.
    if [ $armed -eq 1 ] || [ $empty -gt $GRACE ]; then
      echo "SWEEP DOWN: nothing matches $SCRATCH/$WATCH — not watching anything"
      exit 1
    fi
    sleep "$INTERVAL"; continue
  fi
  armed=1; empty=0
  for d in "${dirs[@]}"; do
    if find "$d" -name .git -prune -o -newermt "-${STALE_MIN} minutes" \
         -print -quit 2>/dev/null | grep -q .; then
      said="${said//"|$d|"/}"       # healthy again: a later stall is news
      continue
    fi
    case "$said" in *"|$d|"*) continue ;; esac
    said="$said|$d|"
    echo "STALL: $(basename "$d") — nothing written for ${STALE_MIN}m"
  done
  sleep "$INTERVAL"
done
