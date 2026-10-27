# claude-shared

Shared Claude Code environment and workflow skills. This glossary covers the
words used for keeping a session's work intact across context compaction.

## Session continuity

**Checkpoint note**:
The single per-session file that lets a session resume after **Compaction**. It
holds one **Rich section** and one **Safety snapshot**, each with its own timestamp.
_Avoid_: handoff (that is the cross-machine, in-repo document), save file

**Rich section**:
The part of a **Checkpoint note** written by the agent on `/checkpoint` — goal,
position, unfinished work, decisions, user corrections, failed attempts, live things.
Replaced on every `/checkpoint`.

**Safety snapshot**:
The part of a **Checkpoint note** written mechanically before every **Compaction**,
with no judgment — session identity, transcript path, git state, and the user's
recent messages verbatim. Replaced on every **Compaction**.
_Avoid_: backup, dump

**Position**:
The exact next step of the work at the moment of a checkpoint, in one line.
_Avoid_: status, progress

**Compaction**:
Claude Code replacing the conversation with its own summary, whether started by
`/compact` or automatically.
_Avoid_: refresh, clear

**Restore**:
Loading a **Checkpoint note** back into context after **Compaction**, then checking
it against reality before acting.
_Avoid_: resume (that is the handoff skill's mode)
