---
name: token-report
description: Measure where Claude Code token spend actually goes across this machine's transcripts — by day, model, project, subagent, and context size. Use when the user asks why quota is burning, wants a token/cost breakdown, asks "where are tokens leaking", wants to check spend against a weekly limit, or before/after changing an orchestration workflow.
---

# Token report

Raw token counts lie. On a typical orchestration run **~97% of raw tokens are
cache reads** — the context being re-read on every turn. Counting tokens tells
you almost nothing; counting *weighted* tokens tells you everything.

This skill wraps `token_audit.py`, which walks `~/.claude/projects/**/*.jsonl`,
deduplicates by `requestId` (resumed and forked transcripts replay history
verbatim — counting lines double-counts), and prices every call at real
per-MTok rates.

## What this assumes

- **`python3` on PATH.** No third-party packages, no network — the script is
  standard library only and never calls an API.
- **Transcripts under `~/.claude/projects`**, in Claude Code's current JSONL
  shape: assistant records carrying `message.usage` and `requestId`, subagents
  at `<project>/<session>/subagents/agent-*.jsonl` with optional
  `agent-*.meta.json` sidecars. Override the location with `--root`. A `--root`
  that does not exist says so rather than reporting an empty window.
- **Local transcripts only.** It measures this machine. Work done in another
  checkout, another machine, or the web app is not in the total.
- **A hand-maintained price table** (`BASE` in `token_audit.py`, dated in a
  comment). A model released after that date is not in it; `rates()` falls back
  to the dearest known rate in its family, so an unknown model is over-reported
  rather than silently under-reported. Update the table from Anthropic's
  published pricing when the numbers matter — never from memory.
- **Dollar figures are an equivalence, not an invoice.** They price raw usage at
  list rates; a subscription plan, discounts, or free tiers are not modelled.

## Run it

```bash
S=~/.claude/skills/token-report/token_audit.py

python3 $S                                   # last 7 days, full report
python3 $S --since YYYY-MM-DD --until YYYY-MM-DD  # one run window
python3 $S --view leaks --top 20             # ranked recoverable $
python3 $S --view agents --top 40            # per-subagent cost + context
python3 $S --json                            # totals for scripting/budget gates
```

`--ctx-cap N` (default 200, in k-tokens) sets the threshold the `leaks` view
prices against.

## Reading the output

- **WHERE THE MONEY GOES** — if `cache_read` dominates, the problem is context
  *size × turns*, not the work being done. Chasing verbose tool output or
  chatty agents will not help.
- **COST BY CONTEXT SIZE** — the `$/turn` column is the real diagnostic. A turn
  at 600k context costs ~10× the same turn at 50k. Identical work, 10× price.
- **LANE** — sidechain vs main loop. Heavy sidechain spend means subagent
  design is the lever; heavy main-loop spend means the orchestrator's own
  context is.
- **LEAKS** — per-agent dollars recoverable by holding context under the cap.

## Decompose one session's context

`token_audit.py` says which session is expensive; `ctx_decompose.py` says why.
Use it when one session's context grew faster than its work explains — an
orchestrator that crossed its ceiling early, a fixer that started heavy:

```bash
D=~/.claude/skills/token-report/ctx_decompose.py

python3 $D 3f9a                       # session whose id starts with 3f9a
python3 $D 3f9a 7c21 --out ctx.md     # several sessions, report to a file
python3 $D 3f9a --project-dir DIR     # transcripts outside the cwd's project
```

For each session it writes a Markdown report: context size at key points, what
was read before the first subagent dispatch, tool-result volume by tool and by
file or command, the share of turns spent polling, and context growth per turn.

- **`SESSION_PREFIX…`** — leading characters of a session id; each must match
  exactly one transcript in the project directory.
- **`--project-dir`** — where the `.jsonl` transcripts are; defaults to the
  Claude Code project directory for the current working directory.
- **`--out`** — write the report to a file instead of stdout.

## The one rule this exists to enforce

Cost is **quadratic in agent lifetime**: an agent whose context grows to C over
N turns pays roughly `N × C / 2` in cache reads. Halving an agent's peak
context saves more than halving its turn count.

So: **long-lived agents are the expensive failure mode, not chatty ones.** When
an agent passes ~150k context, have it write a handoff note (files touched,
decisions made, work remaining, branch/PR/SHA) and continue in a fresh agent.
A fresh agent starts near 30k; a dispatch brief costs ~1k tokens. Resuming is
cheap below ~150k and the dominant cost driver above it.

## Budget gate

To make a token target enforceable rather than aspirational:

```bash
python3 $S --since <run-start> --json | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["usd"])'
```

Check it between waves; stop starting new work when it crosses the target.

`--json` always emits an object, including for an empty window (`usd: 0`) — the
gate reads a number rather than dying on empty stdin at the moment it is meant
to speak. Read `root_missing` alongside `usd`: a mistyped `--since` and a
mistyped `--root` both total zero, and only that flag tells them apart.
