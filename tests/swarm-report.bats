#!/usr/bin/env bats
#
# skills/swarm-of-clickers/tools/report.py — findings.json to a gallery page.
# Needs python3 only, except the tick-key test, which opens the reports in a
# /look session and skips when no browser or Playwright CLI is available.

load 'helpers/setup'

setup() {
  common_setup
  REPORT="$REPO/skills/swarm-of-clickers/tools/report.py"
  RUN="$TEST_TMP/run"
  mkdir -p "$RUN"
  cp -r "$REPO/tests/fixtures/swarm/." "$RUN/"
}
teardown() {
  [ -z "${LOOK-}" ] || "$LOOK" close "t$$-r" >/dev/null 2>&1 || true
  common_teardown
}

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

# The filter, tick and overlay behaviour (chips, hide-done, N / M open, arrow
# keys, focus return) is JavaScript in the page; bats cannot run it. It is
# checked by /look in a browser and by review. This test only checks the
# page carries the pieces.
@test "ticks, filters and the counter are in the page, with storage guarded" {
  run python3 "$REPORT" "$RUN"
  [ "$status" -eq 0 ]
  html="$(cat "$RUN/report.html")"
  assert_contains "$html" "prefers-color-scheme"
  assert_contains "$html" "\"swarm:\" + window.location.pathname + \":\" + id"
  assert_contains "$html" "try {"
  refute_contains "$html" "innerHTML"
  refute_contains "$html" "http://fonts"
  refute_contains "$html" "<script src"
}

# Chromium gives every file:// page one localStorage, so a key that two runs
# can share (the same date and finding ids) carries one run's ticks into the
# next. Two runs here differ only in their directory.
@test "a tick in one report does not show in another report with the same date and ids" {
  LOOK="$REPO/skills/look/tools/look.sh"
  export LOOK_HOME="$TEST_TMP/look"
  "$LOOK" setup >/dev/null 2>&1 || skip "no browser or Playwright CLI here"
  B="$TEST_TMP/run-b"
  cp -r "$RUN" "$B"
  python3 "$REPORT" "$RUN" >/dev/null
  python3 "$REPORT" "$B" >/dev/null
  S="t$$-r"
  run "$LOOK" open "$S" "$RUN/report.html"
  [ "$status" -eq 0 ] || fail "$output"
  ticked() { "$LOOK" cli "$S" eval "() => 'F1 ' + document.querySelector('input[data-tick=\"F1\"]').checked"; }
  run "$LOOK" cli "$S" eval "() => { document.querySelector('input[data-tick=\"F1\"]').click(); return 'clicked'; }"
  assert_contains "$output" '"clicked"'
  run ticked
  assert_contains "$output" '"F1 true"'
  run "$LOOK" cli "$S" goto "file://$B/report.html"
  [ "$status" -eq 0 ] || fail "$output"
  run ticked
  assert_contains "$output" '"F1 false"'
  # The control: the first report kept its tick, so storage did carry over.
  run "$LOOK" cli "$S" goto "file://$RUN/report.html"
  [ "$status" -eq 0 ] || fail "$output"
  run ticked
  assert_contains "$output" '"F1 true"'
}

@test "a placeholder-looking string in a field stays literal and injects nothing" {
  jq '.run.changed = "@@CARDS@@" | .findings[0].page = "@@DATA@@"
      | .findings[0].title = "@@KIND_CHIPS@@"
      | .findings[0].fix = "\" onfocus=window.PWNED=1 autofocus x=\""
      | .findings[0].evidence = "@@DATA@@"' \
    "$RUN/findings.json" > "$RUN/f2.json" && mv "$RUN/f2.json" "$RUN/findings.json"
  run python3 "$REPORT" "$RUN"
  [ "$status" -eq 0 ]
  html="$(cat "$RUN/report.html")"
  assert_contains "$html" 'data-page="@@DATA@@"'
  assert_contains "$html" '<p>@@CARDS@@</p>'
  assert_contains "$html" '@@KIND_CHIPS@@</span>'
  assert_equal "$(grep -o 'class="card"' "$RUN/report.html" | wc -l | tr -d ' ')" 5
  run python3 -I - "$RUN/report.html" <<'PY'
import sys
from html.parser import HTMLParser
class P(HTMLParser):
    n = 0
    def handle_starttag(self, tag, attrs):
        P.n += sum(1 for k, _ in attrs if k.startswith("on"))
p = P(); p.feed(open(sys.argv[1], encoding="utf-8").read())
print(P.n)
PY
  assert_equal "$output" 0
}

@test "an empty findings list is valid and says so" {
  jq '.findings = []' "$RUN/findings.json" > "$RUN/f2.json" && mv "$RUN/f2.json" "$RUN/findings.json"
  run python3 "$REPORT" "$RUN"
  [ "$status" -eq 0 ]
  html="$(cat "$RUN/report.html")"
  assert_contains "$html" "0 / 0 open"
  assert_contains "$html" "No findings"
  assert_equal "$(grep -o 'class="card"' "$RUN/report.html" | wc -l | tr -d ' ')" 0
}

@test "a shot already in shots/ is accepted and no other shot is overwritten" {
  mkdir -p "$RUN/shots"
  cp "$RUN/raw/notes-saved.png" "$RUN/shots/F2-1.png"
  # F1's first shot lives at shots/F2-1.png, F2's own shot is elsewhere: F2's
  # copy lands on the file F1 reads from.
  jq '.findings[0].shots[0].path = "shots/F2-1.png"' "$RUN/findings.json" > "$RUN/f2.json" \
    && mv "$RUN/f2.json" "$RUN/findings.json"
  run python3 "$REPORT" "$RUN"
  [ "$status" -eq 0 ]
  cmp "$RUN/shots/F1-1.png" "$REPO/tests/fixtures/swarm/raw/notes-saved.png"
  cmp "$RUN/shots/F2-1.png" "$REPO/tests/fixtures/swarm/raw/notes-list.png"
  # a shot already at its own destination does not raise SameFileError
  cp "$REPO/tests/fixtures/swarm/raw/settings.png" "$RUN/shots/F4-1.png"
  jq '.findings[3].shots[0].path = "shots/F4-1.png"' "$RUN/findings.json" > "$RUN/f2.json" \
    && mv "$RUN/f2.json" "$RUN/findings.json"
  run python3 "$REPORT" "$RUN"
  [ "$status" -eq 0 ]
  refute_contains "$output" "Traceback"
}

@test "a shot that is not a PNG stops the build, naming it, with no traceback" {
  echo "not a png" > "$RUN/raw/settings.png"
  run python3 "$REPORT" "$RUN"
  [ "$status" -eq 2 ]
  assert_contains "$output" "raw/settings.png"
  refute_contains "$output" "Traceback"
  : > "$RUN/raw/settings.png"
  run python3 "$REPORT" "$RUN"
  [ "$status" -eq 2 ]
  assert_contains "$output" "raw/settings.png"
  refute_contains "$output" "Traceback"
  [ ! -e "$RUN/report.html" ]
}

@test "a finding id with a newline or a quote still builds" {
  jq '.findings[0].id = "a\"b\nc"' "$RUN/findings.json" > "$RUN/f2.json" && mv "$RUN/f2.json" "$RUN/findings.json"
  run python3 "$REPORT" "$RUN"
  [ "$status" -eq 0 ]
  assert_file_exists "$RUN/shots/a_b_c-1.png"
}
