#!/usr/bin/env bats
#
# The /swarm-of-clickers tier-test fixture (skills/swarm-of-clickers/eval/).
# Self-test: `look.sh checks` on each fixture page returns exactly the hit kinds
# the answer key's "Expected check hits" table lists, so the six measurable
# defects are caught as themselves and nothing else on the pages is flagged.
# Browser tests skip when no browser or Playwright CLI is available (the Docker
# suite has neither). Point LOOK_CLI at an installed playwright-cli to skip the
# install.

load 'helpers/setup'

EVAL_DIR_REL="skills/swarm-of-clickers/eval"

# One static server for the file, on a port the OS picks. The fixture needs
# http: the reports page asks for a file that does not exist.
setup_file() {
  EVAL_PORT="" EVAL_SRV_PID="" EVAL_SRV_LOG="$BATS_FILE_TMPDIR/http.log"
  if command -v python3 >/dev/null 2>&1; then
    local log="$EVAL_SRV_LOG" i
    python3 -u -m http.server 0 --bind 127.0.0.1 \
      --directory "$REPO_ROOT/$EVAL_DIR_REL/fixture" >"$log" 2>&1 3>&- &
    EVAL_SRV_PID=$!
    for i in $(seq 50); do
      EVAL_PORT="$(sed -n 's/^Serving HTTP on 127\.0\.0\.1 port \([0-9][0-9]*\) .*/\1/p' "$log")"
      [ -z "$EVAL_PORT" ] || break
      sleep 0.1
    done
  fi
  export EVAL_PORT EVAL_SRV_PID EVAL_SRV_LOG
}
teardown_file() {
  [ -z "${EVAL_SRV_PID-}" ] || kill "$EVAL_SRV_PID" 2>/dev/null || true
}

setup() {
  common_setup
  LOOK="$REPO/skills/look/tools/look.sh"
  KEY="$REPO/$EVAL_DIR_REL/answer-key.md"
  export LOOK_HOME="$TEST_TMP/look"
}
teardown() {
  "$LOOK" close "t$$-e" >/dev/null 2>&1 || true
  common_teardown
}

need_browser() {
  [ -x "$LOOK" ] || fail "look.sh missing"
  "$LOOK" setup >/dev/null 2>&1 || skip "no browser or Playwright CLI here"
  [ -n "${EVAL_PORT-}" ] || skip "no python3 http.server here"
}

# The key's "Expected check hits" row for a page, column 1..3 (1280 light,
# 390 light, 1280 dark): sorted hit kinds, one per line.
expected_kinds() { # page column
  awk -F'|' -v page="$1" -v col="$2" '
    /^## Expected check hits/ { on = 1; next }
    on && /^## / { on = 0 }
    on && NF > 4 { p = $2; gsub(/^ +| +$/, "", p); if (p == page) { print $(col + 2) } }
  ' "$KEY" | tr ',' '\n' | sed 's/^ *//; s/ *$//' | sed '/^$/d' | sort -u
}

# The sorted distinct non-limit hit kinds `checks` finds on a fixture page.
measured_kinds() { # page width scheme
  local S="t$$-e"
  run "$LOOK" open "$S" "http://127.0.0.1:$EVAL_PORT/$1.html" --width "$2" --scheme "$3"
  [ "$status" -eq 0 ] || fail "open: $output"
  run "$LOOK" checks "$S"
  [ "$status" -eq 0 ] || fail "checks: $output"
  local out="$output"
  "$LOOK" close "$S" >/dev/null 2>&1 || true
  node -e '
    const kinds = new Set(JSON.parse(process.argv[1]).map(h => h.check).filter(k => k !== "limit"));
    console.log([...kinds].sort().join("\n"));
  ' "$out"
}

assert_page_kinds() { # page
  local page="$1" col=1 w s want got
  for cfg in "1280 light" "390 light" "1280 dark"; do
    set -- $cfg; w="$1"; s="$2"
    want="$(expected_kinds "$page" "$col")"
    got="$(measured_kinds "$page" "$w" "$s")"
    [ "$got" = "$want" ] || fail "$page at $w $s: checks found [$(echo $got)], the key expects [$(echo $want)]"
    col=$((col + 1))
  done
}

@test "the answer key lists ids K01 to K20 in the four categories, 6, 6, 4 and 4" {
  [ -r "$KEY" ] || fail "answer-key.md missing"
  ids="$(grep -oE '^\| K[0-9]{2} ' "$KEY" | tr -d '| ' | tr '\n' ' ')"
  want="$(printf 'K%02d ' $(seq 1 20))"
  [ "$ids" = "$want" ] || fail "ids are [$ids]"
  for pair in measurable:6 visual:6 UX:4 functional:4; do
    n="$(grep -cE "^\| K[0-9]{2} \| ${pair%%:*} \|" "$KEY")"
    [ "$n" -eq "${pair##*:}" ] || fail "${pair%%:*}: $n rows"
  done
}

@test "the key's expected hits cover all six measurable kinds at 1280 light" {
  all="$( { for p in index settings reports; do expected_kinds "$p" 1; done; } | sort -u | tr '\n' ' ')"
  [ "$all" = "console-error contrast img-alt overflow overlap small-target " ] || fail "kinds covered: [$all]"
}

@test "fixture pages carry no hint of the key" {
  run grep -rniE 'defect|seeded|\bbug\b|broken|\bK[0-9]{2}\b|answer.?key' "$REPO/$EVAL_DIR_REL/fixture"
  [ "$status" -ne 0 ] || fail "a hint in the fixture: $output"
}

@test "index page: checks find exactly the expected kinds at 1280 light, 390 light and 1280 dark" {
  need_browser
  assert_page_kinds index
}

@test "settings page: checks find exactly the expected kinds at 1280 light, 390 light and 1280 dark" {
  need_browser
  assert_page_kinds settings
}

@test "reports page: checks find exactly the expected kinds at 1280 light, 390 light and 1280 dark" {
  need_browser
  assert_page_kinds reports
}
