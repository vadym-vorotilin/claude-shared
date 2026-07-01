---
name: handoff
description: Resume or wrap up a work session via the living handoff doc ({{HANDOFF_DOC}}). On resume, read the handoff + git state to orient before working. On wrap-up, rewrite the handoff with current progress so the next agent (or another machine) can pick up cleanly. Use when starting a session ("resume", "continue", "pick up", "where were we"), ending one ("wrap up", "hand off", "update the handoff", "I'm done for today"), or switching machines. Also reads a per-turn autosave so a session cut off before wrap-up still resumes.
---

# Handoff — session continuity

This skill manages **`{{HANDOFF_DOC}}`**, the single living handoff document.{{TASK_DOC_INTRO}}
The handoff holds **state** — where things stand, what's next, and the gotchas.
It has two modes — pick by the user's intent:

- **RESUME** — default; also: `resume`, `start`, `continue`, `pick up`, "where were we".
- **WRAP-UP** — `wrap`, `wrap up`, `update`, `end`, `done`, "hand off", "I'm done".

All paths below are relative to the repo root (`{{REPO_ROOT}}`).

---

## RESUME mode

Goal: orient yourself from the doc + real repo state, then tell the user what's
next. **Do not start coding until you've reconciled the doc against reality.**

1. **Check the live autosave.** A Stop hook keeps an autosave beside the handoff
   doc (`{{HANDOFF_DOC}}` with `.md` replaced by `.autosave.md`), gitignored and
   refreshed every turn. If it exists, read it for the freshest raw state of the
   last turn (git facts, last user/assistant messages, transcript path). Judge
   whether the last session was cut off mid-work by the autosave's **content**,
   not its timestamp (the hook rewrites it after every turn, including the
   wrap-up turn, so its mtime is always later than the handoff doc's): if it
   records **uncommitted** changes (`Dirty files` > 0) or **unpushed** commits
   (the `Tracking` line shows `ahead`) that `{{HANDOFF_DOC}}` doesn't already
   account for, the previous session likely ended before a clean wrap-up —
   reconcile that in. `{{HANDOFF_DOC}}` still wins on the plan and locked
   decisions, and live git wins over both. Only open the saved transcript path
   if you need more detail.
2. **Read** `{{HANDOFF_DOC}}` end to end.
3. **Verify the doc against the live repo** (the doc can be stale — trust the repo):
   - `git -C . log --oneline -3` and `git -C . status -sb` (parent).
{{SUBMODULE_RESUME}}   - If the doc's HEAD/Remote table disagrees with the repo, **trust the repo**
     and note the discrepancy to the user.
4. **Skim the next task**{{TASK_DOC_RESUME}} so the decisions/coupling notes are
   loaded before you touch code.
5. **Report** to the user, briefly: where things stand, the single next task, any
   reconciliation surprises, and any open gotcha (disk, unpushed work). Then ask
   whether to proceed or wait — don't auto-start a large coupled change.

---

## WRAP-UP mode

Goal: leave `{{HANDOFF_DOC}}` accurate enough that a fresh agent on another
machine can continue with zero extra context. **Rewrite the doc; don't just
append.**

1. **Gather ground truth first** (don't write from memory):
   - `date +"%Y-%m-%d %H:%M %Z"` — for the stamp.
   - Parent{{SUBMODULE_AND}} branch, HEAD short hash, and whether pushed
     (`git -C <repo> status -sb | head -1` shows `ahead`/`behind`; `[origin/...]`
     with no ahead/behind = pushed).
{{SUBMODULE_WRAP}}   - The current `(in progress)` / next task.
2. **Warn about anything that breaks tomorrow's clone** and surface it to the user:
{{SUBMODULE_WARN}}   - Uncommitted working-tree changes; an in-flight half-done task.
   - Offer to push / commit as needed{{TEST_BEFORE_PUSH}}.
3. **Rewrite `{{HANDOFF_DOC}}`**, preserving its section structure:
   - **Header** — refresh `Last updated` (from `date`) and `Updated by`.
   - **TL;DR** — one honest paragraph: what's done, what's in flight, what's next.
   - **Repo & branch state** — update the HEAD/Remote table from step 1.
   - **Done recently** — add a subsection for each task finished this session
     (decision, commit hashes per repo, test result, open notes). Demote older
     entries into **History** when the list grows long.
   - **Next up** — the next task(s) with their locked decisions/coupling so the
     next agent doesn't re-litigate.
   - **Open known issues** / **Working rules & gotchas** — add any new lesson
     learned this session; drop anything no longer true.
   - **History** — keep a brief, link-out record of completed work; don't let it
     bloat (point to the trackers / git history instead of duplicating detail).
4. **Honesty bar:** if tests were not run, a task is half-done, or something is
   unpushed, **say so explicitly** in the doc. A handoff that overstates "done"
   is worse than none.
5. Remind the user to commit the doc{{COMMIT_DOC_LOCATION}} and, if they're
   switching machines, to push everything.

---

## Notes

{{NOTES_SUBMODULE}}- Salvage, don't hoard: when a handoff item has a permanent home (a known issue in
  a `TASKS.md`, a decision in a design doc), move the detail there and leave a
  one-line pointer in the handoff.
- If `{{HANDOFF_DOC}}` is ever missing, recreate it with the structure above:
  header, TL;DR, repo state, Done recently, Next up, open issues, working rules,
  how to run tests, history.
