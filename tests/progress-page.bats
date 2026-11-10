#!/usr/bin/env bats
#
# progress-page/track.py — turns status.json into dataset files and prints
# version-pinned ArtifactData batches. record and resolve decide what counts as
# live on the page, so each of their branches is pinned here. All data is the
# skill's fictional example; asset urls are fake.

load 'helpers/setup'
bats_require_minimum_version 1.5.0

setup() {
  common_setup
  TOOL="$REPO/skills/progress-page/track.py"
  D="$TEST_TMP/track"
  python3 "$TOOL" init "$D" https://claude.ai/artifact/EXAMPLE >/dev/null
  mkdir -p "$D/img"
  printf '\xff\xd8fake-jpeg' > "$D/img/merge-timeline.jpg"
}
teardown() { common_teardown; }

real() { # make the example pass build: drop the fictional marker
  python3 -c 'import json,sys; p=sys.argv[1]; s=json.load(open(p)); del s["track"]["example"]; json.dump(s,open(p,"w"))' "$D/status.json"
}
built() { # dataset name -> the file build wrote for it
  basename "$(ls "$D"/out/"$1"-*.json)"
}
state() { # jq filter over track-state.json
  jq -r "$1" "$D/track-state.json"
}
# phases pinned at 5, visuals --first, one batch pending for both
pending_mixed() {
  real
  python3 "$TOOL" build "$D" >/dev/null
  python3 "$TOOL" record "$D" --version-only phases=5 >/dev/null 2>&1
  python3 "$TOOL" batch "$D" "$(built phases)=/_blob/p1" "$(built visuals)=/_blob/v1" --first visuals >/dev/null 2>&1
}

@test "build refuses the fictional example until it is replaced" {
  run python3 "$TOOL" build "$D"
  [ "$status" -ne 0 ]
  assert_contains "$output" "fictional example"
}

@test "build rejects a bad date, a non-https link and a missing order" {
  real
  python3 - "$D/status.json" <<'EOF'
import json, sys
p = sys.argv[1]; s = json.load(open(p))
s["phases"][0]["start"] = "May 4"; s["track"]["ref_url"]["#"] = "http://x/{n}"; del s["phases"][1]["order"]
json.dump(s, open(p, "w"))
EOF
  run python3 "$TOOL" build "$D"
  [ "$status" -ne 0 ]
  assert_contains "$output" "YYYY-MM-DD"
  assert_contains "$output" "https://"
  assert_contains "$output" "'order' must be a number"
}

@test "batch refuses a dataset with no recorded version unless --first" {
  real; python3 "$TOOL" build "$D" >/dev/null
  run python3 "$TOOL" batch "$D" "$(built items)=/_blob/i"
  [ "$status" -ne 0 ]
  assert_contains "$output" "no version recorded for items"
  assert_equal "$(state '.datasets.items.pending // "none"')" none
  run --separate-stderr python3 "$TOOL" batch "$D" "$(built items)=/_blob/i" --first items
  [ "$status" -eq 0 ]
  assert_equal "$(jq -r '.writes[0] | [.op, has("if_version"), (.data | has("title"))] | join(" ")' <<<"$output")" "set false true"
}

@test "a pinned update carries if_version and leaves the title alone" {
  real; python3 "$TOOL" build "$D" >/dev/null
  python3 "$TOOL" record "$D" --version-only items=3 >/dev/null 2>&1
  run --separate-stderr python3 "$TOOL" batch "$D" "$(built items)=/_blob/i"
  [ "$status" -eq 0 ]
  assert_equal "$(jq -r '.writes[0].op, .writes[0].if_version, (.writes[0].data | has("title"))' <<<"$output" | paste -sd' ')" "update 3 false"
}

@test "batch refuses any dataset whose write is still pending" {
  pending_mixed
  run python3 "$TOOL" batch "$D" "$(built phases)=/_blob/p2"
  [ "$status" -ne 0 ]
  assert_contains "$output" "track.py resolve"
  assert_equal "$(state .datasets.phases.sent.url)" /_blob/p1
  run python3 "$TOOL" batch "$D" "$(built visuals)=/_blob/v2" --first visuals
  [ "$status" -ne 0 ]
  assert_contains "$output" "track.py resolve"
  assert_equal "$(state .datasets.visuals.sent.url)" /_blob/v1
}

@test "record marks the pending file live; a --first set past version 1 is flagged" {
  pending_mixed
  run python3 "$TOOL" record "$D" "$(built visuals)=4"
  [ "$status" -ne 0 ]
  assert_contains "$output" "may have existed and been replaced"
  run python3 "$TOOL" record "$D" "$(built phases)=6" "$(built visuals)=1"
  [ "$status" -eq 0 ]
  assert_equal "$(state '.datasets.phases | "\(.version) \(.pending // "-")"')" "6 -"
  assert_equal "$(state .datasets.phases.hash)" "$(built phases | sed 's/^phases-//; s/\.json$//')"
}

@test "resolve: our url at pin+1 is recorded as applied" {
  pending_mixed
  run python3 "$TOOL" resolve "$D" phases --version 6 --url /_blob/p1
  [ "$status" -eq 0 ]
  assert_equal "$(state .datasets.phases.hash)" "$(built phases | sed 's/^phases-//; s/\.json$//')"
}

@test "resolve: another url at the pin means never applied, and re-arms" {
  pending_mixed
  run python3 "$TOOL" resolve "$D" phases --version 5 --url /_blob/old
  [ "$status" -eq 0 ]
  assert_equal "$(state '.datasets.phases | "\(.version) \(.hash // "-") \(.pending // "-")"')" "5 - -"
}

@test "resolve stops, recording nothing, when someone else changed the dataset" {
  pending_mixed
  run python3 "$TOOL" resolve "$D" phases --version 7 --url /_blob/user
  [ "$status" -ne 0 ]
  run python3 "$TOOL" resolve "$D" phases --version 8 --url /_blob/p1
  [ "$status" -ne 0 ]
  assert_contains "$output" "someone changed it"
  run python3 "$TOOL" resolve "$D" visuals --version 3 --url /_blob/v1
  [ "$status" -ne 0 ]
  assert_contains "$output" "replaced"
  assert_equal "$(state .datasets.phases.pending)" "$(built phases | sed 's/^phases-//; s/\.json$//')"
}

@test "resolve --missing: a deleted pinned dataset asks the user; a --first one re-arms" {
  pending_mixed
  run python3 "$TOOL" resolve "$D" phases --missing
  [ "$status" -ne 0 ]
  assert_contains "$output" "Ask the user"
  run python3 "$TOOL" resolve "$D" visuals --missing
  [ "$status" -eq 0 ]
  assert_contains "$output" "--first visuals"
}

@test "page needs --version or --new, and pins --version 0" {
  run python3 "$TOOL" page "$D"
  [ "$status" -ne 0 ]
  run --separate-stderr python3 "$TOOL" page "$D" --version 0
  [ "$status" -eq 0 ]
  assert_equal "$(jq -r '.writes[0].if_version' <<<"$output")" 0
}
