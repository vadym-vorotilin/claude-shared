---
name: add-handoff
description: Install the reusable /handoff session-continuity skill into another project, tailored to that repo. Use when the user says "add /handoff to repo <path>", "install the handoff skill in <project>", or wants the handoff workflow available in a different codebase.
---

# add-handoff — install a tailored /handoff skill into a target repo

This installs a project-adapted copy of the `/handoff` skill at
`<target>/.claude/skills/handoff/SKILL.md`. The handoff skill manages a living
`docs/HANDOFF.md` so sessions (and machines) can hand work off cleanly. The
source template lives in this shared repo at `templates/handoff/SKILL.md`.

## 1. Resolve inputs

- **Target repo** — from the user's request (e.g. "add /handoff to repo ~/projects/foo").
  If not given, ask. Expand `~` and make it absolute.
- **Handoff doc path** — default `docs/HANDOFF.md`. Use this unless the user
  asks for a different location.
- **Auto-resume on session start** — default **ON** (see step 4b). Only skip it
  if the user says they don't want the handoff to run automatically.
- **Shared repo** — `SHARED="$(cat ~/.claude/claude-shared-repo 2>/dev/null || echo ~/projects/claude-shared)"`.
  The template is at `$SHARED/templates/handoff/SKILL.md`.

Confirm the target is a git repo: `git -C "<target>" rev-parse --show-toplevel`.
If it isn't, tell the user and ask whether to proceed anyway (the handoff doc
still works; the git-state steps just won't apply).

## 2. Inspect the target repo (this is the "adapt" step)

Run these against the target and record what you find:

- **Repo root:** `git -C "<target>" rev-parse --show-toplevel`
- **Submodules:** `git -C "<target>" submodule status` (or read `.gitmodules`).
  Capture the list of submodule paths, if any.
- **Task/backlog doc:** look for a backlog the handoff should point at, e.g.
  `ls "<target>"/docs/tasks/*.md "<target>"/TASKS.md "<target>"/TODO.md 2>/dev/null`.
  Pick the most likely "current tasks" file, or conclude there's none.
- **Test command:** how does this project self-check? Check for
  `run-*-tests.sh` scripts, a `test-*` skill, `package.json` `scripts.test`,
  a `Makefile` `test` target, etc. Record the command, or conclude there's none.

**Show the user what you detected** (repo root, submodules, task doc, test cmd)
and let them correct it before you write anything.

## 3. Fill the template

Read `$SHARED/templates/handoff/SKILL.md` and substitute every `{{TOKEN}}`:

| Token | Fill with |
|-------|-----------|
| `{{HANDOFF_DOC}}` | `docs/HANDOFF.md` (or another path the user prefers) |
| `{{REPO_ROOT}}` | the absolute repo root from step 2 |
| `{{TASK_DOC_INTRO}}` | **If a task doc exists:** ` Task detail lives in the backlog it points to (\`<task-doc>\` is the current source of truth).` — **else:** empty string |
| `{{TASK_DOC_RESUME}}` | **If a task doc exists:** ` in \`<task-doc>\` (the first \`(in progress)\` item, else the first \`(priority)\`, else the first unchecked)` — **else:** ` from the handoff's "Next up"` |
| `{{TEST_BEFORE_PUSH}}` | **If a test cmd exists:** ` (run \`<test-cmd>\` first if code changed)` — **else:** empty string |

### Submodule tokens

**If the repo has NO submodules,** replace these tokens as follows:

| Token | Fill with |
|-------|-----------|
| `{{SUBMODULE_RESUME}}` | empty string (delete the placeholder line entirely) |
| `{{SUBMODULE_AND}}` | `:` |
| `{{SUBMODULE_WRAP}}` | empty string (delete the line) |
| `{{SUBMODULE_WARN}}` | `   - Unpushed commits that the next clone wouldn't see.\n` |
| `{{NOTES_SUBMODULE}}` | empty string |
| `{{COMMIT_DOC_LOCATION}}` | empty string |

**If the repo HAS submodules** (let `SUBS` = space-separated submodule paths, e.g. `backend frontend edge`):

