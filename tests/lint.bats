#!/usr/bin/env bats
#
# Static lint over the instruction skills / templates. These don't execute
# code; they guard the prose contracts the skills depend on.

load 'helpers/setup'

setup()    { common_setup; }
teardown() { common_teardown; }

TEMPLATE() { echo "$REPO/templates/handoff/SKILL.md"; }
ADDH()     { echo "$REPO/skills/add-handoff/SKILL.md"; }

template_tokens() { grep -oE '\{\{[A-Z0-9_]+\}\}' "$(TEMPLATE)" | sort -u; }

# ------------------------------------------------------------- FEATURES ----

@test "every {{TOKEN}} in the template has a substitution rule in add-handoff" {
  for tok in $(template_tokens); do
    grep -qF "$tok" "$(ADDH)" || fail "template token $tok has no rule in add-handoff"
  done
}

@test "settings.shared.json statusLine command matches the deployed script" {
  cmd="$(jq -r '.statusLine.command' "$REPO/claude/settings.shared.json")"
  assert_contains "$cmd" "statusline-command.sh"
  grep -q 'statusline-command.sh' "$REPO/sync.sh" || fail "sync.sh does not deploy statusline-command.sh"
}

@test "CLAUDE.snippet.md carries both managed-block markers" {
  snip="$REPO/claude/CLAUDE.snippet.md"
  grep -qF '>>> claude-shared' "$snip" || fail "snippet missing START marker"
  grep -qF '<<< claude-shared <<<' "$snip" || fail "snippet missing END marker"
}

@test "every sibling path a skill names exists (../<skill>/… and \$S/…)" {
  # A skill that leans on a sibling (orchestrating-issue-runs -> cache-warmth)
  # names it by path; a rename or move must not leave it dangling. Paths written
  # $S/… are relative to the skill's own directory, wherever the file sits.
  run python3 - "$REPO/skills" <<'PY'
import re, sys, pathlib
root = pathlib.Path(sys.argv[1]); bad = []; n = 0
pat = re.compile(r'(\$S/)?((?:\.\./)?(?:[A-Za-z0-9_-]+/)*[A-Za-z0-9_.-]+\.(?:md|py|sh))')
for f in root.rglob("*.md"):
    skill = root / f.relative_to(root).parts[0]
    for m in pat.finditer(f.read_text()):
        rel = m.group(2)
        if m.group(1):
            base = skill
        elif rel.startswith("../"):
            base = f.parent
        else:
            continue
        if "<" in rel: continue
        n += 1
        if not (base / rel).exists():
            bad.append(f"{f.relative_to(root)}: {m.group(0)} does not exist")
if n < 10: bad.append(f"only {n} sibling paths found; the pattern no longer matches")
print("\n".join(bad)); sys.exit(1 if bad else 0)
PY
  [ "$status" -eq 0 ] || fail "$output"
}

@test "every <file>.md → \"Section\" reference in a skill names a section that exists" {
  # A skill split across files points between them by section name; a rename on
  # one side must not leave the other pointing at nothing. Every name in a
  # `→ "A", "B" and "C"` list is checked, not only the first.
  run python3 - "$REPO/skills" <<'PY'
import re, sys, pathlib
root = pathlib.Path(sys.argv[1]); bad = []; n = 0
ref = re.compile(r'`?((?:\.\./[a-z0-9-]+/)?[A-Za-z0-9_./-]+\.md)`?\s*→\s*'
                 r'((?:"[^"]+"(?:\s*,\s*(?:and\s+)?|\s+and\s+)?)+|[A-Z][^".;)|]{2,60})')
for f in root.rglob("*.md"):
    skill = root / f.relative_to(root).parts[0]
    for m in ref.finditer(" ".join(f.read_text().split())):
        target = next((b / m.group(1) for b in (f.parent, skill) if (b / m.group(1)).exists()), None)
        if target is None:
            bad.append(f"{f.relative_to(root)}: {m.group(1)} does not exist"); continue
        names = re.findall(r'"([^"]+)"', m.group(2)) or [m.group(2)]
        body = " ".join(target.read_text().split())
        for name in names:
            n += 1
            words = " ".join(name.strip().split()[:3]).rstrip(":")
            if not re.search(r"#+ (?:\d+\. )?" + re.escape(words), body) and f"**{words}" not in body:
                bad.append(f"{f.relative_to(root)}: {m.group(1)} has no section '{words}'")
if n < 10: bad.append(f"only {n} references found; the pattern no longer matches")
print("\n".join(bad)); sys.exit(1 if bad else 0)
PY
  [ "$status" -eq 0 ] || fail "$output"
}

