#!/usr/bin/env bats
#
# statusline-command.sh — reads a JSON blob on stdin, prints a colored line.

load 'helpers/setup'

setup()    { common_setup; }
teardown() { common_teardown; }

statusline() { printf '%s' "$1" | bash "$REPO/claude/statusline-command.sh"; }

@test "renders model display name and cwd" {
  json="$(jq -n --arg c /tmp/proj --arg m 'Opus 4.8' '{cwd:$c, model:{display_name:$m}}')"
  out="$(statusline "$json")"
  assert_contains "$out" "Opus 4.8"
  assert_contains "$out" "/tmp/proj"
}

@test "shortens \$HOME to a literal ~" {
  json="$(jq -n --arg c "$HOME/foo" --arg m M '{cwd:$c, model:{display_name:$m}}')"
  out="$(statusline "$json")"
  # BUG: ${cwd/#$home/~} tilde-expands the replacement back to $HOME, so the
  # home prefix is rewritten to itself and the full path is shown, never "~".
  assert_contains "$out" "~/foo"
  refute_contains "$out" "$HOME/foo"
}

@test "renders context window percentage, rounded" {
  json="$(jq -n --arg c /tmp --arg m M '{cwd:$c, model:{display_name:$m}, context_window:{used_percentage:42.7}}')"
  out="$(statusline "$json")"
  assert_contains "$out" "ctx: 43%"
}

@test "renders 5-hour quota percentage" {
  json="$(jq -n --arg c /tmp --arg m M '{cwd:$c, model:{display_name:$m}, rate_limits:{five_hour:{used_percentage:10}}}')"
  out="$(statusline "$json")"
  assert_contains "$out" "5h: 10%"
}

@test "omits ctx/5h segments when those fields are absent" {
  json="$(jq -n --arg c /tmp --arg m M '{cwd:$c, model:{display_name:$m}}')"
  out="$(statusline "$json")"
  refute_contains "$out" "ctx:"
  refute_contains "$out" "5h:"
}

@test "shows the git branch for a repo cwd" {
  make_git_repo "$TEST_TMP/r"
  json="$(jq -n --arg c "$TEST_TMP/r" --arg m M '{cwd:$c, model:{display_name:$m}}')"
  out="$(statusline "$json")"
  assert_contains "$out" "main"
}

@test "shows staged / unstaged / untracked indicators" {
  make_git_repo "$TEST_TMP/r"
  echo new > "$TEST_TMP/r/staged.txt";   git -C "$TEST_TMP/r" add staged.txt   # staged  +1
  echo more >> "$TEST_TMP/r/seed.txt"                                          # unstaged !1
  echo loose > "$TEST_TMP/r/untracked.txt"                                     # untracked ?1
  json="$(jq -n --arg c "$TEST_TMP/r" --arg m M '{cwd:$c, model:{display_name:$m}}')"
  out="$(statusline "$json")"
  assert_contains "$out" "+1"
  assert_contains "$out" "!1"
  assert_contains "$out" "?1"
}

@test "shows ahead count against an upstream" {
  make_git_repo_with_upstream "$TEST_TMP/r"
  echo a >> "$TEST_TMP/r/seed.txt"
  git -C "$TEST_TMP/r" commit -qam local   # one commit ahead of origin/main
  json="$(jq -n --arg c "$TEST_TMP/r" --arg m M '{cwd:$c, model:{display_name:$m}}')"
  out="$(statusline "$json")"
  assert_contains "$out" "⇡1"
}

@test "a non-git cwd shows no branch segment" {
  json="$(jq -n --arg c "$HOME" --arg m M '{cwd:$c, model:{display_name:$m}}')"
  out="$(statusline "$json")"
  assert_contains "$out" "M"
  refute_contains "$out" "main"
}
