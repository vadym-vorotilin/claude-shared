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
  for rel in $(grep -ohE '`(briefs/[a-z-]+\.md|(cache-warmth|context-ceiling)/brief\.md)`' "$S/phase1-loop.md" | tr -d '`' | sort -u); do
    n=$((n + 1))
    case "$rel" in briefs/*) p="$S/$rel" ;; *) p="$S/../$rel" ;; esac
    [ -r "$p" ] || fail "phase1-loop.md names brief block $rel, missing"
  done
  [ "$n" -ge 5 ] || fail "found only $n brief blocks named"
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
