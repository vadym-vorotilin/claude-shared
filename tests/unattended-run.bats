#!/usr/bin/env bats
#
# unattended-run SKILL.md — the liveness sweep. These tests run the *actual*
# documented block: silent while healthy, STALL on a stale directory, and
# SWEEP DOWN (exit 1) rather than watching nothing in silence.

load 'helpers/setup'
load 'helpers/extract'

setup() {
  common_setup
  SWEEP="$TEST_TMP/sweep.sh"
  extract_code_block "$REPO/skills/unattended-run/SKILL.md" "### The liveness sweep" bash > "$SWEEP"
  export SCRATCH="$TEST_TMP/scratch"
  mkdir -p "$SCRATCH"
  export INTERVAL=1
}
teardown() { common_teardown; }

sweep() { timeout 4 bash "$SWEEP" 2>&1; }

make_dir() { # name age
  mkdir -p "$SCRATCH/$1"; echo x > "$SCRATCH/$1/f"
  touch -d "$2" "$SCRATCH/$1/f" "$SCRATCH/$1"
}

# ------------------------------------------------------------- FEATURES ----

@test "silent while every directory was written recently" {
  make_dir wt-a "1 minute ago"
  run sweep
  [ "$status" -eq 124 ] || fail "sweep should still be running; exit $status"
  assert_equal "$output" ""
}

@test "STALL names a directory untouched past the threshold" {
  make_dir wt-a "1 minute ago"
  make_dir wt-b "2 hours ago"
  run sweep
  assert_contains "$output" "STALL: wt-b"
  refute_contains "$output" "wt-a"
}

@test "a stale .git alone does not count as progress" {
  make_dir wt-a "2 hours ago"
  mkdir -p "$SCRATCH/wt-a/.git"; echo x > "$SCRATCH/wt-a/.git/index"
  touch -d "2 hours ago" "$SCRATCH/wt-a"
  run sweep
  assert_contains "$output" "STALL: wt-a"
}

# ----------------------------------------------------------- EDGE CASES ----

@test "nothing to watch past the grace period: SWEEP DOWN once, exit 1" {
  INTERVAL=0 run sweep
  [ "$status" -eq 1 ] || fail "expected exit 1; got $status"
  assert_equal "$(grep -c 'SWEEP DOWN' <<<"$output")" 1
}

@test "refuses to start without SCRATCH" {
  unset SCRATCH
  run sweep
  [ "$status" -ne 0 ] && [ "$status" -ne 124 ] || fail "expected an immediate error; got $status"
}

@test "a stalled directory is reported once, not on every pass" {
  make_dir wt-b "2 hours ago"
  run sweep          # INTERVAL=1 over 4 seconds: several passes
  assert_equal "$(grep -c 'STALL: wt-b' <<<"$output")" 1
}

@test "a literal WATCH naming a missing directory is SWEEP DOWN, not a stall" {
  INTERVAL=0 WATCH=my-wt/ run sweep
  [ "$status" -eq 1 ] || fail "expected exit 1; got $status"
  refute_contains "$output" "STALL"
  assert_contains "$output" "SWEEP DOWN"
}
