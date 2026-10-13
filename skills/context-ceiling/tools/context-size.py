#!/usr/bin/env python3
"""Measure a session's context size from its own transcript (context-ceiling skill).

The harness reports no context size to the model, and the token-report skill's
agent view is built from subagent rows, so the main loop has no instrument for
its own soft / hard ceiling (defaults 200k / 500k). This reads the session transcript
JSONL and, for every assistant turn, sums the prompt the model was given:
input_tokens + cache_read_input_tokens + cache_creation_input_tokens. That sum
IS the context size for that turn.

Usage:
  context-size.py                      # newest main-loop transcript for the cwd's project
  context-size.py --transcript PATH    # a specific transcript
  context-size.py --session <uuid>     # by session id, under the cwd's project
  context-size.py --project-dir DIR    # another project's transcript directory
  context-size.py --json               # machine-readable
  context-size.py --soft 200 --hard 500   # ceilings in k-tokens (defaults)

Exit status: 0 under the soft ceiling, 1 past the soft, 2 past the hard — so a
stamp line can branch on it. Read it at every progress report and record the
figure; a threshold with no instrument is decoration.
"""
import argparse, json, os, sys, glob

def project_dir(cwd):
    root = os.path.expanduser("~/.claude/projects")
    return os.path.join(root, cwd.replace("/", "-"))

def newest_main_transcript(pdir):
    cands = [p for p in glob.glob(os.path.join(pdir, "*.jsonl"))]
    if not cands:
        sys.exit(f"no transcript under {pdir}")
    return max(cands, key=os.path.getmtime)

def measure(path):
    # One assistant turn is written as one JSONL line per content block, each
    # repeating the turn's usage. Count each turn once, keyed by its request
    # (or message) id, in first-appearance order; a line with neither id is
    # its own turn.
    rows, seen = [], set()
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            try:
                d = json.loads(line)
            except json.JSONDecodeError:
                continue
            if d.get("type") != "assistant":
                continue
            u = (d.get("message") or {}).get("usage") or {}
            ctx = (u.get("input_tokens", 0) + u.get("cache_read_input_tokens", 0)
                   + u.get("cache_creation_input_tokens", 0))
            if ctx:
                key = d.get("requestId") or (d.get("message") or {}).get("id")
                if key:
                    if key in seen:
                        continue
                    seen.add(key)
                rows.append((d.get("timestamp", ""), ctx, u.get("output_tokens", 0)))
    return rows

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--transcript"); ap.add_argument("--session"); ap.add_argument("--project-dir")
    ap.add_argument("--soft", type=int, default=200); ap.add_argument("--hard", type=int, default=500)
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()
    pdir = a.project_dir or project_dir(os.getcwd())
    if a.transcript:
        path = a.transcript
    elif a.session:
        path = os.path.join(pdir, f"{a.session}.jsonl")
        if not os.path.exists(path):
            # A session id is unique across projects: search every project dir,
            # so the tool works from any cwd (a scratch dir, a worktree).
            hits = glob.glob(os.path.expanduser(f"~/.claude/projects/*/{a.session}.jsonl"))
            if not hits:
                sys.exit(f"no transcript named {a.session}.jsonl under ~/.claude/projects")
            path = hits[0]
    else:
        path = newest_main_transcript(pdir)
    rows = measure(path)
    if not rows:
        sys.exit(f"no assistant usage rows in {path}")
    current = rows[-1][1]; peak = max(r[1] for r in rows); avg = sum(r[1] for r in rows) // len(rows)
    status = 2 if current >= a.hard * 1000 else 1 if current >= a.soft * 1000 else 0
    out = {"transcript": path, "turns": len(rows), "current": current, "peak": peak, "avg": avg,
           "last_timestamp": rows[-1][0], "soft_k": a.soft, "hard_k": a.hard,
           "state": ["under-soft", "past-soft", "past-hard"][status]}
    if a.json:
        print(json.dumps(out))
    else:
        print(f"context current {current:,} · peak {peak:,} · avg {avg:,} over {len(rows)} turns "
              f"· {out['state']} (soft {a.soft}k / hard {a.hard}k) · {os.path.basename(path)} @ {rows[-1][0][11:19]}Z")
    sys.exit(status)

if __name__ == "__main__":
    main()
