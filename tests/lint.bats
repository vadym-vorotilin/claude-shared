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

@test "settings.shared.json subagentStatusLine command matches the deployed script" {
  cmd="$(jq -r '.subagentStatusLine.command' "$REPO/claude/settings.shared.json")"
  assert_contains "$cmd" "subagent-statusline-command.sh"
  grep -q 'subagent-statusline-command.sh' "$REPO/sync.sh" || fail "sync.sh does not deploy subagent-statusline-command.sh"
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

@test "only /agency maps work to a model tier and an effort" {
  # Two skills once carried their own tier/effort tables and drifted apart;
  # /agency is now the one source. A table outside it with both a tier (or
  # model) column and an effort column is a second matrix, and a concrete model
  # version (Sonnet 5.5, claude-opus-5-5) outside it is a second ladder.
  # Family words ("Opus-class", `/model opus`) stay allowed.
  A="$REPO/skills/agency"
  grep -qE '^\|.*\b(Tier|Model)\b.*\|.*\bEffort\b' "$A/matrix.md" || fail "agency/matrix.md has no tier/effort table"
  grep -qE '\b(Haiku|Sonnet|Opus|Fable) [0-9]' "$A/matrix.md" || fail "agency/matrix.md names no model version"
  run grep -rnE '^\|.*\b(Tier|Model)\b.*\|.*\bEffort\b' "$REPO/skills" --include=*.md --exclude-dir=agency
  [ "$status" -ne 0 ] || fail "a tier/effort table outside /agency: $output"
  run grep -rniE '\b(haiku|sonnet|opus|fable|mythos) [0-9]+(\.[0-9]+)?\b|claude-(haiku|sonnet|opus|fable|mythos)-[0-9]' \
      "$REPO/skills" --include=*.md --exclude-dir=agency
  [ "$status" -ne 0 ] || fail "a model version outside /agency: $output"
}

@test "every brief block the orchestrator assembles exists" {
  # Briefs are joined with cat and never read by the orchestrator, so a missing
  # block would ship a brief without its rules and nobody would see it.
  S="$REPO/skills/orchestrating-issue-runs"
  n=0
  for rel in $(grep -ohE '`(\.\./)?(briefs/[a-z-]+\.md|(cache-warmth|context-ceiling)/brief\.md|agency/matrix\.md)`' "$S/SKILL.md" "$S"/phase*.md | tr -d '`' | sed 's#^\.\./##' | sort -u); do
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
  # The budget includes the shared /agency matrix (raised from 28 KB when the
  # matrix replaced the orchestrator's own, smaller tier table).
  S="$REPO/skills/orchestrating-issue-runs"
  budget=32768
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

@test "every test's XDG base directories live under its throwaway HOME" {
  # common_setup ran in setup(); a host value left in place points at the real home.
  for v in XDG_STATE_HOME XDG_CONFIG_HOME XDG_CACHE_HOME XDG_DATA_HOME; do
    [[ "${!v}" == "$TEST_TMP"/* ]] || fail "$v=${!v} is outside the test's HOME"
  done
}

@test "leg assembles each role's row in order, adds run.md, and refuses an unknown role" {
  # leg is the one call the orchestrator makes per dispatch, so its rows must
  # match the table: a fixer without the ceiling block runs unbounded.
  fn="$TEST_TMP/leg.sh"
  sed -n -e '/^brief() {/,/^}/p' -e '/^leg() {/,/^}/p' "$REPO/skills/orchestrating-issue-runs/SKILL.md" > "$fn"
  grep -q '^leg() {' "$fn" || fail "no leg() function found in SKILL.md"
  . "$fn"
  S="$TEST_TMP/s/orch"; RUN="$TEST_TMP/run"
  mkdir -p "$S/briefs" "$S/../cache-warmth" "$S/../context-ceiling" "$RUN/briefs"
  for f in common issue fixer reviewer approach adjudicator; do echo "$f" > "$S/briefs/$f.md"; done
  echo warmth > "$S/../cache-warmth/brief.md"; echo ceiling > "$S/../context-ceiling/brief.md"
  for l in 1-fixer-1 1-review-1 1-approach-1; do echo "spec $l" > "$RUN/briefs/spec-$l.md"; done
  out=$(leg fixer 1-fixer-1) || fail "a fixer leg was refused"
  assert_equal "$out" "$RUN/briefs/brief-1-fixer-1.md"
  assert_equal "$(grep -v '^$' "$out" | tr '\n' ' ')" "common issue warmth ceiling fixer spec 1-fixer-1 "
  leg reviewer 1-review-1 >/dev/null || fail "a reviewer leg was refused"
  ! grep -q ceiling "$RUN/briefs/brief-1-review-1.md" || fail "a reviewer got the ceiling block"
  echo "run cap" > "$RUN/briefs/run.md"
  leg approach 1-approach-1 ceiling >/dev/null || fail "an approach leg was refused"
  assert_equal "$(grep -v '^$' "$RUN/briefs/brief-1-approach-1.md" | tr '\n' ' ')" "common issue warmth ceiling approach run cap spec 1-approach-1 "
  ! leg scope 1-scope-1 2>/dev/null || fail "an unknown role passed"
  ! leg approach 1-approach-1 --ceiling >/dev/null 2>&1 || fail "a mistyped ceiling argument passed"
  ! leg reviewer 1-review-1 ceiling >/dev/null 2>&1 || fail "a reviewer took a ceiling argument"
  ! leg fixer 1-fixer-1 x >/dev/null 2>&1 || fail "a fixer took a third argument"
  ! leg fixer 9-fixer-1 >/dev/null 2>&1 || fail "a missing spec part passed"
}

@test "run state lives under .orchestration/<run>; worktrees never do" {
  # A fixed place is what lets a fresh orchestrator find the ledger; a worktree
  # inside the repo gets built, grepped and committed.
  O="$REPO/skills/orchestrating-issue-runs"
  run grep -ohE '[^ "`(]*(brief|spec)-<leg>[^ "`)]*' "$O/SKILL.md" "$O"/phase*.md
  [ -n "$output" ] || fail "no brief/spec path found to check"
  while IFS= read -r path; do
    [[ "$path" == '$RUN/briefs/'* ]] || fail "brief or spec part outside \$RUN/briefs: $path"
  done <<< "$output"
  grep -qF '$RUN/ledger.md' "$O/phase1-loop.md" || fail "the ledger path is not \$RUN/ledger.md"
  ! grep -nE '(RUN|\.orchestration)[^ ]*/wt-' "$O/SKILL.md" "$O"/phase*.md "$O"/briefs/*.md \
    || fail "a worktree placed under the run state directory"
}

@test "run state is excluded through the shared exclude file, and a tracked folder stops the run" {
  # A literal .git/info/exclude fails in a linked worktree (.git is a file);
  # an exclude does not untrack, so an already-tracked folder must be asked about.
  O="$REPO/skills/orchestrating-issue-runs"
  for f in "$O/SKILL.md" "$O/INSTALL.md"; do
    grep -qF 'git rev-parse --git-path info/exclude' "$f" || fail "$f: exclude not via --git-path"
    grep -qF 'git ls-files .orchestration' "$f" || fail "$f: no check for an already-tracked folder"
  done
  ! grep -rnE '\b(append|add)s?\b[^—]{0,60}\.git/info/exclude' "$O" --include=*.md --exclude-dir=full \
    || fail "an instruction writes the literal .git/info/exclude"
}

@test "agents write reports to the absolute path their brief names" {
  # A report written relative to a worktree is deleted with the worktree.
  O="$REPO/skills/orchestrating-issue-runs"
  grep -qF 'absolute path your brief names' "$O/briefs/common.md" || fail "common.md: report path not absolute"
  grep -qF '$RUN/reports/<leg>.md' "$O/phase1-loop.md" || fail "the spec part does not name the report path"
  # one report per dispatch: a fix round or a part must not overwrite the last one
  grep -qF '`<leg>` = `<issue>-<role>-<n>`' "$O/SKILL.md" || fail "report names do not count dispatches"
  # tracked mode commits named paths only: a blanket add would commit reports/
  block="$(sed -n '/run state: tracked/,/^  ```$/p' "$O/INSTALL.md")"
  assert_contains "$block" 'add -f ".orchestration/<run>/ledger.md"'
  code="$(grep -vE '^\s*(#|- )' <<< "$block")"   # the commands, not the prose or comments
  ! grep -qE 'add (-f )?(-A|\.|--all)\b|reports' <<< "$code" \
    || fail "the tracked-mode commit adds more than named paths"
  ! grep -rniE "(scratch(pad)? (file|directory)[^.]*(ledger|report)|(ledger|report)[^.]*scratch(pad)? (file|directory))" \
      "$REPO/skills" --include=*.md --exclude-dir=full || fail "run state still placed in a scratch file or directory"
}

@test "the playwright-cli version is pinned in one place" {
  # No skill file may spell out a version of the CLI; look.sh names it once
  # (LOOK_CLI_VERSION) and uses the variable everywhere else.
  run grep -rnE '@playwright/cli@[0-9]' "$REPO/skills"
  [ "$status" -eq 1 ] || fail "a file names a literal playwright-cli version: $output"
  [ "$(grep -cE '^LOOK_CLI_VERSION=[0-9]' "$REPO/skills/look/tools/look.sh")" -eq 1 ] \
    || fail "look.sh does not define LOOK_CLI_VERSION exactly once"
  run grep -rnE '@playwright/cli@' "$REPO/skills"
  ! grep -qv 'skills/look/tools/look.sh:.*@playwright/cli@\$LOOK_CLI_VERSION' <<< "$output" \
    || fail "another use of @playwright/cli@ than look.sh's LOOK_CLI_VERSION: $output"
}

@test "the look skill's first code block runs: it assigns L and S before using them" {
  skill="$REPO/skills/look/SKILL.md"
  block="$(awk '/^```bash$/{f=1;next} /^```$/{if(f)exit} f' "$skill")"
  [ -n "$block" ] || fail "no bash block in SKILL.md"
  script="${block//<path to this SKILL.md>/$skill}"
  # Offline and browserless: stub scripts stand in for the browser, the CLI and
  # node (which the Docker image lacks), so setup must succeed.
  stubs="$TEST_TMP/stubs"
  mkdir -p "$stubs"
  printf '#!/bin/sh\nexit 0\n' > "$stubs/browser"
  printf '#!/bin/sh\nexit 0\n' > "$stubs/cli"
  printf '#!/bin/sh\necho 20\n' > "$stubs/node"
  chmod +x "$stubs/browser" "$stubs/cli" "$stubs/node"
  PATH="$stubs:$PATH" LOOK_BROWSER="$stubs/browser" LOOK_CLI="$stubs/cli" run bash -c "$script"
  [ "$status" -eq 0 ] || fail "status $status: $output"
  refute_contains "$output" "No such file"
  # The checkout may be reached through a symlink; the block resolves it.
  assert_contains "$output" "L=$(readlink -f "$REPO")/skills/look S=look-"
}

@test "swarm-of-clickers names the UI clicker matrix row, and the row exists" {
  grep -q '^| UI clicker' "$REPO/skills/agency/matrix.md" || fail "agency/matrix.md has no UI clicker row"
  grep -q 'UI clicker' "$REPO/skills/swarm-of-clickers/SKILL.md" || fail "swarm-of-clickers does not name the UI clicker row"
  [ -r "$REPO/skills/swarm-of-clickers/clicker-brief.md" ] || fail "clicker-brief.md missing"
}
