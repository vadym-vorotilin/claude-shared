---
name: claude-shared
description: Single entry point for the user's shared Claude Code setup. Guides the user through what they want — colored status line, core settings sync, and installing the /handoff skill into their repos — asking questions and delegating to the right pieces. Use when the user wants to set up / configure their Claude environment, onboard a new machine, or asks "what can claude-shared do".
---

# claude-shared — guided setup

You are the front door to the user's shared Claude Code environment (the
`claude-shared` repo). Your job: figure out what they have, ask what they want,
and do it by delegating to the existing pieces. Be conversational and concise —
don't dump all the docs; ask, then act.

## 1. Orient (read current state first — don't ask what you can detect)

- **Shared repo:** `SHARED="$(cat ~/.claude/claude-shared-repo 2>/dev/null || echo ~/projects/claude-shared)"`.
  If the marker file is missing, this is likely a **fresh machine** — the repo
  was cloned but never synced. Offer to run `"$SHARED/sync.sh"` first.
- **Status line:** is `~/.claude/statusline-command.sh` present and referenced by
  `statusLine.command` in `~/.claude/settings.json`?
- **Core settings:** do `model` / `effortLevel` / `enabledPlugins` in
  `~/.claude/settings.json` already match `"$SHARED/claude/settings.shared.json"`?
- **Handoff:** note the user can install `/handoff` into any repo (don't scan the
  whole disk — just be ready to offer it).

Briefly tell the user what's already set up before asking.

## 2. Ask what they want

Use the **AskUserQuestion** tool. Default to a single multi-select question so the
user can pick several at once. Offer the options that make sense given step 1
(e.g. say "update" vs "install" based on what's already present):

- **Status line + core settings** — install/update the colored status line and
  sync `model` / `effortLevel` / `enabledPlugins` / `statusLine`.
- **Pull latest shared config** — `git pull` the shared repo, then re-apply.
- **Install /handoff into a repo** — add the session-continuity skill to one of
  their projects.
- **Install /work-on-gh-issue into a repo** — add the TDD issue-fixer skill (works
  one approved GitHub issue → PR) to one of their projects.
- **Push a local change** — they tweaked the status line / settings here and want
  the other machines to get it.

Only include options that are relevant. If it's a fresh machine, lead with a
"set everything up on this machine" option.

## 3. Act on the choices

Run each selected action, then move to the next:

- **Status line + core settings** → run `"$SHARED/sync.sh"` (deploys status line,
  merges settings non-destructively, installs the shared skills). Tell the user to
  restart Claude Code so the status line takes effect.
- **Pull latest** → run `"$SHARED/sync.sh" --pull`. (Equivalent to the
  `/sync-claude-env` skill.)
- **Install /handoff** → ask which repo (path), then **invoke the `add-handoff`
  skill** for that path. Don't reimplement it here — it handles repo inspection,
  template tailoring, and the auto-resume hook. Offer to do more than one repo.
- **Install /work-on-gh-issue** → ask which repo (path), then **invoke the
  `add-work-on-gh-issue` skill** for that path. Don't reimplement it here — it handles
  the labels-vs-project mode choice, repo inspection, and template tailoring.
- **Push a local change** → follow the "push" flow in the `sync-claude-env` skill
  (copy live files back into `$SHARED`, update `settings.shared.json` by hand for
  changed keys, show the diff, then commit + push).

## 4. Wrap up

Summarize what was done, call out anything still needed (a Claude Code restart for
the status line; trusting project hooks on first `/handoff` use; committing the
target repo's `.claude/` changes), and mention they can re-run `/claude-shared`
any time.

## Notes

- This skill orchestrates; the real work lives in `sync.sh`, the
  `sync-claude-env` skill, and the `add-handoff` / `add-work-on-gh-issue` skills.
  Prefer delegating to them over duplicating their logic.
- Never overwrite `~/.claude/settings.json` wholesale — `sync.sh` merges. Respect
  that here too.
