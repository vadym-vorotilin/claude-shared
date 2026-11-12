#!/usr/bin/env bats
#
# skills/swarm-of-clickers/tools/report.py — findings.json to a gallery page.
# Needs python3 only; no browser.

load 'helpers/setup'

setup() {
  common_setup
  REPORT="$REPO/skills/swarm-of-clickers/tools/report.py"
  RUN="$TEST_TMP/run"
  mkdir -p "$RUN"
  cp -r "$REPO/tests/fixtures/swarm/." "$RUN/"
}
teardown() { common_teardown; }

@test "the report has one card per finding and filter chips per page and kind" {
  run python3 "$REPORT" "$RUN"
  [ "$status" -eq 0 ]
  assert_equal "$output" "$RUN/report.html"
  html="$(cat "$RUN/report.html")"
  assert_equal "$(grep -o 'class="card"' "$RUN/report.html" | wc -l | tr -d ' ')" 5
  for chip in 'data-page="/notes"' 'data-page="/settings"' \
              'data-kind="functional"' 'data-kind="visual"' 'data-kind="ux"'; do
    assert_contains "$html" "$chip"
  done
  assert_contains "$html" "Larkspur Notes"
  assert_contains "$html" "open</"
}

@test "page text in a finding is escaped" {
  run python3 "$REPORT" "$RUN"
  [ "$status" -eq 0 ]
  html="$(cat "$RUN/report.html")"
  refute_contains "$html" "<script>alert"
  assert_contains "$html" "&lt;script&gt;alert(1)&lt;/script&gt;"
  # evidence only reaches the page through the overlay data: quotes are JSON-escaped,
  # and the "<" in it cannot start a tag
  assert_contains "$html" '\"Sync\" & nothing'
  refute_contains "$html" 'x < y'
  assert_contains "$html" 'x \u003c y'
  # the overlay data cannot close its own script element either
  refute_contains "$html" "</script> label"
}

@test "the run header is escaped too" {
  sed -i 's/"Larkspur Notes"/"<b>Lark<\/b>"/' "$RUN/findings.json"
  run python3 "$REPORT" "$RUN"
  [ "$status" -eq 0 ]
  refute_contains "$(cat "$RUN/report.html")" "<b>Lark"
}

@test "a missing screenshot stops the build and names the file" {
  rm "$RUN/raw/settings.png"
  run python3 "$REPORT" "$RUN"
  [ "$status" -eq 2 ]
  assert_contains "$output" "raw/settings.png"
  [ ! -e "$RUN/report.html" ]
  [ ! -e "$RUN/shots" ]
}

@test "missing keys and values outside the enums stop the build" {
  sed -i 's/"kind": "ux"/"kind": "cosmetic"/' "$RUN/findings.json"
  run python3 "$REPORT" "$RUN"
  [ "$status" -eq 2 ]
  assert_contains "$output" "kind"
  [ ! -e "$RUN/report.html" ]
  cp "$REPO/tests/fixtures/swarm/findings.json" "$RUN/findings.json"
  sed -i 's/"source": "check"/"source": "guess"/' "$RUN/findings.json"
  run python3 "$REPORT" "$RUN"
  [ "$status" -eq 2 ]
  assert_contains "$output" "source"
  cp "$REPO/tests/fixtures/swarm/findings.json" "$RUN/findings.json"
  sed -i '/"fix": "Pad the icon/d' "$RUN/findings.json"
  run python3 "$REPORT" "$RUN"
  [ "$status" -eq 2 ]
  assert_contains "$output" "fix"
}

@test "screenshots are copied next to the report and referenced relatively" {
  run python3 "$REPORT" "$RUN"
  [ "$status" -eq 0 ]
  html="$(cat "$RUN/report.html")"
  assert_file_exists "$RUN/shots/F1-1.png"
  assert_file_exists "$RUN/shots/F1-2.png"
  assert_file_exists "$RUN/shots/F4-1.png"
  assert_contains "$html" 'src="shots/F1-1.png"'
  refute_contains "$html" "$RUN"
}

@test "boxes are percentages of the image size read from the PNG" {
  run python3 "$REPORT" "$RUN"
  [ "$status" -eq 0 ]
  # F1 box x=40 y=60 w=160 h=40 on a 400 x 250 image
  assert_contains "$(cat "$RUN/report.html")" "left:10%;top:24%;width:40%;height:16%"
  # F4 has box null: its card has no box element
  card="$(grep "data-id=\"F4\"" "$RUN/report.html")"
  refute_contains "$card" "class=\"box\""
}

@test "ticks, filters and the counter are in the page, with storage guarded" {
  run python3 "$REPORT" "$RUN"
  html="$(cat "$RUN/report.html")"
  assert_contains "$html" "prefers-color-scheme"
  assert_contains "$html" "swarm:"
  assert_contains "$html" "try {"
  refute_contains "$html" "innerHTML"
  refute_contains "$html" "http://fonts"
  refute_contains "$html" "<script src"
}