@test "every brief block the orchestrator assembles exists" {
  # Briefs are joined with cat and never read by the orchestrator, so a missing
  # block would ship a brief without its rules and nobody would see it.
  S="$REPO/skills/orchestrating-issue-runs"
  n=0
  for rel in $(grep -ohE '`(\.\./)?(briefs/[a-z-]+\.md|(cache-warmth|context-ceiling)/brief\.md)`' "$S/SKILL.md" "$S"/phase*.md | tr -d '`' | sed 's#^\.\./##' | sort -u); do
    n=$((n + 1))
    case "$rel" in briefs/*) p="$S/$rel" ;; *) p="$S/../$rel" ;; esac
    [ -r "$p" ] || fail "the orchestrator names brief block $rel, missing"
  done
  [ "$n" -ge 9 ] || fail "found only $n brief blocks named"
}

@test "the orchestrator's every-run reading stays within its budget" {
  # The decomposition's goal was to carry LESS skill text than the old single
  # runbook did (a median old run carried about 28 KB). SKILL.md plus every file
  # its "Every run" table names is what a run carries; it must not creep back.
  S="$REPO/skills/orchestrating-issue-runs"
  budget=28672
  files=$(awk '/^\| Every run \|/{t=1; next} t && /^\|/{print; next} t{exit}' "$S/SKILL.md" \
          | grep -oE '\]\(([A-Za-z0-9_./-]+\.md)\)' | sed -E 's/^\]\(|\)$//g' | sort -u)
  [ "$(echo "$files" | grep -c .)" -ge 3 ] || fail "could not read the Every-run table: [$files]"
  total=$(wc -c < "$S/SKILL.md")
  for f in $files; do total=$((total + $(wc -c < "$S/$f"))); done
  [ "$total" -le "$budget" ] || fail "every-run reading is $total bytes, over the $budget budget: SKILL.md $files"
}

@test "an overlay that links only SKILL.md resolves every file the skill's map names" {
  # Project overlays symlink SKILL.md into the project's own skill directory;
  # the skill reads its other files from where that link resolves.
  overlay="$TEST_TMP/proj/.claude/skills/orchestrating-issue-runs"
  mkdir -p "$overlay"
  ln -s "$REPO/skills/orchestrating-issue-runs/SKILL.md" "$overlay/SKILL.md"
  S="$(dirname "$(readlink -f "$overlay/SKILL.md")")"
  n=0
  for rel in $(grep -oE '\]\(([A-Za-z0-9_./-]+\.md)\)' "$overlay/SKILL.md" | sed -E 's/^\]\(|\)$//g' | sort -u); do
    n=$((n + 1))
    [ -e "$S/$rel" ] || fail "map names $rel, missing under $S"
  done
  [ "$n" -ge 5 ] || fail "found only $n file links in SKILL.md"
  for sib in cache-warmth context-ceiling unattended-run; do
    [ -e "$S/../$sib/SKILL.md" ] || fail "sibling skill $sib not beside $S"
  done
}

# ----------------------------------------------------------- EDGE CASES ----

@test "tokens sharing a line with content aren't told to delete the line" {
  for tok in $(template_tokens); do
    line="$(grep -F "$tok" "$(TEMPLATE)" | head -1)"
    rest="$(printf '%s' "${line//$tok/}" | tr -d '[:space:]')"
    [ -n "$rest" ] || continue   # token alone on its line -> deleting the line is safe
    bad="$(grep -F "$tok" "$(ADDH)" | grep -i 'delete the' || true)"
    [ -z "$bad" ] || fail "token $tok shares a line with real content but add-handoff says: $bad"
  done
}

@test "the leftover-placeholder scan covers {{...}} tokens and unfilled <fill-in> markers" {
  scan="$(grep -i 'leftover' "$(ADDH)")"
  assert_contains "$scan" '{{'
  # The fill tables use <task-doc>/<test-cmd> as fill-in markers that must not survive.
  assert_contains "$scan" '<task-doc>'
}

@test "the only <...> literal intentionally left in the handoff template is <repo>" {
  # The scan in add-handoff must be satisfiable: it allows exactly these literals.
  lits="$(grep -oE '<[^>]+>' "$(TEMPLATE)" | sort -u)"
  assert_equal "$lits" "<repo>"
  grep -qF '<repo>' "$(ADDH)" || fail "add-handoff does not list <repo> as an allowed literal"
}

@test "the brief function refuses a missing, empty or lone block and leaves no stale brief" {
  # The orchestrator never reads the assembled brief, so the function is the
  # only thing between a broken block and an agent briefed without its rules.
  fn="$TEST_TMP/brief.sh"
  sed -n '/^brief() {/,/^}/p' "$REPO/skills/orchestrating-issue-runs/SKILL.md" > "$fn"
  [ -s "$fn" ] || fail "no brief() function found in SKILL.md"
  . "$fn"
  echo rules > "$TEST_TMP/a.md"; echo spec > "$TEST_TMP/b.md"; : > "$TEST_TMP/empty.md"
  out="$TEST_TMP/out.md"
  brief "$out" "$TEST_TMP/a.md" "$TEST_TMP/b.md" || fail "a good brief was refused"
  assert_contains "$(cat "$out")" "spec"
  ! brief "$out" "$TEST_TMP/a.md" "$TEST_TMP/missing.md" 2>/dev/null || fail "a missing block passed"
  [ ! -e "$out" ] || fail "a refused brief left the earlier one in place"
  ! brief "$out" "$TEST_TMP/a.md" "$TEST_TMP/empty.md" 2>/dev/null || fail "an empty block passed"
  ! brief "$out" "$TEST_TMP/a.md" 2>/dev/null || fail "a lone block passed"
  ! brief "$out" 2>/dev/null || fail "no blocks passed"
}

@test "run state lives under .orchestration/<run>; worktrees never do" {
  # A fixed place is what lets a fresh orchestrator find the ledger unprompted;
  # a worktree inside the repo gets built, grepped and committed.
  O="$REPO/skills/orchestrating-issue-runs"
  run grep -nE '(brief|spec)-<issue>' "$O/SKILL.md" "$O"/phase*.md
  [ -n "$output" ] || fail "no brief/spec path found to check"
  while IFS= read -r line; do
    [[ "$line" == *'$RUN/briefs/'* ]] || fail "brief or spec part outside \$RUN/briefs: $line"
  done <<< "$output"
  grep -qF '$RUN/ledger.md' "$O/phase1-loop.md" || fail "the ledger path is not \$RUN/ledger.md"
  ! grep -nE '(RUN|\.orchestration)[^ ]*/wt-' "$O/SKILL.md" "$O"/phase*.md "$O"/briefs/*.md \
    || fail "a worktree placed under the run state directory"
}