- `{{SUBMODULE_RESUME}}` →
  ```
     - For each submodule: `for s in SUBS; do echo "== $s =="; git -C $s log --oneline -1; git -C $s status -sb | head -1; done`
     - `git submodule status` — confirm pointers are clean (no `+`/`-`).
  ```
  (keep the trailing newline so the next `   - If the doc's...` line aligns)
- `{{SUBMODULE_AND}}` → ` + each submodule:`
- `{{SUBMODULE_WRAP}}` → `   - \`git submodule status\` for pointer cleanliness.\n`
- `{{SUBMODULE_WARN}}` →
  ```
     - Unpushed submodule commits, or a parent pointer referencing an unpushed
       submodule commit (a fresh `--recurse-submodules` clone would fail).
  ```
- `{{NOTES_SUBMODULE}}` → `- \`docs/HANDOFF.md\` is **parent-repo** content, not a submodule.\n`
- `{{COMMIT_DOC_LOCATION}}` → ` (it lives in the **parent** repo)`

After substituting, **scan the result for any leftover `{{` — there must be none.**

## 4. Write it

```bash
mkdir -p "<target>/.claude/skills/handoff"
```
Write the filled content to `<target>/.claude/skills/handoff/SKILL.md`.

## 4b. Wire up auto-resume on session start (default ON)

So `/handoff` runs automatically at the start of every new session in this repo,
add a `SessionStart` hook to `<target>/.claude/settings.json`. The hook injects a
directive (only when the handoff doc exists) telling the agent to begin in RESUME
mode. Skip this step only if the user opted out.

The hook command (single line — adjust the doc path if the user changed it):

```sh
test -f docs/HANDOFF.md && printf '%s\n' 'A docs/HANDOFF.md exists for this project. Before doing anything else this session, invoke the handoff skill in RESUME mode: read docs/HANDOFF.md, reconcile it against current git state, and report where things stand and the single next task.' || true
```

Merge this into the target's `.claude/settings.json` **without clobbering** any
existing config (back the file up first if it exists; create `{}` if not). The
shape to merge in:

```json
{
  "hooks": {
    "SessionStart": [
      { "hooks": [ { "type": "command", "command": "<the command above>" } ] }
    ]
  }
}
```

Use `jq` to merge — append to any existing `hooks.SessionStart` array rather than
replacing it, and don't add a duplicate if an identical handoff hook is already
present (idempotent re-install). Example:

```bash
cd "<target>"
mkdir -p .claude
[ -f .claude/settings.json ] || echo '{}' > .claude/settings.json
cp .claude/settings.json .claude/settings.json.bak.$(date +%Y%m%d%H%M%S)
HOOK_CMD='test -f docs/HANDOFF.md && printf '"'"'%s\n'"'"' '"'"'A docs/HANDOFF.md exists for this project. Before doing anything else this session, invoke the handoff skill in RESUME mode: read docs/HANDOFF.md, reconcile it against current git state, and report where things stand and the single next task.'"'"' || true'
tmp=$(mktemp)
jq --arg cmd "$HOOK_CMD" '
  .hooks.SessionStart |= (
    (. // [])
    | if any(.[]?; (.hooks[]?.command // "") | contains("handoff skill in RESUME"))
      then .
      else . + [ { "hooks": [ { "type": "command", "command": $cmd } ] } ]
      end
  )
' .claude/settings.json > "$tmp" && mv "$tmp" .claude/settings.json
```

Note: project `.claude/settings.json` hooks require the user to trust/approve
them in that repo — mention this in the report.

## 5. Report

Tell the user:
- where it was written,
- that `/handoff` is now available in that repo (after a Claude Code restart there),
- the tailoring applied (submodules / task doc / test cmd, or "generic — none detected"),
- whether the auto-resume `SessionStart` hook was added (and that project hooks
  need to be trusted/approved in that repo on first use),
- to **commit** `.claude/skills/handoff/SKILL.md` and `.claude/settings.json` so
  collaborators and other machines get it.

Do **not** create `docs/HANDOFF.md` yourself — the handoff skill creates it on
the first wrap-up.
