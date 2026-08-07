#!/usr/bin/env bash
#
# Build the test image and run the bats suite inside it. The repo is mounted
# read-only; tests deploy into a throwaway $HOME, never the host's ~/.claude.
#
# Usage:
#   tests/run.sh
set -euo pipefail

HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
REPO="$(cd -P "$HERE/.." >/dev/null 2>&1 && pwd)"
IMAGE=claude-shared-tests

docker build -t "$IMAGE" "$HERE" >&2

out="$(mktemp)"
trap 'rm -f "$out"' EXIT

set +e
docker run --rm -v "$REPO:/repo:ro" "$IMAGE" bats /repo/tests | tee "$out"
rc=${PIPESTATUS[0]}
set -e

total="$(grep -cE '^(ok|not ok) ' "$out" || true)"
failed="$(grep -cE '^not ok ' "$out" || true)"
passed=$((total - failed))

GREEN=$'\033[32m'; RED=$'\033[31m'; RESET=$'\033[0m'
echo
if [ "$total" -eq 0 ]; then
  printf '%s✗ no tests ran (the container produced no TAP output)%s\n' "$RED" "$RESET"
  exit "$(( rc == 0 ? 1 : rc ))"
elif [ "$failed" -eq 0 ]; then
  printf '%s✓ all %d tests passed%s\n' "$GREEN" "$total" "$RESET"
else
  printf '%s✗ %d/%d passed, %d failed%s\n' "$RED" "$passed" "$total" "$failed" "$RESET"
fi

exit "$rc"
