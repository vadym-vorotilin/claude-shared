---
name: checkpoint
description: Write this session's Checkpoint note — the Rich section the agent fills with judgment (goal, position, unfinished work, decisions, the user's corrections, failed attempts, live things) — so the session can pick up exactly where it was after a compaction. Use when the user says "checkpoint", "/checkpoint", "save where we are", "write the checkpoint before I compact", or before a long run is likely to hit auto-compaction.
---

# checkpoint — leave a note the compacted session can trust

A compaction replaces the conversation with Claude Code's own summary. The summary keeps
the gist and loses the things that matter most for continuing: the exact next step, which
options were already rejected and why, what the user corrected, what is still running.

This repo keeps one **Checkpoint note** per session at
`~/.claude/checkpoints/<session-id>.md`, with two sections (see `CONTEXT.md`):

- the **Safety snapshot** — written mechanically by the `PreCompact` hook before every
  compaction: session id, working directory, transcript path, git state, and the user's
  last 10 messages verbatim. You never write it.
- the **Rich section** — written by **you**, here, with judgment. Each `/checkpoint`
  replaces only this section; the snapshot stays as it is.

You rarely need to run this by hand before a compaction: when the Rich section is
missing or older than 15 minutes, the `PreCompact` hook writes it itself with a headless
`claude -p --model opus --effort xhigh` run over the transcript (the
note then says it was written automatically). A note you write here is better — it is
built from checked evidence — and a fresh one is kept as it is. Knobs:
`CHECKPOINT_AUTO_RICH=0` turns it off; `CHECKPOINT_RICH_MODEL`, `CHECKPOINT_RICH_EFFORT`,
`CHECKPOINT_RICH_TIMEOUT` (seconds, default 240) and `CHECKPOINT_RICH_FRESH_MIN` change
it. Each run leaves one line in `~/.claude/checkpoints/auto-rich.log`.

After `/compact` (or an automatic compaction) the `SessionStart` hook with matcher
`compact` puts the whole note back into context, with instructions for checking it
against reality. Nothing is injected on startup, resume or clear.

## Gather before you write

Write from evidence, not from memory of the conversation. Run, in the session's working
directory:

```bash
git status --short; git branch --show-current; git log --oneline -3
gh pr list --author @me --state open 2>/dev/null
```

and list the background processes this session started (dev servers, watchers, long test
runs), with their PIDs. Anything you cannot check, mark as *not checked*.

## Write the note

Fill every heading. Keep the **Position** to one line — the exact next step, concrete
enough that a fresh agent can do it without asking (a command, a file and a function, a
question to put to the user). Name rejected options in **Decisions and why**; a compacted
session that does not know an option was rejected will propose it again. Quote the user's
corrections in their words when they are short.

Pipe it into the script through a **quoted** heredoc, so nothing in it is expanded:

```bash
bash ~/.claude/checkpoint.sh rich <<'CHECKPOINT_EOF'
### Goal
What the user wants at the end of this session, in one or two lines.

### Position
The exact next step, in one line.

### Unfinished work
- item — status (done / in progress / not started / blocked on …)

### Decisions and why
- decision — why; rejected: option — why not

### User's corrections this session
- what the user corrected, in their words where short

### Failed attempts
- what was tried — why it failed

### Live things
- Pull requests: number, URL, state
- Branches and worktrees: name, path
- Background processes: PID, command, what it is for
- Test and scratch directories: path
CHECKPOINT_EOF
```

The command reads the session id from `$CLAUDE_CODE_SESSION_ID`, writes the note
atomically, and prints its path. Then tell the user, in two lines: the note's path and the
Position you wrote.

## Rules

- **Overwrite, do not append.** The note holds the latest state only; there is no history.
- **No secrets.** The note lives in `~/.claude/checkpoints/`, outside every repository, but
  do not copy tokens or passwords into it.
- `bash ~/.claude/checkpoint.sh delete` deletes the session's note. Notes older than 14 days are deleted automatically at
  the next compaction of any session.
