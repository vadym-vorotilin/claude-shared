#!/usr/bin/env bats
#
# orchestrating-issue-runs tools/same-diff.sh — the check that lets a rebased PR
# keep its review. It must pass only on a real, identical patch.

load 'helpers/setup'

setup() {
  common_setup
  TOOL="$REPO/skills/orchestrating-issue-runs/tools/same-diff.sh"
  R="$TEST_TMP/repo"; make_git_repo "$R"
  g() { git -C "$R" -c user.name=t -c user.email=t@example.com "$@"; }
  base1=$(g rev-parse HEAD)
  echo a > "$R/a.txt"; g add a.txt; g commit -qm feature; head1=$(g rev-parse HEAD)
  g checkout -q -b other "$base1"; echo s > "$R/s.txt"; g add s.txt; g commit -qm sibling; base2=$(g rev-parse HEAD)
  g cherry-pick "$head1" >/dev/null; head2=$(g rev-parse HEAD)
}
teardown() { common_teardown; }

@test "identical rebased content passes" {
  run "$TOOL" "$base1" "$head1" "$base2" "$head2" "$R"
  [ "$status" -eq 0 ] || fail "$output"
}

@test "changed content fails" {
  echo b > "$R/a.txt"; git -C "$R" -c user.name=t -c user.email=t@example.com commit -qam change
  run "$TOOL" "$base1" "$head1" "$base2" "$(git -C "$R" rev-parse HEAD)" "$R"
  [ "$status" -eq 1 ]; assert_contains "$output" "differs"
}

@test "a bad SHA on both sides never reads as identical" {
  run "$TOOL" deadbeef deadbeef cafebabe cafebabe "$R"
  [ "$status" -eq 1 ]; assert_contains "$output" "NOT verified"
}

@test "an empty patch on both sides never reads as identical" {
  run "$TOOL" "$base1" "$base1" "$base2" "$base2" "$R"
  [ "$status" -eq 1 ]; assert_contains "$output" "NOT verified"
}

@test "a bad SHA on one side fails as that side, not as a mismatch" {
  run "$TOOL" deadbeef "$head1" "$base2" "$head2" "$R"
  [ "$status" -eq 1 ]; assert_contains "$output" "old side failed"
}
