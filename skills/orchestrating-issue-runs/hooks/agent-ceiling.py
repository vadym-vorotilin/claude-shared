#!/usr/bin/env python3
"""PreToolUse hook: enforce the agent context ceiling (iron rules 9 and 10).

A dispatched agent cannot read its own context — the harness does not report it
and /context belongs to the operator — so "stop at N tokens" is a rule its
subject cannot obey, and it gets breached silently. This hook measures the
agent and says so, turning the instruction into enforcement.

On the first tool call after a threshold is crossed it BLOCKS once (exit 2,
message on stderr where the model reads it), records the crossing, and then
stops interfering. Blocking once is what makes it unmissable; blocking every
call would deadlock the agent.

FAILS OPEN. This is advisory, and a bug here must never halt a run. The
companion guard hook, which enforces prohibitions rather than budgets, fails
CLOSED — opposite rule, opposite reason.

Env: AGENT_CEILING_SOFT (default 150000), AGENT_CEILING_HARD (default 200000).
"""
import json, os, sys

def _threshold(name, default):
    try:
        return int(os.environ[name])
    except Exception:      # unset, or set to something that is not a number
        return default

SOFT = _threshold("AGENT_CEILING_SOFT", 150_000)
HARD = _threshold("AGENT_CEILING_HARD", 200_000)

def main():
    try:
        payload = json.loads(sys.stdin.read() or "{}")
    except Exception:
        return 0
    tp = payload.get("transcript_path") or ""
    # Only dispatched agents. The orchestrator's budget is the ledger's job,
    # and a main-loop transcript does not sit under a subagents/ directory.
    if not tp or "/subagents/" not in tp or not os.path.isfile(tp):
        return 0

    name = os.path.basename(tp).removesuffix(".jsonl")
    state = os.path.join(os.path.dirname(tp), ".ceiling-" + name)
    try:
        fired = open(state).read().strip()
    except FileNotFoundError:
        fired = "none"
    except Exception:
        # It exists but will not read, so a crossing cannot be de-duplicated
        # and blocking would repeat forever. Stay quiet.
        return 0
    # Nothing left to say once the hard stop has fired, and this runs on every
    # tool call — leave before reading a multi-megabyte transcript.
    if fired == "hard":
        return 0

    try:
        size = os.path.getsize(tp)
        with open(tp, "rb") as f:
            if size > 262_144:          # only the tail can hold the newest row
                f.seek(size - 262_144)
            data = f.read().decode("utf-8", "replace")
    except Exception:
        return 0

    ctx = 0
    for line in data.split("\n"):
        if '"usage"' not in line:
            continue
        try:
            d = json.loads(line)
        except Exception:
            continue
        if d.get("type") != "assistant":
            continue
        u = (d.get("message") or {}).get("usage") or {}
        ctx = max(ctx, (u.get("input_tokens") or 0)
                       + (u.get("cache_read_input_tokens") or 0)
                       + (u.get("cache_creation_input_tokens") or 0))
    if ctx <= 0:
        return 0

    def emit(level, msg):
        try:
            with open(state, "w") as f:
                f.write(level)
        except Exception:
            # Cannot record the crossing, so a block here would repeat on
            # every call and deadlock the agent. Stay quiet instead.
            return 0
        sys.stderr.write(msg)
        return 2

    if ctx >= HARD and fired != "hard":
        return emit("hard",
            f"CONTEXT CEILING — HARD STOP. Your context is {ctx:,} tokens, past the "
            f"~{HARD:,} hard stop.\nYou cannot measure this yourself, so the harness is "
            "telling you: stop now.\nWrite HANDOFF.md into your worktree (FILES TOUCHED / "
            "DECISIONS / REMAINING / STATE / GOTCHAS) and return it with STATUS: HANDOFF.\n"
            "Start no new work. This blocks once; your next tool call goes through so you "
            "can write the note.\n")

    if ctx >= SOFT and fired == "none":
        return emit("soft",
            f"CONTEXT CEILING — SOFT. Your context is {ctx:,} tokens, past the ~{SOFT:,} "
            "ceiling in your brief.\nYou cannot measure this yourself, so the harness is "
            "telling you.\nUnless you are in a BOUNDED finish — suite already green, one "
            "named deliverable left, no open decision —\nstop now: write HANDOFF.md into "
            "your worktree and return STATUS: HANDOFF.\nIf the finish really is bounded, "
            f"say so in the note and finish it; the hard stop is ~{HARD:,}.\n"
            "This blocks once; your next tool call goes through.\n")
    return 0

if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        sys.exit(0)            # fail open, always
